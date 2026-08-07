<#
.SYNOPSIS
    AI Landing Zone のデプロイプリセットを azd 環境に適用します。

.DESCRIPTION
    presets/ ディレクトリの .env ファイルを読み込み、azd env set で各値を設定します。
    環境が存在しない場合は azd env new で作成します。

.PARAMETER Preset
    適用するプリセット。minimal / secure / full のいずれか。

.PARAMETER EnvName
    azd 環境名。省略時はプリセット名にタイムスタンプを付与。

.PARAMETER Location
    デプロイ先リージョン。省略時はプリセットの既定値（swedencentral）。

.PARAMETER AllowedIpRanges
    PaaS データプレーンへのアクセスを許可する CIDR の配列。
    'auto' を指定すると自分のグローバル IP を自動設定。

.EXAMPLE
    .\scripts\Set-Preset.ps1 -Preset minimal
    最小構成を ailz-minimal-<timestamp> 環境に設定

.EXAMPLE
    .\scripts\Set-Preset.ps1 -Preset secure -EnvName ailz-pilot -Location japaneast
    閉域構成を japaneast に、環境名 ailz-pilot で設定

.EXAMPLE
    .\scripts\Set-Preset.ps1 -Preset minimal -AllowedIpRanges auto
    最小構成 + 自分の IP のみ許可
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('minimal', 'secure', 'full')]
    [string]$Preset,

    [string]$EnvName,

    [string]$Location,

    [string[]]$AllowedIpRanges
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path $PSScriptRoot -Parent
$presetFile = Join-Path $repoRoot "presets\$Preset.env"
$infraDir   = Join-Path $repoRoot 'infra-upstream'

if (-not (Test-Path $presetFile)) {
    throw "プリセットファイルが見つかりません: $presetFile"
}
if (-not (Test-Path $infraDir)) {
    throw "infra-upstream ディレクトリが見つかりません: $infraDir"
}

# --- 前提ツールの確認 ---
foreach ($tool in @('az', 'azd')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool が見つかりません。'winget install Microsoft.AzureCLI' / 'winget install Microsoft.Azd' でインストールしてください。"
    }
}

if (-not $EnvName) {
    $EnvName = "ailz-$Preset-$(Get-Date -Format 'MMddHHmm')"
}

Write-Host "`n=== AI Landing Zone プリセット適用 ===" -ForegroundColor Cyan
Write-Host "プリセット : $Preset"
Write-Host "環境名     : $EnvName"
Write-Host "作業先     : $infraDir`n"

Push-Location $infraDir
try {
    # --- 環境の作成 / 選択 ---
    $existing = (azd env list --output json 2>$null | ConvertFrom-Json)
    if ($existing.Name -contains $EnvName) {
        Write-Host "既存の環境 '$EnvName' を選択します" -ForegroundColor Yellow
        azd env select $EnvName | Out-Null
    }
    else {
        Write-Host "環境 '$EnvName' を作成します"
        azd env new $EnvName --no-prompt | Out-Null
    }

    # --- プリセットの適用 ---
    $applied = 0
    foreach ($line in Get-Content $presetFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#') -or $t -notmatch '=') { continue }

        $key, $value = $t -split '=', 2
        $key   = $key.Trim()
        $value = $value.Trim()

        # -Location が指定されていればプリセットの値を上書き
        if ($key -eq 'AZURE_LOCATION' -and $Location) { $value = $Location }

        azd env set $key $value | Out-Null
        Write-Host ("  {0,-45} = {1}" -f $key, $value) -ForegroundColor DarkGray
        $applied++
    }

    # --- 許可 IP の設定 ---
    if ($AllowedIpRanges) {
        if ($AllowedIpRanges.Count -eq 1 -and $AllowedIpRanges[0] -eq 'auto') {
            $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
            $AllowedIpRanges = @("$myIp/32")
            Write-Host "`n  自分のグローバル IP を検出: $myIp" -ForegroundColor Yellow
        }
        $json = ($AllowedIpRanges | ConvertTo-Json -Compress -AsArray)
        azd env set ALLOWED_IP_RANGES $json | Out-Null
        Write-Host ("  {0,-45} = {1}" -f 'ALLOWED_IP_RANGES', $json) -ForegroundColor DarkGray
        $applied++
    }

    # --- principalId の設定 ---
    $principalId = az ad signed-in-user show --query id -o tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and $principalId) {
        azd env set AZURE_PRINCIPAL_ID $principalId  | Out-Null
        azd env set AZURE_PRINCIPAL_TYPE 'User'      | Out-Null
        Write-Host ("  {0,-45} = {1}" -f 'AZURE_PRINCIPAL_ID', $principalId) -ForegroundColor DarkGray
        $applied += 2
    }
    else {
        Write-Warning "principalId を取得できませんでした。'az login' を実行してから再試行するか、手動で設定してください:"
        Write-Warning "  azd env set AZURE_PRINCIPAL_ID <your-object-id>"
    }

    Write-Host "`n$applied 個の設定を適用しました。" -ForegroundColor Green

    # --- コスト警告 ---
    $costNote = switch ($Preset) {
        'minimal' { '月 ~400 USD（インフラのみ）／ 所要 10-15 分'  }
        'secure'  { '月 ~785 USD（インフラのみ）／ 所要 20-25 分'  }
        'full'    { '月 ~1,715 USD（インフラのみ）／ 所要 30-40 分' }
    }
    Write-Host "`n⚠ 概算コスト: $costNote" -ForegroundColor Yellow
    Write-Host "  検証後は必ず 'azd down --force --purge' で削除してください。`n" -ForegroundColor Yellow

    Write-Host "次のステップ:" -ForegroundColor Cyan
    Write-Host "  cd `"$infraDir`""
    Write-Host "  azd up`n"
}
finally {
    Pop-Location
}

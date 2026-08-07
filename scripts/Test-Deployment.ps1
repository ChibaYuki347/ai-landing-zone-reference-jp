<#
.SYNOPSIS
    デプロイされた AI Landing Zone の構成を確認します。

.DESCRIPTION
    リソース数、種別内訳、Foundry のエンドポイントとモデルデプロイ、
    Container App の状態、Private Endpoint の一覧を表示します。

    注意: az CLI の --query（JMESPath）には ASCII のみを渡します。
    日本語を含む JMESPath は Windows のコードページで文字化けし、
    `invalid jmespath_type value` エラーになるためです。
    同様に `length(@)` のような `(` `)` を含む式も cmd.exe に解釈されるため使いません。
    表示のローカライズは PowerShell 側の Format-Table で行います。

.PARAMETER ResourceGroup
    確認対象のリソースグループ。省略時は azd env から取得。

.EXAMPLE
    .\scripts\Test-Deployment.ps1

.EXAMPLE
    .\scripts\Test-Deployment.ps1 -ResourceGroup rg-ailz-full
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "az CLI が見つかりません。"
}

if (-not $ResourceGroup) {
    $infraDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra-upstream'
    Push-Location $infraDir
    try   { $ResourceGroup = (azd env get-value AZURE_RESOURCE_GROUP 2>$null) }
    finally { Pop-Location }

    if (-not $ResourceGroup) {
        throw "リソースグループを特定できませんでした。-ResourceGroup で明示してください。"
    }
}

Write-Host "`n=== デプロイ確認: $ResourceGroup ===`n" -ForegroundColor Cyan

# --- リソース一覧（1 回だけ取得して使い回す） ---
$resources = az resource list -g $ResourceGroup -o json | ConvertFrom-Json

Write-Host "リソース数: $($resources.Count)" -ForegroundColor Green
Write-Host "  （目安: 最小 ~60 / Zero Trust ~75 / フル ~80）`n"

# --- 種別内訳 ---
Write-Host "--- リソース種別の内訳 ---" -ForegroundColor Cyan
$resources | Group-Object type | Sort-Object Count -Descending |
    Format-Table @{L='数';E={$_.Count}}, @{L='種別';E={$_.Name}} -AutoSize

# --- プロビジョニング失敗しているリソース ---
$notOk = $resources | Where-Object { $_.provisioningState -and $_.provisioningState -ne 'Succeeded' }
if ($notOk) {
    Write-Host "--- Succeeded 以外のリソース ---" -ForegroundColor Red
    $notOk | Format-Table @{L='名前';E={$_.name}}, @{L='種別';E={$_.type}}, @{L='状態';E={$_.provisioningState}} -AutoSize
}
else {
    Write-Host "すべてのリソースが Succeeded です。`n" -ForegroundColor Green
}

# --- Foundry ---
Write-Host "--- Microsoft Foundry ---" -ForegroundColor Cyan
$accounts = az cognitiveservices account list -g $ResourceGroup -o json | ConvertFrom-Json
if ($accounts) {
    foreach ($a in $accounts) {
        Write-Host "  $($a.name)"
        Write-Host "    endpoint : $($a.properties.endpoint)"
        Write-Host "    kind     : $($a.kind)"
        Write-Host "    public   : $($a.properties.publicNetworkAccess)"
    }

    Write-Host "`n--- モデルデプロイ ---" -ForegroundColor Cyan
    $deployments = az cognitiveservices account deployment list `
        -g $ResourceGroup -n $accounts[0].name -o json | ConvertFrom-Json
    if ($deployments) {
        $deployments | Format-Table `
            @{L='名前';E={$_.name}}, `
            @{L='モデル';E={$_.properties.model.name}}, `
            @{L='バージョン';E={$_.properties.model.version}}, `
            @{L='SKU';E={$_.sku.name}}, `
            @{L='容量';E={$_.sku.capacity}} -AutoSize
    }
    else {
        Write-Warning "モデルデプロイが見つかりません。"
    }

    # --- Foundry プロジェクト ---
    $projects = $resources | Where-Object { $_.type -eq 'Microsoft.CognitiveServices/accounts/projects' }
    if ($projects) {
        Write-Host "--- Foundry プロジェクト ---" -ForegroundColor Cyan
        $projects | ForEach-Object { Write-Host "  $($_.name)" }
        Write-Host ""
    }
}
else {
    Write-Warning "Foundry アカウントが見つかりません。"
}

# --- Container Apps ---
Write-Host "--- Container Apps ---" -ForegroundColor Cyan
$apps = az containerapp list -g $ResourceGroup -o json | ConvertFrom-Json
if ($apps) {
    # ACA Environment が internal の場合、ingress.external=true でも VNet 内からのみ到達可能
    $envs = az containerapp env list -g $ResourceGroup -o json | ConvertFrom-Json
    foreach ($app in $apps) {
        $ing = $app.properties.configuration.ingress
        $envId = $app.properties.environmentId
        $envObj = $envs | Where-Object { $_.id -eq $envId }
        $envInternal = $envObj.properties.vnetConfiguration.internal

        if (-not $ing) {
            $scope = 'ingress なし'
        }
        elseif ($envInternal) {
            $scope = 'VNet 内のみ（ACA Environment が internal）'
        }
        elseif ($ing.external) {
            $scope = 'インターネット公開'
        }
        else {
            $scope = 'VNet 内のみ（ingress internal）'
        }

        Write-Host "  $($app.name)"
        Write-Host "    FQDN  : $($ing.fqdn)"
        Write-Host "    到達性: $scope"
        if ($envObj) {
            Write-Host "    環境IP: $($envObj.properties.staticIp)"
        }
        Write-Host "    状態  : $($app.properties.provisioningState)"
    }
    Write-Host ""
}
else {
    Write-Host "  なし`n"
}

# --- Private Endpoint ---
Write-Host "--- Private Endpoint ---" -ForegroundColor Cyan
$pes = $resources | Where-Object { $_.type -eq 'Microsoft.Network/privateEndpoints' }
Write-Host "  Private Endpoint 数: $($pes.Count)"
if ($pes.Count -gt 0) {
    $pes | Sort-Object name | Format-Table `
        @{L='名前';E={$_.name}}, @{L='状態';E={$_.provisioningState}} -AutoSize
}

# --- Private DNS Zone ---
Write-Host "--- Private DNS Zone ---" -ForegroundColor Cyan
$zones = $resources | Where-Object { $_.type -eq 'Microsoft.Network/privateDnsZones' }
Write-Host "  Private DNS Zone 数: $($zones.Count)`n"

# --- ネットワーク構成 ---
Write-Host "--- ネットワーク構成 ---" -ForegroundColor Cyan
$netChecks = [ordered]@{
    'Azure Firewall' = 'Microsoft.Network/azureFirewalls'
    'Bastion'        = 'Microsoft.Network/bastionHosts'
    'NAT Gateway'    = 'Microsoft.Network/natGateways'
    'Jumpbox VM'     = 'Microsoft.Compute/virtualMachines'
}
foreach ($k in $netChecks.Keys) {
    $hit = $resources | Where-Object { $_.type -eq $netChecks[$k] }
    $mark = if ($hit) { '[o]' } else { '[-]' }
    $color = if ($hit) { 'Green' } else { 'DarkGray' }
    Write-Host ("  {0} {1,-16} {2}" -f $mark, $k, ($hit.name -join ', ')) -ForegroundColor $color
}
Write-Host ""

# --- 失敗したデプロイ ---
Write-Host "--- デプロイ履歴 ---" -ForegroundColor Cyan
$allDeployments = az deployment group list -g $ResourceGroup -o json | ConvertFrom-Json |
    Sort-Object { [datetime]$_.properties.timestamp } -Descending

$latestSuccess = $allDeployments | Where-Object { $_.properties.provisioningState -eq 'Succeeded' } | Select-Object -First 1
if ($latestSuccess) {
    Write-Host "  最新の成功: $($latestSuccess.name)  ($($latestSuccess.properties.timestamp))" -ForegroundColor Green
    $successTime = [datetime]$latestSuccess.properties.timestamp
}
else {
    $successTime = [datetime]::MinValue
}

# 最新の成功より後に失敗したものだけが実質的な問題
$active = @()
$superseded = @()
foreach ($d in ($allDeployments | Where-Object { $_.properties.provisioningState -eq 'Failed' })) {
    # ガバナンスポリシー由来は AILZ と無関係
    if ($d.name -like 'PolicyDeployment_*') { continue }
    if ([datetime]$d.properties.timestamp -gt $successTime) { $active += $d } else { $superseded += $d }
}

if ($active) {
    Write-Host "`n  未解決の失敗:" -ForegroundColor Red
    foreach ($f in $active) {
        Write-Host "    $($f.name)" -ForegroundColor Red
        Write-Host "      $($f.properties.error.message)" -ForegroundColor DarkGray
        Write-Host "      詳細: az deployment operation group list -g $ResourceGroup -n $($f.name) --query ""[?properties.provisioningState=='Failed']""" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  未解決の失敗: なし" -ForegroundColor Green
}

if ($superseded) {
    Write-Host "  （リトライで解決済みの過去の失敗: $($superseded.Count) 件）" -ForegroundColor DarkGray
}

$policyFailed = $allDeployments | Where-Object {
    $_.properties.provisioningState -eq 'Failed' -and $_.name -like 'PolicyDeployment_*'
}
if ($policyFailed) {
    Write-Host "  （サブスクリプションのガバナンスポリシー由来の失敗: $($policyFailed.Count) 件 / AILZ とは無関係のため無視可）" -ForegroundColor DarkGray
}

Write-Host "`n=== 確認完了 ===`n" -ForegroundColor Cyan
Write-Host "削除するには:" -ForegroundColor Yellow
Write-Host "  cd infra-upstream ; azd down --force --purge`n" -ForegroundColor Yellow

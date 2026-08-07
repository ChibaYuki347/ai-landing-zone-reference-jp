<#
.SYNOPSIS
    デプロイされた AI Landing Zone の構成を確認します。

.DESCRIPTION
    リソース数、種別内訳、Foundry のエンドポイントとモデルデプロイ、
    Container App の状態、Private Endpoint の一覧を表示します。

.PARAMETER ResourceGroup
    確認対象のリソースグループ。省略時は azd env から取得。

.EXAMPLE
    .\scripts\Test-Deployment.ps1

.EXAMPLE
    .\scripts\Test-Deployment.ps1 -ResourceGroup rg-ailz-0304121530
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

# --- リソース数 ---
$count = az resource list -g $ResourceGroup --query "length(@)" -o tsv
Write-Host "リソース数: $count" -ForegroundColor Green
Write-Host "  （目安: 最小 ~60 / Zero Trust ~75 / フル ~80）`n"

# --- 種別内訳 ---
Write-Host "--- リソース種別の内訳 ---" -ForegroundColor Cyan
az resource list -g $ResourceGroup --query "[].type" -o tsv |
    Group-Object |
    Sort-Object Count -Descending |
    Format-Table @{L='数';E={$_.Count}}, @{L='種別';E={$_.Name}} -AutoSize

# --- Foundry ---
Write-Host "--- Microsoft Foundry ---" -ForegroundColor Cyan
$accounts = az cognitiveservices account list -g $ResourceGroup -o json | ConvertFrom-Json
if ($accounts) {
    $accounts | ForEach-Object {
        Write-Host "  $($_.name)"
        Write-Host "    endpoint : $($_.properties.endpoint)"
        Write-Host "    kind     : $($_.kind)"
        Write-Host "    public   : $($_.properties.publicNetworkAccess)"
    }

    Write-Host "`n--- モデルデプロイ ---" -ForegroundColor Cyan
    az cognitiveservices account deployment list -g $ResourceGroup -n $accounts[0].name `
        --query "[].{名前:name, モデル:properties.model.name, バージョン:properties.model.version, SKU:sku.name, 容量:sku.capacity}" -o table
}
else {
    Write-Warning "Foundry アカウントが見つかりません。"
}

# --- Container Apps ---
Write-Host "`n--- Container Apps ---" -ForegroundColor Cyan
az containerapp list -g $ResourceGroup `
    --query "[].{名前:name, FQDN:properties.configuration.ingress.fqdn, 状態:properties.provisioningState}" -o table

# --- Private Endpoint ---
Write-Host "`n--- Private Endpoint ---" -ForegroundColor Cyan
$peCount = az network private-endpoint list -g $ResourceGroup --query "length(@)" -o tsv
Write-Host "  Private Endpoint 数: $peCount"
if ([int]$peCount -gt 0) {
    az network private-endpoint list -g $ResourceGroup `
        --query "[].{名前:name, 状態:provisioningState}" -o table
}

# --- Private DNS Zone ---
Write-Host "`n--- Private DNS Zone ---" -ForegroundColor Cyan
$dnsCount = az network private-dns zone list -g $ResourceGroup --query "length(@)" -o tsv 2>$null
Write-Host "  Private DNS Zone 数: $dnsCount"

# --- 失敗したデプロイ ---
Write-Host "`n--- 失敗したデプロイ ---" -ForegroundColor Cyan
$failed = az deployment group list -g $ResourceGroup `
    --query "[?properties.provisioningState=='Failed'].{名前:name, エラー:properties.error.message}" -o json | ConvertFrom-Json
if ($failed) {
    $failed | Format-List
}
else {
    Write-Host "  なし" -ForegroundColor Green
}

Write-Host "`n=== 確認完了 ===`n" -ForegroundColor Cyan
Write-Host "削除するには:" -ForegroundColor Yellow
Write-Host "  cd infra-upstream ; azd down --force --purge`n" -ForegroundColor Yellow

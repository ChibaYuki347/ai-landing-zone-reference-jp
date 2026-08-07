<#
.SYNOPSIS
    閉域構成の AI Landing Zone を確実に削除します。

.DESCRIPTION
    `azd down --force --purge` は閉域構成では 2 段階で失敗します。

      1. CannotDeleteWorkspaceWhenLinkedToPrivateLinkScopes (409)
         Log Analytics / App Insights が AMPLS に紐づいているため purge できない。
         purge 段階の失敗なのでリソースは 1 つも削除されません。

      2. ResourceGroupDeletionBlocked
         リソースグループの削除は依存関係を無視して並列削除するため、
         削除順序が必要なリソースが残ります（実測 91 -> 6 個で停止）。
           - AI Search : Shared Private Link Resource が LockedSPLResourceFound
           - VNet      : agent-subnet の孤児 legionservicelink が InUseSubnetCannotBeDeleted

    このスクリプトは正しい順序で片付けてから azd down を呼びます。

      AMPLS 解除 -> ACA 環境削除 -> Search SPL 削除 -> Search 削除
        -> azd down --force --purge -> NAT Gateway 切り離し -> SAL 待ち
        -> RG 削除 -> 論理削除の purge

    注意: az CLI の --query（JMESPath）には ASCII のみを渡します。
    日本語を含む JMESPath は Windows のコードページで文字化けするためです。
    同様に `length(@)` のような `(` `)` を含む式も cmd.exe に解釈されるため使いません。

.PARAMETER ResourceGroup
    削除対象のリソースグループ。省略時は azd env から取得します。

.PARAMETER SkipAzdDown
    azd down を呼ばず、残存リソースの後片付けだけを行います。
    azd down が既に失敗した後のリカバリに使います。

.PARAMETER SalTimeoutMinutes
    孤児 Service Association Link の自動回収を待つ上限（分）。既定 60。
    0 を指定すると待たずに終了します（課金対象は先に削除済み）。

.EXAMPLE
    .\scripts\Remove-Deployment.ps1

.EXAMPLE
    # azd down が ResourceGroupDeletionBlocked で失敗した後のリカバリ
    .\scripts\Remove-Deployment.ps1 -ResourceGroup rg-ailz-full -SkipAzdDown

.EXAMPLE
    # SAL を待たずに課金だけ止めて抜ける
    .\scripts\Remove-Deployment.ps1 -SalTimeoutMinutes 0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ResourceGroup,
    [switch]$SkipAzdDown,
    [int]$SalTimeoutMinutes = 60
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "az CLI が見つかりません。"
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$infraDir = Join-Path $repoRoot 'infra-upstream'

if (-not $ResourceGroup) {
    Push-Location $infraDir
    try   { $ResourceGroup = (azd env get-value AZURE_RESOURCE_GROUP 2>$null) }
    finally { Pop-Location }

    if (-not $ResourceGroup) {
        throw "リソースグループを特定できませんでした。-ResourceGroup で明示してください。"
    }
}

$exists = az group exists -n $ResourceGroup -o tsv
if ($exists -ne 'true') {
    Write-Host "リソースグループ $ResourceGroup は既に存在しません。" -ForegroundColor Green
    Write-Host "論理削除の確認だけ行います。`n" -ForegroundColor Cyan
    $SkipAzdDown = $true
}

$subscriptionId = az account show --query id -o tsv
$location       = az group show -n $ResourceGroup --query location -o tsv 2>$null

Write-Host "`n=== AI Landing Zone の削除: $ResourceGroup ===" -ForegroundColor Cyan
Write-Host "サブスクリプション: $subscriptionId"
Write-Host "リージョン        : $location`n"

function Write-Step {
    param([string]$Message)
    Write-Host "`n--- $Message ---" -ForegroundColor Cyan
}

# =====================================================================
# 1. AMPLS のスコープリンクを解除
#    これを先にやらないと azd down が purge 段階で 409 になる。
# =====================================================================
if ($exists -eq 'true') {
    Write-Step "1. Azure Monitor Private Link Scope のスコープリンクを解除"

    $scopes = az resource list -g $ResourceGroup `
        --resource-type "microsoft.insights/privateLinkScopes" -o json | ConvertFrom-Json

    if (-not $scopes -or $scopes.Count -eq 0) {
        Write-Host "  AMPLS はありません（スキップ）"
    }
    foreach ($pls in $scopes) {
        $uri = "https://management.azure.com/subscriptions/$subscriptionId" +
               "/resourceGroups/$ResourceGroup/providers/microsoft.insights" +
               "/privatelinkscopes/$($pls.name)/scopedResources?api-version=2019-10-17-preview"

        $scoped = (az rest --method get --url $uri -o json 2>$null | ConvertFrom-Json).value

        if (-not $scoped -or $scoped.Count -eq 0) {
            Write-Host "  $($pls.name): スコープリソースなし"
            continue
        }

        foreach ($s in $scoped) {
            $linked = ($s.properties.linkedResourceId -split '/')[-1]
            if ($PSCmdlet.ShouldProcess("$($pls.name)/$($s.name)", "スコープリンクを解除")) {
                # az monitor private-link-scope scoped-resource delete は
                # application-insights 拡張の対話インストールで EOFError になりうるため az rest を使う
                az rest --method delete `
                    --url "https://management.azure.com$($s.id)?api-version=2019-10-17-preview" 2>&1 | Out-Null
                Write-Host "  解除: $($s.name) -> $linked"
            }
        }
    }
}

# =====================================================================
# 2. Container Apps 環境を先に削除
#    サブネットの Service Association Link は非同期に回収されるため、
#    できるだけ早く削除を始めさせる。
# =====================================================================
if ($exists -eq 'true') {
    Write-Step "2. Container Apps 環境を削除（Service Association Link の回収を開始させる）"

    $acaEnvs = az resource list -g $ResourceGroup `
        --resource-type "Microsoft.App/managedEnvironments" -o json | ConvertFrom-Json

    if (-not $acaEnvs -or $acaEnvs.Count -eq 0) {
        Write-Host "  ACA 環境はありません（スキップ）"
    }
    foreach ($e in $acaEnvs) {
        if ($PSCmdlet.ShouldProcess($e.name, "ACA 環境を削除")) {
            Write-Host "  削除中: $($e.name) ..."
            az containerapp env delete -g $ResourceGroup -n $e.name --yes 2>&1 | Out-Null
            Write-Host "  完了: $($e.name)"
        }
    }
}

# =====================================================================
# 3. AI Search の Shared Private Link Resource を削除してから Search を削除
#    接続先が先に消えると status は Disconnected になるが、
#    残っている限り Search 本体は LockedSPLResourceFound で削除できない。
# =====================================================================
if ($exists -eq 'true') {
    Write-Step "3. AI Search の Shared Private Link Resource を削除"

    $searches = az resource list -g $ResourceGroup `
        --resource-type "Microsoft.Search/searchServices" -o json | ConvertFrom-Json

    if (-not $searches -or $searches.Count -eq 0) {
        Write-Host "  AI Search はありません（スキップ）"
    }
    foreach ($srch in $searches) {
        $spl = az search shared-private-link-resource list `
            --service-name $srch.name -g $ResourceGroup -o json 2>$null | ConvertFrom-Json

        if ($spl -and $spl.Count -gt 0) {
            Write-Host "  $($srch.name): SPL $($spl.Count) 件"
            foreach ($s in $spl) {
                if ($PSCmdlet.ShouldProcess("$($srch.name)/$($s.name)", "SPL を削除")) {
                    Write-Host "    削除中: $($s.name) [$($s.properties.status)] ..."
                    az search shared-private-link-resource delete `
                        --service-name $srch.name -g $ResourceGroup --name $s.name --yes 2>&1 | Out-Null
                }
            }
        } else {
            Write-Host "  $($srch.name): SPL なし"
        }

        if ($PSCmdlet.ShouldProcess($srch.name, "Search サービスを削除")) {
            Write-Host "  Search 本体を削除中: $($srch.name) ..."
            az resource delete --ids $srch.id 2>&1 | Out-Null
            Write-Host "  完了: $($srch.name)"
        }
    }
}

# =====================================================================
# 4. azd down
# =====================================================================
if (-not $SkipAzdDown) {
    Write-Step "4. azd down --force --purge"
    Write-Host "  10〜20 分かかります。ResourceGroupDeletionBlocked で終わっても想定内です。`n"

    Push-Location $infraDir
    try {
        if ($PSCmdlet.ShouldProcess($ResourceGroup, "azd down --force --purge")) {
            azd down --force --purge
        }
    } finally { Pop-Location }
} else {
    Write-Step "4. azd down はスキップ（-SkipAzdDown）"
}

# =====================================================================
# 5. NAT Gateway を切り離して削除（課金を止める）
#    VNet が SAL で残ると NAT Gateway / Public IP も連鎖的に残り、
#    合計 約 $35/月 が発生し続けるため優先して削除する。
# =====================================================================
$exists = az group exists -n $ResourceGroup -o tsv
if ($exists -eq 'true') {
    Write-Step "5. NAT Gateway と Public IP を削除（課金を止める）"

    $natGws = az resource list -g $ResourceGroup `
        --resource-type "Microsoft.Network/natGateways" -o json | ConvertFrom-Json

    if (-not $natGws -or $natGws.Count -eq 0) {
        Write-Host "  NAT Gateway はありません（スキップ）"
    }
    foreach ($ng in $natGws) {
        # NAT Gateway を参照しているサブネットから先に外す
        $vnets = az network vnet list -g $ResourceGroup -o json | ConvertFrom-Json
        foreach ($v in $vnets) {
            foreach ($sn in $v.subnets) {
                if ($sn.natGateway -and $sn.natGateway.id -eq $ng.id) {
                    if ($PSCmdlet.ShouldProcess("$($v.name)/$($sn.name)", "NAT Gateway を切り離し")) {
                        Write-Host "  切り離し: $($v.name)/$($sn.name)"
                        az network vnet subnet update -g $ResourceGroup `
                            --vnet-name $v.name -n $sn.name --remove natGateway 2>&1 | Out-Null
                    }
                }
            }
        }
        if ($PSCmdlet.ShouldProcess($ng.name, "NAT Gateway を削除")) {
            az network nat gateway delete -g $ResourceGroup -n $ng.name 2>&1 | Out-Null
            Write-Host "  削除: $($ng.name)"
        }
    }

    $pips = az resource list -g $ResourceGroup `
        --resource-type "Microsoft.Network/publicIPAddresses" -o json | ConvertFrom-Json
    foreach ($p in $pips) {
        if ($PSCmdlet.ShouldProcess($p.name, "Public IP を削除")) {
            az network public-ip delete -g $ResourceGroup -n $p.name 2>&1 | Out-Null
            Write-Host "  削除: $($p.name)"
        }
    }
}

# =====================================================================
# 6. 孤児 Service Association Link の自動回収を待つ
#    委任と SAL が相互ロックするため手動解除は一切できない。
#      - subnet update --remove delegations -> SubnetMissingRequiredDelegation
#      - subnet delete                      -> InUseSubnetCannotBeDeleted
#      - az rest で SAL を DELETE           -> UnauthorizedClientApplication
#        (SAL の削除は Microsoft.App RP のみに許可されている)
# =====================================================================
$exists = az group exists -n $ResourceGroup -o tsv
if ($exists -eq 'true' -and $SalTimeoutMinutes -gt 0) {
    Write-Step "6. 孤児 Service Association Link の回収を待機（最大 $SalTimeoutMinutes 分）"
    Write-Host "  手動解除はできません。Microsoft.App RP による自動回収を待ちます。"
    Write-Host "  この間の課金対象は残っていません（VNet / NSG / Route Table は無料）。`n"

    $deadline = (Get-Date).AddMinutes($SalTimeoutMinutes)
    $salGone  = $false

    while ((Get-Date) -lt $deadline) {
        $found = $false
        $vnets = az network vnet list -g $ResourceGroup -o json 2>$null | ConvertFrom-Json

        foreach ($v in $vnets) {
            foreach ($sn in $v.subnets) {
                $url = "https://management.azure.com/subscriptions/$subscriptionId" +
                       "/resourceGroups/$ResourceGroup/providers/Microsoft.Network" +
                       "/virtualNetworks/$($v.name)/subnets/$($sn.name)?api-version=2023-09-01"
                $detail = az rest --method get --url $url -o json 2>$null | ConvertFrom-Json
                if ($detail.properties.serviceAssociationLinks) {
                    foreach ($sal in $detail.properties.serviceAssociationLinks) {
                        Write-Host ("  [{0}] 残存: {1}/{2} -> {3}" -f `
                            (Get-Date -Format 'HH:mm:ss'), $sn.name, $sal.name, $sal.properties.linkedResourceType)
                        $found = $true
                    }
                }
            }
        }

        if (-not $found) {
            Write-Host "  SAL は解消されました。" -ForegroundColor Green
            $salGone = $true
            break
        }
        Start-Sleep -Seconds 120
    }

    if (-not $salGone) {
        Write-Host "`n  タイムアウトしました。SAL がまだ残っています。" -ForegroundColor Yellow
        Write-Host "  課金対象は削除済みなので、時間をおいて以下を再実行してください:" -ForegroundColor Yellow
        Write-Host "    az group delete -n $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
    }
}

# =====================================================================
# 7. リソースグループを削除
# =====================================================================
$exists = az group exists -n $ResourceGroup -o tsv
if ($exists -eq 'true') {
    Write-Step "7. リソースグループを削除"

    $remaining = az resource list -g $ResourceGroup -o json | ConvertFrom-Json
    Write-Host "  残存リソース: $($remaining.Count)"
    foreach ($r in $remaining) { Write-Host "    $($r.type) / $($r.name)" }

    if ($PSCmdlet.ShouldProcess($ResourceGroup, "リソースグループを削除")) {
        az group delete -n $ResourceGroup --yes 2>&1 | Select-Object -Last 3
    }
}

# =====================================================================
# 8. 論理削除の purge
#    azd down が RG 削除で失敗すると --purge が最後まで走らないため、
#    Key Vault / App Configuration / Foundry が論理削除で残ることがある。
#    残っていると同じ名前で再デプロイできない。
# =====================================================================
Write-Step "8. 論理削除の残骸を purge"

$kvs = az keyvault list-deleted --query "[].name" -o tsv 2>$null
foreach ($n in ($kvs -split "`n" | Where-Object { $_ })) {
    $n = $n.Trim()
    if ($PSCmdlet.ShouldProcess($n, "Key Vault を purge")) {
        az keyvault purge --name $n --location $location 2>&1 | Out-Null
        Write-Host "  Key Vault purge: $n (exit=$LASTEXITCODE)"
    }
}

$acs = az appconfig list-deleted --query "[].name" -o tsv 2>$null
foreach ($n in ($acs -split "`n" | Where-Object { $_ })) {
    $n = $n.Trim()
    if ($PSCmdlet.ShouldProcess($n, "App Configuration を purge")) {
        az appconfig purge --name $n --yes 2>&1 | Out-Null
        Write-Host "  App Configuration purge: $n (exit=$LASTEXITCODE)"
    }
}

$cogs = az cognitiveservices account list-deleted -o json 2>$null | ConvertFrom-Json
foreach ($c in $cogs) {
    if ($PSCmdlet.ShouldProcess($c.name, "Cognitive Services を purge")) {
        az cognitiveservices account purge --name $c.name --location $c.location `
            --resource-group $ResourceGroup 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # アカウント削除直後は provisioningState が terminal でないため
            # RequestConflict になる。数分おいて再実行すれば通る。
            Write-Host "  Cognitive Services purge 失敗（状態遷移待ち）: $($c.name)" -ForegroundColor Yellow
            Write-Host "    数分後に次を再実行してください:" -ForegroundColor Yellow
            Write-Host "    az cognitiveservices account purge --name $($c.name) --location $($c.location) --resource-group $ResourceGroup" -ForegroundColor Yellow
        } else {
            Write-Host "  Cognitive Services purge: $($c.name)"
        }
    }
}

# =====================================================================
# 最終確認
# =====================================================================
Write-Step "最終確認"

$exists = az group exists -n $ResourceGroup -o tsv
Write-Host "リソースグループ: $ResourceGroup -> exists=$exists"

$kvLeft  = (az keyvault list-deleted --query "[].name" -o tsv 2>$null) -join ", "
$acLeft  = (az appconfig list-deleted --query "[].name" -o tsv 2>$null) -join ", "
$cogLeft = (az cognitiveservices account list-deleted --query "[].name" -o tsv 2>$null) -join ", "

Write-Host "論理削除 Key Vault        : $(if ($kvLeft)  { $kvLeft }  else { 'なし' })"
Write-Host "論理削除 App Config       : $(if ($acLeft)  { $acLeft }  else { 'なし' })"
Write-Host "論理削除 Cognitive Svc    : $(if ($cogLeft) { $cogLeft } else { 'なし' })"

if ($exists -eq 'false' -and -not $kvLeft -and -not $acLeft -and -not $cogLeft) {
    Write-Host "`n削除は完了しました。`n" -ForegroundColor Green
} else {
    Write-Host "`n残っているものがあります。上記の指示に従って再実行してください。`n" -ForegroundColor Yellow
}

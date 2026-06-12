# lib_cold_wallet_alert.ps1 -- Hot wallet ratio alert (vulnerability #6 single-venue).
#
# Premissa: CoinEx eh hot wallet. Total declarado (incluindo cold) deveria ser
# > capital exposto. Cron diario checa ratio e alerta se hot/total > threshold.
#
# Config user em $global:TOTAL_DECLARED_USD (em config.local.ps1 ou env):
#   - Se nao setado: skip alert (sem total declarado, nao da pra calcular ratio)
#   - Se setado: alerta quando hot > threshold * total
#
# Default threshold 0.80 (80% do total declarado em hot = alta exposicao).


function Test-HotWalletRatio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $HotWalletUsd,
        [Parameter(Mandatory)] [double] $TotalDeclaredUsd,
        [double] $Threshold = 0.80
    )
    if ($TotalDeclaredUsd -le 0) {
        return [PSCustomObject]@{
            ratio  = 0
            alert  = $false
            reason = "no_total_declared"
        }
    }
    $ratio = [Math]::Round($HotWalletUsd / $TotalDeclaredUsd, 3)
    # Strict greater: ratio EXATAMENTE no threshold ainda eh OK (so dispara acima)
    $alert = ($ratio -gt $Threshold) -and ($HotWalletUsd -gt 0)
    return [PSCustomObject]@{
        ratio          = $ratio
        alert          = $alert
        threshold      = $Threshold
        hot_usd        = $HotWalletUsd
        total_usd      = $TotalDeclaredUsd
        reason         = if ($alert) { "ratio_${ratio}_exceeds_${Threshold}" } else { "ok" }
    }
}


function Get-AlertMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $Check)
    $pct = [int]($Check.ratio * 100)
    return @"
<b>Hot wallet exposure ALTA</b>
CoinEx hot: `$$($Check.hot_usd)
Total declarado: `$$($Check.total_usd)
Ratio: ${pct}% (threshold $([int]($Check.threshold * 100))%)

Recomendacao: considere withdraw a cold wallet pra reduzir single-venue risk.
"@
}


function Invoke-HotWalletAuditAndAlert {
    # Wrapper pra cron: le saldo CoinEx + $global:TOTAL_DECLARED_USD + alerta TG se exceder.
    [CmdletBinding()]
    param(
        [double] $TotalDeclaredUsd = 0,
        [double] $Threshold = 0.80,
        [switch] $SkipTelegram
    )
    $hot = 0.0
    if (Get-Command CoinEx-GetTotalCapitalUSDT -ErrorAction SilentlyContinue) {
        try { $hot = [double](CoinEx-GetTotalCapitalUSDT) } catch {}
    }
    $total = if ($TotalDeclaredUsd -gt 0) { $TotalDeclaredUsd } `
             elseif ($null -ne $global:TOTAL_DECLARED_USD) { [double]$global:TOTAL_DECLARED_USD } `
             else { 0 }
    $check = Test-HotWalletRatio -HotWalletUsd $hot -TotalDeclaredUsd $total -Threshold $Threshold
    if ($check.alert -and -not $SkipTelegram -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
        try { Send-TelegramAlert -Message (Get-AlertMessage -Check $check) | Out-Null } catch {}
    }
    return $check
}

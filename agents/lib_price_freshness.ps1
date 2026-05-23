# lib_price_freshness.ps1 -- B18 fix 2026-05-20 PM6+410min.
#
# Stale price detection: garante que decisao de trade usa preco recente.
# Antes: CoinEx-GetTicker retorna .last sem timestamp; se REST API/WS cachear ou
# orquestrador segurar variavel por 30min, decisao seria tomada com preco antigo
# = stop ATR calculado errado = position errada size/protection.
#
# Pattern: caller envolve ticker em New-FreshTicker (registra fetched_at local) e
# downstream chama Test-PriceFresh antes de usar.
#
# PS 5.1, UTF-8 BOM.

function New-FreshTicker {
    <#
    .SYNOPSIS
        Envolve raw ticker da exchange em wrapper com fetched_at local + flag is_fresh.
    .OUTPUTS
        PSCustomObject { ticker, fetched_at, is_fresh }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $RawTicker
    )
    return [PSCustomObject]@{
        ticker     = $RawTicker
        fetched_at = (Get-Date)
        is_fresh   = $true  # ao criar, sempre fresh
    }
}

function Test-PriceFresh {
    <#
    .SYNOPSIS
        Verifica se um ticker (com fetched_at registrado) ainda esta dentro do
        threshold de freshness. Null/missing fetched_at = fail-closed (is_fresh=false).
    .OUTPUTS
        PSCustomObject { is_fresh, age_seconds, threshold_seconds }
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [Nullable[datetime]] $FetchedAt = $null,
        [int] $MaxAgeSeconds = 60
    )
    if ($null -eq $FetchedAt -or $FetchedAt -eq [datetime]::MinValue) {
        return [PSCustomObject]@{
            is_fresh = $false
            age_seconds = -1
            threshold_seconds = $MaxAgeSeconds
            reason = "fetched_at_missing_fail_closed"
        }
    }
    $age = ((Get-Date) - $FetchedAt).TotalSeconds
    $fresh = $age -le $MaxAgeSeconds
    return [PSCustomObject]@{
        is_fresh = $fresh
        age_seconds = [Math]::Round($age, 1)
        threshold_seconds = $MaxAgeSeconds
        reason = if ($fresh) { "ok" } else { "stale_price_${age}s_exceeded_${MaxAgeSeconds}s" }
    }
}

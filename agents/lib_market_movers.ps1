# lib_market_movers.ps1 -- Universo dinamico: top gainers/losers (vol spike real)
# 2026-06-09: prioriza moedas que estao se MOVENDO agora, nao lentas micro-caps.

# Get-PrioritizedMarkets (simples): movers (gainers+losers) primeiro, quiet depois
function Get-PrioritizedMarkets {
    param(
        [object[]]$AllMarkets,  # tickers com change_24h
        [double]$GainerThreshold = 10,
        [double]$LoserThreshold = -10
    )

    $gainers = @()
    $losers = @()
    $quiet = @()

    foreach ($m in $AllMarkets) {
        $c = if ($m.PSObject.Properties['change_24h'] -and $null -ne $m.change_24h) { [double]$m.change_24h } else { 0 }
        if ($c -ge $GainerThreshold) { $gainers += $m }
        elseif ($c -le $LoserThreshold) { $losers += $m }
        else { $quiet += $m }
    }

    return @($gainers + $losers + $quiet)
}

Set-Location 'C:\Users\thiag\Coinex_AI_USER_API'
. 'agents\lib_promotion_ladder.ps1'
. 'agents\lib_promotion_paper_engine.ps1'

foreach ($mkt in @('PENDLEUSDT','TONUSDT','HYPEUSDT')) {
    Write-Host '===' $mkt '==='
    try {
        $url = 'https://api.coinex.com/v2/spot/kline?market=' + $mkt + '&period=1day&limit=250'
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 10
        if (-not $r.data -or $r.data.Count -lt 50) { Write-Host '  Insufficient history'; continue }
        $candles = @($r.data | ForEach-Object {
            [PSCustomObject]@{ close=[double]$_.close; high=[double]$_.high; low=[double]$_.low }
        })
        Write-Host ("  candles: {0}" -f $candles.Count)

        $bt = Compute-PaperBacktest -Candles $candles
        Write-Host ("  paper: n_trades={0} sharpe_30d={1} max_dd={2}" -f $bt.n_trades, $bt.sharpe_30d, $bt.max_dd)

        $closes = [double[]]@($candles | ForEach-Object { $_.close })
        $reg = Compute-AssetRegime -Closes $closes
        Write-Host ("  regime: {0} dist_sma200={1} mom_20d={2}" -f $reg.regime, $reg.dist_sma200, $reg.mom_20d)

        $external = @{
            sharpe_30d=$bt.sharpe_30d; n_trades=$bt.n_trades; max_dd=$bt.max_dd
        }
        $m = Get-PromotionMetrics -Market $mkt -AssetCloses $closes -External $external
        $m.regime_btc = 'BEAR_WEAK'

        $gate = Test-GateObservationToC -Metrics $m
        Write-Host ("  gate PASSED={0}" -f $gate.passed)
        if ($gate.failures.Count -gt 0) {
            foreach ($f in $gate.failures) { Write-Host ("    FAIL: {0}" -f $f) }
        } else {
            foreach ($reason in $gate.reasons) { Write-Host ("    OK: {0}" -f $reason) }
        }
    } catch {
        Write-Host ("  ERROR: {0}" -f $_.Exception.Message)
    }
}

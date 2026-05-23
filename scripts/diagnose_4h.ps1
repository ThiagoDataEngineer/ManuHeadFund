Set-Location 'C:\Users\thiag\Coinex_AI_USER_API'
. 'agents\lib_promotion_ladder.ps1'
. 'agents\lib_promotion_paper_engine.ps1'

foreach ($mkt in @('PENDLEUSDT','TONUSDT','HYPEUSDT','BTCUSDT','ZECUSDT')) {
    Write-Host '===' $mkt '==='
    $url = 'https://api.coinex.com/v2/spot/kline?market=' + $mkt + '&period=4hour&limit=500'
    try {
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 10
        if (-not $r.data -or $r.data.Count -lt 250) {
            Write-Host ('  Insufficient 4h: ' + $r.data.Count)
            continue
        }
        $candles = @($r.data | ForEach-Object {
            [PSCustomObject]@{ close=[double]$_.close; high=[double]$_.high; low=[double]$_.low }
        })
        $bt = Compute-PaperBacktest -Candles $candles
        $msg = '  4h: candles={0} n_trades={1} sharpe={2} max_dd={3}' -f $candles.Count, $bt.n_trades, $bt.sharpe_30d, $bt.max_dd
        Write-Host $msg
    } catch {
        Write-Host ('  err: ' + $_.Exception.Message)
    }
}

# diag_btc_swing_readonly_2026_08_05.ps1 -- ONE-SHOT, so leitura, ZERO mudanca.
#
# Owner cogitando "swing" em BTC (segurar por dias/semanas, nao scalp) --
# achado real (diag_spot_historical_performance): 0 trades SPOT fechados
# nos ultimos 7 dias, e a unica posicao BTCUSDT do periodo foi SHORT via
# FUTURES fechada por reconciliacao de orfa, nao TP/SL normal. Sem dado de
# trade pra avaliar. Este script puxa candle REAL de mercado (30d e 90d)
# pra avaliar visualmente se teria valido a pena segurar, sem depender de
# nenhum trade do sistema.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG: BTC swing -- historico real de preco (30d/90d), so leitura ===" -ForegroundColor Cyan

try {
    $ticker = CoinEx-GetTicker "BTCUSDT"
    $current = [double]$ticker.last
    Write-Host "Preco atual BTCUSDT: `$$current`n"

    foreach ($days in @(7, 30, 90)) {
        $candles = @(CoinEx-GetCandles "BTCUSDT" "1day" ($days + 1))
        if ($candles.Count -lt 2) { continue }
        $sorted = @($candles | Sort-Object ts)
        $oldest = $sorted[0]
        $newest = $sorted[-1]
        $highs = @($sorted | ForEach-Object { [double]$_.high })
        $lows  = @($sorted | ForEach-Object { [double]$_.low })
        $rangeHigh = ($highs | Measure-Object -Maximum).Maximum
        $rangeLow  = ($lows  | Measure-Object -Minimum).Minimum
        $changePct = (([double]$newest.close - [double]$oldest.close) / [double]$oldest.close) * 100

        Write-Host "--- Janela de ${days}d ---" -ForegroundColor Yellow
        Write-Host ("  Close ha {0}d: `${1}  ->  Close hoje: `${2}  (variacao: {3:N2}%)" -f $days, [double]$oldest.close, [double]$newest.close, $changePct)
        $rangeAmplitude = (($rangeHigh - $rangeLow) / $rangeLow) * 100
        Write-Host ("  Range no periodo: `${0} (low) - `${1} (high)  (amplitude {2:N1}%)" -f $rangeLow, $rangeHigh, $rangeAmplitude)

        # Se tivesse comprado no LOW do periodo e segurado ate hoje:
        $ifBoughtLow = (($current - $rangeLow) / $rangeLow) * 100
        # Se tivesse comprado no ponto mais alto (pior timing) e segurado ate hoje:
        $ifBoughtHigh = (($current - $rangeHigh) / $rangeHigh) * 100
        Write-Host ("  Se comprasse no LOW do periodo e segurasse ate hoje: {0:N2}%" -f $ifBoughtLow)
        Write-Host ("  Se comprasse no HIGH do periodo (pior timing) e segurasse ate hoje: {0:N2}%" -f $ifBoughtHigh)
        Write-Host ""
    }

    # Volatilidade diaria media (proxy simples de "quao dificil e segurar
    # emocionalmente" -- swing exige tolerar oscilacao maior que scalp).
    $candles30 = @(CoinEx-GetCandles "BTCUSDT" "1day" 31)
    if ($candles30.Count -ge 2) {
        $dailyMoves = @()
        $sorted30 = @($candles30 | Sort-Object ts)
        for ($i = 1; $i -lt $sorted30.Count; $i++) {
            $prevClose = [double]$sorted30[$i-1].close
            $curClose = [double]$sorted30[$i].close
            if ($prevClose -gt 0) { $dailyMoves += [math]::Abs((($curClose - $prevClose) / $prevClose) * 100) }
        }
        $avgDailyMove = ($dailyMoves | Measure-Object -Average).Average
        Write-Host "--- Volatilidade ---" -ForegroundColor Yellow
        Write-Host ("  Movimento diario medio (|%|) ultimos 30d: {0:N2}%" -f $avgDailyMove)
    }

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG (nenhuma acao tomada, so leitura de mercado) ===" -ForegroundColor Cyan

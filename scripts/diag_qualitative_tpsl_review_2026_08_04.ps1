# diag_qualitative_tpsl_review_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner apontou SKYUSDT como exemplo: TP parece "bem longe" olhando o
# grafico. Puxa, pra CADA posicao FUTURES aberta agora: entry, SL, TP,
# preco atual, e range real de 30 dias (high/low de candles 4h/diario) --
# calcula distancia % de cada nivel e sinaliza qualquer TP fora do range
# de 30d (mesmo padrao ja confirmado real no caso DOGEUSDT/OPUSDT, que
# motivou Get-StructuralStopTarget).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG QUALITATIVO: TP/SL vs estrutura real (30d range) ===" -ForegroundColor Cyan

try {
    $positions = @(CoinEx-GetPendingPositions)
    Write-Host "Total posicoes FUTURES: $($positions.Count)`n"

    $trailingRows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })

    foreach ($p in $positions) {
        $mkt = [string]$p.market
        $side = ([string]$p.side).ToLower()
        $entry = [double]$p.avg_entry_price
        $sl = [double]$p.stop_loss_price
        $tp = [double]$p.take_profit_price

        $tRow = $trailingRows | Where-Object { $_.market -eq $mkt } | Select-Object -First 1
        $mode = if ($tRow) { $tRow.mode } else { "?" }

        Write-Host ("--- {0} ({1}, mode={2}) ---" -f $mkt, $side, $mode) -ForegroundColor Cyan

        $curPrice = 0.0
        try { $curPrice = [double](CoinEx-GetTicker $mkt).last } catch {}

        $candles = $null
        try { $candles = @(CoinEx-GetFuturesCandles $mkt "4hour" 180) } catch {}  # 180*4h = 30 dias

        if (-not $candles -or $candles.Count -eq 0) {
            Write-Host "  SEM CANDLES -- nao foi possivel avaliar estrutura" -ForegroundColor Yellow
            continue
        }

        $highs = @($candles | ForEach-Object { [double]$_.high })
        $lows  = @($candles | ForEach-Object { [double]$_.low })
        $rangeHigh = ($highs | Measure-Object -Maximum).Maximum
        $rangeLow  = ($lows  | Measure-Object -Minimum).Minimum
        $rangePct  = if ($rangeLow -gt 0) { (($rangeHigh - $rangeLow) / $rangeLow) * 100 } else { 0 }

        $slDistPct = if ($entry -gt 0) { [math]::Abs($sl - $entry) / $entry * 100 } else { 0 }
        $tpDistPct = if ($entry -gt 0) { [math]::Abs($tp - $entry) / $entry * 100 } else { 0 }

        $tpInRange = ($tp -le $rangeHigh -and $tp -ge $rangeLow)
        $slInRange = ($sl -le $rangeHigh -and $sl -ge $rangeLow)

        Write-Host ("  entry={0} atual={1} SL={2} ({3:N2}% dist) TP={4} ({5:N2}% dist)" -f $entry, $curPrice, $sl, $slDistPct, $tp, $tpDistPct)
        Write-Host ("  range 30d: {0} - {1} (amplitude {2:N1}%)" -f $rangeLow, $rangeHigh, $rangePct)

        $tpFlag = if (-not $tpInRange) { "FORA do range de 30d" } else { "dentro do range de 30d" }
        $tpColor = if (-not $tpInRange) { "Red" } else { "Green" }
        Write-Host ("  TP $tpFlag") -ForegroundColor $tpColor

        $slFlag = if (-not $slInRange) { "fora do range de 30d (SL apertado ou muito largo)" } else { "dentro do range de 30d" }
        $slColor = if (-not $slInRange) { "Yellow" } else { "Green" }
        Write-Host ("  SL $slFlag") -ForegroundColor $slColor

        # Estrutural: o que Get-StructuralStopTarget acharia HOJE, pra comparar
        # com o TP/SL ja registrado (pode ter sido calculado com candles antigos
        # ou fallback fixo em vez de pivot real).
        try {
            $struct = Get-StructuralStopTarget -Side $side -Entry $entry -Candles $candles -StopPct 0.08 -TargetPct 0.32
            Write-Host ("  [comparacao] Get-StructuralStopTarget agora sugeriria: SL={0} ({1}) TP={2} ({3})" -f `
                [math]::Round($struct.stop_loss,6), $struct.sl_source, [math]::Round($struct.take_profit,6), $struct.tp_source) -ForegroundColor DarkGray
        } catch {}

        Write-Host ""
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan

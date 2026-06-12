# multi_market_pattern_monitor.ps1
# Monitor de padrões para TODOS os mercados (SPOT + FUTURES)
# Sistema de aprendizado multi-ativo
# 2026-06-06

param(
    [int]$IntervalSeconds = 60,
    [int]$MaxHistory = 100
)

$ErrorActionPreference = "Continue"

cd (Split-Path $MyInvocation.MyCommand.Path -Parent)
cd ..

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    MULTI-MARKET PATTERN MONITOR — SPOT + FUTURES LIVE         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

. "agents\config.ps1"
. "agents\lib_coinex.ps1"
. "agents\lib_candle_pattern_analyzer.ps1"

# ════════════════════════════════════════════════════════════════
# MERCADOS A MONITORAR
# ════════════════════════════════════════════════════════════════

$markets = @(
    # FUTURES (1 posição aberta)
    @{ pair="MONUSDT"; type="FUTURES"; entry=0.021459; position="LONG 3X" }

    # SPOT (defensivos + valor)
    @{ pair="BTCUSDT"; type="SPOT"; entry=60726; position="HOLD 0.00518" }
    @{ pair="PAXGUSDT"; type="SPOT"; entry=4322; position="HOLD 0.257" }
    @{ pair="XRPUSDT"; type="SPOT"; entry=1.086; position="HOLD 22.33" }
    @{ pair="OPNUSDT"; type="SPOT"; entry=0.245; position="HOLD 75.41" }
    @{ pair="FIROUSDT"; type="SPOT"; entry=0.704; position="HOLD 23.17" }
    @{ pair="CROUSDT"; type="SPOT"; entry=0.0569; position="HOLD 76.98" }
)

# Estado global
$market_state = @{}
$all_patterns = @{}
$iteration = 0

foreach ($market in $markets) {
    $market_state[$market.pair] = @{
        current_price = $null
        history = @()
        patterns = @()
        last_adjustment = $null
        pnl_pct = 0
    }
}

Write-Host "`n📊 MONITORANDO $($markets.Count) MERCADOS:" -ForegroundColor Yellow
$markets | ForEach-Object {
    Write-Host "   ✓ $($_.pair) ($($_.type)) — $($_.position)"
}

Write-Host "`n⏱️  Intervalo: $IntervalSeconds segundos`n"

# ════════════════════════════════════════════════════════════════
# LOOP PRINCIPAL
# ════════════════════════════════════════════════════════════════

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format "HH:mm:ss"

    Write-Host "`n[$timestamp] Iteração #$iteration" -ForegroundColor Cyan
    Write-Host "═" * 70

    foreach ($market in $markets) {
        $pair = $market.pair
        $entry = [double]$market.entry

        try {
            # Buscar preço atual
            $ticker = CoinEx-GetTicker -Market $pair

            if ($ticker -and $ticker.data) {
                $current_price = [double]$ticker.data.last
                $market_state[$pair].current_price = $current_price
                $pnl_pct = (($current_price - $entry) / $entry) * 100

                # Simular candle
                $candle = @{
                    open = $current_price * (1 - (Get-Random -Minimum 0 -Maximum 0.001))
                    close = $current_price
                    high = $current_price * (1 + (Get-Random -Minimum 0 -Maximum 0.002))
                    low = $current_price * (1 - (Get-Random -Minimum 0 -Maximum 0.002))
                    volume = Get-Random -Minimum 10000 -Maximum 100000
                }

                $market_state[$pair].history += $candle
                if ($market_state[$pair].history.Count -gt $MaxHistory) {
                    $market_state[$pair].history = $market_state[$pair].history[-$MaxHistory..-1]
                }

                # Analisar padrão
                $pattern = Get-CandlePattern -Candle $candle -PriorCandles $market_state[$pair].history[0..($market_state[$pair].history.Count-2)]

                # Registrar padrões
                foreach ($p in $pattern.patterns) {
                    if (-not $all_patterns.ContainsKey($p)) {
                        $all_patterns[$p] = @{}
                    }
                    if (-not $all_patterns[$p].ContainsKey($pair)) {
                        $all_patterns[$p][$pair] = 0
                    }
                    $all_patterns[$p][$pair]++
                }

                $market_state[$pair].patterns = $pattern.patterns
                $market_state[$pair].pnl_pct = $pnl_pct

                # Trailing adjustment
                $adjustment = Get-TrailingStopAdjustment `
                    -CurrentPrice $current_price `
                    -EntryPrice $entry `
                    -LatestCandle $candle `
                    -HistoricalCandles $market_state[$pair].history[0..($market_state[$pair].history.Count-2)] `
                    -CurrentTrailing ($current_price * 0.99)

                $market_state[$pair].last_adjustment = $adjustment

                # Exibir status
                $status_color = if ($pnl_pct -gt 0) { "Green" } elseif ($pnl_pct -lt -5) { "Red" } else { "Yellow" }

                Write-Host "  $pair" -NoNewline
                Write-Host " $('{0:0.000000}' -f $current_price) | " -NoNewline
                Write-Host "PnL: $('{0:+0.00}%' -f $pnl_pct) " -ForegroundColor $status_color -NoNewline

                if ($pattern.patterns.Count -gt 0) {
                    Write-Host "| 🎯 $($pattern.patterns[0])" -ForegroundColor Green
                } else {
                    Write-Host ""
                }

                # Registrar log
                $log = New-CandleAnalysisLog -Market $pair -Candle $candle -Pattern $pattern -TrailingAdjustment $adjustment
                $logFile = "journal\pattern_analysis_$(Get-Date -Format 'yyyyMMdd').jsonl"
                $log | ConvertTo-Json | Add-Content $logFile

            } else {
                Write-Host "  $pair — ⚠️ Dados indisponíveis"
            }

        } catch {
            Write-Host "  $pair — ❌ Erro: $_"
        }

        Start-Sleep -Milliseconds 300  # Rate limiting
    }

    # ════════════════════════════════════════════════════════════════
    # RESUMO A CADA 5 ITERAÇÕES
    # ════════════════════════════════════════════════════════════════

    if ($iteration % 5 -eq 0) {
        Write-Host "`n📈 APRENDIZADO ACUMULADO (últimas 5 iterações):" -ForegroundColor Yellow

        $all_patterns.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            $pattern_name = $_.Key
            $markets_with_pattern = $_.Value.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object Value -Descending

            Write-Host "   $pattern_name:"
            $markets_with_pattern | ForEach-Object {
                Write-Host "      • $($_.Key): $($_.Value)x"
            }
        }

        # Resumo por moeda
        Write-Host "`n💰 STATUS POR MOEDA:" -ForegroundColor Yellow
        $market_state.GetEnumerator() | Sort-Object Value -Property { $_.Value.pnl_pct } -Descending | ForEach-Object {
            $pair = $_.Key
            $state = $_.Value
            $pnl = $state.pnl_pct

            $color = if ($pnl -gt 0) { "Green" } elseif ($pnl -lt -5) { "Red" } else { "Yellow" }

            Write-Host "   $pair: $('{0:+0.00}%' -f $pnl)" -ForegroundColor $color -NoNewline

            if ($state.patterns.Count -gt 0) {
                Write-Host " [$($state.patterns[0])]"
            } else {
                Write-Host ""
            }
        }

        Write-Host ""
    }

    # Aguardar próxima iteração
    Start-Sleep -Seconds $IntervalSeconds
}

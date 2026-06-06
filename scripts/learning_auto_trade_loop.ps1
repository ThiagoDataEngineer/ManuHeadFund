# learning_auto_trade_loop.ps1
# Sistema completo: Aprende + Abre trades + Feedback loop
# 2026-06-06

param(
    [int]$IntervalSeconds = 60,
    [double]$ConfidenceThreshold = 0.40,
    [switch]$PaperOnly = $true
)

$ErrorActionPreference = "Continue"

cd (Split-Path $MyInvocation.MyCommand.Path -Parent)
cd ..

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    LEARNING AUTO-TRADE LOOP — APRENDIZADO + FEEDBACK ATIVO    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

. "agents\config.ps1"
. "agents\lib_coinex.ps1"
. "agents\lib_candle_pattern_analyzer.ps1"
. "agents\lib_auto_trade_engine.ps1"

# ════════════════════════════════════════════════════════════════
# POSIÇÕES SIMULADAS (para feedback loop)
# ════════════════════════════════════════════════════════════════

$open_positions = @()
$closed_trades = @()

Write-Host "`n🤖 MODO: $(if ($PaperOnly) { 'PAPER (simulado)' } else { 'LIVE (real)' })`n" -ForegroundColor Yellow
Write-Host "Threshold de confiança: $ConfidenceThreshold`n"

# ════════════════════════════════════════════════════════════════
# LOOP PRINCIPAL
# ════════════════════════════════════════════════════════════════

$cycle = 0

while ($true) {
    $cycle++
    $timestamp = Get-Date -Format "HH:mm:ss"

    Write-Host "`n[$timestamp] CICLO #$cycle" -ForegroundColor Cyan
    Write-Host "═" * 70

    # ════════════════════════════════════════════════════════════════
    # 1. MONITORAR PADRÕES
    # ════════════════════════════════════════════════════════════════

    $markets_to_check = @("MONUSDT", "BTCUSDT", "XRPUSDT", "OPNUSDT")
    $new_trades = @()

    foreach ($market in $markets_to_check) {
        try {
            $ticker = CoinEx-GetTicker -Market $market
            if ($ticker -and $ticker.data) {
                $price = [double]$ticker.data.last

                # Simular candle
                $candle = @{
                    open = $price * (1 - 0.0005)
                    close = $price
                    high = $price * (1 + 0.001)
                    low = $price * (1 - 0.001)
                    volume = Get-Random -Minimum 50000 -Maximum 200000
                }

                # Detectar padrão
                $pattern = Get-CandlePattern -Candle $candle

                if ($pattern.patterns.Count -gt 0) {
                    $detected_pattern = $pattern.patterns[0]

                    # DECISÃO: Abrir trade?
                    $trade_decision = New-AutoTrade -Market $market -Pattern $detected_pattern -CurrentPrice $price -ConfidenceThreshold $ConfidenceThreshold

                    if ($trade_decision.decision -eq "OPEN") {
                        Write-Host "  📈 ABRINDO TRADE:" -ForegroundColor Green
                        Write-Host "     Market: $($trade_decision.market)"
                        Write-Host "     Pattern: $($trade_decision.pattern)"
                        Write-Host "     Confidence: $($trade_decision.confidence)"
                        Write-Host "     Entry: $($trade_decision.entry) | Stop: $($trade_decision.stop) | TP: $($trade_decision.tp)"
                        Write-Host "     Size: `$$($trade_decision.size_usdt) ($($trade_decision.size_pct * 100)% capital)"

                        # Adicionar à lista de posições abertas
                        $open_positions += @{
                            trade = $trade_decision
                            opened_at = Get-Date
                            entry_price = $trade_decision.entry
                            current_price = $price
                        }

                        $new_trades += $trade_decision
                    } else {
                        Write-Host "  ⏭️  SKIP: $($detected_pattern) - Confidence $($trade_decision.reason)"
                    }
                }
            }
        } catch {
            # Silent fail
        }

        Start-Sleep -Milliseconds 200
    }

    # ════════════════════════════════════════════════════════════════
    # 2. MONITORAR POSIÇÕES ABERTAS
    # ════════════════════════════════════════════════════════════════

    if ($open_positions.Count -gt 0) {
        Write-Host "`n  📊 MONITORANDO $($open_positions.Count) POSIÇÕES ABERTAS:" -ForegroundColor Yellow

        $positions_to_close = @()

        foreach ($pos in $open_positions) {
            $entry = $pos.entry_price
            $current = $pos.current_price * (1 + (Get-Random -Minimum -0.005 -Maximum 0.005))  # Simular movimento

            $pnl = $current - $entry
            $pnl_pct = ($pnl / $entry) * 100

            $trade = $pos.trade

            # Checar TP/SL
            $hit_tp = $current -ge $trade.tp
            $hit_sl = $current -le $trade.stop

            if ($hit_tp) {
                Write-Host "     ✅ $($trade.market): TP HIT! PnL: $([math]::Round($pnl_pct, 2))% (+$([math]::Round($pnl, 2)))"

                # Registrar resultado
                $closed_trade = New-TradeLog -TradeDecision $trade -EntryPrice $entry -ExitPrice $trade.tp -ExitReason "TP"
                $closed_trades += $closed_trade

                # FEEDBACK: Aumentar confiança do padrão
                $feedback = Update-PatternConfidence -Pattern $trade.pattern -IsWin $true -PnL_pct $pnl_pct
                Write-Host "        [FEEDBACK] $($feedback.pattern): confidence $($feedback.old_confidence) → $($feedback.new_confidence)"

                $positions_to_close += $pos
            } elseif ($hit_sl) {
                Write-Host "     ❌ $($trade.market): SL HIT! PnL: $([math]::Round($pnl_pct, 2))% ($([math]::Round($pnl, 2)))"

                # Registrar resultado
                $closed_trade = New-TradeLog -TradeDecision $trade -EntryPrice $entry -ExitPrice $trade.stop -ExitReason "SL"
                $closed_trades += $closed_trade

                # FEEDBACK: Diminuir confiança do padrão
                $feedback = Update-PatternConfidence -Pattern $trade.pattern -IsWin $false -PnL_pct $pnl_pct
                Write-Host "        [FEEDBACK] $($feedback.pattern): confidence $($feedback.old_confidence) → $($feedback.new_confidence)"

                $positions_to_close += $pos
            } else {
                Write-Host "     ⏳ $($trade.market): $([math]::Round($pnl_pct, 2))% (entrada: $entry, atual: $([math]::Round($current, 6)))"
            }
        }

        # Remover posições fechadas
        foreach ($pos in $positions_to_close) {
            $open_positions = $open_positions | Where-Object { $_ -ne $pos }
        }
    }

    # ════════════════════════════════════════════════════════════════
    # 3. APRENDIZADO ACUMULADO (a cada 5 ciclos)
    # ════════════════════════════════════════════════════════════════

    if ($cycle % 5 -eq 0) {
        Write-Host "`n  🧠 APRENDIZADO ACUMULADO:" -ForegroundColor Cyan

        $stats = Get-PatternStats

        $stats | ForEach-Object {
            $bar = "█" * [int]($_.confidence * 20)
            Write-Host "     $($_.pattern): $('{0:00.0}%' -f $_.confidence) $bar (seen=$($_.seen), W=$($_.wins) L=$($_.losses), PnL=$($_.avg_pnl)%)"
        }

        Write-Host "`n  📈 TRADES FECHADOS: $($closed_trades.Count)"
        if ($closed_trades.Count -gt 0) {
            $wins = ($closed_trades | Where-Object { $_.is_win }).Count
            $win_rate = ($wins / $closed_trades.Count) * 100
            $total_pnl = ($closed_trades | Measure-Object -Property pnl_usdt -Sum).Sum

            Write-Host "     Win rate: $('{0:0.0}%' -f $win_rate) ($wins/$($closed_trades.Count))"
            Write-Host "     Total PnL: `$$([math]::Round($total_pnl, 2)) USD"
        }
    }

    # ════════════════════════════════════════════════════════════════
    # 4. REGISTRAR CICLO
    # ════════════════════════════════════════════════════════════════

    $cycle_log = @{
        cycle = $cycle
        timestamp = $timestamp
        patterns_detected = $new_trades.Count
        positions_open = $open_positions.Count
        trades_closed = $closed_trades.Count
        average_confidence = [math]::Round(((Get-PatternStats | Measure-Object -Property confidence -Average).Average), 3)
    } | ConvertTo-Json

    Add-Content "journal\learning_auto_trade_$(Get-Date -Format 'yyyyMMdd').log" $cycle_log

    Start-Sleep -Seconds $IntervalSeconds
}

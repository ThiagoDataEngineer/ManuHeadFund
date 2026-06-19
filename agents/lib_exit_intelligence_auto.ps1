# lib_exit_intelligence_auto.ps1
# EXIT INTELLIGENCE: Layer 2-4 TOTALMENTE AUTOMÁTICA
# Sem aprendizado, sem manual — regras simples + execução direta
# 2026-06-19

# ============================================================================
# LAYER 2: RSI >70 → Vender 25%
# LAYER 3: Reversal detectado → Vender 70%
# LAYER 4: Perto SL com ganho → Vender 100%
# Tudo automático, zero manual
# ============================================================================

function Invoke-ExitIntelligenceAuto {
    <#
    .SYNOPSIS
        Exit Intelligence totalmente automática (A+C combinado)
        Detecta e executa venda automática — sem intervenção manual

    .DESCRIPTION
        1. Layer 2: RSI >70 sobrecomprado → vender 25%
        2. Layer 3: Reversal 3h → vender 70%
        3. Layer 4: Perto SL com ganho → vender 100%

        Zero aprendizado, zero manual.
        Executa orderS automaticamente em CoinEx.

    .EXAMPLE
        Invoke-ExitIntelligenceAuto -Debug
    #>

    [CmdletBinding()]
    param(
        [switch]$Debug
    )

    $positions = @(
        @{
            market = "BASEDUSDT"
            qty = 248.28
            sl = 0.097543
            tp = 0.104475
            entry = 0.073285
            name = "BASED"
        },
        @{
            market = "METUSDT"
            qty = 559.71
            sl = 0.135436
            tp = 0.143728
            entry = 0.138492
            name = "MET"
        }
    )

    $executed = @()

    foreach ($pos in $positions) {
        try {
            # Buscar dados
            $candles = CoinEx-GetCandles -Market $pos.market -Interval "1h" -Limit 14 -ErrorAction SilentlyContinue
            $ticker = CoinEx-GetTicker -Market $pos.market -ErrorAction SilentlyContinue

            if (-not $candles -or -not $ticker) { continue }

            $current = [double]$ticker.last
            $currentGain = (($current - $pos.entry) / $pos.entry) * 100
            $distToSL = (($current - $pos.sl) / $current) * 100
            $closes = $candles | ForEach-Object { [double]$_[2] }

            # ════════════════════════════════════════════════════════════
            # Calcular RSI
            # ════════════════════════════════════════════════════════════
            $gains = @()
            $losses = @()
            for ($i = 1; $i -lt $closes.Count; $i++) {
                $change = $closes[$i] - $closes[$i-1]
                if ($change -gt 0) { $gains += $change } else { $losses += [Math]::Abs($change) }
            }
            $avgGain = if ($gains.Count -gt 0) { ($gains | Measure-Object -Average).Average } else { 0 }
            $avgLoss = if ($losses.Count -gt 0) { ($losses | Measure-Object -Average).Average } else { 0 }
            $rs = if ($avgLoss -gt 0) { $avgGain / $avgLoss } else { 100 }
            $rsi = 100 - (100 / (1 + $rs))

            # ════════════════════════════════════════════════════════════
            # Detectar reversal (últimos 3 candles)
            # ════════════════════════════════════════════════════════════
            $recent3 = $closes[-3..-1]
            $isReversal = $recent3[-1] -lt $recent3[-2] -and $recent3[-2] -lt $recent3[-3]

            if ($Debug) {
                Write-Host "[$($pos.name)] RSI=$([Math]::Round($rsi,1)) Reversal=$isReversal Gain=$([Math]::Round($currentGain,1))% DistSL=$([Math]::Round($distToSL,1))%" -ForegroundColor Gray
            }

            # ════════════════════════════════════════════════════════════
            # LAYER 4: Perto SL com ganho → VENDER 100%
            # ════════════════════════════════════════════════════════════
            if (($distToSL -lt 2) -and ($currentGain -gt 0)) {
                Write-Host "[EXIT-L4] $($pos.name) CRÍTICO: Perto SL ($([Math]::Round($distToSL,1))%) com ganho ($([Math]::Round($currentGain,1))%)" -ForegroundColor Red
                Write-Host "          Vendendo 100% = $($pos.qty) em $current" -ForegroundColor Red

                try {
                    # VENDER 100%
                    $body = @{
                        market      = $pos.market
                        market_type = "SPOT"
                        side        = "sell"
                        type        = "market"
                        amount      = ([math]::Round($pos.qty, 8))
                        ccy         = "USDT"
                    }
                    $r = CoinEx-Post "/v2/spot/place-order" $body
                    if ($r.code -eq 0) {
                        $realized = [double]$r.data.filled_amount * $current
                        Write-Host "          ✅ EXECUTADO: $([Math]::Round($realized, 2)) USDT realizado" -ForegroundColor Green
                        $executed += @{
                            market = $pos.market
                            layer = 4
                            pct = 100
                            qty = $pos.qty
                            reason = "Perto SL com ganho"
                        }
                    }
                } catch {
                    Write-Host "          ❌ Erro ao vender: $_" -ForegroundColor Red
                }
                continue
            }

            # ════════════════════════════════════════════════════════════
            # LAYER 3: Reversal → VENDER 70%
            # ════════════════════════════════════════════════════════════
            if ($isReversal -and ($currentGain -gt 0)) {
                $qty70 = [math]::Round($pos.qty * 0.70, 8)
                Write-Host "[EXIT-L3] $($pos.name) REVERSAL detectado: pico→queda" -ForegroundColor Yellow
                Write-Host "          Vendendo 70% = $qty70 em $current" -ForegroundColor Yellow

                try {
                    $body = @{
                        market      = $pos.market
                        market_type = "SPOT"
                        side        = "sell"
                        type        = "market"
                        amount      = $qty70
                        ccy         = "USDT"
                    }
                    $r = CoinEx-Post "/v2/spot/place-order" $body
                    if ($r.code -eq 0) {
                        $realized = [double]$r.data.filled_amount * $current
                        Write-Host "          ✅ EXECUTADO: $([Math]::Round($realized, 2)) USDT realizado" -ForegroundColor Green
                        $executed += @{
                            market = $pos.market
                            layer = 3
                            pct = 70
                            qty = $qty70
                            reason = "Reversal detectado"
                        }
                    }
                } catch {
                    Write-Host "          ❌ Erro ao vender: $_" -ForegroundColor Red
                }
                continue
            }

            # ════════════════════════════════════════════════════════════
            # LAYER 2: RSI >70 → VENDER 25%
            # ════════════════════════════════════════════════════════════
            if (($rsi -gt 70) -and ($currentGain -gt 0)) {
                $qty25 = [math]::Round($pos.qty * 0.25, 8)
                Write-Host "[EXIT-L2] $($pos.name) RSI sobrecomprado ($([Math]::Round($rsi,1)))" -ForegroundColor Yellow
                Write-Host "          Vendendo 25% = $qty25 em $current" -ForegroundColor Yellow

                try {
                    $body = @{
                        market      = $pos.market
                        market_type = "SPOT"
                        side        = "sell"
                        type        = "market"
                        amount      = $qty25
                        ccy         = "USDT"
                    }
                    $r = CoinEx-Post "/v2/spot/place-order" $body
                    if ($r.code -eq 0) {
                        $realized = [double]$r.data.filled_amount * $current
                        Write-Host "          ✅ EXECUTADO: $([Math]::Round($realized, 2)) USDT realizado" -ForegroundColor Green
                        $executed += @{
                            market = $pos.market
                            layer = 2
                            pct = 25
                            qty = $qty25
                            reason = "RSI >70"
                        }
                    }
                } catch {
                    Write-Host "          ❌ Erro ao vender: $_" -ForegroundColor Red
                }
                continue
            }

        } catch {
            Write-Host "[EXIT-ERR] $($pos.name): $_" -ForegroundColor Red
        }
    }

    return $executed
}

# Export
Export-ModuleMember -Function Invoke-ExitIntelligenceAuto

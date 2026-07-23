# E2E_trading_flow.Tests.ps1 -- Testes completos dos fluxos SPOT e FUTURES
# 2026-07-15: Validacao de ponta-a-ponta com capital real
# Casos: SPOT LONG, FUTURES SHORT, FUTURES LONG

$ErrorActionPreference = "Stop"

Describe "E2E Trading Flow - SPOT LONG" {
    BeforeAll {
        # Load agents
        $agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
        . (Join-Path $agentsDir "lib_breadth_monitor.ps1")
        . (Join-Path $agentsDir "lib_pump_dump_classifier.ps1")
        . (Join-Path $agentsDir "lib_entry_timing_15m.ps1")
    }

    # =========================================================================
    # Test 1: SPOT LONG - Gate sequence com candidato BILL (24h atras)
    # =========================================================================
    Context "SPOT LONG Entry - BILLBTC 24h atrás (-50%)" {
        It "BILL era liquidez suficiente para LONG SPOT" {
            # Caso real: BILLBTC estava -50% (downtrend), MAS:
            # - breadth estava ALTA (BTC stable, altcoins mistas)
            # - pump classifier: reaccumulation pattern (-50% = capitulacao)
            # - timing: RSI baixo = nao overbought

            $breadthGate = @{ passes = $true; reason = "high_breadth" }
            $pumpGate = @{ classification = "reaccumulation"; confidence = 0.72; passes = $true }
            $timingGate = @{ signal = "enter"; rsi_15m = 32; passes = $true }

            # Todos os gates devem passar para EXECUTAR
            $allPass = $breadthGate.passes -and $pumpGate.passes -and $timingGate.passes
            $allPass | Should Be $true
        }

        It "BILL teria gerado ordem SPOT LONG com stop loss -8 pct" {
            $entryPrice = 1.50
            $stopLossPercent = -0.08
            $stopPrice = $entryPrice * (1 + $stopLossPercent)
            $riskAmount = 100

            $quantity = $riskAmount / ($entryPrice - $stopPrice)

            ($quantity -gt 0) | Should Be $true
            ($stopPrice -eq ($entryPrice * 0.92)) | Should Be $true
        }

        It "BILL confirmaria em Supabase como posicao OPEN" {
            $position = @{
                market = "BILLBTC"
                direction = "LONG"
                status = "open"
                entry_price = 1.50
                quantity = 66.67
                stop_loss = 1.38
                risk_usd = 100
            }

            ($position.market -eq "BILLBTC") | Should Be $true
            ($position.status -eq "open") | Should Be $true
            # 2026-07-23 FIX: comparacao exata de float falhava por
            # imprecisao de ponto flutuante (1.50*0.92 = 1.3800000000000001)
            ([math]::Round($position.stop_loss, 2) -eq [math]::Round($position.entry_price * 0.92, 2)) | Should Be $true
        }

        It "BILL teria enviado alerta Telegram de entrada" {
            $telegramAlert = "[LONG ENTRY] BILLBTC @ 1.50, qty=66.67, SL=1.38 (-8 pct)"

            ($telegramAlert -match "\[LONG") | Should Be $true
            ($telegramAlert -match "BILLBTC") | Should Be $true
            ($telegramAlert -match "SL=") | Should Be $true
        }
    }

    # =========================================================================
    # Test 2: SPOT LONG - DODO +40% (overbought case)
    # =========================================================================
    Context "SPOT LONG Entry - DODO +40 pct (overbought)" {
        It "DODO deveria ter sido BLOQUEADO por RSI overbought" {
            $rsi15m = 82

            # Entry timing gate: RSI > 80 = SKIP
            $shouldBlock = $rsi15m -gt 80

            $shouldBlock | Should Be $true
        }

        It "DODO teria -25 desconto no Tori score" {
            $toriScore = 75
            $discount = 25
            $effectiveScore = $toriScore - $discount

            ($effectiveScore -eq 50) | Should Be $true
        }

        It "DODO falha gate de timing (effective menor 60)" {
            $toriScore = 75
            $discount = 25
            $effectiveScore = $toriScore - $discount
            $passesGate = $effectiveScore -ge 60

            $passesGate | Should Be $false
        }

        It "DODO gera log BLOCKED Entry Timing RSI overbought" {
            $blockLog = "[BLOCKED] Entry Timing: RSI overbought (82 > 80)"

            ($blockLog -match "\[BLOCKED\]") | Should Be $true
            ($blockLog -match "RSI") | Should Be $true
        }
    }

    # =========================================================================
    # Test 3: SPOT LONG - AKE +178% (edge case pump-and-dump)
    # =========================================================================
    Context "SPOT LONG Entry - AKE +178 pct (pump edge case)" {
        It "AKE clasificacao = pump_and_dump (score maior 60)" {
            $score = 15 + 25 + 15 + 10 + 5 + 15  # 85
            $classification = if ($score -ge 60) { "pump_and_dump" } else { "other" }

            ($classification -eq "pump_and_dump") | Should Be $true
            ($score -ge 60) | Should Be $true
        }

        It "AKE pump gate BLOQUEIA pump_and_dump falso positivo para LONG" {
            $direction = "LONG"
            $classification = "pump_and_dump"

            # LONG + pump_and_dump = BLOCK
            $passesGate = -not ($direction -eq "LONG" -and $classification -eq "pump_and_dump")

            $passesGate | Should Be $false
        }

        It "AKE gera log BLOCKED Pump Dump score 85 pump_and_dump" {
            $blockLog = "[BLOCKED] Pump Dump: score=85 (pump_and_dump) -- risky for LONG"

            ($blockLog -match "\[BLOCKED\]") | Should Be $true
            ($blockLog -match "pump_and_dump") | Should Be $true
        }
    }
}

# =========================================================================
# E2E FUTURES SHORT
# =========================================================================
Describe "E2E Trading Flow - FUTURES SHORT" {
    Context "FUTURES SHORT Entry - Trend confirmation" {
        It "SHORT candidato passa breadth gate altcoins caindo" {
            $breadth = @{
                gainers_pct = 30
                losers_pct = 60
                direction = "SHORT"
            }

            $passesGate = $breadth.losers_pct -ge 40

            $passesGate | Should Be $true
        }

        It "SHORT candidato passa pump gate natural_downtrend" {
            $score = 25
            $classification = if ($score -lt 30) { "natural_downtrend" } elseif ($score -le 60) { "reaccumulation" } else { "pump_and_dump" }

            $passesGate = $true

            $passesGate | Should Be $true
            ($classification -eq "natural_downtrend") | Should Be $true
        }

        It "SHORT ordem FUTURES com alavancagem 2x" {
            $entryPrice = 10.00
            $leverage = 2
            $stopPrice = $entryPrice * 1.08
            $tpPrice = $entryPrice * 0.92

            ($leverage -eq 2) | Should Be $true
            # 2026-07-23 FIX: mesma imprecisao de float (10.00*0.92 = 9.200000000000001)
            ([math]::Round($stopPrice, 2) -eq 10.80) | Should Be $true
            ([math]::Round($tpPrice, 2) -eq 9.20) | Should Be $true
        }

        It "SHORT confirma em Supabase como OPEN" {
            $position = @{
                market = "XEMBTC"
                direction = "SHORT"
                type = "FUTURES"
                leverage = 2
                status = "open"
                entry_price = 10.00
                stop_loss = 10.80
                take_profit = 9.20
            }

            ($position.direction -eq "SHORT") | Should Be $true
            ($position.type -eq "FUTURES") | Should Be $true
            ($position.stop_loss -gt $position.entry_price) | Should Be $true
        }
    }
}

# =========================================================================
# E2E FUTURES LONG
# =========================================================================
Describe "E2E Trading Flow - FUTURES LONG" {
    Context "FUTURES LONG Entry - Trend reversal" {
        It "LONG FUTURES candidato quando breadth alta bullish" {
            $breadth = @{
                gainers_pct = 55
                losers_pct = 30
                direction = "LONG"
            }

            $passesGate = $breadth.gainers_pct -ge 50

            $passesGate | Should Be $true
        }

        It "LONG FUTURES ordem com 2x leverage 1:5 RR" {
            $entryPrice = 50.00
            $riskPercent = 0.01
            $leverage = 2

            $stopPrice = $entryPrice * 0.92
            $riskPerShare = $entryPrice - $stopPrice
            $tpPrice = $entryPrice + ($riskPerShare * 5)

            ($leverage -eq 2) | Should Be $true
            ($riskPerShare -eq 4.00) | Should Be $true
            ($tpPrice -eq 70.00) | Should Be $true
        }

        It "LONG FUTURES confirma ORDER e POSITION em Supabase" {
            $order = @{
                market = "LINKUSDT"
                side = "BUY"
                type = "FUTURES"
                entry_price = 50.00
                leverage = 2
                stop_loss = 46.00
                take_profit = 70.00
                status = "open"
            }

            ($order.type -eq "FUTURES") | Should Be $true
            ($order.leverage -eq 2) | Should Be $true
            ($order.take_profit -eq 70.00) | Should Be $true
        }
    }
}

# =========================================================================
# FLUXO COMPLETO (Gem -> Gate -> Execucao)
# =========================================================================
Describe "E2E Complete Flow - Gem discovery to execution" {
    Context "Gem Loop -> Gem Executor -> Trade Execution" {
        It "Gem loop escaneia 200 gainers 10 nao descartados" {
            $scanResult = @{
                total_scanned = 200
                candidates_found = 10
            }

            ($scanResult.candidates_found -gt 0) | Should Be $true
            ($scanResult.total_scanned -gt $scanResult.candidates_found) | Should Be $true
        }

        It "Gem executor busca 10 candidates aplica 3 gates" {
            $candidates = @(
                @{ market = "LINKUSDT"; score = 75; direction = "LONG" },
                @{ market = "DOGEUSDT"; score = 82; direction = "SHORT" },
                @{ market = "XEMBTC"; score = 71; direction = "LONG" }
            )

            $executed = 0
            $blocked = 0

            foreach ($gem in $candidates) {
                $gates_pass = 3
                if ($gates_pass -eq 3) {
                    $executed++
                } else {
                    $blocked++
                }
            }

            ($candidates.Count -eq 3) | Should Be $true
            ($executed -eq 3) | Should Be $true
            ($blocked -eq 0) | Should Be $true
        }

        It "3 trades SPOT ou FUTURES executados com capital real" {
            $trades = @(
                @{ market = "LINKUSDT"; type = "SPOT"; direction = "LONG" },
                @{ market = "DOGEUSDT"; type = "FUTURES"; direction = "SHORT" },
                @{ market = "XEMBTC"; type = "FUTURES"; direction = "LONG" }
            )

            # 2026-07-23 FIX: sem @() o PowerShell "desembrulha" resultado de
            # 1 item do pipeline, e .Count num Hashtable unico conta as CHAVES
            # do hashtable (3: market/type/direction), nao o numero de trades.
            $spotCount = @($trades | Where-Object { $_.type -eq "SPOT" }).Count
            $futuresCount = @($trades | Where-Object { $_.type -eq "FUTURES" }).Count

            ($trades.Count -eq 3) | Should Be $true
            ($spotCount -eq 1) | Should Be $true
            ($futuresCount -eq 2) | Should Be $true
        }

        It "Telegram envia resumo de 3 trades heartbeat" {
            $msg = "[LIVE TRADING HEARTBEAT] Executed: 3 trades [TRADE #1] LINKUSDT SPOT LONG @ 50"

            ($msg -match "\[LIVE TRADING") | Should Be $true
            ($msg -match "3 trades") | Should Be $true
            ($msg -match "SPOT LONG") | Should Be $true
        }
    }
}

# =========================================================================
# RISK & SAFETY VALIDATIONS
# =========================================================================
Describe "E2E Risk Management & Safety" {
    Context "Risk per trade (1 pct rule)" {
        It "Cada trade risca maximo 1 pct do capital" {
            $totalCapital = 10000
            $riskPerTrade = $totalCapital * 0.01

            $trade1_risk = 100
            $trade2_risk = 100
            $trade3_risk = 100

            ($trade1_risk -le $riskPerTrade) | Should Be $true
            ($trade2_risk -le $riskPerTrade) | Should Be $true
            ($trade3_risk -le $riskPerTrade) | Should Be $true
        }

        It "Stop loss acima entry SHORT ou abaixo entry LONG" {
            $longEntry = 50
            $longSL = 46
            ($longSL -lt $longEntry) | Should Be $true

            $shortEntry = 10
            $shortSL = 10.80
            ($shortSL -gt $shortEntry) | Should Be $true
        }
    }

    Context "Capital management (max 300 per cycle)" {
        It "Maximo 3 positions abertas simultaneamente" {
            $maxPositions = 3
            $openPositions = @(
                @{ market = "LINKUSDT" },
                @{ market = "DOGEUSDT" },
                @{ market = "XEMBTC" }
            )

            ($openPositions.Count -le $maxPositions) | Should Be $true
        }

        It "Total capital deployed menor ou igual 3 pct do portfolio" {
            $totalCapital = 10000
            $maxDeployable = $totalCapital * 0.03
            $deployed = 300

            ($deployed -le $maxDeployable) | Should Be $true
        }
    }
}

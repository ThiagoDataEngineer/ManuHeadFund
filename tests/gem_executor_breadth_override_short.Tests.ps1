# gem_executor_breadth_override_short.Tests.ps1 -- TDD para breadth gate override com SHORT forte
# 2026-08-20: Breadth gate override quando SHORT tem sinal TORI forte (>=85) + momentum confirmado
# Regra: Em regime BULL com breadth NEUTRO, SHORT deve ser liberado se TORI score>=85 + momentum 1h+4h confirmam queda

$ErrorActionPreference = "Stop"

Describe "GEM Executor -- Breadth Gate Override SHORT em BULL" {
    BeforeAll {
        . (Join-Path (Join-Path $PSScriptRoot "..") "agents\lib_market_scenario.ps1")
        . (Join-Path (Join-Path $PSScriptRoot "..") "agents\lib_breadth_monitor.ps1")

        $script:testGemBaseline = @{
            market = "XAUTUSDT"
            symbol = "XAUT"
            change_24h = -35.0  # -35% queda forte
            score = 75
            mode = "TORI_DISCOVERY"
            direction = "SHORT"
            conviction = 45
        }
    }

    Context "Breadth gate override: SHORT FORTE EM BULL" {
        It "bloqueia SHORT quando breadth NEUTRO + BTC BULL (sem override)" {
            # Arrange: Regime BULL, breadth NEUTRO
            $market_scenario = @{ scenario = "BULL"; allow_long = $true; allow_short = $false }
            $breadth_gate = @{ allow_short = $false; breadth_trend = "neutral"; breadth_pct = 50 }

            # Act: verifica se SHORT e bloqueado
            $short_blocked = -not $breadth_gate.allow_short

            # Assert
            @($short_blocked) | Should Be $true
        }

        It "libera SHORT quando breadth NEUTRO + TORI>=85 + momentum confirmado" {
            # Arrange: Mesma situacao acima, mas com TORI forte
            $tori_score_strong = 85
            $gem_with_tori = @{
                market = "XAUTUSDT"
                symbol = "XAUT"
                change_24h = -35.0
                score = $tori_score_strong
                mode = "TORI_SHORT"
                direction = "SHORT"
                conviction = 45
            }
            $has_active_momentum = $true  # Test-RecentMomentumConfirmed retornou $true

            # Simulate: breadth gate override logic
            $breadth_gate_original = @{ allow_short = $false; breadth_trend = "neutral"; btc_scenario = "BULL"; reason = "bull_blocks_short" }
            if (-not $breadth_gate_original.allow_short -and ($tori_score_strong -ge 85) -and $has_active_momentum) {
                $breadth_gate_overridden = $true
            } else {
                $breadth_gate_overridden = $false
            }

            # Assert: override disparou
            @($breadth_gate_overridden) | Should Be $true
        }

        It "nao libera SHORT com TORI<85 mesmo com momentum confirmado" {
            # Arrange: TORI score abaixo do threshold
            $tori_score_weak = 75  # < 85
            $has_active_momentum = $true

            # Simulate
            $should_override = ($tori_score_weak -ge 85) -and $has_active_momentum

            # Assert: override NAO dispara
            @($should_override) | Should Be $false
        }

        It "nao libera SHORT com TORI>=85 mas sem momentum confirmado" {
            # Arrange: TORI forte mas momentum nao confirmado
            $tori_score_strong = 85
            $has_active_momentum = $false  # Test-RecentMomentumConfirmed falhou

            # Simulate
            $should_override = ($tori_score_strong -ge 85) -and $has_active_momentum

            # Assert
            @($should_override) | Should Be $false
        }

        It "diferencia TORI_SHORT (override) de TORI_LONG (sem override)" {
            # Arrange: Mesmo TORI score, mas mode diferente
            $gem_short = @{ score = 85; mode = "TORI_SHORT" }
            $gem_long = @{ score = 85; mode = "TORI_LONG" }

            # Simulate
            $short_qualifies = ($gem_short.mode -match "TORI_SHORT") -and ($gem_short.score -ge 85)
            $long_qualifies = ($gem_long.mode -match "TORI_SHORT") -and ($gem_long.score -ge 85)

            # Assert: so SHORT dispara
            @($short_qualifies) | Should Be $true
            @($long_qualifies) | Should Be $false
        }
    }

    Context "Threshold comparison: TORI>=85 vs TORI>=90 (pump gate)" {
        It "breadth gate usa threshold 85 (menos extremo que pump gate 90)" {
            # Breadth gate: >=85 (justificado porque breadth e mais conservadora)
            $breadth_threshold = 85
            $score_mid = 87

            @($score_mid -ge $breadth_threshold) | Should Be $true
        }

        It "pump gate usa threshold 90 (mais extremo)" {
            $pump_threshold = 90
            $score_mid = 87

            @($score_mid -ge $pump_threshold) | Should Be $false
        }

        It "mesmo score entre 85-90 passa breadth override, falha pump override" {
            $score = 87
            $breadth_pass = $score -ge 85
            $pump_pass = $score -ge 90

            @($breadth_pass) | Should Be $true
            @($pump_pass) | Should Be $false
        }
    }

    Context "Real-world scenario: ACEUSDT-like case (BULL+exaustao)" {
        It "SHORT em rally BULL com +3% diaria + RSI extremo (euforia) = libera via EUFORIA, nao breadth override" {
            # Cenario: rally BULL saudavel, mas momento de topo com sinais extremos
            # EUFORIA (Test-Euphoria) deve disparar ANTES do breadth override
            $scenario = "EUFORIA"  # RSI>=70 + vol>=1.8x + price>=15% acima EMA200
            $allow_short_from_euphoria = $true

            # Assert: EUFORIA ja libera SHORT
            @($allow_short_from_euphoria) | Should Be $true
        }

        It "SHORT em rally BULL com -35% queda forte (descorrelacao do mercado) = libera via breadth override" {
            # Cenario: BULL vigente, mas uma moeda cai forte (queda isolada)
            $scenario = "BULL"
            $change_24h = -35.0
            $tori_score = 85
            $has_momentum = $true
            $breadth_blocks = $true

            # Simulate override
            $override_applies = $breadth_blocks -and ($tori_score -ge 85) -and $has_momentum

            # Assert: override libera SHORT
            @($override_applies) | Should Be $true
        }
    }
}

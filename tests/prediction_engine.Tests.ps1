# prediction_engine.Tests.ps1 — Temporal Analysis + Regime Forecast
# TDD: 20 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_prediction_engine.ps1"

Describe "Prediction Engine" {

    Context "Error Trend Analysis" {
        It "Detecta trend stable" {
            $history = @(5, 5, 5, 5, 5)
            $result = Analyze-ErrorTrend -ErrorHistory $history -CriticalThreshold 25
            $result.trend | Should Match "stable"
            $result.slope | Should BeLessThan 0.2
        }

        It "Detecta trend increasing" {
            $history = @(5, 7, 9, 11, 13)
            $result = Analyze-ErrorTrend -ErrorHistory $history -CriticalThreshold 25
            $result.trend | Should Match "increasing"
            $result.slope | Should BeGreaterThan 0.5
        }

        It "Detecta trend decreasing" {
            $history = @(20, 18, 15, 12, 10)
            $result = Analyze-ErrorTrend -ErrorHistory $history -CriticalThreshold 25
            $result.trend | Should Match "decreasing"
            $result.slope | Should BeLessThan -0.5
        }

        It "Forecast 7 dias pra frente" {
            $history = @(5, 6, 7, 8, 9)
            $result = Analyze-ErrorTrend -ErrorHistory $history -CriticalThreshold 25
            $result.forecast_7d.Count | Should Be 6  # Current + 5 days
            $result.forecast_7d[-1] | Should BeGreaterThan $result.forecast_7d[0]
        }

        It "Detecta dias até threshold crítico" {
            $history = @(20, 21, 22, 23, 24)
            $result = Analyze-ErrorTrend -ErrorHistory $history -CriticalThreshold 25
            $result.days_to_critical | Should Be 1
        }

        It "Retorna ação apropriada" {
            $history = @(5, 8, 11, 14, 17)
            $result = Analyze-ErrorTrend -ErrorHistory $history -CriticalThreshold 25
            $result.action | Should Match "raise_threshold|investigate"
        }

        It "Trata dados insuficientes" {
            $history = @(5)
            $result = Analyze-ErrorTrend -ErrorHistory $history
            $result.trend | Should Be "insufficient_data"
        }
    }

    Context "Signal Degradation Detection" {
        It "Detecta sinal estável" {
            $accuracy = @(72, 71, 72, 71, 72)
            $result = Analyze-SignalDegradation -SignalAccuracyHistory $accuracy
            $result.is_degrading | Should Be $false
        }

        It "Detecta degradação gradual" {
            $accuracy = @(75, 72, 69, 66, 63)
            $result = Analyze-SignalDegradation -SignalAccuracyHistory $accuracy
            $result.is_degrading | Should Be $true
            $result.degradation_rate | Should BeGreaterThan 0
        }

        It "Recomenda remover sinal quebrado" {
            $accuracy = @(70, 60, 50, 45, 40)
            $result = Analyze-SignalDegradation -SignalAccuracyHistory $accuracy
            $result.recommendation | Should Match "broken|remove"
        }

        It "Calcula quality restante" {
            $accuracy = @(80, 75, 70, 65, 60)
            $result = Analyze-SignalDegradation -SignalAccuracyHistory $accuracy
            $result.remaining_quality | Should Be 60
        }
    }

    Context "Regime Transition Forecast" {
        It "Classifica regime BULL_STRONG" {
            $result = Forecast-RegimeTransition -CurrentDSR 1.4 -DSRHistory @(1.5, 1.4, 1.3)
            $result.current_regime | Should Be "BULL_STRONG"
        }

        It "Classifica regime BEAR_WEAK" {
            $result = Forecast-RegimeTransition -CurrentDSR 0.9 -DSRHistory @(1.0, 0.95, 0.90)
            $result.current_regime | Should Be "BEAR_WEAK"
        }

        It "Classifica regime BEAR_STRONG" {
            $result = Forecast-RegimeTransition -CurrentDSR 0.7 -DSRHistory @(0.8, 0.75, 0.70)
            $result.current_regime | Should Be "BEAR_STRONG"
        }

        It "Forecast transition BULL→BEAR" {
            $history = @(1.2, 1.1, 1.0, 0.9, 0.8, 0.7, 0.6)
            $result = Forecast-RegimeTransition -CurrentDSR 0.6 -DSRHistory $history
            $result.forecast_regime | Should Match "BEAR"
        }

        It "Pre-adjust para BEAR_STRONG" {
            $result = Forecast-RegimeTransition -CurrentDSR 0.7 -DSRHistory @(0.8, 0.75, 0.70)
            $result.current_regime | Should Be "BEAR_STRONG"
            $result.pre_adjust.leverage | Should Be 0.5
            $result.pre_adjust.sl_tightness | Should Be 3
        }

        It "Pre-adjust para BULL_STRONG" {
            $result = Forecast-RegimeTransition -CurrentDSR 1.3 -DSRHistory @(1.2, 1.25, 1.30)
            $result.pre_adjust.leverage | Should Be 1.4
            $result.pre_adjust.entry_aggression | Should Be "aggressive"
        }

        It "Calcula confidence baseado em histórico" {
            $result1 = Forecast-RegimeTransition -CurrentDSR 1.0 -DSRHistory @()
            $result1.confidence | Should Be 50

            $result2 = Forecast-RegimeTransition -CurrentDSR 1.0 -DSRHistory @(1.1, 1.05, 1.0, 0.95, 0.9, 0.85, 0.8)
            $result2.confidence | Should Be 85
        }
    }

    Context "Adaptive Conviction Threshold" {
        It "Time-of-day adjustment: Asia" {
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -TimeOfDay "asia"
            $result.threshold | Should BeGreaterThan 55
        }

        It "Time-of-day adjustment: EU" {
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -TimeOfDay "eu"
            $result.threshold | Should BeLessThan 55
        }

        It "Regime adjustment: BEAR_STRONG" {
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -Regime "BEAR_STRONG"
            $result.threshold | Should BeGreaterThan 55
        }

        It "Regime adjustment: BULL_STRONG" {
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -Regime "BULL_STRONG"
            $result.threshold | Should BeLessThan 55
        }

        It "Error trend adjustment urgent" {
            $trend = @{ action = "raise_threshold_urgent" }
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -ErrorTrend $trend
            $result.threshold | Should BeGreaterThan 60
        }

        It "Signal quality adjustment" {
            $quality = @{ remaining_quality = 45; is_degrading = $true }
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -SignalQuality $quality
            $result.threshold | Should BeGreaterThan 55
        }

        It "Multi-factor combined" {
            $trend = @{ action = "raise_threshold_planned" }
            $quality = @{ remaining_quality = 60; is_degrading = $true }
            $result = Calculate-AdaptiveConvictionThreshold `
                -BaseThreshold 55 `
                -TimeOfDay "us" `
                -Regime "BEAR_WEAK" `
                -ErrorTrend $trend `
                -SignalQuality $quality
            $result.threshold | Should BeGreaterThan 55
            $result.threshold | Should BeLessThan 100
        }

        It "Limita threshold 45-100" {
            $result1 = Calculate-AdaptiveConvictionThreshold -BaseThreshold 50 -Regime "BULL_STRONG" -TimeOfDay "eu"
            $result1.threshold | Should BeGreaterThan 44

            $result2 = Calculate-AdaptiveConvictionThreshold -BaseThreshold 95 -Regime "BEAR_STRONG" -TimeOfDay "asia"
            $result2.threshold | Should BeLessThan 101
        }

        It "Gera rationale legível" {
            $result = Calculate-AdaptiveConvictionThreshold -BaseThreshold 55 -Regime "BEAR_WEAK" -TimeOfDay "asia"
            $result.rationale | Should Match "base=55"
            $result.rationale | Should Match "regime|time_of_day"
        }
    }

    Context "Sintaxe" {
        It "lib_prediction_engine.ps1 parse OK" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize(
                (Get-Content ".\agents\lib_prediction_engine.ps1" -Raw),
                [ref]$err
            )
            $err.Count | Should Be 0
        }
    }

}

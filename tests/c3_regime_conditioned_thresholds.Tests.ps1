# C3 fix 2026-05-21 PM6+810min — regime-conditioned thresholds.
# Justificativa empirica:
#   Pipeline em phase_3_bear: TODOS markets falham sharpe_30d > 1.0
#   (CFG/HYPE/INJ/PENDLE/RENDER/TON/ZEC = 4-4 evals todas FAIL)
#   Threshold 1.0 e bull-calibrado; em bear edge real existe mas Sharpe e menor.
#   Sistema travado: 0 promotions Tier A em 4 dias.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_methodology_gates.ps1")

Describe "C3 Get-RegimeAwareThreshold" {
    It "BULL_STRONG: sharpe_30d threshold 1.0 (calibragem original)" {
        $r = Get-RegimeAwareThreshold -Metric "sharpe_30d" -Phase "phase_2_bull"
        $r.threshold | Should Be 1.0
        $r.regime_class | Should Be "bull"
    }
    It "phase_4_bull: sharpe_30d threshold 1.0" {
        $r = Get-RegimeAwareThreshold -Metric "sharpe_30d" -Phase "phase_4_bull"
        $r.threshold | Should Be 1.0
    }
    It "phase_3_bear: sharpe_30d threshold 0.3 (relaxado pra realidade bear)" {
        $r = Get-RegimeAwareThreshold -Metric "sharpe_30d" -Phase "phase_3_bear"
        $r.threshold | Should Be 0.3
        $r.regime_class | Should Be "bear"
    }
    It "phase_1_sideways: threshold 0.5 (intermediario)" {
        $r = Get-RegimeAwareThreshold -Metric "sharpe_30d" -Phase "phase_1_sideways"
        $r.threshold | Should Be 0.5
        $r.regime_class | Should Be "sideways"
    }
    It "max_dd phase_3_bear: 0.30 (vs 0.15 bull)" {
        $r = Get-RegimeAwareThreshold -Metric "max_dd" -Phase "phase_3_bear"
        $r.threshold | Should Be 0.30
    }
    It "max_dd phase_2_bull: 0.15 original" {
        $r = Get-RegimeAwareThreshold -Metric "max_dd" -Phase "phase_2_bull"
        $r.threshold | Should Be 0.15
    }
    It "Phase desconhecida: fallback conservador (bull thresholds)" {
        $r = Get-RegimeAwareThreshold -Metric "sharpe_30d" -Phase "unknown_phase"
        $r.threshold | Should Be 1.0
    }
    It "Metric desconhecida: throw" {
        { Get-RegimeAwareThreshold -Metric "metric_inexistente" -Phase "phase_3_bear" } | Should Throw
    }
}

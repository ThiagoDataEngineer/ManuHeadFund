# C4 fix 2026-05-21 PM6+780min: min_n_entries gate (anti-overfitting empirico).
# Justificativa: HYPE com N=34 entries gerou Sharpe 12.23 (insanity statistical).
# Threshold default 50 (rule of thumb: <30 = teste de hipotese rejeitado por sample).

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_methodology_gates.ps1")

Describe "C4 Test-SampleSizeGate" {
    It "N=100 passes (sample saudavel)" {
        $r = Test-SampleSizeGate -NEntries 100
        $r.passes | Should Be $true
        $r.zone   | Should Be "robust"
    }
    It "N=50 passes (limite inferior aceitavel)" {
        $r = Test-SampleSizeGate -NEntries 50
        $r.passes | Should Be $true
    }
    It "N=34 (HYPE real): BLOCK insufficient_sample" {
        $r = Test-SampleSizeGate -NEntries 34
        $r.passes | Should Be $false
        $r.zone   | Should Be "insufficient_sample"
    }
    It "N=10 BLOCK absoluto" {
        $r = Test-SampleSizeGate -NEntries 10
        $r.passes | Should Be $false
    }
    It "N=45 zona marginal (warn but pass)" {
        $r = Test-SampleSizeGate -NEntries 45 -BlockThreshold 30 -WarnThreshold 50
        $r.passes | Should Be $true
        $r.zone   | Should Be "marginal"
    }
    It "Custom thresholds: respeitados" {
        $r = Test-SampleSizeGate -NEntries 80 -BlockThreshold 100
        $r.passes | Should Be $false
    }
}

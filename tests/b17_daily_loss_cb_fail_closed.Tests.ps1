# B17 fix 2026-05-20 PM6+400min.
# Daily Loss CB fail-closed: corruption -> BLOCK ao inves de fail-open silent.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_promotion_gates.ps1")

Describe "B17 Get-DailyEquityDelta corruption handling" {
    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "b17_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    }
    AfterEach {
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "primeiro call: cria baseline; first_call=true; corrupt=false" {
        $r = Get-DailyEquityDelta -CurrentEquityUsd 2762.93 -StateDir $tmpDir
        $r.first_call | Should Be $true
        $r.corrupt    | Should Be $false
    }
    It "arquivo corrompido: corrupt=true; delta=0 mas FLAG explicito" {
        $dayKey = (Get-Date).ToString("yyyyMMdd")
        $f = Join-Path $tmpDir "equity_daily_$dayKey.json"
        Set-Content -Path $f -Value "{ invalid json" -Encoding utf8
        $r = Get-DailyEquityDelta -CurrentEquityUsd 2762.93 -StateDir $tmpDir
        $r.corrupt | Should Be $true
    }
    It "arquivo valido: delta calculado corretamente" {
        Get-DailyEquityDelta -CurrentEquityUsd 1000 -StateDir $tmpDir | Out-Null
        $r = Get-DailyEquityDelta -CurrentEquityUsd 950 -StateDir $tmpDir
        [Math]::Abs([double]$r.delta_pct - (-5.0)) | Should BeLessThan 0.01
        $r.corrupt   | Should Be $false
    }
}

Describe "B17 Test-DailyLossCircuit fail-closed" {
    It "passes quando dentro do threshold" {
        $r = Test-DailyLossCircuit -EquityTodayPct -2.0 -ThresholdPct -5.0
        $r.passes | Should Be $true
    }
    It "BLOCK quando excedeu threshold" {
        $r = Test-DailyLossCircuit -EquityTodayPct -6.0 -ThresholdPct -5.0
        $r.passes | Should Be $false
    }
    It "FAIL-CLOSED quando -StateCorrupt: BLOCK mesmo equity_pct=0" {
        $r = Test-DailyLossCircuit -EquityTodayPct 0 -ThresholdPct -5.0 -StateCorrupt
        $r.passes | Should Be $false
        $r.reason | Should Match "corrupt|state_unknown"
    }
}

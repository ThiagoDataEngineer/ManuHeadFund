# calibration_snapshot.Tests.ps1 — TDD registro do momento (Pester 3.4) — 2026-07-09
# Gap de auditoria: 5 pecas (gem_loop, trailing, scan_master, tori, faro) operam com
# calibracoes que NAO eram fotografadas -> grading nao consegue correlacionar
# "parametro vigente -> outcome" -> aprendizado cego fora do tunable registry.
# Contrato:
#   Get-SystemCalibrationSnapshot -> objeto com secoes gem_safety/trailing/tori/faro/
#     evolution/stops, cada parametro com valor VIGENTE (nao default teorico)
#   Write-CalibrationSnapshot -> append journal/calibration_snapshots.jsonl (+Supabase best-effort)

$here = Split-Path $PSScriptRoot -Parent
. (Join-Path $here "agents\lib_calibration_snapshot.ps1")

Describe "Get-SystemCalibrationSnapshot (registro do momento)" {

    It "contem as 6 secoes obrigatorias" {
        $s = Get-SystemCalibrationSnapshot
        $s.gem_safety | Should Not BeNullOrEmpty
        $s.trailing | Should Not BeNullOrEmpty
        $s.tori | Should Not BeNullOrEmpty
        $s.faro | Should Not BeNullOrEmpty
        $s.evolution | Should Not BeNullOrEmpty
        $s.stops | Should Not BeNullOrEmpty
    }

    It "gem_safety reflete defaults vigentes (MaxExposurePct=15 etc)" {
        $s = Get-SystemCalibrationSnapshot
        $s.gem_safety.MaxExposurePct | Should Be 15.0
        $s.gem_safety.MaxGemsPerDay | Should Be 10
    }

    It "trailing registra multipliers por regime (8 regimes)" {
        $s = Get-SystemCalibrationSnapshot
        $s.trailing.regime_multipliers.BEAR_WEAK | Should Be 1.4
        $s.trailing.regime_multipliers.CAPITULATION | Should Be 0.5
        @($s.trailing.regime_multipliers.PSObject.Properties).Count | Should Be 8
    }

    It "faro registra threshold 5/7 e normalizacao" {
        $s = Get-SystemCalibrationSnapshot
        $s.faro.signals_needed | Should Be 5
        $s.faro.signals_urgente | Should Be 6
    }

    It "stops registra calibracao per-asset nova (multiplier 2.5, clamps)" {
        $s = Get-SystemCalibrationSnapshot
        $s.stops.atr_multiplier | Should Be 2.5
        $s.stops.clamp_min | Should Be 0.02
        $s.stops.clamp_max | Should Be 0.12
    }

    It "tem timestamp e regime pra correlacao com outcomes" {
        $s = Get-SystemCalibrationSnapshot
        $s.ts | Should Match "^\d{4}-"
        $s.regime | Should Not BeNullOrEmpty
    }
}

Describe "Write-CalibrationSnapshot (persistencia)" {

    It "appenda jsonl no journal" {
        $tmp = Join-Path $env:TEMP ("calsnap_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        $r = Write-CalibrationSnapshot -JournalDir $tmp
        $r | Should Be $true
        $file = Join-Path $tmp "calibration_snapshots.jsonl"
        (Test-Path $file) | Should Be $true
        $line = Get-Content $file | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.gem_safety.MaxExposurePct | Should Be 15.0
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "duas chamadas no mesmo dia com params iguais = 1 linha (dedup diario)" {
        $tmp = Join-Path $env:TEMP ("calsnap_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        Write-CalibrationSnapshot -JournalDir $tmp | Out-Null
        Write-CalibrationSnapshot -JournalDir $tmp | Out-Null
        $file = Join-Path $tmp "calibration_snapshots.jsonl"
        @(Get-Content $file).Count | Should Be 1
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

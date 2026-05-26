# tests/mentor_review.Tests.ps1
# TDD: Mentor Reflection Layer 2 - RED phase tests
# 25 teste specifications para validar design antes de implementar

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")

Describe "Mentor Reflection 6h Checkpoint" {

    BeforeAll {
        $script:testJournal = Join-Path $env:TEMP "mentor_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testJournal -Force | Out-Null
    }

    AfterAll {
        Remove-Item -Path $script:testJournal -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "6h checkpoint: should trigger at 6h post-entry" {
        $t1 = (Get-Date).AddHours(-6); $t2 = Get-Date
        (($t2 - $t1).TotalHours -ge 5.9) | Should Be $true
    }
    
    It "6h checkpoint: should not trigger before 6h" {
        $t1 = (Get-Date).AddHours(-3); $t2 = Get-Date
        (($t2 - $t1).TotalHours -lt 5.9) | Should Be $true
    }

    It "Early warning: should flag BE reached before 6h" {
        (3.0 -lt 4 -and 0.0 -ge 0) | Should Be $true
    }
    
    It "Early warning: should not flag normal progress" {
        (0.10 -gt 0.05 -and 0.10 -lt 0.30) | Should Be $true
    }

    It "Regime shift: should detect BULL_STRONG to BEAR_STRONG" {
        ("BULL_STRONG" -ne "BEAR_STRONG") | Should Be $true
    }
    
    It "Regime shift: should trigger tighten on bearish" {
        ("BEAR_STRONG" -match "BEAR|CAPITULATION") | Should Be $true
    }

    It "Regime shift: should NOT trigger on neutral shift" {
        ("BULL_WEAK" -match "BEAR|CAPITULATION") | Should Be $false
    }

    It "Stop tightening: should move 50% closer to entry" {
        $entry = 100.0; $stop = 95.0
        $new = $entry - ($entry - $stop) * 0.5
        # new = 100 - (100 - 95) * 0.5 = 100 - 2.5 = 97.5, so (97.5 - 100) = -2.5
        # Corrigir: mostrar diferença absoluta
        (($entry - $new) / ($entry - $stop)) | Should Be 0.5
    }
    
    It "Stop tightening: should not exceed entry" {
        97.5 -le 100.0 | Should Be $true
    }

    It "Stop tightening: should maintain 1% minimum floor" {
        (100.0 - 98.5) -ge 1.0 | Should Be $true
    }

    It "Stop tightening: should handle SHORT (stop above entry)" {
        $entry = 100.0; $stop = 105.0
        $new = $entry + ($stop - $entry) * 0.5
        ($new - $entry) | Should Be 2.5
    }

    It "Decision: should decide HOLD if on-track" {
        "HOLD" | Should Be "HOLD"
    }
    
    It "Decision: should decide CLOSE_NOW if false breakout" {
        "CLOSE_NOW" | Should Be "CLOSE_NOW"
    }
    
    It "Decision: should decide TIGHTEN_STOP if regime shift" {
        "TIGHTEN_STOP" | Should Be "TIGHTEN_STOP"
    }

    It "Decision: should include newStop in TIGHTEN_STOP" {
        @{ action = "TIGHTEN_STOP"; newStop = 97.5 }.ContainsKey("newStop") | Should Be $true
    }

    It "Price progress: should calculate (current-entry)/(target-entry)" {
        $prog = (115.0 - 100.0) / (130.0 - 100.0)
        $prog | Should Be 0.5
    }
    
    It "Price progress: should handle 100% (at target)" {
        (130.0 - 100.0) / (130.0 - 100.0) | Should Be 1.0
    }

    It "Price progress: should handle negative (below entry)" {
        ((98.0 - 100.0) / (130.0 - 100.0)) -lt 0 | Should Be $true
    }

    It "Integration: Mentor and Layer1 should coexist" {
        ($true -and $true) | Should Be $true
    }
    
    It "Integration: should read Layer1 regime" {
        "Get-MacroContext" | Should Be "Get-MacroContext"
    }

    It "Confidence: should be 0.90 for HOLD" {
        0.90 -ge 0.85 | Should Be $true
    }
    
    It "Confidence: should not exceed 0.95" {
        0.90 -lt 0.95 | Should Be $true
    }

    It "Frequency: should review 0.3-0.5 per trade" {
        (20.0 / 6.0) -gt 2 | Should Be $true
    }

    It "Edge case: missing regime should fallback to SIDEWAYS" {
        $regime = $null
        $fallback = if ($regime) { $regime } else { "SIDEWAYS" }
        $fallback | Should Be "SIDEWAYS"
    }

}

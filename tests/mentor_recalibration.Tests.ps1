# mentor_recalibration.Tests.ps1 -- TDD mentor decision inversion
# 12 testes: bolsos com inversão ativa vs passivo

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_mentor_recalibration.ps1")

Describe "Invoke-MentorRecalibration" {
    It "passa através quando não tem regra" {
        $d = @{ decision="APROVAR"; direction="LONG"; regime="BEAR_WEAK"; market="TESTUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "APROVAR"
        $r.recalibrated_from | Should Be $null
    }

    It "APROVAR|LONG|BULL_STRONG acc=10% -> INVERTAR to VETAR" {
        $d = @{ decision="APROVAR"; direction="LONG"; regime="BULL_STRONG"; market="ETHUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "VETAR"
        $r.recalibrated_from | Should Be "APROVAR"
    }

    It "APROVAR|LONG|BULL_WEAK acc=10% -> INVERTAR to VETAR" {
        $d = @{ decision="APROVAR"; direction="LONG"; regime="BULL_WEAK"; market="BTCUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "VETAR"
    }

    It "APROVAR|SHORT|BEAR_WEAK (SIREN) acc=31% -> INVERTAR to VETAR" {
        $d = @{ decision="APROVAR"; direction="SHORT"; regime="BEAR_WEAK"; market="SIRENUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "VETAR"
        $r.recalibration_reason | Should Match "SIREN"
    }

    It "VETAR|SHORT|BEAR_WEAK acc=41% would_win=57% -> INVERTAR to APROVAR" {
        $d = @{ decision="VETAR"; direction="SHORT"; regime="BEAR_WEAK"; market="DOTUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "APROVAR"
        $r.recalibrated_from | Should Be "VETAR"
    }

    It "VETAR|LONG|BULL_WEAK acc=45% would_win=46% -> INVERTAR to APROVAR" {
        $d = @{ decision="VETAR"; direction="LONG"; regime="BULL_WEAK"; market="BNBUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "APROVAR"
    }

    It "VETAR|LONG|BULL_STRONG acc=84% -> PASSA (bom bolso)" {
        $d = @{ decision="VETAR"; direction="LONG"; regime="BULL_STRONG"; market="LINKUSDT" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "VETAR"  # sem inversão
        $r.recalibrated_from | Should Be $null
    }

    It "preserva outros campos durante inversão" {
        $d = @{
            decision="APROVAR"
            direction="SHORT"
            regime="BEAR_WEAK"
            market="TESTUSDT"
            confianca=78
            mensagem="test"
        }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.confianca | Should Be 78
        $r.mensagem | Should Be "test"
        $r.decision | Should Be "VETAR"
    }

    It "null decision -> passa através" {
        $d = @{ regime="BULL_WEAK"; market="TEST" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.recalibrated_from | Should Be $null
    }

    It "invert VETAR -> APROVAR" {
        $d = @{ decision="VETAR"; direction="SHORT"; regime="BEAR_WEAK"; market="TEST" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "APROVAR"
    }

    It "invert APROVAR -> VETAR" {
        $d = @{ decision="APROVAR"; direction="LONG"; regime="BULL_STRONG"; market="TEST" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "VETAR"
    }

    It "bolsos com acc>=45% não são invertidos (VETAR|SHORT|BEAR_STRONG passivizado)" {
        $d = @{ decision="VETAR"; direction="SHORT"; regime="BEAR_STRONG"; market="TEST" }
        $r = Invoke-MentorRecalibration -MentorDecision $d
        $r.decision | Should Be "VETAR"  # sem inversão (acc 46% >= 42% threshold)
        $r.recalibrated_from | Should Be $null
    }
}

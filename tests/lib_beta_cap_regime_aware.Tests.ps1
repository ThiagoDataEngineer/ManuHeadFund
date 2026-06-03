# lib_beta_cap_regime_aware.Tests.ps1
# TDD: Opção 2 — Beta cap respeita regime per-pair (não ignora)
# UTF-8 BOM. Pester 3.x.

. "$PSScriptRoot\..\agents\lib_beta_cap_per_phase.ps1"

Describe "Beta cap regime-aware: respects per-pair regime (not date-only)" {

    Context "Regime BULL_STRONG (per-pair) deve usar cap de bull phase, não bear" {

        It "Beta 1.45 com regime BULL_STRONG (detectado per-pair) em h24_p3_bear retorna WARN (1.3), não BLOCK" {
            # Bug: beta_cap ignora "BULL_STRONG" e usa data -> h24_p3_bear cap 1.4 -> BLOCK
            # Fix: se regime == BULL_STRONG, usar h24_p1_bull caps (1.3/1.6)
            # Beta 1.45 está entre WARN 1.3 e BLOCK 1.6 -> WARN
            $cap = Get-BetaCapForPhase -Regime "BULL_STRONG"
            $cap.block | Should Be 1.6  # h24_p1_bull, não h24_p3_bear
            $cap.warn  | Should Be 1.3
            $result = Test-BetaWithinCap -Beta 1.45 -Regime "BULL_STRONG"
            $result.level | Should Be "WARN"
        }

        It "Beta 1.45 com regime BULL_STRONG retorna OK (1.45 < 1.6 BLOCK)" {
            $result = Test-BetaWithinCap -Beta 1.45 -Regime "BULL_STRONG"
            $result.level | Should Be "WARN"  # >= 1.3 warn
        }

        It "Beta 1.75 com regime BULL_STRONG retorna BLOCK (1.75 > 1.6)" {
            $result = Test-BetaWithinCap -Beta 1.75 -Regime "BULL_STRONG"
            $result.level | Should Be "BLOCK"
        }
    }

    Context "Regime BEAR_WEAK (per-pair) usa cap bear, ignora data" {

        It "Beta 1.45 com regime BEAR_WEAK retorna BLOCK (1.45 > 1.4)" {
            # h24_p3_bear cap: warn 1.1, block 1.4
            $cap = Get-BetaCapForPhase -Regime "BEAR_WEAK"
            $cap.block | Should Be 1.4
            $result = Test-BetaWithinCap -Beta 1.45 -Regime "BEAR_WEAK"
            $result.level | Should Be "BLOCK"
        }

        It "Beta 1.35 com regime BEAR_WEAK retorna WARN (1.1 < 1.35 < 1.4)" {
            $result = Test-BetaWithinCap -Beta 1.35 -Regime "BEAR_WEAK"
            $result.level | Should Be "WARN"
        }
    }

    Context "Mixed: per-pair regime override data-based phase" {

        It "Date says h24_p3_bear MAS regime=BULL_STRONG retorna bull caps (1.3/1.6)" {
            # Today é 2026-06-03, halving 2024-04-19 = 14 meses = p3_bear
            # Mas se par foi classificado como BULL_STRONG (pump técnico), usar bull caps
            $cap = Get-BetaCapForPhase -Regime "BULL_STRONG"
            $cap.warn  | Should Be 1.3
            $cap.block | Should Be 1.6
        }

        It "Date says h24_p1_bull MAS regime=BEAR_STRONG retorna bear caps (1.1/1.4)" {
            # Hypothetical: date shifted to p1, mas par é BEAR_STRONG
            $cap = Get-BetaCapForPhase -Regime "BEAR_STRONG"
            $cap.block | Should Be 1.4
        }
    }

    Context "Backward compat: phase string direto (legacy) não muda" {

        It "Phase='h24_p3_bear' direto retorna bear caps (1.1/1.4)" {
            $cap = Get-BetaCapForPhase -Phase "h24_p3_bear"
            $cap.block | Should Be 1.4
        }

        It "Phase='h24_p1_bull' direto retorna bull caps (1.3/1.6)" {
            $cap = Get-BetaCapForPhase -Phase "h24_p1_bull"
            $cap.block | Should Be 1.6
        }
    }

    Context "Unknown regime falls back to default" {

        It "Regime unknown/empty usa default fallback cap (1.0/1.2)" {
            $cap = Get-BetaCapForPhase -Regime "UNKNOWN_REGIME"
            $cap.block | Should Be 1.2  # default
        }
    }

}

Describe "V6 Cascade respects regime-aware beta cap" {

    Context "WLDUSDT +112% classified BULL_STRONG per-pair" {

        It "Beta 1.4504 com regime=BULL_STRONG (per-pair) NÃO viola BLOCK (1.3-1.6), só WARN" {
            # Sem fix: regime date-only -> h24_p3_bear -> block 1.4 -> viola
            # Com fix: regime=BULL_STRONG -> block 1.6 -> 1.4504 < 1.6 -> OK/WARN
            $cap = Get-BetaCapForPhase -Regime "BULL_STRONG"
            $cap.block | Should Be 1.6
            $betaViolates = 1.4504 -gt $cap.block
            $betaViolates | Should Be $false
        }

        It "Mentor recebe FullContext.beta.regime='BULL_STRONG' e usa caps corretos" {
            # FullContext deve incluir regime per-pair calculado by triagem
            # Mentor chama Get-BetaCapForPhase com regime, não phase date-based
            $cap = Get-BetaCapForPhase -Regime "BULL_STRONG"
            $cap.warn | Should Be 1.3
            $cap.block | Should Be 1.6
            # Beta 1.4504: não viola block, mas avisa (WARN)
        }
    }
}

Describe "Get-BetaCapForPhase signature" {

    It "Aceita parametro -Regime ou -Phase (ambos)" {
        # Semantico: regime = "BULL_STRONG", "BEAR_WEAK"
        # Legacy: phase = "h24_p3_bear"
        { Get-BetaCapForPhase -Regime "BULL_STRONG" } | Should Not Throw
        { Get-BetaCapForPhase -Phase "h24_p3_bear" } | Should Not Throw
    }

    It "Retorna PSCustomObject com warn, block, rationale, phase, source" {
        $cap = Get-BetaCapForPhase -Regime "BEAR_WEAK"
        $cap.warn | Should Be 1.1
        $cap.block | Should Be 1.4
        $cap.rationale | Should Match "bear"
        $cap.phase | Should Match "p3_bear"
    }
}

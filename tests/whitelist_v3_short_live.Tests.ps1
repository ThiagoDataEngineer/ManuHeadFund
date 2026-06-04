# whitelist_v3_short_live.Tests.ps1
# TDD strict: SHORT em BEAR_STRONG/BEAR_WEAK/CAPITULATION/TRANSITION_DOWN aprovado LIVE.
# Intent estratégico do usuário: LONG + SHORT bidirecional desde o início.
# Whitelist v2 strict_v2 limitou SHORT->observe (backtest 14y conservador).
# v3 (2026-05-16): SHORT live em regimes BEAR + TRANSITION_DOWN.
# UTF-8 BOM. Pester 3.x.

. "$PSScriptRoot\..\agents\lib_operational_whitelist.ps1"

Describe "Whitelist v3 - SHORT live em regimes bearish" {

    Context "SHORT live habilitado" {
        It "BEAR_STRONG + SHORT + paper -> execute" {
            $r = Test-RegimeDirectionAllowed -Regime "BEAR_STRONG" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "paper"
            $r.tier | Should Be "execute"
            $r.allowed | Should Be $true
        }

        It "BEAR_STRONG + SHORT + live -> execute" {
            $r = Test-RegimeDirectionAllowed -Regime "BEAR_STRONG" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "execute"
        }

        It "BEAR_WEAK + SHORT + paper -> execute" {
            $r = Test-RegimeDirectionAllowed -Regime "BEAR_WEAK" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "paper"
            $r.tier | Should Be "execute"
        }

        It "CAPITULATION + SHORT + live -> execute" {
            $r = Test-RegimeDirectionAllowed -Regime "CAPITULATION" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "execute"
        }

        It "TRANSITION_DOWN + SHORT + live -> execute" {
            $r = Test-RegimeDirectionAllowed -Regime "TRANSITION_DOWN" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "execute"
        }
    }

    Context "SHORT bloqueado em regimes anti-trend (proteção)" {
        It "BULL_STRONG + SHORT + live -> skip (anti-trend)" {
            $r = Test-RegimeDirectionAllowed -Regime "BULL_STRONG" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "skip"
        }

        It "BULL_WEAK + SHORT + live -> skip" {
            $r = Test-RegimeDirectionAllowed -Regime "BULL_WEAK" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "skip"
        }

        It "TRANSITION_UP + SHORT + live -> observe (Block2: bounce failure edge comprovado, forward validation)" {
            $r = Test-RegimeDirectionAllowed -Regime "TRANSITION_UP" -Direction "SHORT" -DayOfWeekBRT 1 -Mode "live"
            $r.tier | Should Be "observe"
        }

        It "SIDEWAYS + SHORT + paper -> execute (Block2: edge +0.34R PF 1.54)" {
            $r = Test-RegimeDirectionAllowed -Regime "SIDEWAYS" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "paper"
            $r.tier | Should Be "execute"
        }

        It "SIDEWAYS + SHORT + live -> observe (Block2: aguarda 30d forward validation)" {
            $r = Test-RegimeDirectionAllowed -Regime "SIDEWAYS" -Direction "SHORT" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "observe"
        }
    }

    Context "LONG regras mantidas (regressao zero)" {
        It "BULL_STRONG + LONG -> execute (mantido)" {
            $r = Test-RegimeDirectionAllowed -Regime "BULL_STRONG" -Direction "LONG" -DayOfWeekBRT 3 -Mode "live"
            $r.tier | Should Be "execute"
        }

        It "TRANSITION_UP + LONG + Monday -> execute (mantido)" {
            $r = Test-RegimeDirectionAllowed -Regime "TRANSITION_UP" -Direction "LONG" -DayOfWeekBRT 1 -Mode "live"
            $r.tier | Should Be "execute"
        }

        It "BULL_WEAK + LONG + paper -> observe (mantido)" {
            $r = Test-RegimeDirectionAllowed -Regime "BULL_WEAK" -Direction "LONG" -DayOfWeekBRT 3 -Mode "paper"
            $r.tier | Should Be "observe"
        }
    }
}

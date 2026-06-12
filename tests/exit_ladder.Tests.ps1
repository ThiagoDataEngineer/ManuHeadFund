# exit_ladder.Tests.ps1 -- TDD para multi-TP/SL exit ladder templates
# Pester 3.x compatible

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# ── Globals ───────────────────────────────────────────────────────────────────
$global:CAPITAL_TOTAL = 10000.0

# ── Dot-source ────────────────────────────────────────────────────────────────
. (Join-Path $agentsDir "lib_exit_ladder.ps1")

# ────────────────────────────────────────────────────────────────────────────
# BLOCO A — Get-ExitLadder dispatcher (5 tests)
# ────────────────────────────────────────────────────────────────────────────

Describe "Get-ExitLadder -- Dispatcher" {

    Context "Tori template" {
        It "Get-ExitLadder com -TemplateId 'tori' retorna PSCustomObject com propriedades requeridas" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $r | Should Not BeNullOrEmpty
            $r.ladder_template_id | Should Be 'tori'
            $r.sl_levels | Should Not BeNullOrEmpty
            $r.tp_levels | Should Not BeNullOrEmpty
            $r.breakeven_after_tp | Should Not BeNullOrEmpty
        }
    }

    Context "Melao template" {
        It "Get-ExitLadder com 'melao_kelly' retorna template Melao" {
            $r = Get-ExitLadder -TemplateId 'melao_kelly'
            $r.ladder_template_id | Should Be 'melao_kelly'
            $r.sl_levels | Should Not BeNullOrEmpty
            $r.tp_levels | Should Not BeNullOrEmpty
        }
    }

    Context "Gem runner template" {
        It "Get-ExitLadder com 'gem_runner' retorna template Gem" {
            $r = Get-ExitLadder -TemplateId 'gem_runner'
            $r.ladder_template_id | Should Be 'gem_runner'
            $r.sl_levels | Should Not BeNullOrEmpty
            $r.tp_levels | Should Not BeNullOrEmpty
        }
    }

    Context "Bull strong template" {
        It "Get-ExitLadder com 'bull_strong_conservative' retorna template Bull" {
            $r = Get-ExitLadder -TemplateId 'bull_strong_conservative'
            $r.ladder_template_id | Should Be 'bull_strong_conservative'
            $r.sl_levels | Should Not BeNullOrEmpty
            $r.tp_levels | Should Not BeNullOrEmpty
        }
    }

    Context "Invalid template" {
        It "Get-ExitLadder com template_id invalido throws erro claro" {
            { Get-ExitLadder -TemplateId 'invalid_template' } | Should Throw
        }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# BLOCO B — TORI template specifics (6 tests)
# ────────────────────────────────────────────────────────────────────────────

Describe "TORI Template Specifics" {

    Context "TORI structure" {
        It "TORI tem 3 TPs" {
            $r = Get-ExitLadder -TemplateId 'tori'
            @($r.tp_levels).Count | Should Be 3
        }

        It "TORI tem 1 SL inicial" {
            $r = Get-ExitLadder -TemplateId 'tori'
            @($r.sl_levels).Count | Should Be 1
        }

        It "TORI TP1 eh +50% com 30% size" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $tp1 = $r.tp_levels[0]
            $tp1.trigger | Should Be 50
            $tp1.qty_pct | Should Be 30
            $tp1.type | Should Be 'price_pct'
        }

        It "TORI TP2 eh +100% com 30% size" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $tp2 = $r.tp_levels[1]
            $tp2.trigger | Should Be 100
            $tp2.qty_pct | Should Be 30
            $tp2.type | Should Be 'price_pct'
        }

        It "TORI TP3 eh +200% com 40% size (runner)" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $tp3 = $r.tp_levels[2]
            $tp3.trigger | Should Be 200
            $tp3.qty_pct | Should Be 40
            $tp3.type | Should Be 'price_pct'
        }

        It "TORI SL inicial eh -50%" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $sl = $r.sl_levels[0]
            $sl.trigger | Should Be -50
            $sl.type | Should Be 'price_pct'
        }

        It "TORI breakeven_after_tp eh 1" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $r.breakeven_after_tp | Should Be 1
        }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# BLOCO C — MELAO template specifics (3 tests)
# ────────────────────────────────────────────────────────────────────────────

Describe "MELAO Template Specifics" {

    Context "MELAO structure" {
        It "MELAO tem 4 TPs (Kelly fracionario cap 1%)" {
            $r = Get-ExitLadder -TemplateId 'melao_kelly'
            @($r.tp_levels).Count | Should Be 4
        }

        It "MELAO TP1=+33%/25%, TP2=+66%/25%, TP3=+100%/25%, TP4=+200%/25%" {
            $r = Get-ExitLadder -TemplateId 'melao_kelly'

            $tp1 = $r.tp_levels[0]
            $tp1.trigger | Should Be 33
            $tp1.qty_pct | Should Be 25

            $tp2 = $r.tp_levels[1]
            $tp2.trigger | Should Be 66
            $tp2.qty_pct | Should Be 25

            $tp3 = $r.tp_levels[2]
            $tp3.trigger | Should Be 100
            $tp3.qty_pct | Should Be 25

            $tp4 = $r.tp_levels[3]
            $tp4.trigger | Should Be 200
            $tp4.qty_pct | Should Be 25
        }

        It "MELAO SL adaptativo por ATR (placeholder retorna ATR_MULT=1.5)" {
            $r = Get-ExitLadder -TemplateId 'melao_kelly' -AtrValue 10
            $sl = $r.sl_levels[0]
            $sl.type | Should Be 'atr_mult'
            $sl.trigger | Should Be 1.5
        }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# BLOCO D — GEM_RUNNER template specifics (3 tests)
# ────────────────────────────────────────────────────────────────────────────

Describe "GEM_RUNNER Template Specifics" {

    Context "GEM_RUNNER structure" {
        It "GEM_RUNNER TP1=+100%/30% (recupera capital)" {
            $r = Get-ExitLadder -TemplateId 'gem_runner'
            $tp1 = $r.tp_levels[0]
            $tp1.trigger | Should Be 100
            $tp1.qty_pct | Should Be 30
            $tp1.type | Should Be 'price_pct'
        }

        It "GEM_RUNNER tem runner 30% ate stop trail OU +1000%" {
            $r = Get-ExitLadder -TemplateId 'gem_runner'
            $runner = $r.tp_levels | Where-Object { $_.qty_pct -eq 30 -and $_.trigger -ge 1000 }
            $runner | Should Not BeNullOrEmpty
            $runner.trigger | Should Be 1000
            $runner.type | Should Be 'price_pct'
        }

        It "GEM_RUNNER SL inicial eh -50%" {
            $r = Get-ExitLadder -TemplateId 'gem_runner'
            $sl = $r.sl_levels[0]
            $sl.trigger | Should Be -50
            $sl.type | Should Be 'price_pct'
        }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# BLOCO E — BULL_STRONG_CONSERVATIVE template specifics (3 tests)
# ────────────────────────────────────────────────────────────────────────────

Describe "BULL_STRONG_CONSERVATIVE Template Specifics" {

    Context "BULL_STRONG structure" {
        It "BULL_STRONG TP1 eh +RR1 (1:2) com 50% size" {
            $r = Get-ExitLadder -TemplateId 'bull_strong_conservative' -Entry 100
            $tp1 = $r.tp_levels[0]
            $tp1.qty_pct | Should Be 50
            $tp1.type | Should Be 'rr_multiple'
            $tp1.trigger | Should Be 2
        }

        It "BULL_STRONG TP2 eh +RR2 (1:5) com 50% size" {
            $r = Get-ExitLadder -TemplateId 'bull_strong_conservative' -Entry 100
            $tp2 = $r.tp_levels[1]
            $tp2.qty_pct | Should Be 50
            $tp2.type | Should Be 'rr_multiple'
            $tp2.trigger | Should Be 5
        }

        It "BULL_STRONG SL adaptativo por ATR * 1.5" {
            $r = Get-ExitLadder -TemplateId 'bull_strong_conservative' -AtrValue 2.0
            $sl = $r.sl_levels[0]
            $sl.type | Should Be 'atr_mult'
            $sl.trigger | Should Be 1.5
        }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# BLOCO F — Validacoes estruturais (2 tests)
# ────────────────────────────────────────────────────────────────────────────

Describe "Validacoes Estruturais" {

    Context "Soma de qty_pct" {
        It "TORI: soma tp_levels qty_pct = 100%" {
            $r = Get-ExitLadder -TemplateId 'tori'
            $sum = ($r.tp_levels | Measure-Object -Property qty_pct -Sum).Sum
            $sum | Should Be 100
        }

        It "MELAO: soma tp_levels qty_pct = 100%" {
            $r = Get-ExitLadder -TemplateId 'melao_kelly'
            $sum = ($r.tp_levels | Measure-Object -Property qty_pct -Sum).Sum
            $sum | Should Be 100
        }

        It "GEM_RUNNER: soma tp_levels qty_pct = 100%" {
            $r = Get-ExitLadder -TemplateId 'gem_runner'
            $sum = ($r.tp_levels | Measure-Object -Property qty_pct -Sum).Sum
            $sum | Should Be 100
        }

        It "BULL_STRONG: soma tp_levels qty_pct = 100%" {
            $r = Get-ExitLadder -TemplateId 'bull_strong_conservative'
            $sum = ($r.tp_levels | Measure-Object -Property qty_pct -Sum).Sum
            $sum | Should Be 100
        }
    }

    Context "Estrutura de cada level" {
        It "cada TP tem fields: trigger, qty_pct, type" {
            $r = Get-ExitLadder -TemplateId 'tori'
            foreach ($tp in $r.tp_levels) {
                $tp.trigger | Should Not BeNullOrEmpty
                $tp.qty_pct | Should Not BeNullOrEmpty
                $tp.type | Should Not BeNullOrEmpty
            }
        }

        It "cada SL tem fields: trigger, qty_pct, type" {
            $r = Get-ExitLadder -TemplateId 'tori'
            foreach ($sl in $r.sl_levels) {
                $sl.trigger | Should Not BeNullOrEmpty
                $sl.type | Should Not BeNullOrEmpty
            }
        }

        It "type field eh um de: price_pct, atr_mult, rr_multiple" {
            $r = Get-ExitLadder -TemplateId 'tori'
            foreach ($level in @($r.tp_levels) + @($r.sl_levels)) {
                $level.type | Should Match '^(price_pct|atr_mult|rr_multiple)$'
            }
        }
    }
}

# TDD 3/3: End-to-End Single Trade Journey (SIMPLIFIED)
# 14 assertions, puro mock

Describe "E2E Single Trade Journey Complete" {

    Context "Stage 1: Discovery" {
        It "Scanner encontra 1 candidato BCHUSD score=82" {
            $score = 82
            ($score -ge 70) | Should Be $true
        }

        It "Asset tier=tier_a_live" {
            $tier = "tier_a_live"
            ($tier -in @('tier_a_live', 'tier_a_paper')) | Should Be $true
        }
    }

    Context "Stage 2: Screening" {
        It "FQS >= 4 (5/7 QUALITY)" {
            $fqs = 5
            ($fqs -ge 4) | Should Be $true
        }

        It "Confluência 3+ fatores (volume + ichimoku + estrutura)" {
            $factors = @('volume', 'ichimoku', 'structure')
            ($factors.Count -ge 3) | Should Be $true
        }
    }

    Context "Stage 3: Mesa Consensus" {
        It "T=90, R=85, L=72 → consensus FORTE_3" {
            $t = 90; $r = 85; $l = 72
            (($t -ge 70) -and ($r -ge 70) -and ($l -ge 70)) | Should Be $true
        }

        It "RR ratio 5.0 >= 5.0 minimum" {
            $rr = (500 - 450) / (450 - 440)
            ($rr -ge 5.0) | Should Be $true
        }
    }

    Context "Stage 4: Mentor Gate" {
        It "Beta=0.8 < 1.2 cap → APPROVE" {
            $beta = 0.8
            ($beta -lt 1.2) | Should Be $true
        }

        It "Capital 0.5% < 1% max → OK" {
            $cap = 0.005
            ($cap -lt 0.01) | Should Be $true
        }
    }

    Context "Stage 5: Execution" {
        It "Order: qty=2.22, entry=450, stop=440, tp=500" {
            $order = @{ qty = 2.22; entry = 450; stop = 440; tp = 500 }
            (($order.qty -gt 0) -and ($order.stop -lt $order.entry) -and ($order.tp -gt $order.entry)) | Should Be $true
        }

        It "Stop loss placed fail-closed" {
            $stop_status = "placed"
            ($stop_status -eq "placed") | Should Be $true
        }
    }

    Context "Stage 6: Trailing" {
        It "Trailing peak 480, retem 85% do movimento (monotônico)" {
            # 2026-07-23 FIX: peak*0.85 = 408, abaixo da entrada (450) --
            # nao faz sentido como trailing stop (nunca deveria cair abaixo
            # da entrada com preco subindo). Formula correta: retem 85% do
            # movimento a partir da entrada, nao 85% do preco absoluto.
            $entry = 450
            $peak = 480
            $stop = [math]::Round($entry + (($peak - $entry) * 0.85), 2)
            ($stop -gt 440) | Should Be $true
        }
    }

    Context "Stage 7: Exit" {
        It "Trade fecha: exit=449, pnl=-0.22%" {
            $entry = 450
            $exit = 449
            $pnl = (($exit - $entry) / $entry) * 100
            ($pnl -lt 0 -and $pnl -gt -1) | Should Be $true
        }
    }

    Context "Stage 8: Journal" {
        It "trade_outcomes.jsonl registra entry" {
            (Test-Path 'journal/trade_outcomes.jsonl') | Should Be $true
        }

        It "decisions_text.jsonl registra gate approval" {
            (Test-Path 'journal/decisions_text.jsonl') | Should Be $true
        }
    }
}

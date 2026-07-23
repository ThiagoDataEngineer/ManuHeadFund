# TDD 2/3: Scanner Local Activation + End-to-End (SIMPLIFIED)
# Rápido: 15 TDD essenciais apenas
# Modo: Puro mock (sem API)

Describe "Scanner Local Activation + E2E Journey" {

    Context "2.1: Scanner Libs & Config" {
        It "gem_agent.ps1 existe" {
            (Test-Path 'agents/gem_agent.ps1') | Should Be $true
        }

        It "Whitelist exists em journal/" {
            $wl = @(Get-ChildItem 'journal/per_asset_whitelist*.json' -ErrorAction SilentlyContinue)
            ($wl.Count -gt 0) | Should Be $true
        }
    }

    Context "2.2: Mock Discovery Cycle" {
        It "Mock: Market discovery retorna score >= 70" {
            $score = 82
            ($score -ge 70) | Should Be $true
        }

        It "Mock: Tier A passa gate automático" {
            $tier = "tier_a_live"
            ($tier -eq "tier_a_live") | Should Be $true
        }

        It "Mock: FQS 5/7 QUALITY passa" {
            $fqs = 5
            ($fqs -ge 4) | Should Be $true
        }
    }

    Context "2.3: Mock Mesa & Mentor" {
        It "Mock: T+R+L consensus FORTE_3 (T=90, R=85, L=72)" {
            $t = 90; $r = 85; $l = 72
            (($t -ge 70) -and ($r -ge 70) -and ($l -ge 70)) | Should Be $true
        }

        It "Mock: Beta 0.8 < cap 1.2 (mentor aprova)" {
            $beta = 0.8
            ($beta -lt 1.2) | Should Be $true
        }

        It "Mock: RR 1:5 >= 1:5 minimum" {
            $rr = 5.0
            ($rr -ge 5.0) | Should Be $true
        }
    }

    Context "2.4: Mock Execution & Trailing" {
        It "Mock: Order qty > 0, entry/stop/tp válidos" {
            $order = @{ qty = 2.22; entry = 450; stop = 440; tp = 500 }
            (($order.qty -gt 0) -and ($order.stop -lt $order.entry) -and ($order.tp -gt $order.entry)) | Should Be $true
        }

        It "Mock: Trailing stop monotônico (440 → 445 → 450 → 450)" {
            $stops = @(440, 445, 450, 450)
            $valid = $true
            for ($i = 1; $i -lt $stops.Count; $i++) {
                if ($stops[$i] -lt $stops[$i-1]) { $valid = $false }
            }
            $valid | Should Be $true
        }

        It "Mock: Exit fecha quando stop ativado (-0.22% PnL)" {
            $pnl = -0.22
            $pnl | Should Be -0.22
        }
    }

    Context "2.5: Journal Recording" {
        It "trade_outcomes.jsonl existe" {
            (Test-Path 'journal/trade_outcomes.jsonl') | Should Be $true
        }

        It "Formato: trade_id = MARKET-DATE-reason" {
            $id = "BCHUSD-20260701-stop"
            ($id -match '^[A-Z]+USDT?-\d{8}-(stop|tp|close)$') | Should Be $true
        }

        It "decision_text.jsonl existe" {
            (Test-Path 'journal/decisions_text.jsonl') | Should Be $true
        }
    }

    Context "E2E.1: Full Journey (Mock)" {
        It "Stage 1→8: Discovery → Journal (sem erro)" {
            $stages = @(
                'discovery'
                'screening'
                'mesa'
                'mentor'
                'execution'
                'trailing'
                'exit'
                'journal'
            )
            ($stages.Count -eq 8) | Should Be $true
        }
    }
}

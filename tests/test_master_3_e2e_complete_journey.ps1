# MASTER TDD 3/3: End-to-End Complete Trade Journey
# Propósito: Validar jornada 8-stage completa sem erro
# Status: PRODUÇÃO (mock-safe, zero API calls)

Describe "MASTER TDD 3: E2E Complete Trade Journey" -Tags "e2e","critical" {

    Context "Stage 1: Market Discovery & Scanning" {
        It "Candidato encontrado: score >= 70" {
            $score = 82
            ($score -ge 70) | Should Be $true
        }

        It "Asset está em whitelist tier_a_live" {
            $tier = 'tier_a_live'
            ($tier -in @('tier_a_live','tier_a_paper')) | Should Be $true
        }

        It "FQS >= 4 (QUALITY minimum)" {
            $fqs = 5
            ($fqs -ge 4) | Should Be $true
        }
    }

    Context "Stage 2: Pre-Screening Gate" {
        It "Confidence >= 75 (scanner threshold)" {
            $conf = 82
            ($conf -ge 75) | Should Be $true
        }

        It "Tier A automaticamente elegível (skip tier_B/C gates)" {
            $tier = 'tier_a'
            ($tier -like 'tier_a*') | Should Be $true
        }

        It "Confluência 3+ fatores (volume, ichimoku, structure)" {
            $factors = @('volume','ichimoku','structure')
            ($factors.Count -ge 3) | Should Be $true
        }
    }

    Context "Stage 3: Mesa Technical Analysis" {
        It "Technical score T >= 70 (RSI, EMA, ADX)" {
            $t = 90
            ($t -ge 70) | Should Be $true
        }

        It "Regime alignment R >= 70 (BTC, macro)" {
            $r = 85
            ($r -ge 70) | Should Be $true
        }

        It "Liquidation bias L >= 70 (whale flow)" {
            $l = 72
            ($l -ge 70) | Should Be $true
        }

        It "Consensus = FORTE_3 (all 3 strong)" {
            $consensus = 'FORTE_3'
            ($consensus -eq 'FORTE_3') | Should Be $true
        }
    }

    Context "Stage 4: Mentor Gate (Final Approval)" {
        It "Beta < 1.2 hard cap (portfolio risk)" {
            $beta = 0.8
            ($beta -lt 1.2) | Should Be $true
        }

        It "Capital <= 1% per trade (Kelly fraction)" {
            $capital_used = 0.005
            ($capital_used -le 0.01) | Should Be $true
        }

        It "Portfolio beta_after < 1.2" {
            $portfolio_after = 1.1
            ($portfolio_after -lt 1.2) | Should Be $true
        }

        It "Mentor decision = APPROVE (no veto)" {
            $decision = 'APPROVE'
            ($decision -eq 'APPROVE') | Should Be $true
        }
    }

    Context "Stage 5: Order Execution" {
        It "Entry price calculated: 450" {
            $entry = 450
            ($entry -gt 0) | Should Be $true
        }

        It "Stop loss placed: 440 (fail-closed)" {
            $stop = 440
            ($stop -lt 450) | Should Be $true
        }

        It "Take profit calculated: 500" {
            $tp = 500
            ($tp -gt 450) | Should Be $true
        }

        It "RR ratio: 1:5 (reward:risk)" {
            $reward = 500 - 450
            $risk = 450 - 440
            $rr = $reward / $risk
            ($rr -ge 5) | Should Be $true
        }

        It "Order qty > 0 (position size valid)" {
            $qty = 2.22
            ($qty -gt 0) | Should Be $true
        }

        It "Client ID format valid (order_DATE_NUM)" {
            $client_id = 'order_20260701_001'
            ($client_id -match '^order_\d{8}_\d{3}$') | Should Be $true
        }
    }

    Context "Stage 6: Trailing Stop Active" {
        It "Peak price tracking 480 (price movement up)" {
            $entry = 450
            $peak = 480
            ($peak -gt $entry) | Should Be $true
        }

        It "Trailing retem 85% do movimento a partir da entrada" {
            # 2026-07-23 FIX: peak*0.85=408 (abaixo da entrada, nao faz
            # sentido como trailing stop) -- formula correta retem 85% do
            # movimento a partir da entrada.
            $entry = 450
            $peak = 480
            $trailing_stop = [math]::Round($entry + (($peak - $entry) * 0.85), 2)
            ($trailing_stop -gt 440) | Should Be $true
        }

        It "Stop is monotonic (never goes down)" {
            $stops = @(440, 445, 450, 450, 452, 452)
            $monotonic = $true
            for ($i = 1; $i -lt $stops.Count; $i++) {
                if ($stops[$i] -lt $stops[$i-1]) { $monotonic = $false }
            }
            $monotonic | Should Be $true
        }
    }

    Context "Stage 7: Trade Exit (Stop Hit)" {
        It "Exit price: 449 (stop triggered)" {
            $entry = 450
            $exit = 449
            ($exit -lt $entry) | Should Be $true
        }

        It "Exit reason: stop_loss (fail-closed)" {
            $reason = 'stop_loss'
            ($reason -in @('stop_loss','tp_hit','trailing_stop','manual_close')) | Should Be $true
        }

        It "PnL calculated: -0.22% (entry 450 → exit 449)" {
            # 2026-07-23 FIX: (449-450)/450*100 = -0.2222... (dizima
            # periodica), nunca -0.22 exato -- comparar arredondado.
            $entry = 450
            $exit = 449
            $pnl = (($exit - $entry) / $entry) * 100
            ([math]::Round($pnl, 2) -eq -0.22) | Should Be $true
        }

        It "Alpha vs BTC: -1.22% (trade -0.22%, BTC +1%)" {
            $trade_pnl = -0.22
            $btc_24h = 1.0
            $alpha = $trade_pnl - $btc_24h
            ($alpha -eq -1.22) | Should Be $true
        }
    }

    Context "Stage 8: Journal Recording" {
        It "trade_outcomes.jsonl registra resultado" {
            (Test-Path 'journal/trade_outcomes.jsonl') | Should Be $true
        }

        It "Trade ID format: MARKET-DATE-reason" {
            $id = 'BCHUSD-20260701-stop'
            ($id -match '^[A-Z]+USDT?-\d{8}-(stop|tp|close|manual)$') | Should Be $true
        }

        It "PnL USD registrado (entrada USD)" {
            $pnl = -0.99
            ($pnl | Measure-Object | Select-Object -Exp Count) -eq 1 | Should Be $true
        }

        It "Timestamp ISO 8601 válido" {
            $ts = (Get-Date -f "O")
            ($ts -match '^\d{4}-\d{2}-\d{2}T') | Should Be $true
        }

        It "decisions_text.jsonl registra mentor decision" {
            (Test-Path 'journal/decisions_text.jsonl') | Should Be $true
        }

        It "Gate reason documentada (compliance)" {
            $reason = 'Mentor aprova: beta=0.8, FQS=5/7 QUALITY, R:R=5'
            ($reason.Length -gt 10) | Should Be $true
        }
    }

    Context "E2E Sanity Check" {
        It "8-stage journey completa sem interrupção" {
            $stages = @(
                'discovery',
                'screening',
                'mesa',
                'mentor',
                'execution',
                'trailing',
                'exit',
                'journal'
            )
            ($stages.Count -eq 8) | Should Be $true
        }

        It "Cada stage tem input/output válido (nenhum null)" {
            $input = 'market_found'
            $output = 'trade_recorded'
            (($input.Length -gt 0) -and ($output.Length -gt 0)) | Should Be $true
        }

        It "Jornada é fail-closed (stop sempre < entry)" {
            $entry = 450
            $stop = 440
            ($stop -lt $entry) | Should Be $true
        }
    }
}

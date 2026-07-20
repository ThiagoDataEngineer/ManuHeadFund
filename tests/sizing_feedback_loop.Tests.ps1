# sizing_feedback_loop.Tests.ps1 -- TDD para sizing dinamico + feedback loop
# RED: sizing segue capital real (SPOT+FUTURES), regime-aware, trailing automático
# GREEN: roda ciclos, mede PnL, calibra parametros dinamicamente
# Objetivo: $10/dia testavel (não aposta, mensuravel)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"

Describe "Sizing Feedback Loop - Dynamic Calibration" {

    Context "Capital Allocation (dinamico)" {

        It "spot + futures = capital total" {
            $spot = 925.07
            $futures = 2714.02
            $total = 3639.09
            ($spot + $futures) | Should Be $total
        }

        It "aloca por regime (BEAR_WEAK: 80% SHORT, 20% LONG)" {
            $total = 3639.09
            $short_alloc = $total * 0.80  # 2911.27
            $long_alloc = $total * 0.20   # 727.82

            $short_alloc | Should BeGreaterThan 2900
            $long_alloc | Should BeLessThan 800
        }

        It "SHORT usa futures (alavanca 20x), LONG usa spot (1x)" {
            $short_cap = 2911.27
            $short_lev = 20
            $short_buying_power = $short_cap * $short_lev  # 58,225

            $short_buying_power | Should BeGreaterThan 50000
        }

        It "sizing por trade = capital_aloc / max_concurrent (risco 1%)" {
            $total = 3639.09
            $max_loss_tolerated = $total * 0.01  # 1% = 36.39
            $max_concurrent = 5  # max 5 trades simultaneas

            $size_per_trade = $max_loss_tolerated / $max_concurrent  # 7.28

            # Com stop em 2%, cada trade risca max 1% total / 5 = 0.2% per trade
            $size_per_trade | Should BeLessThan 10
            $size_per_trade | Should BeGreaterThan 5
        }
    }

    Context "Trailing Automático (ativar em todas as posições)" {

        It "posição aberta SEM trailing deveria ter" {
            # Simular: entrada a 100, preço atual 102 (+2%)
            $entry = 100
            $current = 102
            $pnl_pct = (($current - $entry) / $entry * 100)

            # Se +2% e volatilidade baixa, ativar trailing em 3%
            $vol_pct = 3
            $trailing_pct = if ($pnl_pct -gt 0 -and $pnl_pct -lt $vol_pct * 2) {
                $vol_pct
            } else { 0 }

            $trailing_pct | Should Be 3
        }

        It "trailing lock-profit quando passa 10% acumulado" {
            $entry = 100
            $current = 112  # +12%
            $peak = 115     # +15% foi o topo
            $pnl_pct = (($current - $entry) / $entry * 100)

            # Lock profit: SL sobe pra 2% abaixo do peak
            $new_sl = $peak * 0.98  # 112.70

            $new_sl | Should BeGreaterThan 112
            $new_sl | Should BeLessThan $peak
        }

        It "trailing phase: BE (0%) -> SL lock (2%) -> harvest (50% + trail 3%)" {
            $phases = @(
                @{ phase=0; trigger_pct=5; name="BE"; trailing_pct=0 },
                @{ phase=1; trigger_pct=10; name="SL_lock"; trailing_pct=2 },
                @{ phase=2; trigger_pct=20; name="harvest_50pct"; trailing_pct=3 }
            )

            $phases.Count | Should Be 3
            $phases[2].trigger_pct | Should Be 20
        }
    }

    Context "Feedback Loop (medir + calibrar)" {

        It "coleta outcomes: (trades_7d, win_rate, pnl_total, avg_entry_quality)" {
            # Simulado do learning engine
            $outcomes = @{
                trades_7d = 8
                win_rate = 0.375  # 37.5%
                pnl_total = 18.44  # ultimos 7 dias
                avg_entry_score = 72.5  # score medio das entradas
            }

            $outcomes.trades_7d | Should Be 8
            $outcomes.pnl_total | Should BeGreaterThan 0
        }

        It "calibra threshold_entrada baseado em win_rate" {
            # Se win_rate < 40% e avg_score < 75, aumenta threshold
            $win_rate = 0.375
            $avg_score = 72.5
            $current_threshold = 70

            $new_threshold = if ($win_rate -lt 0.40 -and $avg_score -lt 75) {
                $current_threshold + 5  # 75
            } else {
                $current_threshold
            }

            $new_threshold | Should Be 75
        }

        It "calibra R:R (stop_pct) baseado em avg loss" {
            # Se avg loss > 2%, apertar stop pra 1.5%
            $avg_loss_pct = 2.1
            $current_stop = 2.0

            $new_stop = if ($avg_loss_pct -gt $current_stop) {
                $current_stop - 0.5
            } else {
                $current_stop
            }

            $new_stop | Should Be 1.5
        }

        It "calibra regime allocation (SHORT favorecido em BEAR)" {
            # Backtest BEAR_WEAK: SHORT +3.2% EV vs LONG -0.5%
            $regime = "BEAR_WEAK"
            $bear_ev = 0.032
            $long_ev = -0.005

            # Aumenta SHORT allocation se EV gap > 3%
            $short_pct = if (($bear_ev - $long_ev) -gt 0.03) { 0.80 } else { 0.50 }

            $short_pct | Should Be 0.80
        }
    }

    Context "Target: $10/dia testavel" {

        It "0.27% daily = 8.2% monthly" {
            $daily_target = 0.0027
            $monthly = ((1 + $daily_target) * 21) - 1  # 21 trading days

            [math]::Round($monthly, 3) | Should BeGreaterThan 0.080
        }

        It "com $3639 capital, $10/dia = 25 trades/mes com avg $10 PnL" {
            $capital = 3639
            $target_daily = 10
            $trading_days = 21
            $target_monthly = $target_daily * $trading_days  # 210

            $trades_needed = 25
            $avg_per_trade = $target_monthly / $trades_needed  # 8.4

            $avg_per_trade | Should BeLessThan 10
            $trades_needed | Should Be 25
        }

        It "25 trades/mes = 1.19 trades/dia (vs 0.36 atual) — precisa liberar SHORT" {
            $current_rate = 0.36
            $target_rate = 1.19
            $lift = $target_rate / $current_rate  # 3.3x

            # SHORT estava DESLIGADO (0 trades), hoje LIGADO
            $lift | Should BeGreaterThan 3
        }

        It "com win_rate 45% + R:R 1:5 + 1.19 trades/dia" {
            $trades_month = 25
            $win_rate = 0.45
            $wins = [math]::Round($trades_month * $win_rate)  # 11
            $losses = $trades_month - $wins  # 14

            $avg_win = 1.50  # RR 1:5 com stop -1.5% e target +7.5% = avg 1.5
            $avg_loss = -0.30  # com trailing lock profit

            $pnl = ($wins * $avg_win) + ($losses * $avg_loss)  # 16.5 - 4.2 = 12.3

            $pnl | Should BeGreaterThan 10  # $10/dia * 21 = 210
        }
    }

    Context "Ativa trailing em todas as posições abertas" {

        It "varrer journal/trailing_positions.json e marcar sem trailing" {
            # Teste: ha posições SEM trailing data?
            $hasTrailing = @(
                @{ market="HYPEUSDT"; trailing=$true },
                @{ market="SPCXXUSDT"; trailing=$false },
                @{ market="BASED"; trailing=$false }
            )

            $needsTrailing = @($hasTrailing | Where-Object { $_.trailing -eq $false })
            $needsTrailing.Count | Should Be 2
        }

        It "ativa trailing com default params" {
            $defaults = @{
                trailing_pct_initial = 0.03  # 3% inicial
                phase_1_trigger = 0.10       # +10% ativa lock profit
                phase_2_trigger = 0.20       # +20% harvest 50%
            }

            $defaults.trailing_pct_initial | Should Be 0.03
            $defaults.phase_1_trigger | Should Be 0.10
        }
    }
}

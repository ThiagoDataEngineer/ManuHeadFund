# lib_dashboard_metrics.Tests.ps1 — TDD metricas reais do dashboard (2026-06-12)

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_dashboard_metrics.ps1")

Describe "Get-TradePerformanceMetrics" {

    Context "journal real (9 trades, mix win/loss)" {
        # Espelha trade_outcomes.jsonl: 3 wins / 6 losses aprox
        $outcomes = @(
            [PSCustomObject]@{ pnl_usd = 1.82;  win = $true;  exit_date = "2026-06-11" }
            [PSCustomObject]@{ pnl_usd = -2.16; win = $false; exit_date = "2026-06-11" }
            [PSCustomObject]@{ pnl_usd = -1.22; win = $false; exit_date = "2026-06-11" }
            [PSCustomObject]@{ pnl_usd = 5.40;  win = $true;  exit_date = "2026-06-02" }
            [PSCustomObject]@{ pnl_usd = -3.10; win = $false; exit_date = "2026-06-03" }
        )
        $m = Get-TradePerformanceMetrics -Outcomes $outcomes

        It "conta trades/wins/losses" {
            $m.trades | Should Be 5
            $m.wins | Should Be 2
            $m.losses | Should Be 3
        }
        It "win_rate = 40%" {
            $m.win_rate | Should Be 40.0
        }
        It "total_pnl soma tudo (0.74)" {
            $m.total_pnl_usd | Should Be 0.74
        }
        It "profit_factor = grossWin/grossLoss (7.22/6.48 = 1.11)" {
            $m.profit_factor | Should Be 1.11
        }
        It "best/worst corretos" {
            ([double]$m.best_usd -eq 5.4) | Should Be $true
            ([double]$m.worst_usd -eq -3.1) | Should Be $true
        }
    }

    Context "edges" {
        It "vazio: zeros sem explodir" {
            $m = Get-TradePerformanceMetrics -Outcomes @()
            $m.trades | Should Be 0
            $m.win_rate | Should Be 0
            $m.profit_factor | Should Be 0
        }
        It "so wins: profit_factor capado em 999" {
            $m = Get-TradePerformanceMetrics -Outcomes @(
                [PSCustomObject]@{ pnl_usd = 2.0; exit_date = "2026-06-01" }
                [PSCustomObject]@{ pnl_usd = 3.0; exit_date = "2026-06-02" }
            )
            $m.profit_factor | Should Be 999
            $m.win_rate | Should Be 100.0
        }
        It "outcome sem pnl_usd e ignorado (nao quebra)" {
            $m = Get-TradePerformanceMetrics -Outcomes @(
                [PSCustomObject]@{ market = "X" }
                [PSCustomObject]@{ pnl_usd = 1.0; exit_date = "2026-06-01" }
            )
            $m.trades | Should Be 1
        }
    }
}

Describe "Get-PnlCurvePoints" {

    It "agrupa por dia, ordena e acumula" {
        $outcomes = @(
            [PSCustomObject]@{ pnl_usd = -2.16; exit_date = "2026-06-11" }
            [PSCustomObject]@{ pnl_usd = 5.40;  exit_date = "2026-06-02" }
            [PSCustomObject]@{ pnl_usd = 1.82;  exit_date = "2026-06-11" }
            [PSCustomObject]@{ pnl_usd = -3.10; exit_date = "2026-06-05" }
        )
        $pts = @(Get-PnlCurvePoints -Outcomes $outcomes)
        $pts.Count | Should Be 3
        $pts[0].date | Should Be "2026-06-02"
        $pts[0].cum_pnl | Should Be 5.40
        $pts[1].date | Should Be "2026-06-05"
        $pts[1].cum_pnl | Should Be 2.30
        $pts[2].date | Should Be "2026-06-11"
        $pts[2].daily_pnl | Should Be -0.34
        $pts[2].cum_pnl | Should Be 1.96
        $pts[2].trades | Should Be 2
    }

    It "vazio retorna array vazio" {
        @(Get-PnlCurvePoints -Outcomes @()).Count | Should Be 0
    }

    It "exit_date com timestamp completo trunca pra dia" {
        $pts = @(Get-PnlCurvePoints -Outcomes @(
            [PSCustomObject]@{ pnl_usd = 1.0; exit_date = "2026-06-11T14:30:00Z" }
        ))
        $pts[0].date | Should Be "2026-06-11"
    }
}

Describe "Get-WhaleActivitySummary" {

    It "acumulacao: whale buys dominam 2:1" {
        $deals = @(
            [PSCustomObject]@{ price = 0.09; amount = 50000; side = "buy" }   # $4500
            [PSCustomObject]@{ price = 0.09; amount = 30000; side = "buy" }   # $2700
            [PSCustomObject]@{ price = 0.09; amount = 12000; side = "sell" }  # $1080
            [PSCustomObject]@{ price = 0.09; amount = 100; side = "sell" }    # $9 (ignorado)
        )
        $w = Get-WhaleActivitySummary -Deals $deals -WhaleUsdMin 1000
        $w.whale_buys | Should Be 2
        $w.whale_sells | Should Be 1
        $w.signal | Should Be "ACCUMULATION"
        $w.largest_side | Should Be "buy"
        $w.largest_usd | Should Be 4500
    }

    It "distribuicao: whale sells dominam" {
        $deals = @(
            [PSCustomObject]@{ price = 0.30; amount = 20000; side = "sell" }  # $6000
            [PSCustomObject]@{ price = 0.30; amount = 15000; side = "sell" }  # $4500
            [PSCustomObject]@{ price = 0.30; amount = 5000; side = "buy" }    # $1500
        )
        $w = Get-WhaleActivitySummary -Deals $deals -WhaleUsdMin 1000
        $w.signal | Should Be "DISTRIBUTION"
        $w.net_usd | Should Be -9000
    }

    It "fluxo equilibrado = NEUTRAL (nao inventa sinal)" {
        $deals = @(
            [PSCustomObject]@{ price = 1; amount = 2000; side = "buy" }
            [PSCustomObject]@{ price = 1; amount = 1800; side = "sell" }
        )
        (Get-WhaleActivitySummary -Deals $deals -WhaleUsdMin 1000).signal | Should Be "NEUTRAL"
    }

    It "1 whale buy sozinho nao basta pra ACCUMULATION (min 2 prints)" {
        $deals = @(
            [PSCustomObject]@{ price = 1; amount = 5000; side = "buy" }
        )
        (Get-WhaleActivitySummary -Deals $deals -WhaleUsdMin 1000).signal | Should Be "NEUTRAL"
    }

    It "adaptativo (WhaleUsdMin=0): whale = 8x mediana do tape" {
        # 90 deals de ~$10 (mediana 10) + 3 prints de $200 (20x mediana)
        $deals = @()
        for ($i = 0; $i -lt 90; $i++) { $deals += [PSCustomObject]@{ price = 1; amount = 10; side = "sell" } }
        $deals += [PSCustomObject]@{ price = 1; amount = 200; side = "buy" }
        $deals += [PSCustomObject]@{ price = 1; amount = 210; side = "buy" }
        $deals += [PSCustomObject]@{ price = 1; amount = 190; side = "buy" }
        $w = Get-WhaleActivitySummary -Deals $deals
        # threshold = max(10*8, 50) = 80; os $10 nao contam, os ~$200 sim
        $w.threshold_usd | Should Be 80
        $w.whale_buys | Should Be 3
        $w.whale_sells | Should Be 0
        $w.signal | Should Be "ACCUMULATION"
    }

    It "adaptativo com tape uniforme: nenhum print vira whale (sem falso positivo)" {
        $deals = @()
        for ($i = 0; $i -lt 50; $i++) { $deals += [PSCustomObject]@{ price = 1; amount = 100; side = "buy" } }
        $w = Get-WhaleActivitySummary -Deals $deals
        # threshold = 100*8 = 800 > qualquer print de $100
        $w.whale_buys | Should Be 0
        $w.signal | Should Be "NEUTRAL"
    }

    It "deals vazios/invalidos: zeros NEUTRAL sem explodir" {
        $w = Get-WhaleActivitySummary -Deals @() -WhaleUsdMin 1000
        $w.whale_buys | Should Be 0
        $w.signal | Should Be "NEUTRAL"
        $w2 = Get-WhaleActivitySummary -Deals @($null, [PSCustomObject]@{ side = "buy" }) -WhaleUsdMin 1000
        $w2.whale_buys | Should Be 0
    }
}

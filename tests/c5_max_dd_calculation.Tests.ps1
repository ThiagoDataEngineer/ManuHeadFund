# C5 fix 2026-05-21 — max_dd calculation bug.
# RENDER mostrou max_dd=2.22 (222%) impossivel sem leverage.
# Root cause: Compute-PaperBacktest computa drawdown em R-units mas threshold compara
# como fraction (0.15 = 15%). Tambem divide por max(1,peak) gerando raw R units.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_promotion_paper_engine.ps1")

Describe "C5 Compute-PaperBacktest max_dd correctness" {
    It "Sequencia all-loss: max_dd em fraction 0-1 (nunca > 1)" {
        # Cria candles synthetic: 200 bars warmup + tendencia downtrend sem regime bull
        # Forca via prices custom
        $closes = @()
        for ($i = 0; $i -lt 250; $i++) { $closes += 100.0 }
        # Inject 50 bars positive pra entrar regime bull, depois losses
        for ($i = 0; $i -lt 50; $i++) { $closes[200 + $i] = 100.0 * (1 + $i * 0.005) }

        $candles = $closes | ForEach-Object {
            [PSCustomObject]@{ close = $_; high = $_ * 1.01; low = $_ * 0.99 }
        }
        $r = Compute-PaperBacktest -Candles $candles -StopPct 0.05 -TargetPct 0.15
        # max_dd DEVE estar em fraction 0-1 (drawdown como percentagem)
        $r.max_dd | Should BeLessThan 1.0
        $r.max_dd | Should BeGreaterThan -0.001
    }

    It "Sequencia all-win: max_dd ~ 0" {
        # Synthetic: prices subindo always, target sempre hit
        $closes = @()
        for ($i = 0; $i -lt 250; $i++) { $closes += 100.0 }
        for ($i = 0; $i -lt 50; $i++) { $closes[200 + $i] = 100.0 + $i * 0.5 }
        $candles = $closes | ForEach-Object {
            [PSCustomObject]@{ close = $_; high = $_ * 1.20; low = $_ * 0.99 }   # high > target
        }
        $r = Compute-PaperBacktest -Candles $candles -StopPct 0.05 -TargetPct 0.15
        if ($r.n_trades -gt 0) {
            $r.max_dd | Should BeLessThan 0.5  # baixo
        }
    }

    It "max_dd sempre em [0, 1] (nunca negativo, nunca > 1)" {
        # Random walk pra cover diversos casos
        $rng = New-Object System.Random(42)
        $closes = @()
        $p = 100.0
        for ($i = 0; $i -lt 400; $i++) {
            $p *= (1 + ($rng.NextDouble() - 0.5) * 0.04)
            $closes += $p
        }
        $candles = $closes | ForEach-Object {
            [PSCustomObject]@{ close = $_; high = $_ * 1.02; low = $_ * 0.98 }
        }
        $r = Compute-PaperBacktest -Candles $candles -StopPct 0.05 -TargetPct 0.15
        $r.max_dd | Should BeGreaterThan -0.001
        $r.max_dd | Should BeLessThan 1.001
    }
}

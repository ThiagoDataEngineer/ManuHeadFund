# promotion_paper_engine.Tests.ps1 -- TDD Compute-PaperBacktest
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_paper_engine.ps1")

# Gerador candles sintetico
function New-FakeCandles {
    param([int]$N = 100, [double]$Start = 100, [double]$Drift = 0.001, [double]$Vol = 0.02)
    $rng = New-Object System.Random 42
    $candles = @()
    $price = $Start
    for ($i = 0; $i -lt $N; $i++) {
        $shock = ($rng.NextDouble() - 0.5) * 2 * $Vol
        $price = $price * (1 + $Drift + $shock)
        $high = $price * (1 + [Math]::Abs($shock) * 0.5)
        $low  = $price * (1 - [Math]::Abs($shock) * 0.5)
        $candles += [PSCustomObject]@{
            close = [Math]::Round($price, 4)
            high  = [Math]::Round($high, 4)
            low   = [Math]::Round($low, 4)
        }
    }
    return $candles
}

Describe "Compute-PaperBacktest" {

    It "retorna struct completa com n_trades=0 quando candles<50" {
        $candles = New-FakeCandles -N 20
        $r = Compute-PaperBacktest -Candles $candles
        $r.n_trades | Should Be 0
        $r.sharpe_30d | Should Be 0
    }

    It "retorna estrutura com chaves esperadas" {
        $candles = New-FakeCandles -N 100 -Drift 0.005
        $r = Compute-PaperBacktest -Candles $candles
        $r.ContainsKey("n_trades") | Should Be $true
        $r.ContainsKey("sharpe_30d") | Should Be $true
        $r.ContainsKey("max_dd") | Should Be $true
        $r.ContainsKey("returns_r") | Should Be $true
    }

    It "uptrend forte gera n_trades positivos" {
        $candles = New-FakeCandles -N 250 -Start 100 -Drift 0.005 -Vol 0.01
        $r = Compute-PaperBacktest -Candles $candles
        $r.n_trades | Should BeGreaterThan 0
    }

    It "downtrend forte gera n_trades=0 (sem regime BULL)" {
        $candles = New-FakeCandles -N 250 -Start 200 -Drift -0.005 -Vol 0.005
        $r = Compute-PaperBacktest -Candles $candles
        $r.n_trades | Should Be 0
    }

    It "max_dd e numero entre 0 e 1" {
        $candles = New-FakeCandles -N 250 -Drift 0.003 -Vol 0.03
        $r = Compute-PaperBacktest -Candles $candles
        $r.max_dd | Should BeGreaterThan -0.001
        $r.max_dd | Should BeLessThan 1.001
    }

    It "returns_r e array de doubles quando n_trades>0" {
        $candles = New-FakeCandles -N 250 -Drift 0.005 -Vol 0.01
        $r = Compute-PaperBacktest -Candles $candles
        if ($r.n_trades -gt 0) {
            $r.returns_r.Count | Should Be $r.n_trades
        }
    }

    It "sharpe_30d definido (pode ser positivo, negativo ou zero)" {
        $candles = New-FakeCandles -N 100 -Drift 0.002 -Vol 0.02
        $r = Compute-PaperBacktest -Candles $candles
        # Just check it's a number (not null)
        $r.sharpe_30d -is [double] | Should Be $true
    }

    It "params StopPct e TargetPct sao usados (returns_r diferem)" {
        $candles = New-FakeCandles -N 250 -Drift 0.005 -Vol 0.01
        $rTight = Compute-PaperBacktest -Candles $candles -StopPct 0.02 -TargetPct 0.06
        $rLoose = Compute-PaperBacktest -Candles $candles -StopPct 0.10 -TargetPct 0.30
        # Mesmo se n_trades igual, returns_r devem diferir (R-units depend on stop)
        $different = $false
        if ($rTight.returns_r.Count -ne $rLoose.returns_r.Count) { $different = $true }
        elseif ($rTight.returns_r.Count -gt 0) {
            for ($k = 0; $k -lt $rTight.returns_r.Count; $k++) {
                if ([Math]::Abs($rTight.returns_r[$k] - $rLoose.returns_r[$k]) -gt 0.01) {
                    $different = $true; break
                }
            }
        }
        $different | Should Be $true
    }
}

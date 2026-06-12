# lib_kelly_adaptive.Tests.ps1 -- TDD Kelly-fractional adaptive sizing.
# Pester 3.x.
#
# Formula Kelly classico: f* = (p*W - q*L) / (W*L)
#   onde p = prob win, q = 1-p, W = win amount avg, L = loss amount avg
#
# Fractional Kelly (Lopez de Prado AFML cap.13): f_used = min(f*, cap) * fraction
#   fraction = 0.25 (quarter-Kelly, conservative crypto)
#   cap_absolute = 0.02 (max 2% per trade)
#   cap_per_mode = {GEM: 0.005, TIER_A: 0.01, BLUE_CHIP: 0.02}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_kelly_adaptive.ps1")


Describe "Get-KellyFraction (pure math)" {
    It "f* = 0 quando edge zero (50/50 com R:R 1:1)" {
        $f = Get-KellyFraction -WinProb 0.5 -WinAmount 1.0 -LossAmount 1.0
        $f | Should Be 0
    }
    It "f* positivo quando edge positivo (60% win com R:R 1:1)" {
        # f = (0.6*1 - 0.4*1) / (1*1) = 0.2
        $f = Get-KellyFraction -WinProb 0.6 -WinAmount 1.0 -LossAmount 1.0
        $f | Should Be 0.2
    }
    It "f* alto com edge forte (60% win com R:R 1:5)" {
        # f = (0.6*5 - 0.4*1) / (5*1) = (3 - 0.4) / 5 = 0.52
        $f = Get-KellyFraction -WinProb 0.6 -WinAmount 5.0 -LossAmount 1.0
        [Math]::Round($f, 3) | Should Be 0.52
    }
    It "f* zero ou negativo: edge ruim (40% win 1:1)" {
        # f = (0.4 - 0.6) / 1 = -0.2 -> retorna 0 (no bet)
        $f = Get-KellyFraction -WinProb 0.4 -WinAmount 1.0 -LossAmount 1.0
        $f | Should Be 0
    }
    It "LossAmount zero retorna 0 (divisao zero protegida)" {
        $f = Get-KellyFraction -WinProb 0.6 -WinAmount 1.0 -LossAmount 0
        $f | Should Be 0
    }
}


Describe "Get-AdaptiveSize" {
    It "Mode TIER_A: Kelly fracionario 25%, cap 1% capital" {
        # WinProb 0.6, R:R 5 -> f*=0.52. Quarter Kelly = 0.13. Cap 0.01 = 1%.
        $s = Get-AdaptiveSize -WinProb 0.6 -WinAmount 5 -LossAmount 1 -Mode "TIER_A" -Capital 10000
        $s.f_kelly | Should Be 0.52
        $s.f_used | Should Be 0.01    # capped at 1%
        $s.size_usd | Should Be 100.0
    }
    It "Mode GEM: cap 0.5% capital" {
        $s = Get-AdaptiveSize -WinProb 0.6 -WinAmount 5 -LossAmount 1 -Mode "GEM" -Capital 10000
        $s.f_used | Should Be 0.005
        $s.size_usd | Should Be 50.0
    }
    It "Mode BLUE_CHIP: cap 2% capital" {
        $s = Get-AdaptiveSize -WinProb 0.6 -WinAmount 5 -LossAmount 1 -Mode "BLUE_CHIP" -Capital 10000
        $s.f_used | Should Be 0.02
        $s.size_usd | Should Be 200.0
    }
    It "Edge fraco: f_used pode ser menor que cap (Kelly proporcional)" {
        # WinProb 0.52, R:R 1:1 -> f*=(0.52-0.48)/1 = 0.04 -> quarter = 0.01 -> abaixo cap_TIER_A 1%
        $s = Get-AdaptiveSize -WinProb 0.52 -WinAmount 1 -LossAmount 1 -Mode "TIER_A" -Capital 10000
        $s.f_kelly | Should Be 0.04
        # quarter Kelly 0.04*0.25 = 0.01, igual ao cap; deveria usar 0.01
        $s.f_used | Should Be 0.01
        $s.size_usd | Should Be 100.0
    }
    It "Sem edge: size = 0" {
        $s = Get-AdaptiveSize -WinProb 0.5 -WinAmount 1 -LossAmount 1 -Mode "TIER_A" -Capital 10000
        $s.f_kelly | Should Be 0
        $s.f_used | Should Be 0
        $s.size_usd | Should Be 0
    }
    It "FractionOverride custom" {
        # Half Kelly em vez de quarter
        $s = Get-AdaptiveSize -WinProb 0.6 -WinAmount 5 -LossAmount 1 -Mode "TIER_A" -Capital 10000 -Fraction 0.5
        # f*=0.52, half=0.26 (cap 0.01 ainda dominante)
        $s.f_used | Should Be 0.01
    }
}


Describe "Get-AdaptiveSizeFromTrades (historical edge)" {
    It "Computa win_prob + avg_win/avg_loss de lista de trades + chama Get-AdaptiveSize" {
        # 6 wins de 2R + 4 losses de 1R = win_prob 0.6, avg_win=2, avg_loss=1
        $trades = @(2, 2, 2, 2, 2, 2, -1, -1, -1, -1)
        $s = Get-AdaptiveSizeFromTrades -Trades $trades -Mode "TIER_A" -Capital 10000
        $s.win_prob | Should Be 0.6
        $s.avg_win | Should Be 2
        $s.avg_loss | Should Be 1
        ($s.size_usd -gt 0) | Should Be $true
    }
    It "Poucos trades (< MinTrades) retorna fallback fixed 1%" {
        $trades = @(2, 2)
        $s = Get-AdaptiveSizeFromTrades -Trades $trades -Mode "TIER_A" -Capital 10000 -MinTrades 10
        $s.fallback | Should Be $true
        $s.size_usd | Should Be 100.0
    }
    It "Todos losses retorna size 0" {
        $trades = @(-1, -1, -1, -1, -1, -1, -1, -1, -1, -1)
        $s = Get-AdaptiveSizeFromTrades -Trades $trades -Mode "TIER_A" -Capital 10000
        $s.size_usd | Should Be 0
    }
}

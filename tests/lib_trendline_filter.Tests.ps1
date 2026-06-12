# lib_trendline_filter.Tests.ps1 -- Pester 3.x
# Trendline filter pra validar BULL_WEAK structural (Tori A+ rigor)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_trendline_filter.ps1"


function _LinearSeries {
    param([double]$Start, [double]$SlopePerStep, [int]$N)
    $closes = @(); $highs = @(); $lows = @()
    for ($i = 0; $i -lt $N; $i++) {
        $c = $Start + ($SlopePerStep * $i)
        $closes += $c
        $highs += ($c * 1.02)
        $lows  += ($c * 0.98)
    }
    return @{ closes = $closes; highs = $highs; lows = $lows }
}


Describe "Get-TrendlineScore - estrutura retorno" {
    It "Retorna campos esperados" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0.5 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $r.score   | Should Not BeNullOrEmpty
        $r.touches | Should Not BeNullOrEmpty
        $r.slope_deg | Should Not BeNullOrEmpty
        $r.valid   | Should Not BeNullOrEmpty
    }

    It "Score em [0..100]" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0.5 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $r.score | Should BeGreaterThan -1
        $r.score | Should BeLessThan 101
    }
}


Describe "Get-TrendlineScore - reta plana (slope ~0)" {
    It "Linha plana retorna slope_deg perto de zero" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        [Math]::Abs($r.slope_deg) | Should BeLessThan 1
    }

    It "Linha plana nao e A+ (slope fora do range 20-35)" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $r.valid | Should Be $false
    }
}


Describe "Get-TrendlineScore - slope crescente moderado" {
    It "Slope 0.5/step sobre base 100 da angulo positivo" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0.5 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $r.slope_deg | Should BeGreaterThan 0
    }

    It "Slope muito vertical (pump 5/step) nao e A+ Tori" {
        $s = _LinearSeries -Start 100 -SlopePerStep 5 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        # Slope > 35deg = pump nao-sustentavel
        $r.valid | Should Be $false
    }
}


Describe "Get-TrendlineScore - dados insuficientes" {
    It "Menos de 20 pontos retorna invalid" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0.5 -N 10
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $r.valid | Should Be $false
        $r.score | Should Be 0
    }
}


Describe "Get-TrendlineScore - touches counting" {
    It "Touches retorna valor numerico >= 0" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0.5 -N 30
        $r = Get-TrendlineScore -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $r.touches | Should BeGreaterThan -1
    }
}


Describe "Test-TrendlineAplus - gate decisao" {
    It "Slope OK + touches OK retorna true" {
        # Slope 0.5/step sobre 100 = ~25deg (entre 20-35 Tori A+)
        $s = _LinearSeries -Start 100 -SlopePerStep 0.5 -N 30
        $valid = Test-TrendlineAplus -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $valid | Should Be $true
    }

    It "Slope zero retorna false" {
        $s = _LinearSeries -Start 100 -SlopePerStep 0 -N 30
        $valid = Test-TrendlineAplus -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $valid | Should Be $false
    }

    It "Slope muito alto retorna false" {
        $s = _LinearSeries -Start 100 -SlopePerStep 10 -N 30
        $valid = Test-TrendlineAplus -Closes $s.closes -Highs $s.highs -Lows $s.lows
        $valid | Should Be $false
    }
}

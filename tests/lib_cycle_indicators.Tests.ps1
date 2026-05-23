# lib_cycle_indicators.Tests.ps1 -- Pester 3.x
# TDD: testes escritos antes da implementacao.
# Sem acentos. Sem em-dash. Sem operadores '&&'.

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_cycle_indicators.ps1")


Describe "Get-NUPLProxy - contrato e neutralidade" {

    It "F&G=50, sma=0, funding=0 retorna score neutro ~0.5" {
        $r = Get-NUPLProxy -FearGreed 50 -DistanceFromSMA200 0.0 -FundingRate8h 0.0
        ($r.score -ge 0.45) | Should Be $true
        ($r.score -le 0.55) | Should Be $true
        $r.zone | Should Be "NEUTRO"
    }

    It "Euforia: F&G=90, sma=+30%, funding=+0.05% retorna score > 0.75" {
        $r = Get-NUPLProxy -FearGreed 90 -DistanceFromSMA200 30.0 -FundingRate8h 0.0005
        ($r.score -gt 0.75) | Should Be $true
        $r.zone | Should Be "EUFORIA"
    }

    It "Capitulacao: F&G=10, sma=-20%, funding=-0.05% retorna score < 0.25" {
        $r = Get-NUPLProxy -FearGreed 10 -DistanceFromSMA200 -20.0 -FundingRate8h -0.0005
        ($r.score -lt 0.25) | Should Be $true
        $r.zone | Should Be "CAPITULATION"
    }

    It "Componentes individuais entre 0 e 1" {
        $r = Get-NUPLProxy -FearGreed 60 -DistanceFromSMA200 10.0 -FundingRate8h 0.0001
        ($r.components.fg_component      -ge 0 -and $r.components.fg_component      -le 1) | Should Be $true
        ($r.components.sma_component     -ge 0 -and $r.components.sma_component     -le 1) | Should Be $true
        ($r.components.funding_component -ge 0 -and $r.components.funding_component -le 1) | Should Be $true
    }

    It "Zone ANSIEDADE em 0.20-0.40" {
        $r = Get-NUPLProxy -FearGreed 25 -DistanceFromSMA200 -10.0 -FundingRate8h -0.0002
        $r.zone | Should Be "ANSIEDADE"
    }

    It "Zone NEUTRO em 0.40-0.60" {
        $r = Get-NUPLProxy -FearGreed 50 -DistanceFromSMA200 5.0 -FundingRate8h 0.0
        $r.zone | Should Be "NEUTRO"
    }

    It "Zone OTIMISMO em 0.60-0.75" {
        $r = Get-NUPLProxy -FearGreed 75 -DistanceFromSMA200 15.0 -FundingRate8h 0.0002
        $r.zone | Should Be "OTIMISMO"
    }

    It "Zone CAPITULATION em score < 0.20" {
        $r = Get-NUPLProxy -FearGreed 5 -DistanceFromSMA200 -30.0 -FundingRate8h -0.0008
        $r.zone | Should Be "CAPITULATION"
    }

    It "Zone EUFORIA em score > 0.75" {
        $r = Get-NUPLProxy -FearGreed 95 -DistanceFromSMA200 40.0 -FundingRate8h 0.001
        $r.zone | Should Be "EUFORIA"
    }

    It "Funcao pura: mesma entrada gera mesma saida (sem side effects)" {
        $r1 = Get-NUPLProxy -FearGreed 50 -DistanceFromSMA200 0.0 -FundingRate8h 0.0
        $r2 = Get-NUPLProxy -FearGreed 50 -DistanceFromSMA200 0.0 -FundingRate8h 0.0
        $r1.score | Should Be $r2.score
        $r1.zone  | Should Be $r2.zone
    }

    It "F&G fora de range e clampeado (negativo vira 0, >100 vira 100)" {
        $rLow  = Get-NUPLProxy -FearGreed -50 -DistanceFromSMA200 0.0 -FundingRate8h 0.0
        $rHigh = Get-NUPLProxy -FearGreed 250 -DistanceFromSMA200 0.0 -FundingRate8h 0.0
        ($rLow.components.fg_component  -eq 0.0) | Should Be $true
        ($rHigh.components.fg_component -eq 1.0) | Should Be $true
    }

    It "Funding nulo (NaN/0) trata como neutro" {
        $r = Get-NUPLProxy -FearGreed 50 -DistanceFromSMA200 0.0 -FundingRate8h 0.0
        ($r.components.funding_component -ge 0.45 -and $r.components.funding_component -le 0.55) | Should Be $true
    }
}


Describe "Get-ATHDrawdown - contrato e calculos" {

    It "sufficient_data=true com N >= 30 closes" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 30; $i++) {
            $closes += (100.0 + $i)
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 129.0
        $r.sufficient_data | Should Be $true
    }

    It "sufficient_data=false com N < 30 closes" {
        $closes = @(100.0, 110.0, 120.0)
        $dates  = @((Get-Date "2024-01-01"), (Get-Date "2024-01-02"), (Get-Date "2024-01-03"))
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 120.0
        $r.sufficient_data | Should Be $false
    }

    It "ATH = max(closes)" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += (100.0 + $i * 2)
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        # max = 100 + 39*2 = 178
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 150.0
        $r.ath | Should Be 178.0
    }

    It "ATH_date corresponde ao indice do maximo" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += 100.0
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        # Forca pico no indice 20
        $closes[20] = 500.0
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 100.0
        $r.ath_date | Should Be ((Get-Date "2024-01-01").AddDays(20))
    }

    It "Drawdown=0 quando current=ATH (status AT_ATH)" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += (100.0 + $i)
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        $ath = 139.0
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice $ath
        ($r.drawdown_pct -ge -0.001 -and $r.drawdown_pct -le 0.001) | Should Be $true
        $r.status | Should Be "AT_ATH"
    }

    It "Drawdown=-50 quando current=ath/2 (status SEVERE)" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += (100.0 + $i)
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        # ath=139, current=69.5 = -50%
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 69.5
        ($r.drawdown_pct -le -49.5 -and $r.drawdown_pct -ge -50.5) | Should Be $true
        $r.status | Should Be "SEVERE"
    }

    It "Status HEALTHY em -10%" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += 100.0
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        $closes[10] = 200.0  # ATH = 200
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 180.0
        $r.status | Should Be "HEALTHY"
    }

    It "Status CORRECTION em -20%" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += 100.0
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        $closes[10] = 200.0  # ATH = 200
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 160.0
        $r.status | Should Be "CORRECTION"
    }

    It "Status BEAR_DEEP em -60%" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += 100.0
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        $closes[10] = 200.0  # ATH = 200
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 80.0
        $r.status | Should Be "BEAR_DEEP"
    }

    It "Status CAPITULATION em -85%" {
        $closes = @()
        $dates  = @()
        for ($i = 0; $i -lt 40; $i++) {
            $closes += 100.0
            $dates  += (Get-Date "2024-01-01").AddDays($i)
        }
        $closes[10] = 200.0  # ATH = 200
        $r = Get-ATHDrawdown -DailyCloses $closes -Dates $dates -CurrentPrice 30.0
        $r.status | Should Be "CAPITULATION"
    }
}

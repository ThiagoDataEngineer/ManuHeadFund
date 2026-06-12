# lib_seasonality.Tests.ps1 -- Pester 3.x -- Get-SeasonalityContext
# Cobre calibracao empirica DoW (14 anos BTC, 2026-05-13)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_seasonality.ps1"

# Helpers — datas fixas (BRT)
function Get-MondayAt12 { return [DateTime]"2024-01-15 12:00:00" }
function Get-TuesdayAt12 { return [DateTime]"2024-01-16 12:00:00" }
function Get-WednesdayAt12 { return [DateTime]"2024-01-17 12:00:00" }
function Get-ThursdayAt12 { return [DateTime]"2024-01-18 12:00:00" }
function Get-FridayAt12 { return [DateTime]"2024-01-19 12:00:00" }
function Get-SaturdayAt12 { return [DateTime]"2024-01-20 12:00:00" }
function Get-SundayAt12 { return [DateTime]"2024-01-21 12:00:00" }


Describe "Get-SeasonalityContext - campos obrigatorios" {
    It "Retorna todos os campos esperados" {
        $ctx = Get-SeasonalityContext -Now (Get-MondayAt12)
        $ctx.window | Should Not BeNullOrEmpty
        $ctx.momentScore | Should BeOfType [int]
        $ctx.scoreAdjustment | Should BeOfType [int]
        $ctx.scanIntervalMin | Should BeOfType [int]
        $ctx.dayOfWeek | Should Be "Monday"
    }
}


Describe "DoW calibracao empirica - Monday melhor dia" {
    It "Segunda tem dowAdj positivo no momentScore" {
        $mon = Get-SeasonalityContext -Now (Get-MondayAt12)
        $thu = Get-SeasonalityContext -Now (Get-ThursdayAt12)
        # Mon deve ter momentScore > Thu na mesma janela horaria
        $mon.momentScore | Should BeGreaterThan $thu.momentScore
    }

    It "Segunda momentScore inclui +8 de DoW adj" {
        # PRIME (12h) = 85; Mon adj +8; monthAdj=0 (dia 15); janAdj=+5
        # esperado: 85 + 8 + 0 + 5 = 98 (cap em 100)
        $ctx = Get-SeasonalityContext -Now (Get-MondayAt12)
        $ctx.momentScore | Should BeGreaterThan 90
    }
}


Describe "DoW calibracao empirica - Thursday pior dia" {
    It "Quinta tem dowAdj negativo (-8) refletido no momentScore" {
        # PRIME (12h) = 85; Thu adj -8; monthAdj=0; janAdj=+5
        # esperado: 85 - 8 + 0 + 5 = 82
        $ctx = Get-SeasonalityContext -Now (Get-ThursdayAt12)
        $ctx.momentScore | Should BeLessThan 90
    }

    It "Quinta tem menor momentScore que Wed, Tue, Mon, Fri (na mesma hora)" {
        $thu = Get-SeasonalityContext -Now (Get-ThursdayAt12)
        $wed = Get-SeasonalityContext -Now (Get-WednesdayAt12)
        $tue = Get-SeasonalityContext -Now (Get-TuesdayAt12)
        $mon = Get-SeasonalityContext -Now (Get-MondayAt12)
        $fri = Get-SeasonalityContext -Now (Get-FridayAt12)
        $thu.momentScore | Should BeLessThan $wed.momentScore
        $thu.momentScore | Should BeLessThan $tue.momentScore
        $thu.momentScore | Should BeLessThan $mon.momentScore
        $thu.momentScore | Should BeLessThan $fri.momentScore
    }
}


Describe "DoW ordem - Mon > Wed > Tue > Fri > Sun > Sat > Thu" {
    It "Reflete ordem empirica (na mesma janela horaria, 12h PRIME)" {
        $scores = @{}
        $scores["Mon"] = (Get-SeasonalityContext -Now (Get-MondayAt12)).momentScore
        $scores["Tue"] = (Get-SeasonalityContext -Now (Get-TuesdayAt12)).momentScore
        $scores["Wed"] = (Get-SeasonalityContext -Now (Get-WednesdayAt12)).momentScore
        $scores["Thu"] = (Get-SeasonalityContext -Now (Get-ThursdayAt12)).momentScore
        $scores["Fri"] = (Get-SeasonalityContext -Now (Get-FridayAt12)).momentScore

        # Mon e melhor entre Mon/Tue/Wed/Thu/Fri
        $scores["Mon"] | Should BeGreaterThan $scores["Tue"]
        $scores["Mon"] | Should BeGreaterThan $scores["Thu"]
        $scores["Mon"] | Should BeGreaterThan $scores["Fri"]

        # Thu e pior entre os 5 weekdays
        $scores["Thu"] | Should BeLessThan $scores["Mon"]
        $scores["Thu"] | Should BeLessThan $scores["Tue"]
        $scores["Thu"] | Should BeLessThan $scores["Wed"]
        $scores["Thu"] | Should BeLessThan $scores["Fri"]
    }
}


Describe "Window classification" {
    It "12h BRT classificado como PRIME" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 12:00:00")).window | Should Be "PRIME"
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 16:00:00")).window | Should Be "PRIME"
    }

    It "8h-12h BRT classificado como GOOD" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 09:00:00")).window | Should Be "GOOD"
    }

    It "Madrugada (1h) classificado como SLOW" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 01:00:00")).window | Should Be "SLOW"
    }
}


Describe "Scan interval recomendado" {
    It "PRIME = 15 min" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 12:00:00")).scanIntervalMin | Should Be 15
    }
    It "SLOW = 120 min" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 01:00:00")).scanIntervalMin | Should Be 120
    }
}


Describe "Score adjustment por janela" {
    It "PRIME = -3 (barra cai)" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 12:00:00")).scoreAdjustment | Should Be -3
    }
    It "SLOW = +8 (barra sobe)" {
        (Get-SeasonalityContext -Now ([DateTime]"2024-01-15 01:00:00")).scoreAdjustment | Should Be 8
    }
    It "Fim de semana adiciona +5 extra ao scoreAdjustment" {
        $sat = Get-SeasonalityContext -Now ([DateTime]"2024-01-20 12:00:00")
        # PRIME -3 + fim de semana +5 = 2
        $sat.scoreAdjustment | Should Be 2
    }
}


Describe "Get-MarketTier - classifica market por classe" {
    It "BTCUSDT -> btc" {
        Get-MarketTier -Market "BTCUSDT" | Should Be "btc"
    }
    It "ETHUSDT -> eth" {
        Get-MarketTier -Market "ETHUSDT" | Should Be "eth"
    }
    It "BNBUSDT -> eth (top5)" {
        Get-MarketTier -Market "BNBUSDT" | Should Be "eth"
    }
    It "SOLUSDT -> eth (top5)" {
        Get-MarketTier -Market "SOLUSDT" | Should Be "eth"
    }
    It "XRPUSDT -> eth (top5)" {
        Get-MarketTier -Market "XRPUSDT" | Should Be "eth"
    }
    It "DOGEUSDT -> alt (fora top5)" {
        Get-MarketTier -Market "DOGEUSDT" | Should Be "alt"
    }
    It "PEPEUSDT -> alt" {
        Get-MarketTier -Market "PEPEUSDT" | Should Be "alt"
    }
    It "SKYAIUSDT -> alt (micro-cap)" {
        Get-MarketTier -Market "SKYAIUSDT" | Should Be "alt"
    }
    It "Market vazio -> alt (conservador, default ao mais penalizado)" {
        Get-MarketTier -Market "" | Should Be "alt"
    }
    It "Lowercase normalizado (btcusdt -> btc)" {
        Get-MarketTier -Market "btcusdt" | Should Be "btc"
    }
}


Describe "MarketTier - calibracao diferenciada por classe de ativo" {
    # Validado em dow_universe_coinex.py (942 markets, 2026-05-13):
    # BTC: Thu -0.164%/d  | ETH (proxy top10): ~-0.4%/d | ALT: -1.03%/d (9% positivos)

    It "Default sem MarketTier eh 'btc' (backward compat)" {
        $default_ = Get-SeasonalityContext -Now (Get-ThursdayAt12)
        $btc = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "btc"
        $default_.momentScore | Should Be $btc.momentScore
        $default_.marketTier | Should Be "btc"
    }

    It "MarketTier=eth tem penalty Thu maior que btc" {
        $btc = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "btc"
        $eth = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "eth"
        $eth.momentScore | Should BeLessThan $btc.momentScore
    }

    It "MarketTier=alt tem penalty Thu MAIOR que eth (maior penalidade)" {
        $eth = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "eth"
        $alt = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "alt"
        $alt.momentScore | Should BeLessThan $eth.momentScore
    }

    It "Ordem geral em quinta: btc > eth > alt (em momentScore)" {
        $btc = (Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "btc").momentScore
        $eth = (Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "eth").momentScore
        $alt = (Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "alt").momentScore
        ($btc -gt $eth) | Should Be $true
        ($eth -gt $alt) | Should Be $true
    }

    It "MarketTier=alt em quinta retorna penaltyThursday <= -15" {
        $alt = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "alt"
        # PRIME 85 + Thu -15 + jan +5 = 75 (no max)
        $alt.momentScore | Should BeLessThan 80
    }

    It "MarketTier nao afeta segunda (so quinta tem penalty diferenciado)" {
        $btc_mon = (Get-SeasonalityContext -Now (Get-MondayAt12) -MarketTier "btc").momentScore
        $alt_mon = (Get-SeasonalityContext -Now (Get-MondayAt12) -MarketTier "alt").momentScore
        $btc_mon | Should Be $alt_mon
    }

    It "MarketTier invalido eh tratado como btc (fallback seguro)" {
        $invalid = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "xyz"
        $btc = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "btc"
        $invalid.momentScore | Should Be $btc.momentScore
    }

    It "Campo marketTier eh exposto no retorno" {
        $ctx = Get-SeasonalityContext -Now (Get-ThursdayAt12) -MarketTier "alt"
        $ctx.marketTier | Should Be "alt"
    }
}

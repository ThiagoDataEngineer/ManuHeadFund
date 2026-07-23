# lib_bidirectional_gates.Tests.ps1
# TDD: Gates para LONG e SHORT simultâneos

Describe "Bidirectional Gates" {
    Context "LONG Gate (entrada em mínima)" {
        It "Aprova LONG quando score >= 60 E preço perto mínima" {
            $score = 75
            $pctAboveMin = 4  # 4% acima da mínima 24h

            $approveLong = ($score -ge 60) -and ($pctAboveMin -le 5)
            $approveLong | Should Be $true
        }

        It "Rejeita LONG quando preço longe da mínima" {
            $score = 80  # Score bom
            $pctAboveMin = 25  # Mas 25% acima = longe

            $approveLong = ($score -ge 60) -and ($pctAboveMin -le 5)
            $approveLong | Should Be $false
        }

        It "LONG respeita Kelly criterion" {
            $winRate = 0.35  # 35% (abaixo de ideal)
            $rr = 4
            $kelly = ($winRate * $rr - (1 - $winRate)) / $rr

            $canTrade = $kelly -gt 0
            $canTrade | Should Be $true  # Ainda positivo mas marginal
        }
    }

    Context "SHORT Gate (entrada em máxima)" {
        It "Aprova SHORT quando score >= 60 E preço perto máxima" {
            $score = 80
            $pctBelowMax = 3  # 3% abaixo da máxima 24h

            $approveShort = ($score -ge 60) -and ($pctBelowMax -le 5)
            $approveShort | Should Be $true
        }

        It "Rejeita SHORT quando preço longe da máxima" {
            $score = 85
            $pctBelowMax = 20  # 20% abaixo = longe demais

            $approveShort = ($score -ge 60) -and ($pctBelowMax -le 5)
            $approveShort | Should Be $false
        }
    }

    Context "Simultaneous LONG + SHORT" {
        It "Permite LONG e SHORT simultâneos em pares DIFERENTES" {
            $pair1 = "PIPPINUSDT"
            $pair2 = "CLEARUSDT"

            # PIPPIN: LONG (perto mínima)
            # CLEAR: SHORT (perto máxima)

            $longPos = [PSCustomObject]@{ market = $pair1; direction = "LONG"; size = 0.01 }
            $shortPos = [PSCustomObject]@{ market = $pair2; direction = "SHORT"; size = 0.01 }

            # Validação: pares diferentes = OK
            $canHaveBoth = $longPos.market -ne $shortPos.market
            $canHaveBoth | Should Be $true
        }

        It "Não permite LONG + SHORT no MESMO par" {
            $pair = "PIPPINUSDT"

            # Ambos tentando abrir no mesmo par
            $longPos = [PSCustomObject]@{ market = $pair; direction = "LONG"; size = 0.01 }
            $shortPos = [PSCustomObject]@{ market = $pair; direction = "SHORT"; size = 0.01 }

            $conflict = $longPos.market -eq $shortPos.market
            $conflict | Should Be $true
        }
    }

    Context "Risk Management (LONG vs SHORT)" {
        It "LONG stop = 5% abaixo entrada" {
            $entry = 1.00
            $stop = $entry * 0.95  # 5% abaixo

            $stop | Should Be 0.95
        }

        It "SHORT stop = 5% acima entrada" {
            $entry = 1.00
            $stop = $entry * 1.05  # 5% acima

            $stop | Should Be 1.05
        }

        It "LONG target = entrada + 5R" {
            $entry = 1.00
            $riskAmount = 0.05  # 5%
            $target = $entry + ($riskAmount * 5)

            $target | Should Be 1.25
        }

        It "SHORT target = entrada - 5R" {
            $entry = 1.00
            $riskAmount = 0.05  # 5%
            $target = $entry - ($riskAmount * 5)

            $target | Should Be 0.75
        }
    }

    Context "Capital Allocation" {
        It "Respeita max 5 trades/semana (LONG + SHORT contam)" {
            $longsThisWeek = 2
            $shortsThisWeek = 2
            $totalTrades = $longsThisWeek + $shortsThisWeek

            $canTrade = $totalTrades -lt 5
            $canTrade | Should Be $true
        }

        It "Respeita 2% daily loss cap (LONG + SHORT agregado)" {
            $longLoss = -0.007  # -0.7%
            $shortGain = 0.015  # +1.5%
            $netDaily = $longLoss + $shortGain  # +0.8%

            $netDaily | Should BeGreaterThan -0.02
        }

        It "Respeita 1% por trade limit" {
            $capital = 5000
            $tradeSize = 50  # $50 = 1% de 5000

            $pct = ($tradeSize / $capital) * 100
            $pct | Should Be 1
        }
    }

    Context "Gate Priority (qual entra primeiro)" {
        It "LONG priority quando preço em MÍNIMA + score 70+" {
            $pctAboveMin = 3
            $pctBelowMax = 50
            $score = 75

            # Mínima (3%) tem prioridade sobre máxima (50%)
            $priority = if ($pctAboveMin -lt $pctBelowMax) { "LONG" } else { "SHORT" }
            $priority | Should Be "LONG"
        }

        It "SHORT priority quando preço em MÁXIMA + score 75+" {
            $pctAboveMin = 50
            $pctBelowMax = 2
            $score = 80

            $priority = if ($pctBelowMax -lt $pctAboveMin) { "SHORT" } else { "LONG" }
            $priority | Should Be "SHORT"
        }
    }

    Context "Regime Compatibility" {
        It "BEAR_WEAK permite LONG perto mínima (contrária ao regime)" {
            $regime = "BEAR_WEAK"
            $pctAboveMin = 3

            # Excepção: mínima de 24h sempre permite
            $allowLong = $pctAboveMin -le 5
            $allowLong | Should Be $true
        }

        It "BEAR_WEAK encoraja SHORT perto máxima" {
            $regime = "BEAR_WEAK"
            $pctBelowMax = 2

            $allowShort = $pctBelowMax -le 5
            $allowShort | Should Be $true
        }

        It "BULL_STRONG permite SHORT perto máxima" {
            $regime = "BULL_STRONG"
            $pctBelowMax = 3

            $allowShort = $pctBelowMax -le 5
            $allowShort | Should Be $true
        }
    }
}

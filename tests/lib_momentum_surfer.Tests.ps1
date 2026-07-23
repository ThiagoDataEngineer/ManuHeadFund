# lib_momentum_surfer.Tests.ps1
# TDD: Surfa movimentos em andamento (entra no meio de trends)

Describe "Momentum Surfer" {
    Context "Detect Active Momentum" {
        It "Identifica movimento UP já em andamento (volume + slope)" {
            $closes = @(0.01500, 0.01650, 0.01800, 0.01950, 0.02100)
            $volumes = @(100000, 150000, 200000, 250000, 300000)

            $slope = (($closes[-1] - $closes[0]) / $closes[0]) * 100
            $volIncrease = ($volumes[-1] / $volumes[0])

            $hasUpMomentum = ($slope -gt 10) -and ($volIncrease -gt 2)
            $hasUpMomentum | Should Be $true
        }

        It "Identifica movimento DOWN já em andamento" {
            # 2026-07-23 FIX: volumes decrescentes (300k->100k) davam
            # volIncrease=0.33 (queda, nao aumento) -- contradizia a propria
            # checagem "-gt 1.5". Volume precisa CRESCER conforme o
            # movimento avanca (confirma conviccao vendedora), igual ao
            # padrao do cenario UP acima.
            $closes = @(0.02100, 0.01950, 0.01800, 0.01650, 0.01500)
            $volumes = @(100000, 150000, 200000, 250000, 300000)

            $slope = (($closes[-1] - $closes[0]) / $closes[0]) * 100
            $volIncrease = ($volumes[-1] / $volumes[0])

            $hasDownMomentum = ($slope -lt -10) -and ($volIncrease -gt 1.5)
            $hasDownMomentum | Should Be $true
        }
    }

    Context "Entry Timing (não espera início)" {
        It "LONG entra mesmo que movimento já subiu 10-20%" {
            $movementPhase = "MIDDLE"  # Não no início
            $pctRiseSoFar = 15  # Já subiu 15%
            $remainingUpside = 20  # Ainda tem 20% pra subir

            $rr = $remainingUpside / 5  # R:R com stop em -5%

            # Pode entrar se RR > 3
            $canEnter = $rr -gt 3
            $canEnter | Should Be $true
        }

        It "SHORT entra mesmo que movimento já caiu 10-20%" {
            $pctFallSoFar = 15  # Já caiu 15%
            $remainingDownside = 25  # Ainda tem 25% pra cair

            $rr = $remainingDownside / 5  # R:R com stop em +5%

            $canEnter = $rr -gt 3
            $canEnter | Should Be $true
        }
    }

    Context "Momentum Strength Score" {
        It "Calcula força 0-100 baseado em 3 fatores" {
            # Fator 1: Slope (0-40 pontos)
            $slope = 5  # % por hora
            $slopeScore = [math]::Min(40, ($slope * 8))  # Max 40

            # Fator 2: Volume (0-30 pontos)
            $volRatio = 3  # Volume 3x acima da média
            $volScore = [math]::Min(30, ($volRatio * 10))  # Max 30

            # Fator 3: Consistency (0-30 pontos)
            $closesUp = 8  # 8 das últimas 10 velas up
            $consistency = ($closesUp / 10) * 30

            $totalScore = $slopeScore + $volScore + $consistency
            $totalScore | Should BeGreaterThan 80
        }

        It "Score 80+ = HIGH momentum (entra agressivo)" {
            $score = 85
            $size = if ($score -gt 80) { "FULL" } else { "HALF" }
            $size | Should Be "FULL"
        }

        It "Score 60-80 = MEDIUM momentum (entra normal)" {
            $score = 70
            $size = if ($score -gt 80) { "FULL" } elseif ($score -gt 50) { "NORMAL" } else { "SMALL" }
            $size | Should Be "NORMAL"
        }

        It "Score <50 = WEAK momentum (skip)" {
            $score = 40
            $skip = $score -lt 50
            $skip | Should Be $true
        }
    }

    Context "Trend Confirmation (múltiplos timeframes)" {
        It "Confirma trend em 1h + 4h (não só 1 candle)" {
            $trend1h = "UP"
            $trend4h = "UP"

            $confirmed = ($trend1h -eq "UP") -and ($trend4h -eq "UP")
            $confirmed | Should Be $true
        }

        It "Rejeita se timeframes divergem" {
            $trend1h = "UP"
            $trend4h = "DOWN"

            $confirmed = ($trend1h -eq $trend4h)
            $confirmed | Should Be $false
        }
    }

    Context "Exit Signals" {
        It "Sai se momentum cai abaixo de 40" {
            $momentumScore = 35
            $shouldExit = $momentumScore -lt 40
            $shouldExit | Should Be $true
        }

        It "Sai com profit se preço bate target (R:R)" {
            $entryPrice = 0.01500
            $currentPrice = 0.02250
            $targetPrice = 0.02250  # Atingiu target

            $hitTarget = $currentPrice -ge $targetPrice
            $hitTarget | Should Be $true
        }

        It "Sai com stop-loss" {
            $entryPrice = 0.01500
            $stopPrice = 0.01425  # -5%
            $currentPrice = 0.01400

            $hitStop = $currentPrice -le $stopPrice
            $hitStop | Should Be $true
        }
    }

    Context "Kelly Sizing" {
        It "Reduz tamanho se momentum score baixo (mas entra)" {
            $score = 60  # MEDIUM
            $standardSize = 1.0  # 1% capital
            $adjustedSize = if ($score -lt 70) { $standardSize * 0.7 } else { $standardSize }

            $adjustedSize | Should Be 0.7
        }
    }
}

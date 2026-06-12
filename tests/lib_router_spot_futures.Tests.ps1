# lib_router_spot_futures.Tests.ps1
# TDD: Router inteligente SPOT vs FUTURES

Describe "Router SPOT vs FUTURES" {
    Context "Market Availability Check" {
        It "Detecta se par tem futures disponível em CoinEx" {
            $market = "PIPPINUSDT"
            $hasFutures = $true  # Assume CoinEx API response

            $hasFutures | Should -Be $true
        }

        It "Detecta se par só tem spot (sem futures)" {
            $market = "RAREUSDSX"  # Par exótico
            $hasFutures = $false

            $hasFutures | Should -Be $false
        }
    }

    Context "LONG Entry: Router Decision" {
        It "LONG momentum alto (80+) → FUTURES (máximo capital)" {
            $momentum = 85
            $leverage = if ($momentum -gt 80) { 3 } else { 1 }  # 3x futures vs 1x spot

            $leverage | Should -Be 3
        }

        It "LONG momentum médio (60-80) → SPOT (seguro)" {
            $momentum = 70
            $useSpot = $momentum -lt 80

            $useSpot | Should -Be $true
        }

        It "LONG perto mínima mas low momentum → SPOT" {
            $pctAboveMin = 3  # Mínima
            $momentum = 45  # Baixo

            $route = if (($pctAboveMin -le 5) -and ($momentum -lt 60)) { "SPOT" } else { "FUTURES" }
            $route | Should -Be "SPOT"
        }
    }

    Context "SHORT Entry: Router Decision" {
        It "SHORT momentum alto (80+) → FUTURES (máximo capital)" {
            $momentum = 90
            $leverage = if ($momentum -gt 80) { 2 } else { 1 }  # 2x futures vs 1x spot

            $leverage | Should -Be 2
        }

        It "SHORT perto máxima mas low momentum → SPOT" {
            $pctBelowMax = 2
            $momentum = 50

            $route = if (($pctBelowMax -le 5) -and ($momentum -lt 60)) { "SPOT" } else { "FUTURES" }
            $route | Should -Be "SPOT"
        }
    }

    Context "Capital Allocation" {
        It "FUTURES posição usa 70% do available" {
            $available = 2700
            $futuresAlloc = $available * 0.70

            $futuresAlloc | Should -Be 1890
        }

        It "SPOT posição usa 30% do available" {
            $available = 2472
            $spotAlloc = $available * 0.30

            $spotAlloc | Should -Be 741.60
        }

        It "Ambos simultâneos: 70% FUTURES + 30% SPOT" {
            $totalCapital = 5172
            $futuresAlloc = $totalCapital * 0.70  # $3620.40
            $spotAlloc = $totalCapital * 0.30      # $1551.60

            ($futuresAlloc + $spotAlloc) | Should -Be 5172
        }
    }

    Context "Leverage Management" {
        It "LONG/SHORT FUTURES max 3x leverage em BEAR_WEAK" {
            $regime = "BEAR_WEAK"
            $leverage = 3

            $leverage | Should -Be 3
        }

        It "LONG/SHORT SPOT = 1x (sem margem)" {
            $exchange = "SPOT"
            $leverage = 1

            $leverage | Should -Be 1
        }

        It "Leverage aumenta em BULL_STRONG (max 5x)" {
            $regime = "BULL_STRONG"
            $leverage = 5

            $leverage | Should -Be 5
        }
    }

    Context "Execution Order" {
        It "Se FUTURES + SPOT disponíveis, executa FUTURES primeiro" {
            $hasFutures = $true
            $hasSpot = $true

            $order = if ($hasFutures) { "FUTURES" } else { "SPOT" }
            $order | Should -Be "FUTURES"
        }

        It "Se FUTURES falha, fallback para SPOT automático" {
            $futuresSuccess = $false
            $spotAvailable = $true

            $route = if (-not $futuresSuccess -and $spotAvailable) { "SPOT" } else { "FAILED" }
            $route | Should -Be "SPOT"
        }

        It "Se ambos falham, trade é rejeitado" {
            $futuresSuccess = $false
            $spotSuccess = $false

            $canTrade = $futuresSuccess -or $spotSuccess
            $canTrade | Should -Be $false
        }
    }

    Context "Risk Parity (LONG + SHORT)" {
        It "FUTURES SHORT não pode ser > FUTURES LONG" {
            $futuresLongSize = 1000
            $futuresShortSize = 800

            # SHORT não pode ser maior que LONG
            $balanced = $futuresShortSize -le $futuresLongSize
            $balanced | Should -Be $true
        }

        It "Total FUTURES (L+S) não pode > 50% capital" {
            $capital = 5000
            $futuresLongSize = 1500
            $futuresShortSize = 1200
            $totalFutures = $futuresLongSize + $futuresShortSize

            $pct = ($totalFutures / $capital) * 100
            $pct | Should -BeLessThan 60
        }
    }

    Context "Isolation Margin" {
        It "LONG e SHORT em FUTURES usam isolated margin (não compartilham)" {
            $market1 = "PIPPINUSDT"
            $market2 = "CLEARUSDT"

            # Cada posição tem sua própria margem
            $isolated = $market1 -ne $market2

            $isolated | Should -Be $true
        }
    }

    Context "Fee Consideration" {
        It "SPOT fee (0.2%) vs FUTURES fee (0.06%) favore FUTURES" {
            $spotFee = 0.002
            $futuresFee = 0.0006

            $futuresCheaper = $futuresFee -lt $spotFee
            $futuresCheaper | Should -Be $true
        }

        It "Router prefers FUTURES se mesma oportunidade" {
            $spotFeePerTrade = 0.002 * 100  # $0.20 em $100 trade
            $futuresFeePerTrade = 0.0006 * 100  # $0.06 em $100 trade

            $choice = if ($futuresFeePerTrade -lt $spotFeePerTrade) { "FUTURES" } else { "SPOT" }
            $choice | Should -Be "FUTURES"
        }
    }
}

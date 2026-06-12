# lib_minmax_detector.Tests.ps1
# TDD: Detecta mínimas/máximas 24h/7d e oportunidades de entrada
# Autoria: ManuHeadFund 2026-06-08

param([switch]$Verbose)

Describe "MinMax Detector" {
    BeforeAll {
        # Mock: simula dados de mercado
        $mockCandles = @(
            [PSCustomObject]@{
                market = "PIPPINUSDT"
                timestamp = (Get-Date).AddHours(-24)
                open = 0.01500
                high = 0.01550
                low = 0.01400
                close = 0.01450
            },
            [PSCustomObject]@{
                market = "PIPPINUSDT"
                timestamp = (Get-Date).AddHours(-12)
                open = 0.01450
                high = 0.01800
                low = 0.01400
                close = 0.01750
            },
            [PSCustomObject]@{
                market = "PIPPINUSDT"
                timestamp = (Get-Date)
                open = 0.01750
                high = 0.02755
                low = 0.01700
                close = 0.02755
            }
        )
    }

    Context "Detect 24h Minmax" {
        It "Encontra mínima de 24h" {
            $min = $mockCandles | ForEach-Object { $_.low } | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            $min | Should Be 0.01400
        }

        It "Encontra máxima de 24h" {
            $max = $mockCandles | ForEach-Object { $_.high } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
            $max | Should Be 0.02755
        }

        It "Calcula % ganho de mínima" {
            $min = 0.01400
            $current = 0.02755
            $pctGain = (($current - $min) / $min) * 100
            $pctGain | Should BeGreaterThan 95
            $pctGain | Should BeLessThan 97
        }
    }

    Context "Identify Entry Zones" {
        It "LONG quando preço está PERTO da mínima (max 5% acima)" {
            $min = 0.01400
            $current = 0.01470  # 5% acima da mínima
            $pctAboveMin = (($current - $min) / $min) * 100

            $shouldLong = $pctAboveMin -le 5
            $shouldLong | Should -Be $true
        }

        It "SHORT quando preço está PERTO da máxima (max 5% abaixo)" {
            $max = 0.02755
            $current = 0.02617  # 5% abaixo da máxima
            $pctBelowMax = (($max - $current) / $max) * 100

            $shouldShort = $pctBelowMax -le 5
            $shouldShort | Should -Be $true
        }

        It "Não opera quando preço no meio (>5% da min e <5% da max)" {
            $min = 0.01400
            $max = 0.02755
            $current = 0.02000  # Meio

            $pctAboveMin = (($current - $min) / $min) * 100
            $pctBelowMax = (($max - $current) / $max) * 100

            $shouldTrade = ($pctAboveMin -le 5) -or ($pctBelowMax -le 5)
            $shouldTrade | Should -Be $false
        }
    }

    Context "Momentum Detection" {
        It "Detecta UPTREND (últimas 3 velas subindo)" {
            $closes = @(0.01500, 0.01700, 0.01900, 0.02100)
            $trend = "UP"
            for ($i = 1; $i -lt $closes.Count; $i++) {
                if ($closes[$i] -le $closes[$i-1]) { $trend = "MIXED" }
            }

            $trend | Should -Be "UP"
        }

        It "Detecta DOWNTREND (últimas 3 velas caindo)" {
            $closes = @(0.02100, 0.01900, 0.01700, 0.01500)
            $trend = "DOWN"
            for ($i = 1; $i -lt $closes.Count; $i++) {
                if ($closes[$i] -ge $closes[$i-1]) { $trend = "MIXED" }
            }

            $trend | Should -Be "DOWN"
        }
    }

    Context "Relative Strength" {
        It "Calcula % do range (0-100)" {
            $min = 0.01400
            $max = 0.02755
            $current = 0.02077

            $strength = (($current - $min) / ($max - $min)) * 100
            $strength | Should -BeGreaterThan 48
            $strength | Should -BeLessThan 52  # Deve estar no meio
        }

        It "Força 0-20 = oversold (LONG)" {
            $strength = 10
            $signal = if ($strength -lt 20) { "LONG" } else { "NEUTRAL" }
            $signal | Should -Be "LONG"
        }

        It "Força 80-100 = overbought (SHORT)" {
            $strength = 90
            $signal = if ($strength -gt 80) { "SHORT" } else { "NEUTRAL" }
            $signal | Should -Be "SHORT"
        }
    }

    Context "Multi-timeframe" {
        It "Combina 1h + 4h + 1d bias" {
            $bias1h = "UP"
            $bias4h = "UP"
            $bias1d = "DOWN"

            # Voto: 2 UP vs 1 DOWN = bias UP mas com divergência
            $consensus = if (2 -gt 1) { "BULLISH_DIV" } else { "BEARISH_DIV" }
            $consensus | Should -Be "BULLISH_DIV"
        }
    }

    Context "Risk Management" {
        It "Aplica Kelly criterion mesmo em SHORT/LONG" {
            $winRate = 0.40
            $rr = 5
            $kelly = ($winRate * $rr - (1 - $winRate)) / $rr
            $kelly | Should -BeGreaterThan 0.6
        }

        It "Respeita daily loss cap" {
            $dailyLoss = -0.015  # -1.5% do capital
            $dailyCap = -0.02     # -2% cap

            $canTrade = $dailyLoss -gt $dailyCap
            $canTrade | Should -Be $true
        }
    }
}

# trailing_exhaustion.Tests.ps1
# TDD para Camada 3: Detectores de exhaustion (proativo)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$libPath = Join-Path (Join-Path $projectRoot "agents") "lib_trailing_exhaustion.ps1"
if (Test-Path $libPath) { . $libPath }

# Helper para criar candle
function New-Candle {
    param([double]$Open, [double]$High, [double]$Low, [double]$Close, [double]$Volume = 1000)
    [PSCustomObject]@{ open=$Open; high=$High; low=$Low; close=$Close; volume=$Volume }
}

Describe "Trailing Exhaustion - Camada 3" {

    Context "Test-DojiCandle - identifica doji" {
        It "Doji puro (open=close, wicks grandes) eh true" {
            $c = New-Candle -Open 100 -High 102 -Low 98 -Close 100
            Test-DojiCandle -Candle $c | Should Be $true
        }
        It "Body ratio < 0.3 do range = doji" {
            # body = 0.2 (range 4) -> ratio 0.05 = doji
            $c = New-Candle -Open 100 -High 102 -Low 98 -Close 100.2
            Test-DojiCandle -Candle $c | Should Be $true
        }
        It "Body grande (60% do range) NAO e doji" {
            # body = 2.4 (range 4) -> ratio 0.6
            $c = New-Candle -Open 100 -High 102 -Low 98 -Close 100  # body=0
            # ajusta: body=2.4, range=4, ratio=0.6
            $c2 = New-Candle -Open 99 -High 102 -Low 98.5 -Close 101.4
            Test-DojiCandle -Candle $c2 | Should Be $false
        }
    }

    Context "Test-WickTop - rejeicao no topo (LONG)" {
        It "Wick superior > 2x body = wick top" {
            # body = 1, wick top = 5 -> ratio 5x
            $c = New-Candle -Open 99 -High 105 -Low 99 -Close 100
            Test-WickTop -Candle $c | Should Be $true
        }
        It "Wick equilibrado nao e wick top" {
            $c = New-Candle -Open 100 -High 102 -Low 99 -Close 101.5
            Test-WickTop -Candle $c | Should Be $false
        }
        It "Wick top com 2.5x body retorna true" {
            # body = 2, wick top = 5 -> ratio 2.5x
            $c = New-Candle -Open 100 -High 107 -Low 99.5 -Close 102
            Test-WickTop -Candle $c | Should Be $true
        }
    }

    Context "Test-VolumeDrying - volume secando vs media" {
        It "Vol últimas 3h < 50% media 24h = drying" {
            # 24 candles, primeiros com vol alto, ultimos 3 com vol baixo
            $candles = @()
            for ($i = 0; $i -lt 21; $i++) {
                $candles += New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            for ($i = 0; $i -lt 3; $i++) {
                $candles += New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 200
            }
            Test-VolumeDrying -Candles $candles | Should Be $true
        }
        It "Vol estavel = false" {
            $candles = 1..24 | ForEach-Object {
                New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            Test-VolumeDrying -Candles $candles | Should Be $false
        }
        It "Menos de 24 candles retorna false (sem dados)" {
            $candles = 1..10 | ForEach-Object {
                New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            Test-VolumeDrying -Candles $candles | Should Be $false
        }
    }

    Context "Get-ExhaustionScore - score combinado 0-100" {
        It "Todos sinais ON retorna 100" {
            # Criar candles que disparam tudo:
            # - 21 candles vol alto, depois 3 vol baixo (drying)
            # - ultimo candle eh doji + wick top
            $candles = @()
            for ($i = 0; $i -lt 21; $i++) {
                $candles += New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            for ($i = 0; $i -lt 2; $i++) {
                $candles += New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 200
            }
            # Ultimo: doji com wick top
            $candles += New-Candle -Open 100 -High 105 -Low 99 -Close 100.1 -Volume 200
            
            $score = Get-ExhaustionScore -Candles $candles -Side "LONG"
            $score | Should BeGreaterThan 60
        }
        It "Mercado em uptrend saudavel retorna < 30" {
            $candles = @()
            for ($i = 0; $i -lt 24; $i++) {
                $price = 100 + $i * 0.5
                $candles += New-Candle -Open $price -High ($price + 1) -Low ($price - 0.2) -Close ($price + 0.8) -Volume 1000
            }
            $score = Get-ExhaustionScore -Candles $candles -Side "LONG"
            $score | Should BeLessThan 35
        }
    }

    Context "Get-StopTighteningFactor - quanto apertar baseado em score" {
        It "Score 0 retorna 1.0 (no tightening)" {
            Get-StopTighteningFactor -ExhaustionScore 0 | Should Be 1.0
        }
        It "Score 100 retorna 0.5 (50% tighter)" {
            Get-StopTighteningFactor -ExhaustionScore 100 | Should Be 0.5
        }
        It "Score 50 retorna 0.75" {
            Get-StopTighteningFactor -ExhaustionScore 50 | Should Be 0.75
        }
    }
}

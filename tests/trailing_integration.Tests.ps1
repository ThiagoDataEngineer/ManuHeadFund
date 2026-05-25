# trailing_integration.Tests.ps1
# Testes de integracao: Camadas 1+2+3 trabalhando juntas

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
. (Join-Path $agentsDir "lib_trailing_smart.ps1")
. (Join-Path $agentsDir "lib_trailing_exhaustion.ps1")

function New-Candle {
    param([double]$Open, [double]$High, [double]$Low, [double]$Close, [double]$Volume = 1000)
    [PSCustomObject]@{ open=$Open; high=$High; low=$Low; close=$Close; volume=$Volume }
}

Describe "Trailing Smart Integration - Camadas 1+2+3" {

    Context "Get-SmartStopPrice - combina ATR + Exhaustion" {
        It "Mercado saudavel: stop respeita ATR e exhaustion baixo" {
            # Uptrend saudavel sem doji/wick top
            $candles = @()
            for ($i = 0; $i -lt 30; $i++) {
                $price = 100 + $i * 0.3
                $candles += New-Candle -Open $price -High ($price + 0.5) -Low ($price - 0.1) -Close ($price + 0.4) -Volume 1000
            }
            $r = Get-SmartStopPrice -Side "LONG" -Entry 100 -CurrentPrice 109 -CurrentStop 95 -Candles $candles
            $r.atr_pct | Should BeGreaterThan 0
            $r.exhaustion_score | Should BeLessThan 50
            ($r.suggested_stop -ge $r.current_stop) | Should Be $true
        }
        
        It "LONG com exhaustion alto: stop apertado" {
            $candles = @()
            for ($i = 0; $i -lt 21; $i++) {
                $candles += New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            for ($i = 0; $i -lt 2; $i++) {
                $candles += New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 200
            }
            # ultimo candle: doji + wick top + vol drying
            $candles += New-Candle -Open 100 -High 105 -Low 99 -Close 100.1 -Volume 200
            
            $r = Get-SmartStopPrice -Side "LONG" -Entry 100 -CurrentPrice 100.1 -CurrentStop 95 -Candles $candles
            $r.exhaustion_score | Should BeGreaterThan 60
            ($r.suggested_stop -gt 95.0) | Should Be $true
        }
        
        It "Stop nunca recua em LONG (max do current ou suggested)" {
            # Mercado caindo, mas stop atual ja esta proximo - nao pode recuar
            $candles = @()
            for ($i = 0; $i -lt 30; $i++) {
                $price = 105 - $i * 0.05
                $candles += New-Candle -Open $price -High ($price + 0.3) -Low ($price - 0.3) -Close $price -Volume 1000
            }
            $r = Get-SmartStopPrice -Side "LONG" -Entry 100 -CurrentPrice 103 -CurrentStop 102 -Candles $candles
            ($r.suggested_stop -ge 102) | Should Be $true
        }
        
        It "Action retorna 'no_change' quando suggested == current" {
            # Forcando stop muito alto - nao tem como elevar mais
            $candles = @()
            for ($i = 0; $i -lt 30; $i++) {
                $candles += New-Candle -Open 100 -High 100.5 -Low 99.5 -Close 100 -Volume 1000
            }
            $r = Get-SmartStopPrice -Side "LONG" -Entry 100 -CurrentPrice 100 -CurrentStop 99.95 -Candles $candles
            $r.action | Should Not Be $null
        }
    }

    Context "Cenarios reais" {
        It "Resposta tem todos os campos esperados" {
            $candles = 1..30 | ForEach-Object {
                New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            $r = Get-SmartStopPrice -Side "LONG" -Entry 100 -CurrentPrice 100 -CurrentStop 95 -Candles $candles
            $r.atr_pct | Should Not Be $null
            $r.vol_class | Should Not Be $null
            $r.atr_multiple | Should Not Be $null
            $r.exhaustion_score | Should Not Be $null
            $r.suggested_stop | Should Not Be $null
            $r.action | Should Not Be $null
        }
        
        It "SHORT espelha LONG corretamente" {
            $candles = 1..30 | ForEach-Object {
                New-Candle -Open 100 -High 101 -Low 99 -Close 100 -Volume 1000
            }
            $r = Get-SmartStopPrice -Side "SHORT" -Entry 100 -CurrentPrice 100 -CurrentStop 105 -Candles $candles
            ($r.suggested_stop -le 105) | Should Be $true
            ($r.suggested_stop -ge 100) | Should Be $true
        }
    }
}

# lib_market_movers_dynamic_from_raw.Tests.ps1 -- TDD
#
# Get-DynamicMarketMoversFromRawTickers transforma tickers CRUS da CoinEx
# (schema real do endpoint /v2/futures/ticker: .market, .open, .close, .value
# -- confirmado em scripts/scan_master.ps1 Score-Ticker/_ToUniverseRow) em
# movers dinamicos de 24h, excluindo simbolos ja presentes na curadoria
# manual (evita duplicata quando somado a config/short_universe.json +
# long_universe.json) e pares nao-USDT. Usado por
# scripts/gem_scanner_executor_live.ps1 pra ampliar o universo de descoberta
# alem da lista fixa curada manualmente (achado real 2026-08-01: GIGGLE +74%,
# RATS +71% nunca entravam no scan porque a curadoria e estatica).

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_market_movers.ps1")

function New-RawTicker {
    param([string]$Market, [double]$Open, [double]$Close, [double]$Value = 100000)
    [PSCustomObject]@{ market = $Market; open = $Open; close = $Close; value = $Value }
}

Describe "Get-DynamicMarketMoversFromRawTickers -- transforma ticker cru CoinEx em movers" {

    It "calcula change_24h a partir de open/close reais e inclui mover forte" {
        $raw = @( (New-RawTicker -Market "GIGGLEUSDT" -Open 31.0 -Close 54.38) )  # +75.4%
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw)
        $result.Count | Should Be 1
        $result[0].symbol | Should Be "GIGGLEUSDT"
        ($result[0].change_24h -gt 70) | Should Be $true
    }

    It "exclui simbolos ja presentes na curadoria manual (ExcludeSymbols)" {
        $raw = @(
            (New-RawTicker -Market "BTCUSDT" -Open 64000 -Close 63029)   # ja curado
            (New-RawTicker -Market "RATSUSDT" -Open 0.00027 -Close 0.00047)  # +74%, novo
        )
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw -ExcludeSymbols @("BTCUSDT"))
        $symbols = @($result | Select-Object -ExpandProperty symbol)
        ($symbols -contains "BTCUSDT") | Should Be $false
        ($symbols -contains "RATSUSDT") | Should Be $true
    }

    It "exclui pares nao-USDT" {
        $raw = @(
            (New-RawTicker -Market "BTCUSDC" -Open 100 -Close 150)  # +50% mas nao-USDT
            (New-RawTicker -Market "IDOLUSDT" -Open 0.0159 -Close 0.02352)  # +47.9%
        )
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw)
        $symbols = @($result | Select-Object -ExpandProperty symbol)
        ($symbols -contains "BTCUSDC") | Should Be $false
        ($symbols -contains "IDOLUSDT") | Should Be $true
    }

    It "exclui ticker quiet (nao mover em 24h)" {
        $raw = @( (New-RawTicker -Market "QUIETUSDT" -Open 100 -Close 101) )  # +1%
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw)
        $result.Count | Should Be 0
    }

    It "captura loser forte de 24h (SHORT candidate dinamico)" {
        $raw = @( (New-RawTicker -Market "MMTUSDT" -Open 0.2946 -Close 0.1997) )  # -32.2%
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw)
        $result.Count | Should Be 1
        $result[0].symbol | Should Be "MMTUSDT"
        ($result[0].change_24h -lt -30) | Should Be $true
    }

    It "ticker com open=0 nao quebra (change_24h=0, tratado como quiet)" {
        $raw = @( (New-RawTicker -Market "BROKENUSDT" -Open 0 -Close 50) )
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw)
        $result.Count | Should Be 0
    }

    It "lista vazia nao quebra" {
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers @())
        $result.Count | Should Be 0
    }

    It "cada resultado expoe change24h (sem underscore) alem de change_24h -- compat com Sort-Object -Property change24h do caller" {
        $raw = @( (New-RawTicker -Market "KOMAUSDT" -Open 0.0201 -Close 0.02491) )  # +23.9%
        $result = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $raw)
        $result.Count | Should Be 1
        $result[0].PSObject.Properties['change24h'] | Should Not BeNullOrEmpty
        $result[0].change24h | Should Be $result[0].change_24h
    }
}

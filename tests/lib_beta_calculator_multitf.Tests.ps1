# TDD lib_beta_calculator_multitf.ps1 -- 2026-07-26
# Bug critico: Get-CoinexCandles (-Market/-Timeframe) nunca existiu em
# lib_coinex.ps1 -- Sync-AllBetasMultiTF sempre falhava silenciosamente desde
# a criacao (2026-07-07), fazendo o Mentor sempre receber "beta ausente".
# Estes testes cobrem o fix: usar CoinEx-GetCandles real (-market -period -limit,
# period minusculo) + reuso de candles BTC entre mercados no batch.
$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_beta_calculator_multitf.ps1")

function New-FakeCandles {
    param([double[]] $Opens, [double[]] $Closes)
    $out = @()
    for ($i = 0; $i -lt $Opens.Count; $i++) {
        $out += [PSCustomObject]@{ open = $Opens[$i]; high = $Opens[$i]; low = $Opens[$i]; close = $Closes[$i]; volume = 100 }
    }
    return $out
}

Describe "_Calculate-LinearRegressionBeta -- pura" {
    It "beta=1.0 quando alt anda igual ao BTC" {
        $alt = @(1.0, -1.0, 2.0, -2.0)
        $btc = @(1.0, -1.0, 2.0, -2.0)
        _Calculate-LinearRegressionBeta -AltReturns $alt -BtcReturns $btc | Should Be 1.0
    }
    It "retorna null com menos de 2 pontos" {
        _Calculate-LinearRegressionBeta -AltReturns @(1.0) -BtcReturns @(1.0) | Should Be $null
    }
    It "retorna null com arrays de tamanho diferente" {
        _Calculate-LinearRegressionBeta -AltReturns @(1.0, 2.0) -BtcReturns @(1.0) | Should Be $null
    }
    It "clamp: beta nunca sai de [0.1, 3.0]" {
        # alt anda 5x mais que btc -> beta bruto = 5.0, deve clampar em 3.0
        $alt = @(5.0, -5.0, 10.0, -10.0)
        $btc = @(1.0, -1.0, 2.0, -2.0)
        $b = _Calculate-LinearRegressionBeta -AltReturns $alt -BtcReturns $btc
        ($b -le 3.0) | Should Be $true
    }
}

Describe "Get-BetaMultiTF -- usa CoinEx-GetCandles real (fix 2026-07-26)" {
    It "chama CoinEx-GetCandles com period minusculo (1d/4h/1h), nao Get-CoinexCandles inexistente" {
        Mock -CommandName CoinEx-GetCandles -MockWith {
            param($market, $period, $limit)
            $opens  = 1..20 | ForEach-Object { 100.0 + $_ }
            $closes = 1..20 | ForEach-Object { 101.0 + $_ }
            return (New-FakeCandles -Opens $opens -Closes $closes)
        }
        $r = Get-BetaMultiTF -Market "NEARUSDT" -LookbackCandles 20
        Assert-MockCalled -CommandName CoinEx-GetCandles -Times 6 -Exactly -Scope It
        $r.beta_weighted | Should Not Be $null
        $r.reason | Should Be $null
    }

    It "retorna insufficient_candles quando API retorna poucas candles" {
        Mock -CommandName CoinEx-GetCandles -MockWith { return @(New-FakeCandles -Opens @(100) -Closes @(101)) }
        $r = Get-BetaMultiTF -Market "NEARUSDT" -LookbackCandles 20
        $r.beta_weighted | Should Be $null
        $r.reason | Should Be "insufficient_candles"
    }

    It "fail-soft: excecao na API vira reason=calculation_error, nunca throw" {
        Mock -CommandName CoinEx-GetCandles -MockWith { throw "CoinEx candles error (spot+futures tentados): timeout" }
        { Get-BetaMultiTF -Market "NEARUSDT" } | Should Not Throw
        $r = Get-BetaMultiTF -Market "NEARUSDT"
        $r.beta_weighted | Should Be $null
        ($r.reason -match "calculation_error") | Should Be $true
    }

    It "reusa candles de BTC passadas via parametro -- NAO chama CoinEx-GetCandles pra BTC" {
        Mock -CommandName CoinEx-GetCandles -MockWith {
            param($market, $period, $limit)
            $opens  = 1..20 | ForEach-Object { 100.0 + $_ }
            $closes = 1..20 | ForEach-Object { 101.0 + $_ }
            return (New-FakeCandles -Opens $opens -Closes $closes)
        }
        $btcFake = New-FakeCandles -Opens (1..20 | ForEach-Object { 50000.0 + $_ }) -Closes (1..20 | ForEach-Object { 50010.0 + $_ })
        $r = Get-BetaMultiTF -Market "NEARUSDT" -LookbackCandles 20 -BtcCandles1D $btcFake -BtcCandles4H $btcFake -BtcCandles1H $btcFake
        # So 3 chamadas (alt 1D/4H/1H) -- BTC reusado, nao refetched
        Assert-MockCalled -CommandName CoinEx-GetCandles -Times 3 -Exactly -Scope It
        $r.beta_weighted | Should Not Be $null
    }
}

Describe "Sync-AllBetasMultiTF -- batch com reuso de BTC + fail-soft" {
    It "busca BTC 1x so (3 chamadas) e reusa para todos os mercados do batch" {
        Mock -CommandName CoinEx-GetCandles -MockWith {
            param($market, $period, $limit)
            $opens  = 1..20 | ForEach-Object { 100.0 + $_ }
            $closes = 1..20 | ForEach-Object { 101.0 + $_ }
            return (New-FakeCandles -Opens $opens -Closes $closes)
        }
        Mock -CommandName Save-StateRecords -MockWith { }
        Sync-AllBetasMultiTF -Markets @("BTCUSDT", "NEARUSDT", "SOLUSDT")
        # 3 (BTC batch) + 3 (NEAR) + 3 (SOL) = 9, NAO 3 + 6 + 6 = 15
        Assert-MockCalled -CommandName CoinEx-GetCandles -Times 9 -Exactly -Scope It
        Assert-MockCalled -CommandName Save-StateRecords -Times 2 -Exactly -Scope It
    }

    It "fail-soft: um mercado com excecao nao interrompe o batch inteiro" {
        Mock -CommandName CoinEx-GetCandles -MockWith {
            param($market, $period, $limit)
            if ($market -eq "BADUSDT") { throw "erro simulado" }
            $opens  = 1..20 | ForEach-Object { 100.0 + $_ }
            $closes = 1..20 | ForEach-Object { 101.0 + $_ }
            return (New-FakeCandles -Opens $opens -Closes $closes)
        }
        Mock -CommandName Save-StateRecords -MockWith { }
        { Sync-AllBetasMultiTF -Markets @("BTCUSDT", "BADUSDT", "SOLUSDT") } | Should Not Throw
        # SOLUSDT ainda deve ter sido processado com sucesso apesar do BADUSDT falhar
        Assert-MockCalled -CommandName Save-StateRecords -Times 1 -Exactly -Scope It
    }

    It "BTC batch fetch falhando (1a chamada) nao impede fallback individual por mercado" {
        # O try/catch do batch para na PRIMEIRA excecao (fail-fast) -- so 1
        # chamada de BTC acontece no batch antes do catch. O fallback real
        # e cada Get-BetaMultiTF tentar buscar BTC de novo por conta propria.
        $script:btcCallCount = 0
        Mock -CommandName CoinEx-GetCandles -MockWith {
            param($market, $period, $limit)
            if ($market -eq "BTCUSDT") {
                $script:btcCallCount++
                if ($script:btcCallCount -eq 1) { throw "BTC batch falhou" }
            }
            $opens  = 1..20 | ForEach-Object { 100.0 + $_ }
            $closes = 1..20 | ForEach-Object { 101.0 + $_ }
            return (New-FakeCandles -Opens $opens -Closes $closes)
        }
        Mock -CommandName Save-StateRecords -MockWith { }
        { Sync-AllBetasMultiTF -Markets @("BTCUSDT", "NEARUSDT") } | Should Not Throw
        # NEARUSDT deve ter conseguido via fallback individual (BTC refetched dentro de Get-BetaMultiTF)
        Assert-MockCalled -CommandName Save-StateRecords -Times 1 -Exactly -Scope It
    }
}

Describe "Publish-BetaToSupabase" {
    It "grava record com todos os campos esperados" {
        Mock -CommandName Save-StateRecords -MockWith { }
        $betaData = [PSCustomObject]@{ beta_1d = 1.2; beta_4h = 1.1; beta_1h = 1.3; beta_weighted = 1.19 }
        $ok = Publish-BetaToSupabase -Market "NEARUSDT" -BetaData $betaData
        $ok | Should Be $true
        Assert-MockCalled -CommandName Save-StateRecords -Times 1 -Exactly -Scope It
    }
    It "fail-soft: excecao no Save-StateRecords retorna false, nao throw" {
        Mock -CommandName Save-StateRecords -MockWith { throw "supabase down" }
        $betaData = [PSCustomObject]@{ beta_1d = 1.2; beta_4h = 1.1; beta_1h = 1.3; beta_weighted = 1.19 }
        { Publish-BetaToSupabase -Market "NEARUSDT" -BetaData $betaData } | Should Not Throw
        (Publish-BetaToSupabase -Market "NEARUSDT" -BetaData $betaData) | Should Be $false
    }
}

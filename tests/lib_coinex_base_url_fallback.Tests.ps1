# lib_coinex_base_url_fallback.Tests.ps1 -- TDD
#
# Achado real 2026-08-02: short_scanner.ps1 dot-source lib_coinex.ps1 SEM
# nunca carregar agents/config.ps1 antes (workflow so grava config.local.ps1
# com credenciais via secrets, nao a URL base). lib_coinex.ps1 usa
# $COINEX_BASE_URL cru em ~20 chamadas Invoke-RestMethod, sem fallback --
# resultado real em producao: "Invalid URI: The hostname could not be
# parsed" ao chamar CoinEx-GetAllFuturesTickers (radar dinamico SHORT,
# commit d272a61).
#
# Documentado em VARIAS outras libs do projeto ja com o mesmo padrao de
# fallback (lib_candle_fetcher.ps1, lib_breadth_monitor.ps1,
# lib_entry_conviction_ensemble.ps1, lib_tori_gate_wrapper.ps1): mesmo
# quando agents/config.ps1 E carregado, ele define $COINEX_BASE_URL em
# escopo de SCRIPT (sem $global:), entao funcoes chamadas de dentro de
# OUTRA lib (lib_coinex.ps1, escopo proprio) nunca enxergam essa variavel
# via herança de escopo -- so $global: atravessa escopos de forma confiavel
# em PowerShell dot-sourcing entre arquivos diferentes.
#
# Fix: lib_coinex.ps1 agora define $COINEX_BASE_URL no topo do arquivo com
# fallback pra "https://api.coinex.com" caso nem $global:COINEX_BASE_URL
# nem $COINEX_BASE_URL (script-scope, caso config.ps1 tenha sido
# dot-sourced ANTES desta lib no mesmo escopo) estejam populados.

Describe "lib_coinex.ps1 -- fallback de COINEX_BASE_URL quando config.ps1 nunca foi carregado" {

    It "COINEX_BASE_URL fica populado com o default mesmo sem nenhuma variavel pre-existente (cenario real: short_scanner.ps1 sem config.ps1)" {
        # Sandbox: roda num scriptblock isolado, SEM nenhuma variavel
        # COINEX_BASE_URL pre-definida (nem global, nem script) -- reproduz
        # exatamente o bug real (short_scanner.ps1 nunca carrega config.ps1).
        $result = & {
            Remove-Variable -Name COINEX_BASE_URL -Scope Global -ErrorAction SilentlyContinue
            function Write-Host { param() }
            function Write-Warning { param() }
            . "$PSScriptRoot\..\agents\lib_coinex.ps1"
            return $COINEX_BASE_URL
        }
        $result | Should Be "https://api.coinex.com"
    }

    It "respeita $global:COINEX_BASE_URL se ja estiver definido (nao sobrescreve customizacao, ex: testnet)" {
        $result = & {
            $global:COINEX_BASE_URL = "https://custom-testnet.example.com"
            function Write-Host { param() }
            function Write-Warning { param() }
            . "$PSScriptRoot\..\agents\lib_coinex.ps1"
            return $COINEX_BASE_URL
        }
        $result | Should Be "https://custom-testnet.example.com"
        Remove-Variable -Name COINEX_BASE_URL -Scope Global -ErrorAction SilentlyContinue
    }

    It "CoinEx-GetAllFuturesTickers monta uma URI valida mesmo sem config.ps1 carregado antes (regressao real: 'Invalid URI: hostname could not be parsed')" {
        $threw = $false
        try {
            & {
                Remove-Variable -Name COINEX_BASE_URL -Scope Global -ErrorAction SilentlyContinue
                function Write-Host { param() }
                function Write-Warning { param() }
                . "$PSScriptRoot\..\agents\lib_coinex.ps1"
                Set-Item -Path function:Invoke-RestMethod -Value {
                    param([string]$Uri, [string]$Method = "GET", [int]$TimeoutSec = 15, $ErrorAction)
                    $global:__captured_uri = $Uri
                    return [PSCustomObject]@{ code = 0; data = @() }
                }
                CoinEx-GetAllFuturesTickers | Out-Null
            }
        } catch {
            $threw = $true
        }
        $threw | Should Be $false
        $global:__captured_uri | Should Be "https://api.coinex.com/v2/futures/ticker"
        Remove-Variable -Name __captured_uri -Scope Global -ErrorAction SilentlyContinue
        Remove-Item -Path function:Invoke-RestMethod -ErrorAction SilentlyContinue
    }
}

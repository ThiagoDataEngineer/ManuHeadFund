# gem_executor_baseurl_scope.Tests.ps1 -- TDD regressao do bug de scope COINEX_BASE_URL.
#
# Bug 2026-06-20 (cloud): gem_executor montava URIs com $global:COINEX_BASE_URL.
# Sob invocacao via & (gem_loop.ps1 -Once no cloud), config.ps1 e dot-sourced num
# script scope filho -> $COINEX_BASE_URL existe nesse scope mas $global: NAO ->
# URI vira "/v2/futures/..." sem host -> "Invalid URI: The hostname could not be
# parsed" -> Invoke-GemExecute aborta TODOS os gems -> 0 entradas.
# Mesma classe do fix 4309b41 (gem_agent). Cura: ler $COINEX_BASE_URL (scope chain).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "gem_executor.ps1")

Describe "CoinEx-HasFuturesMarket monta URI com host valido" {
    It "URI comeca com https://<host> mesmo quando \$global:COINEX_BASE_URL e null" {
        # reproduz o escopo do '&': global vazio, valor vive no scope do caller
        $global:COINEX_BASE_URL = $null
        $COINEX_BASE_URL = "https://api.coinex.com"
        $script:capUri = $null
        Mock Invoke-RestMethod { $script:capUri = $Uri; [PSCustomObject]@{ code = 0; data = @(1) } }
        CoinEx-HasFuturesMarket -Market "ALICEUSDT" | Out-Null
        $script:capUri | Should Match '^https://api\.coinex\.com/v2/futures/market'
    }
    AfterEach { Remove-Variable -Name COINEX_BASE_URL -Scope Global -ErrorAction SilentlyContinue }
}

Describe "gem_executor.ps1 nao usa \$global:COINEX_BASE_URL em URIs (guarda de regressao)" {
    It "Nenhuma string -Uri interpola \$global:COINEX_BASE_URL" {
        $src = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        # captura linhas com -Uri "...$global:COINEX_BASE_URL..."
        $bad = [regex]::Matches($src, '-Uri\s+"[^"]*\$global:COINEX_BASE_URL')
        $bad.Count | Should Be 0
    }
}

# gem_spot_tickers_diagnostic.Tests.ps1 -- TDD: Get-GemSpotTickers NAO pode falhar
# em silencio. Bug 2026-06-20: cloud retornava "0 pares" sem nenhuma pista da causa
# (try/catch engolia tudo). Codigo OK local (352 tickers) mas cloud 0 -> conectividade
# CoinEx do runner. Sem log, impossivel distinguir "0 legitimo" de "API inalcancavel".

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "gem_agent.ps1")

Describe "Get-GemSpotTickers avisa quando a chamada CoinEx falha" {
    It "Retorna vazio E emite Write-Warning quando Invoke-RestMethod lanca" {
        Mock -CommandName Invoke-RestMethod -MockWith { throw "403 region blocked" }
        Mock -CommandName Write-Warning {}
        $r = Get-GemSpotTickers
        @($r).Count | Should Be 0
        Assert-MockCalled Write-Warning -Scope It -Times 1 -Exactly
    }
}

Describe "Get-GemSpotTickers avisa quando CoinEx retorna code != 0" {
    It "Retorna vazio E avisa quando code != 0" {
        Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ code = 1; message = "rate limit"; data = @() } }
        Mock -CommandName Write-Warning {}
        $r = Get-GemSpotTickers
        @($r).Count | Should Be 0
        Assert-MockCalled Write-Warning -Scope It -Times 1 -Exactly
    }
}

Describe "Get-GemSpotTickers avisa quando COINEX_BASE_URL vazio" {
    It "Retorna vazio E avisa quando base URL ausente no escopo" {
        Mock -CommandName Write-Warning {}
        $COINEX_BASE_URL = $null
        $r = Get-GemSpotTickers
        @($r).Count | Should Be 0
        Assert-MockCalled Write-Warning -Scope It -Times 1 -Exactly
    }
}

Describe "Get-GemSpotTickers loga contagem no caminho de sucesso" {
    It "Retorna filtrados e emite Write-Host com contagem recebida/filtrada" {
        $fake = [PSCustomObject]@{
            code = 0
            data = @(
                [PSCustomObject]@{ market="AAAUSDT"; last="1"; value="100000"; high="1.1"; low="0.9"; open="1" },
                [PSCustomObject]@{ market="BBBUSDT"; last="2"; value="3000";   high="2.1"; low="1.9"; open="2" },  # fora do range (<5000)
                [PSCustomObject]@{ market="CCCBTC";  last="3"; value="100000"; high="3.1"; low="2.9"; open="3" }   # nao USDT
            )
        }
        Mock -CommandName Invoke-RestMethod -MockWith { $fake }
        Mock -CommandName Write-Host {}
        $r = @(Get-GemSpotTickers)
        $r.Count | Should Be 1
        $r[0].market | Should Be "AAAUSDT"
        Assert-MockCalled Write-Host -Scope It -Times 1 -Exactly
    }
}

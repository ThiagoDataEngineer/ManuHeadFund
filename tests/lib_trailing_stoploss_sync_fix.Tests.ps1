# lib_trailing_stoploss_sync_fix.Tests.ps1 -- TDD pro fix critico 2026-07-29.
# Pester 3.4 / ASCII-only.
#
# Achado real: CoinEx-SetStopLoss($market,$price) so aceita 2 parametros
# POSICIONAIS. Update-TrailingStops (lib_trailing.ps1) e Update-MentorReview
# (lib_mentor_reflection.ps1) chamavam com -Market/-OrderId/-StopPrice --
# nomeados que NAO existem na assinatura real. PowerShell ignora
# silenciosamente os nomeados invalidos (sem lancar erro), $price ficava
# $null, [math]::Round($null,4)=0 -- codigo enviava stop_loss_price="0" pra
# CoinEx a cada avanco de fase do trailing, removendo a protecao real de
# stop na corretora sem sintoma visivel (try/catch nunca disparava porque a
# chamada "funcionava", so com o valor errado).
#
# Este teste usa o cmdlet Mock do Pester (nao redefinicao de function global
# simples) pra capturar os parametros REAIS recebidos por CoinEx-SetStopLoss
# quando o trailing avanca de fase -- garante que $price nunca seja $null/0.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_trailing.ps1"

Describe "Update-TrailingStops -- CoinEx-SetStopLoss recebe preco real (nao null/0)" {

    BeforeEach {
        $script:testDir = Join-Path $env:TEMP ("trailstopfix_" + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        $global:TRAILING_FILE = Join-Path $script:testDir "trailing_positions.json"
        $global:TRAILING_USE_STATE_STORE = $false
        $env:TRAILING_USE_STATE_STORE = "0"

        Mock -CommandName Send-TelegramAlert -MockWith { $true }
        Mock -CommandName CoinEx-SetStopLoss -MockWith { $true }
    }
    AfterEach {
        if (Test-Path $script:testDir) { Remove-Item $script:testDir -Recurse -Force }
    }

    It "quando o trailing avanca de fase (preco atinge 33% do alvo), CoinEx-SetStopLoss recebe -price NAO-NULL e NAO-ZERO" {
        # LONG entry=100 stop=90 target=130 -> 33% do caminho = 100 + 30*0.33 = ~109.9
        Add-TrailingPosition -Market "TESTUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem"
        Mock -CommandName CoinEx-GetTicker -MockWith { [PSCustomObject]@{ last = 111.0 } }

        Update-TrailingStops

        Assert-MockCalled -CommandName CoinEx-SetStopLoss -Times 1 -Exactly -Scope It -ParameterFilter {
            $null -ne $price -and [double]$price -gt 0
        }
    }

    It "o valor de -price passado bate com o novo stop calculado (nao e generico/zero)" {
        Add-TrailingPosition -Market "TESTUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem"
        Mock -CommandName CoinEx-GetTicker -MockWith { [PSCustomObject]@{ last = 111.0 } }

        Update-TrailingStops

        $positions = Get-TrailingPositions | Where-Object { $_.market -eq "TESTUSDT" }
        $expectedStop = $positions[0].stopCurrent

        Assert-MockCalled -CommandName CoinEx-SetStopLoss -Times 1 -Exactly -Scope It -ParameterFilter {
            [double]$price -eq [double]$expectedStop
        }
    }

    It "SHORT tambem recebe -price real ao avancar de fase" {
        Add-TrailingPosition -Market "SHORTUSDT" -Side "SHORT" -Entry 100 -Stop 110 -Target 70 -Source "gem"
        Mock -CommandName CoinEx-GetTicker -MockWith { [PSCustomObject]@{ last = 89.0 } }

        Update-TrailingStops

        Assert-MockCalled -CommandName CoinEx-SetStopLoss -Times 1 -Exactly -Scope It -ParameterFilter {
            $null -ne $price -and [double]$price -gt 0
        }
    }
}

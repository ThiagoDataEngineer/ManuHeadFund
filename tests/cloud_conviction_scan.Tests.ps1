# cloud_conviction_scan.Tests.ps1 -- Fase 3: job online de signal+conviction (OBSERVE)
# Roda no Actions: varre movers, computa ensemble 7 eixos, LOGA observacoes
# (state_store, cloud-persistente). NUNCA executa trade. Valida-se 1 semana antes de virar live.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Fase 3 - Cloud Conviction Scan (observe)" {

    BeforeAll {
        $script:src = Get-Content ".\scripts\cloud_conviction_scan.ps1" -Raw
    }

    Context "Observe mode -- seguranca (zero execucao)" {
        It "NAO chama Invoke-GemExecute" {
            $script:src | Should Not Match "Invoke-GemExecute"
        }
        It "NAO chama CoinEx-PlaceOrder" {
            $script:src | Should Not Match "CoinEx-PlaceOrder"
        }
        It "declara OBSERVE explicitamente" {
            $script:src | Should Match "OBSERVE"
        }
    }

    Context "Computa o ensemble" {
        It "usa Get-MarketConviction" {
            $script:src | Should Match "Get-MarketConviction"
        }
        It "avalia LONG e SHORT" {
            ($script:src -match "LONG" -and $script:src -match "SHORT") | Should Be $true
        }
    }

    Context "Persiste observacoes (cloud)" {
        It "grava via state_store ou conviction_observations" {
            ($script:src -match "conviction_observations" -or $script:src -match "Save-StateRecords") | Should Be $true
        }
    }

    Context "Carregavel (sintaxe)" {
        It "script tem sintaxe valida" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize($script:src, [ref]$err)
            $err.Count | Should Be 0
        }
    }

    Context "Workflow tem o job" {
        It "trading-pipeline.yml referencia cloud_conviction_scan" {
            $wf = Get-Content ".\.github\workflows\trading-pipeline.yml" -Raw
            $wf | Should Match "cloud_conviction_scan"
        }
    }
}

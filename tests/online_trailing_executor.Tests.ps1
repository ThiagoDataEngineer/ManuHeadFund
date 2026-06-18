# online_trailing_executor.Tests.ps1 -- Fase 1: trailing EXECUTA online (empurra SL)
# Valida que trailing_stop_monitor (cross-platform, roda no Actions) carrega e
# chama o executor de SL (Sync-TrailingToExchange) + peak update fino.
# Read-only structural + funcional. Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Fase 1 - Online trailing executor" {

    BeforeAll {
        $script:mon = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw
    }

    Context "Monitor online wira o executor de SL" {
        It "carrega lib_trailing_sync" {
            $script:mon | Should Match "lib_trailing_sync"
        }
        It "carrega lib_trailing_peak_update" {
            $script:mon | Should Match "lib_trailing_peak_update"
        }
        It "chama Sync-TrailingToExchange (empurra SL)" {
            $script:mon | Should Match "Sync-TrailingToExchange"
        }
        It "chama Update-TrailingPeakLive (lock fino +2.5pct)" {
            $script:mon | Should Match "Update-TrailingPeakLive"
        }
    }

    Context "Funcoes existem e sao carregaveis (cross-platform)" {
        BeforeAll {
            . ".\agents\lib_trailing_peak_update.ps1"
            . ".\agents\lib_trailing_sync.ps1"
        }
        It "Sync-TrailingToExchange disponivel" {
            (Get-Command Sync-TrailingToExchange -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }
        It "Update-TrailingPeakLive disponivel" {
            (Get-Command Update-TrailingPeakLive -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }
        It "Resolve-TrailingSync seguro (nao empurra SL que dispararia) - regressao" {
            $r = Resolve-TrailingSync -Side "LONG" -CurrentPrice 72.49 -JournalStop 74.65 -ExchangeStop 68.67
            $r.should_push | Should Be $false
        }
    }
}

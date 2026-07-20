# cloud_execution_safety.Tests.ps1 — Validação de segurança cloud-only
# Garante que LOOP local não roda, -Once bypassa gates, e nuvem é único executor
# TDD: 15 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Cloud Execution Safety" {

    Context "Local execution bloqueado (gem_loop)" {
        BeforeAll { $script:gl = Get-Content ".\scripts\gem_loop.ps1" -Raw }

        It "LOCAL_TRADING_DISABLED.flag existe" {
            Test-Path ".\journal\LOCAL_TRADING_DISABLED.flag" | Should Be $true
        }
        It "gem_loop testa flag" {
            $script:gl | Should Match "LOCAL_TRADING_DISABLED"
        }
        It "gem_loop exit 0 se flag presente (sem -Once)" {
            $script:gl | Should Match "exit\s+0"
        }
        It "-Once bypassa o gate" {
            ($script:gl | Should Match '\$Once.*bypas' -or $script:gl | Should Match 'if.*\$Once')
        }
    }

    Context "Local execution bloqueado (scan_master)" {
        BeforeAll { $script:sm = Get-Content ".\scripts\scan_master.ps1" -Raw }

        It "scan_master existe" {
            Test-Path ".\scripts\scan_master.ps1" | Should Be $true
        }
        It "scan_master testa LOCAL_TRADING_DISABLED" {
            $script:sm | Should Match "LOCAL_TRADING_DISABLED"
        }
    }

    Context "Cloud mode: -Once flag presente" {
        It "gem_loop.ps1 aceita -Once" {
            (Get-Content ".\scripts\gem_loop.ps1" -Raw) | Should Match '\[switch\]\$Once'
        }
        It "scan_master.ps1 aceita -Once" {
            (Get-Content ".\scripts\scan_master.ps1" -Raw) | Should Match '\[switch\]\$Once'
        }
        It "telegram_listener.ps1 aceita -Once" {
            (Get-Content ".\scripts\telegram_listener.ps1" -Raw) | Should Match '\[switch\]\$Once'
        }
    }

    Context "State backend: Supabase obrigatório" {
        BeforeAll { $script:ss = Get-Content ".\agents\lib_state_store.ps1" -Raw }

        It "lib_state_store.ps1 existe" {
            Test-Path ".\agents\lib_state_store.ps1" | Should Be $true
        }
        It "Test-StateBackend valida Supabase" {
            $script:ss | Should Match "Test-StateBackend"
        }
        It "Get-StateRecords implementado" {
            $script:ss | Should Match "function Get-StateRecords"
        }
        It "Save-StateRecords implementado" {
            $script:ss | Should Match "function Save-StateRecords"
        }
    }

    Context "Flags de modo" {
        It "CLOUD_ONLY_MODE.flag existe" {
            Test-Path ".\journal\CLOUD_ONLY_MODE.flag" | Should Be $true
        }
        It "LIVE_MODE_ENABLED.flag existe" {
            Test-Path ".\journal\LIVE_MODE_ENABLED.flag" | Should Be $true
        }
        It "POSITION_WATCHER_DISABLED.flag existe" {
            Test-Path ".\journal\POSITION_WATCHER_DISABLED.flag" | Should Be $true
        }
    }

    Context "Sintaxe valida" {
        It "gem_loop.ps1 parse OK" {
            $err=$null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\gem_loop.ps1" -Raw),[ref]$err)
            $err.Count | Should Be 0
        }
        It "scan_master.ps1 parse OK" {
            $err=$null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\scan_master.ps1" -Raw),[ref]$err)
            $err.Count | Should Be 0
        }
    }

}

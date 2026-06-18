# cloud_only_mode.Tests.ps1 — Validação CLOUD-ONLY: local desligado, nuvem ativa
# Modo: local NÃO trada, GitHub Actions (24/7) é única fonte
# State: Supabase backend, zero dependência de PC local
# TDD: 19 testes críticos

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "CLOUD-ONLY Mode — Local Disabled + Nuvem Ativa" {

    Context "Flags: Local desligado" {
        It "LOCAL_TRADING_DISABLED.flag existe" {
            Test-Path ".\journal\LOCAL_TRADING_DISABLED.flag" | Should Be $true
        }
        It "POSITION_WATCHER_DISABLED.flag existe" {
            Test-Path ".\journal\POSITION_WATCHER_DISABLED.flag" | Should Be $true
        }
        It "CLOUD_ONLY_MODE.flag existe" {
            Test-Path ".\journal\CLOUD_ONLY_MODE.flag" | Should Be $true
        }
        It "LIVE_MODE_ENABLED.flag existe" {
            Test-Path ".\journal\LIVE_MODE_ENABLED.flag" | Should Be $true
        }
    }

    Context "gem_loop: respira -Once (nuvem) ou para local" {
        BeforeAll { $script:gl = Get-Content ".\scripts\gem_loop.ps1" -Raw }
        It "arquivo existe" {
            Test-Path ".\scripts\gem_loop.ps1" | Should Be $true
        }
        It "tem param -Once" {
            $script:gl | Should Match '\[switch\]\$Once'
        }
        It "testa LOCAL_TRADING_DISABLED.flag" {
            $script:gl | Should Match "LOCAL_TRADING_DISABLED|local.*disabled"
        }
        It "se -Once, bypassa flag (roda nuvem)" {
            ($script:gl -match 'if.*\$Once' -or $script:gl -match '\$Once.*bypas') | Should Be $true
        }
    }

    Context "scan_master: parado local, ativo nuvem" {
        BeforeAll { $script:sm = Get-Content ".\scripts\scan_master.ps1" -Raw }
        It "arquivo existe" {
            Test-Path ".\scripts\scan_master.ps1" | Should Be $true
        }
        It "testa LOCAL_TRADING_DISABLED.flag" {
            $script:sm | Should Match "LOCAL_TRADING_DISABLED"
        }
    }

    Context "trailing_stop_monitor: JOB1 nuvem" {
        BeforeAll { $script:trail = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw }
        It "arquivo existe" {
            Test-Path ".\scripts\trailing_stop_monitor.ps1" | Should Be $true
        }
        It "carrega libs cross-platform ou state" {
            ($script:trail | Should Match "lib_cross_platform|lib_state_store|lib_coinex")
        }
        It "chama Update-TrailingPeakLive" {
            $script:trail | Should Match "Update-TrailingPeakLive"
        }
        It "chama Sync-TrailingToExchange" {
            $script:trail | Should Match "Sync-TrailingToExchange"
        }
    }

    Context "telegram_listener: JOB24 nuvem" {
        BeforeAll { $script:tg = Get-Content ".\scripts\telegram_listener.ps1" -Raw }
        It "tem param -Once" {
            $script:tg | Should Match '\[switch\]\$Once'
        }
        It "offset persistido em state_store" {
            ($script:tg -match "lastOffset|Save.*Offset|telegram_state") | Should Be $true
        }
    }

    Context "GitHub Actions workflow: 24 jobs, Supabase wired" {
        BeforeAll { $script:wf = Get-Content ".\.github\workflows\trading-pipeline.yml" -Raw }
        It "arquivo existe" {
            Test-Path ".\.github\workflows\trading-pipeline.yml" | Should Be $true
        }
        It "JOB1: trailing-stop-monitor existe e workflow roda cada 5min" {
            ($script:wf | Should Match "trailing-stop-monitor") -and ($script:wf | Should Match "\*/5")
        }
        It "JOB23: cloud-trading (gem_loop -Once)" {
            ($script:wf | Should Match "cloud-trading") -and ($script:wf | Should Match "gem_loop.*-Once")
        }
        It "JOB24: telegram-cloud listener" {
            $script:wf | Should Match "telegram.*listener.*-Once"
        }
        It "SUPABASE_URL injetada" {
            $script:wf | Should Match "SUPABASE_URL"
        }
        It "SUPABASE_SERVICE_KEY injetada" {
            $script:wf | Should Match "SUPABASE_SERVICE_KEY|service_role"
        }
        It "COINEX credenciais injetadas" {
            ($script:wf -match "COINEX_ACCESS_ID" -and $script:wf -match "COINEX_SECRET_KEY") | Should Be $true
        }
        It "TELEGRAM credenciais injetadas" {
            ($script:wf -match "TELEGRAM_BOT_TOKEN" -and $script:wf -match "TELEGRAM_CHAT_ID") | Should Be $true
        }
    }

    Context "State store: Supabase é backend" {
        BeforeAll { $script:ss = Get-Content ".\agents\lib_state_store.ps1" -Raw }
        It "Get-StateRecords implementado" {
            $script:ss | Should Match "function Get-StateRecords"
        }
        It "Save-StateRecords implementado" {
            $script:ss | Should Match "function Save-StateRecords"
        }
        It "Test-StateBackend valida Supabase" {
            $script:ss | Should Match "Test-StateBackend"
        }
        It "USE_SUPABASE_STATE.flag lê env" {
            $script:ss | Should Match "USE_SUPABASE_STATE|STATE_STORE_BACKEND"
        }
    }

    Context "Sintaxe: sem erros de parser" {
        It "gem_loop.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\gem_loop.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
        It "scan_master.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\scan_master.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
        It "trailing_stop_monitor.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
        It "telegram_listener.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\telegram_listener.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
    }

    Context "Cross-platform: nenhum backslash-path" {
        It "gem_loop.ps1 sem backslash-path literal" {
            $content = Get-Content ".\scripts\gem_loop.ps1" -Raw
            ($content -match 'journal\\|agents\\|logs\\') | Should Be $false
        }
        It "trailing_stop_monitor.ps1 sem backslash-path" {
            $content = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw
            ($content -match 'journal\\|agents\\|logs\\') | Should Be $false
        }
    }

}

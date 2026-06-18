# telegram_cloud.Tests.ps1 -- #3: telegram listener na nuvem (getUpdates, sem PC)
# Job Actions: roda telegram_listener.ps1 -Once a cada 5min, responde comandos
# read-only (/status /heartbeat) + execucao (/halt /fechar). Offset persistido em Supabase.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Telegram Cloud (listener -Once, Actions)" {

    Context "telegram_listener aceita -Once" {
        BeforeAll { $script:tg = Get-Content ".\scripts\telegram_listener.ps1" -Raw }
        It "tem param -Once" { $script:tg | Should Match '\[switch\]\$Once' }
        It "loop respeita -Once (sai apos 1 iteracao se presente)" {
            ($script:tg -match 'if.*\$Once' -or $script:tg -match '\$Once.*break' -or $script:tg -match 'exit.*\$Once') | Should Be $true
        }
    }

    Context "offset persistido (stateless cloud)" {
        BeforeAll { $script:tg = Get-Content ".\scripts\telegram_listener.ps1" -Raw }
        It "salva offset no journal apos processar" {
            ($script:tg -match 'lastOffset|offset.*save|Save-Offset' -or $script:tg -match 'telegram_state.json') | Should Be $true
        }
        It "le offset no startup (survive reboot cloud)" {
            ($script:tg -match 'Get-Content.*state|lastOffset.*=' -or $script:tg -match 'load.*offset') | Should Be $true
        }
    }

    Context "Workflow tem o job" {
        BeforeAll { $script:wf = Get-Content ".\.github\workflows\trading-pipeline.yml" -Raw }
        It "referencia telegram_listener.ps1 -Once" {
            $script:wf | Should Match "telegram_listener\.ps1.*-Once"
        }
        It "roda a cada 5min" {
            $script:wf | Should Match "\*\/5|\b5\b.*minute|frequency.*5"
        }
        It "job recebe TELEGRAM_BOT_TOKEN + CHAT_ID" {
            ($script:wf -match "TELEGRAM_BOT_TOKEN" -and $script:wf -match "TELEGRAM_CHAT_ID") | Should Be $true
        }
    }

    Context "Comandos: read-only" {
        BeforeAll { $script:tg = Get-Content ".\scripts\telegram_listener.ps1" -Raw }
        It "implementa /status" { $script:tg | Should Match "/status|Cmd-Status|status.*function" }
        It "implementa /heartbeat ou similar" {
            ($script:tg -match "heartbeat|alive|ping|Cmd-Heart") | Should Be $true
        }
    }

    Context "Comandos: controle" {
        BeforeAll { $script:tg = Get-Content ".\scripts\telegram_listener.ps1" -Raw }
        It "implementa /halt (pause trading)" { $script:tg | Should Match "/halt|Cmd-Halt" }
        It "implementa /resume (resume)" { $script:tg | Should Match "/resume|Cmd-Resume" }
        It "implementa /scan (trigger cron)" { $script:tg | Should Match "/scan|Cmd-Scan" }
    }

    Context "Sintaxe" {
        It "telegram_listener.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\telegram_listener.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
    }
}

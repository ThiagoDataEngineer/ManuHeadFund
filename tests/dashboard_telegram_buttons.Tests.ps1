# dashboard_telegram_buttons.Tests.ps1 -- #4: Dashboard live + Telegram botões controle
# Dashboard: pull Supabase real-time, mostra capital/posições/stops
# Telegram: /halt /resume /balance /stops /scan (botões de controle)
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Dashboard + Telegram Buttons (Control UI)" {

    Context "Dashboard pull dados VIVOS" {
        It "collect_dashboard_data.ps1 existe" {
            Test-Path ".\scripts\collect_dashboard_data.ps1" | Should Be $true
        }
        It "puxa posicoes via CoinEx-GetPendingPositions" {
            (Get-Content ".\scripts\collect_dashboard_data.ps1" -Raw) | Should Match "GetPendingPositions|CoinEx-Get"
        }
        It "puxa balance via CoinEx-GetBalance" {
            (Get-Content ".\scripts\collect_dashboard_data.ps1" -Raw) | Should Match "GetBalance"
        }
        It "puxa open orders (vigilancia)" {
            (Get-Content ".\scripts\collect_dashboard_data.ps1" -Raw) | Should Match "GetOpenOrders"
        }
    }

    Context "Dashboard HTML renderiza dados" {
        BeforeAll { $script:html = Get-Content ".\dashboard\index.html" -Raw }
        It "mostra Capital Total" { $script:html | Should Match "Capital|Balance|Total" }
        It "mostra Posicoes abertas" { $script:html | Should Match "Position|Posicao|Market" }
        It "mostra Open Orders (vigilancia)" { $script:html | Should Match "Order|Pending" }
        It "mostra Status geral" { $script:html | Should Match "Status|Operational|OK" }
    }

    Context "Telegram botões" {
        BeforeAll { $script:tg = Get-Content ".\scripts\telegram_listener.ps1" -Raw }
        It "/halt funciona" { $script:tg | Should Match "/halt|Cmd-Halt" }
        It "/resume funciona" { $script:tg | Should Match "/resume|Cmd-Resume" }
        It "/balance novo (mostra capital)" {
            ($script:tg -match "/balance|Cmd-Balance" -or $script:tg -match "balance.*capital") | Should Be $true
        }
        It "/stops novo (lista vigilancia)" {
            ($script:tg -match "/stops|Cmd-Stops" -or $script:tg -match "stops.*order") | Should Be $true
        }
        It "/scan dispara (trigger cron)" { $script:tg | Should Match "/scan|Cmd-Scan" }
    }

    Context "Journal reconciliado" {
        It "trailing_positions.json sem duplicatas" {
            $t = @(Get-Content ".\journal\trailing_positions.json" -Raw | ConvertFrom-Json)
            $dups = $t | Group-Object market | Where-Object { $_.Count -gt 1 }
            $dups.Count | Should Be 0
        }
        It "trade_outcomes.jsonl tem open orders registrados" {
            (Get-Content ".\journal\trade_outcomes.jsonl" -Raw) | Should Match "PENDING_FILL"
        }
    }

    Context "Workflow jobs wired" {
        BeforeAll { $script:wf = Get-Content ".\.github\workflows\trading-pipeline.yml" -Raw }
        It "JOB 4 dashboard roda (atualiza gh-pages)" {
            $script:wf | Should Match "collect_dashboard_data|dashboard"
        }
        It "JOB 24 telegram roda (botoes)" {
            $script:wf | Should Match "telegram_listener.*-Once"
        }
    }

    Context "Sintaxe" {
        It "collect_dashboard_data.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\collect_dashboard_data.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
        It "telegram_listener.ps1 OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\telegram_listener.ps1" -Raw),[ref]$err); $err.Count | Should Be 0
        }
    }
}

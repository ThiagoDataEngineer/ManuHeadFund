# github_actions_workflow.Tests.ps1 — Validação de workflow Actions
# Garante que JOBs estão configurados, secrets existem, order é correto
# TDD: 12 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "GitHub Actions Workflow (trading-pipeline.yml)" {

    BeforeAll {
        $script:wf = Get-Content ".\.github\workflows\trading-pipeline.yml" -Raw
    }

    Context "Arquivo workflow existe" {
        It "trading-pipeline.yml presente" {
            Test-Path ".\.github\workflows\trading-pipeline.yml" | Should Be $true
        }
        It "Arquivo não vazio" {
            $script:wf.Length | Should BeGreaterThan 1000
        }
    }

    Context "Schedule: a cada 5 minutos" {
        It "schedule section existe" {
            $script:wf | Should Match "on:\s+schedule"
        }
        It "cron: */5 minutos" {
            $script:wf | Should Match "\*/5"
        }
        It "workflow_dispatch presente (manual trigger)" {
            $script:wf | Should Match "workflow_dispatch"
        }
    }

    Context "JOBs críticos existem" {
        It "trailing-stop-monitor (JOB 1)" {
            $script:wf | Should Match "trailing-stop-monitor:"
        }
        It "cloud-trading (JOB 23 — gem_loop -Once)" {
            $script:wf | Should Match "cloud-trading:"
        }
        It "telegram (JOB 24 — listener -Once)" {
            $script:wf | Should Match "telegram"
            $script:wf | Should Match "listener"
        }
    }

    Context "Secrets injezadas (credenciais)" {
        It "SUPABASE_URL" {
            $script:wf | Should Match "SUPABASE_URL"
        }
        It "SUPABASE_SERVICE_KEY" {
            $script:wf | Should Match "SUPABASE_SERVICE_KEY"
        }
        It "COINEX_ACCESS_ID" {
            $script:wf | Should Match "COINEX_ACCESS_ID"
        }
        It "COINEX_SECRET_KEY" {
            $script:wf | Should Match "COINEX_SECRET_KEY"
        }
        It "TELEGRAM_BOT_TOKEN" {
            $script:wf | Should Match "TELEGRAM_BOT_TOKEN"
        }
    }

    Context "Job order (dependencies)" {
        It "trailing-stop-monitor roda antes" {
            # Validar que trailing vem antes de health-check
            $trailingIdx = $script:wf.IndexOf("trailing-stop-monitor:")
            $healthIdx = $script:wf.IndexOf("health-check:")
            $trailingIdx | Should BeLessThan $healthIdx
        }
        It "Ubuntu runner (cross-platform)" {
            $script:wf | Should Match "runs-on:\s+ubuntu-latest"
        }
    }

    Context "PowerShell shell" {
        It "shell: pwsh presente" {
            $script:wf | Should Match "shell:\s+pwsh"
        }
        It "Nenhum cmd.exe" {
            $script:wf | Should Not Match "cmd\.exe|cmd /c"
        }
    }

}

# cloud_trading.Tests.ps1 -- "trading online": gem_loop -Once no Actions, com trava dry.
# Seguranca: enquanto CLOUD_DRY_RUN.flag existir, nenhuma ordem real dispara
# (prova que o stack de 32 libs carrega no ubuntu antes de virar live).
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Cloud Trading (gem_loop -Once no Actions)" {

    Context "gem_loop honra a trava dry" {
        BeforeAll { $script:gl = Get-Content ".\scripts\gem_loop.ps1" -Raw }
        It "tem param -DryRun" { $script:gl | Should Match '\[switch\]\$DryRun' }
        It "honra CLOUD_DRY_RUN.flag (forca dry)" { $script:gl | Should Match "CLOUD_DRY_RUN" }
        It "passa -DryRun ao executor" { $script:gl | Should Match 'Invoke-GemExecute.*-DryRun' }
    }

    Context "Workflow tem o job de trading" {
        BeforeAll { $script:wf = Get-Content ".\.github\workflows\trading-pipeline.yml" -Raw }
        It "referencia gem_loop -Once" { $script:wf | Should Match "gem_loop.ps1 -Once" }
        It "job recebe credenciais (COINEX + SUPABASE)" {
            ($script:wf -match "COINEX_ACCESS_ID" -and $script:wf -match "SUPABASE_URL") | Should Be $true
        }
        It "job recebe chaves LLM (Mesa/Mentor precisam)" {
            ($script:wf -match "ANTHROPIC_API_KEY" -or $script:wf -match "GROQ_API_KEY") | Should Be $true
        }
    }

    Context "Trava dry ATIVA por default (prova antes de live)" {
        # 2026-07-23: FALHA ESPERADA -- este teste valida a fase de transicao
        # (2026-06-18/19, dry-run antes de virar live). Sistema esta em LIVE
        # TRADING real desde antes de 2026-07-22 (ver CLAUDE.md), CLOUD_DRY_RUN.flag
        # foi removido de proposito pelo cutover (ver cutover_online.Tests.ps1,
        # que exige o oposto: flag REMOVIDO = cloud live). Nao recriar o flag.
        It "CLOUD_DRY_RUN.flag presente (deploy dry primeiro)" {
            Test-Path ".\journal\CLOUD_DRY_RUN.flag" | Should Be $true
        }
    }

    Context "Sintaxe" {
        It "gem_loop sintaxe OK apos edit" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\gem_loop.ps1" -Raw), [ref]$err)
            $err.Count | Should Be 0
        }
    }
}

# capital_snapshot_runner.ps1 — TDD entry point
# Verifica que o runner que vai pro GitHub Actions:
#   - Forca Supabase backend + manuheadfund schema
#   - Chama Get-CapitalContext -Force
#   - Trata graciosamente fallback / total=0

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/capital_snapshot_runner.ps1"

Describe "capital_snapshot_runner.ps1" {

    It "Script file exists and parses cleanly" {
        Test-Path $scriptPath | Should Be $true
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should Be 0
    }

    It "Forces state_store backend = supabase" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'STATE_STORE_BACKEND\s*=\s*"supabase"') | Should Be $true
    }

    It "Forces schema = manuheadfund" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'STATE_STORE_SCHEMA\s*=\s*"manuheadfund"') | Should Be $true
    }

    It "Calls Get-CapitalContext with -Force flag" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'Get-CapitalContext\s+-Force') | Should Be $true
    }

    It "Detects source=fallback as warning (not failure)" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'source.*-eq\s+"fallback"') | Should Be $true
    }

    It "Detects total=0 as warning (not failure)" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'total\s+-le\s+0') | Should Be $true
    }

    It "Exits 0 on errors (graceful degradation)" {
        $content = Get-Content $scriptPath -Raw
        # Deve ter exit 0 dentro dos catches/avisos para nao matar workflow
        ($content -match 'exit 0') | Should Be $true
    }
}

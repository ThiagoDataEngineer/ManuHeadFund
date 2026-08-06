# layers_review_runner.ps1 — invocation TDD
#
# Verifica que o entry point chama as funcoes corretas para cada Layer.

$ErrorActionPreference = "Stop"

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/layers_review_runner.ps1"

Describe "layers_review_runner.ps1" {

    It "Script file exists and parses cleanly" {
        Test-Path $scriptPath | Should Be $true
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should Be 0
    }

    It "Has -Layer parameter with valid set 1, 2, 4, 5" {
        $content = Get-Content $scriptPath -Raw
        ($content -match "ValidateSet\(['""]1['""], ['""]2['""], ['""]4['""], ['""]5['""]\)") | Should Be $true
    }

    It "Forces state_store backend = supabase" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'STATE_STORE_BACKEND\s*=\s*"supabase"') | Should Be $true
    }

    It "Forces schema = manuheadfund" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'STATE_STORE_SCHEMA\s*=\s*"manuheadfund"') | Should Be $true
    }

    # 2026-08-06 FIX CRITICO: Update-TrailingStopsAdaptive (lib_trailing_adaptive.ps1)
    # usa ATR placeholder HARDCODED 100.0/100.0 (nunca implementado de verdade) --
    # pra ativos de preco baixo (PIPPINUSDT entry~$0.018), o breakeven calculado
    # (entry - buffer) vira numero absurdamente negativo (reproduzido real:
    # -129.9818, posicao real fechada por stop_atingido em 2026-08-04). Motor
    # unificado (lib_trailing_unified.ps1) ja cobre isso com ATR real. Guard
    # $false desativa a CHAMADA (codigo preservado pra rollback rapido).
    It "Layer 1 NAO chama Update-TrailingStopsAdaptive de verdade (guard $false -- ATR placeholder bug 2026-08-06)" {
        $content = Get-Content $scriptPath -Raw
        ($content -match '\$false\s+-and\s+\(Get-Command\s+Update-TrailingStopsAdaptive') | Should Be $true
    }

    It "Codigo de Update-TrailingStopsAdaptive preservado (mencionado no arquivo, so desativado)" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'Update-TrailingStopsAdaptive') | Should Be $true
    }

    It "Calls Update-MentorReview for Layer 2" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'Update-MentorReview') | Should Be $true
    }

    It "Calls Update-Layer4Review for Layer 4" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'Update-Layer4Review') | Should Be $true
    }

    It "Calls Update-MoonBagReview for Layer 5" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'Update-MoonBagReview') | Should Be $true
    }

    It "Exits 0 when no active positions (graceful skip)" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'Nenhuma posicao ativa' -and $content -match 'exit 0') | Should Be $true
    }
}

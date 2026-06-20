# trailing_monitor_outcome_wire.Tests.ps1 -- TDD wiring do espelho de outcomes.
#
# Garante que scripts/trailing_stop_monitor.ps1 (caminho de FECHAMENTO de posicao
# no cloud) carregue lib_feedback_loop.ps1, para que Add-TradeOutcome exista e a
# chamada gated em lib_trailing.ps1 dispare ao fechar -> grava JSONL local + espelha
# no Supabase. Sem este load, Add-TradeOutcome nao existe no runner e nenhum outcome
# eh registrado (causa de "0 rows" no Supabase).

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/trailing_stop_monitor.ps1"

Describe "trailing_stop_monitor.ps1 -- wire outcome registration" {

    It "Script existe e faz parse limpo" {
        Test-Path $scriptPath | Should Be $true
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should Be 0
    }

    It "Carrega lib_feedback_loop.ps1 (para Add-TradeOutcome existir)" {
        $content = Get-Content $scriptPath -Raw
        ($content -match 'lib_feedback_loop\.ps1') | Should Be $true
    }
}

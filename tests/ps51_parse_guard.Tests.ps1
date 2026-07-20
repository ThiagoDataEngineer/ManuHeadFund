# tests/ps51_parse_guard.Tests.ps1
# GATE (2026-07-07): garante que os arquivos tocados na evolucao trailing multi-TF +
# adocao de Futures PARSEIAM em PowerShell 5.1 (sem `??`, ternario ou sintaxe PS7-only).
# Licao recorrente: codigo PS7-only quebra o PARSE inteiro da lib no PS 5.1 e a funcao
# "some" silenciosamente. Ver project_ps51_class_fix_2026_07_02.
#
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$targets = @(
    "agents/lib_trailing_adaptive.ps1",
    "agents/lib_trailing_orphan_detection.ps1",
    "agents/lib_trailing_policy_live.ps1",
    "scripts/trailing_stop_monitor.ps1",
    "agents/lib_daemon_watchdog_v2.ps1",
    "agents/lib_direction_learning.ps1",
    "agents/lib_evolution_engine.ps1",
    "scripts/mce_counterfactual_report.ps1",
    "scripts/grade_llm_decisions.ps1"
)

Describe "PS 5.1 parse guard (arquivos editados)" {
    foreach ($rel in $targets) {
        It "parseia sem erros: $rel" {
            $path = Join-Path $root $rel
            Test-Path $path | Should Be $true
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content $path -Raw), [ref]$err)
            if ($err.Count -gt 0) {
                Write-Host ("Parse errors em {0}:" -f $rel)
                $err | ForEach-Object { Write-Host ("  L{0}: {1}" -f $_.Token.StartLine, $_.Message) }
            }
            $err.Count | Should Be 0
        }
    }
}

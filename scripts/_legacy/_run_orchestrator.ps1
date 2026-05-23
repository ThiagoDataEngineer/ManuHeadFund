# _run_orchestrator.ps1 — entry point com encoding correto
# Usa: . .\agents\config.ps1 primeiro
param(
    [string]$Market      = "BTCUSDT",
    [switch]$DryRun,
    [switch]$SkipFund,
    [switch]$SkipSent,
    [switch]$SkipChain,
    [switch]$SkipMentor
)

chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\agents\orchestrator.ps1"

Invoke-OrchestratorAgent -Market $Market `
    -DryRun:$DryRun `
    -SkipFund:$SkipFund `
    -SkipSent:$SkipSent `
    -SkipChain:$SkipChain `
    -SkipMentor:$SkipMentor

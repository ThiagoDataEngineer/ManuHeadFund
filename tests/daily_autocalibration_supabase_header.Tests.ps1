# daily_autocalibration_supabase_header.Tests.ps1 — TDD 2026-09-08
# Achado: hourly-autocalibration.yml roda toda hora ha indefinidamente sem
# nunca aplicar calibracao real. Causa raiz dupla em scripts/daily_autocalibration.ps1:
#   1. Chamadas ao PostgREST (Supabase) so mandavam header "Authorization",
#      sem "apikey" -- PostgREST exige os dois, entao GET e PATCH falhavam
#      sempre com "No API key found in request", caindo sempre no fallback local.
#   2. $ConfigDir nunca era definido (nao e' parametro nem setado antes de usar),
#      entao o fallback local (Test-Path "$ConfigDir/gates_drift.json") tambem
#      nunca resolvia certo.
# Sem alerta em nenhum canal -- 100% verde no GitHub Actions, 0% de efeito real.

$here = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $here "scripts\daily_autocalibration.ps1"
$scriptContent = Get-Content $scriptPath -Raw

Describe "daily_autocalibration.ps1 -- headers Supabase e ConfigDir" {

    It "declara ConfigDir como parametro (nao variavel nao-inicializada)" {
        $scriptContent | Should Match '\[string\]\$ConfigDir\s*='
    }

    It "chamada GET a regime_state inclui header apikey junto com Authorization" {
        # bloco do GET: da linha "Try Supabase first" ate "$response = Invoke-RestMethod -Uri .../regime_state"
        $getBlockMatch = [regex]::Match($scriptContent, 'Try Supabase first[\s\S]*?regime_state\?select=\*"')
        $getBlockMatch.Success | Should Be $true
        $getBlockMatch.Value | Should Match '"apikey"\s*='
    }

    It "chamada PATCH a regime_state inclui header apikey junto com Authorization" {
        $patchBlockMatch = [regex]::Match($scriptContent, 'Try Supabase update first[\s\S]*?Method PATCH')
        $patchBlockMatch.Success | Should Be $true
        $patchBlockMatch.Value | Should Match '"apikey"\s*='
    }
}

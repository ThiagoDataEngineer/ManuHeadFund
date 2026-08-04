# diag_evolution_engine_status_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner perguntou se o sistema "se atualiza sozinho" via LLM/aprendizado.
# Achado: lib_evolution_engine.ps1 (class=detection) roda de verdade a
# cada 6h desde 2026-07-17 e AJUSTA parametros sozinho dentro de bounds
# duros -- mas class=risk (sizing/stop/target) so gera proposta pendente,
# nunca aplica. Puxa o estado real: quantas mudancas ja aplicadas, quantas
# pendentes de aprovacao, e o overlay atual de parametros.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_evolution_engine.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: estado real do Evolution Engine ===" -ForegroundColor Cyan

Write-Host "`n--- Registro de parametros tunaveis (Get-TunableRegistry) ---" -ForegroundColor Yellow
Get-TunableRegistry | ForEach-Object {
    Write-Host ("  {0,-28} class={1,-10} default={2} min={3} max={4} step={5}" -f $_.name, $_.class, $_.default, $_.min, $_.max, $_.step)
}

Write-Host "`n--- Overlay atual (evolution_params, Supabase singleton id=current) ---" -ForegroundColor Yellow
try {
    $rows = @(Get-StateRecords -Table "evolution_params" -Filter @{ id = "current" })
    if ($rows.Count -gt 0) {
        $rows[0].PSObject.Properties | Where-Object { $_.Name -notin @("id","updated_at") } | ForEach-Object {
            Write-Host "  $($_.Name) = $($_.Value)"
        }
        Write-Host "  updated_at = $($rows[0].updated_at)"
    } else {
        Write-Host "  Nenhum overlay ainda -- rodando 100% nos defaults do registry."
    }
} catch { Write-Host "  ERRO: $_" -ForegroundColor Red }

Write-Host "`n--- Historico de mudancas aplicadas (evolution_history, Supabase) ---" -ForegroundColor Yellow
try {
    $hist = @(Get-StateRecords -Table "evolution_history")
    Write-Host "Total mudancas aplicadas (todas classe=detection, sozinho): $($hist.Count)"
    $hist | Sort-Object ts -Descending | Select-Object -First 15 | ForEach-Object {
        Write-Host ("  {0} {1}: {2} -> {3} ({4})" -f $_.ts, $_.param, $_.before, $_.after, $_.reason)
    }
} catch { Write-Host "  ERRO: $_" -ForegroundColor Red }

Write-Host "`n--- Propostas de RISCO pendentes de aprovacao humana (journal local) ---" -ForegroundColor Yellow
$journalDir = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
$pendPath = Join-Path $journalDir "evolution_owner_pending.jsonl"
if (Test-Path $pendPath) {
    $lines = @(Get-Content $pendPath -ErrorAction SilentlyContinue)
    Write-Host "Total entradas: $($lines.Count)"
    $lines | Select-Object -Last 10 | ForEach-Object {
        try {
            $entry = $_ | ConvertFrom-Json
            Write-Host "  ts=$($entry.ts)"
            $entry.proposals | ForEach-Object { Write-Host "    $($_.param): $($_.before) -> $($_.after) ($($_.reason))" }
        } catch {}
    }
} else {
    Write-Host "  Arquivo nao existe neste checkout (journal local nao persiste entre runs do GitHub Actions -- cada job comeca limpo)." -ForegroundColor DarkYellow
}

Write-Host "`n--- Ultimo cron_guard state (evolution_cycle) ---" -ForegroundColor Yellow
try {
    $cg = @(Get-StateRecords -Table "cron_state" -Filter @{ job_id = "evolution_cycle" })
    if ($cg.Count -gt 0) {
        Write-Host "  last_run_utc: $($cg[0].last_run_utc)"
    } else {
        Write-Host "  Nenhum registro de execucao encontrado (tabela/nome podem diferir -- verificar cron_guard.ps1)."
    }
} catch { Write-Host "  ERRO ou tabela nao existe: $_" -ForegroundColor DarkYellow }

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan

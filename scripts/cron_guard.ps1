# cron_guard.ps1 -- gate de execucao robusto a throttle do GH Actions.
# Uso no workflow:
#   $due = (& ./scripts/cron_guard.ps1 -JobId kelly -Schedule "daily:5"); if ($LASTEXITCODE -eq 0) { ... }
# Exit 0 = DEVE rodar (e persiste last-run); exit 1 = pular.
# Degrada com seguranca: se Supabase indisponivel, decide so pela janela (sem dedup)
# -- ainda assim melhor que o gate de minuto exato que nunca casava.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$Schedule
)

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }
. (Join-Path $agentsDir "lib_cron_guard.ps1")
# cron_state vive no schema manuheadfund (nao public, o default do state store).
if (-not $env:STATE_STORE_SCHEMA) { $env:STATE_STORE_SCHEMA = "manuheadfund" }
$stateOk = $false
try { . (Join-Path $agentsDir "lib_state_store.ps1"); $stateOk = $true } catch { }

$table = "cron_state"
$lastIso = ""
if ($stateOk) {
    try {
        $rec = @(Get-StateRecords -Table $table -Filter @{ job_id = $JobId })
        if ($rec.Count -gt 0 -and $rec[0].PSObject.Properties['last_run_utc']) {
            $raw = $rec[0].last_run_utc
            # se o cliente ja desserializou pra [datetime], normaliza p/ ISO invariant
            # (evita re-stringificacao em cultura local que quebra o parse a jusante).
            if ($raw -is [datetime]) { $lastIso = ([datetime]$raw).ToUniversalTime().ToString("o") }
            else { $lastIso = "$raw" }
        }
    } catch { }
}

$due = Test-CronDue -Schedule $Schedule -LastRunIso $lastIso -NowUtc ([datetime]::UtcNow)

if (-not $due) {
    Write-Host "[cron_guard] $JobId SKIP (schedule=$Schedule, last=$lastIso)"
    exit 1
}

# due == true: tenta persistir o last-run.
$persisted = $false
if ($stateOk) {
    try {
        Save-StateRecords -Table $table -Records @([PSCustomObject]@{
            job_id      = $JobId
            last_run_utc = ([datetime]::UtcNow).ToString("o")
        }) -PrimaryKey "job_id"
        $persisted = $true
    } catch { Write-Warning "cron_guard: falhou persistir last-run de '$JobId' ($($_.Exception.Message))" }
}

# daily/weekly SEM persistencia = perigoso: ficaria 'due' a janela inteira e rodaria
# dezenas de vezes/dia (ex: digest spammando Telegram). Fail-closed ate a tabela existir.
$isHardSchedule = ($Schedule -match '^(daily|weekly):')
if ($isHardSchedule -and -not $persisted) {
    Write-Warning "cron_guard: '$JobId' ($Schedule) precisa de cron_state p/ dedup diario/semanal, indisponivel -> SKIP. Rode docs/SETUP_SUPABASE_CRON_STATE.sql p/ ativar (sem isso rodaria varias vezes/dia)."
    Write-Host "[cron_guard] $JobId SKIP-NOPERSIST (schedule=$Schedule)"
    exit 1
}

Write-Host "[cron_guard] $JobId DUE (schedule=$Schedule, last=$lastIso)"
exit 0

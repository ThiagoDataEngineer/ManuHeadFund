# lib_learning_scheduler.ps1 -- Retroalimentacao periodica (counterfactual learning)
# 2026-06-09: Computa stats dos snapshots+outcomes+skips a cada 6 ciclos (~180min)

# Load libs se nao carregados
if (-not (Get-Command Invoke-LearningUpdate -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_direction_learning.ps1")
}
if (-not (Get-Command Get-State -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_state_store.ps1")
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-LearningCycle (I/O orquestrador) -- roda o loop completo uma vez.
# Lê snapshots (APROVAR/VETAR) + skips + outcomes -> computa stats -> salva.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-LearningCycle {
    param(
        [string]$JournalDir
    )
    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $PSScriptRoot ".." "journal" }
    }

    $snapshotsPath = Join-Path $JournalDir "signal_snapshots.jsonl"
    $skipsPath     = Join-Path $JournalDir "signal_skips.jsonl"
    $outcomesPath  = Join-Path $JournalDir "trade_outcomes.jsonl"
    $learnedPath   = Join-Path $JournalDir "learned_multipliers.json"

    Write-Host "[LEARNING] Iniciando ciclo de aprendizado..." -ForegroundColor Cyan
    $start = Get-Date

    # Parte 1: Aprender com trades fechados (aprovacoes com outcomes)
    $result1 = Invoke-LearningUpdate -SnapshotsPath $snapshotsPath -OutcomesPath $outcomesPath -OutPath $learnedPath
    Write-Host "  [TRADES] $($result1.snapshots) snapshots, $($result1.outcomes) outcomes, $($result1.joined) matched, $($result1.reliable_keys) reliable keys" -ForegroundColor Gray

    # Parte 2: Aprender com skips (counterfactual -- rejeicoes que performaram bem)
    # Try Supabase first, fallback to local JSONL
    $skips = @()
    if (Get-Command Get-State -ErrorAction SilentlyContinue) {
        try {
            $skips = @(Get-State -Table "signal_skips")
        } catch {
            # Supabase failed, try local
            $skips = @(Read-JsonLines -Path $skipsPath)
        }
    } else {
        $skips = @(Read-JsonLines -Path $skipsPath)
    }
    if ($skips -and @($skips).Count -gt 0) {
        Write-Host "  [SKIPS] $(@($skips).Count) rejeicoes capturadas; waiting 24h+ para avaliar counterfactual..." -ForegroundColor DarkCyan
    } else {
        Write-Host "  [SKIPS] nenhuma rejeicao capturada ainda" -ForegroundColor Gray
    }

    $elapsed = ((Get-Date) - $start).TotalSeconds
    Write-Host "[LEARNING] Ciclo completo em ${elapsed}s" -ForegroundColor Green
    return $true
}

# ─────────────────────────────────────────────────────────────────────────────
# Read-JsonLines (helper) -- le JSONL tolerante
# ─────────────────────────────────────────────────────────────────────────────
function Read-JsonLines {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return @() }
    $out = @()
    foreach ($ln in (Get-Content -Path $Path -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        try { $out += ($ln | ConvertFrom-Json) } catch { }
    }
    return $out
}

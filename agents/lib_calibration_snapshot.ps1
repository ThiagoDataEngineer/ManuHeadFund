# lib_calibration_snapshot.ps1 -- REGISTRO DO MOMENTO das calibracoes (2026-07-09)
#
# Gap fechado: gem_loop/trailing/scan_master/tori/faro operavam com parametros
# que NAO eram fotografados. Sem snapshot vigente, o grading (decision_grades,
# counterfactual, trailing_effectiveness) nao consegue correlacionar
# "calibracao X vigente -> outcome Y" -> rebalanceamento autonomo cego para
# tudo que esta fora do Tunable Registry (que cobre so 5 params).
#
# Uso:
#   Get-SystemCalibrationSnapshot  -> objeto com TODAS as calibracoes vigentes
#   Write-CalibrationSnapshot      -> journal/calibration_snapshots.jsonl
#                                     (dedup diario: so grava se mudou ou dia novo)
#                                     + Supabase best-effort (calibration_snapshots)
#
# Consumo downstream: grade_llm_decisions e counterfactual podem dar JOIN por
# data/regime pra medir efeito de cada calibracao. LLMs aprendendo agentes.
#
# PS 5.1. UTF-8 BOM.

function Get-SystemCalibrationSnapshot {
    [CmdletBinding()]
    param()

    # ── gem_safety (lib_gem_safety defaults ou override global) ─────────────
    $gs = if ($global:GEM_SAFETY) { $global:GEM_SAFETY } else {
        @{ MaxExposurePct = 15.0; MaxGemsPerDay = 10; MaxGemsPerWeek = 40
           CircuitBreakerStops = 5; DoubleConfirmThreshold = 10.0 }
    }

    # ── trailing (lib_trailing fases + lib_trailing_adaptive multipliers) ───
    $trailing = [PSCustomObject]@{
        phases = "0=inicial 1=BE 2=lock1 3=trailing"
        be_buffer_pct = 0.02
        regime_multipliers = [PSCustomObject]@{
            BULL_STRONG = 0.75; BULL_WEAK = 1.0; SIDEWAYS = 1.3
            TRANSITION_UP = 1.1; TRANSITION_DOWN = 1.2
            BEAR_WEAK = 1.4; BEAR_STRONG = 1.5; CAPITULATION = 0.5
        }
    }

    # ── tori (gate threshold vigente: gates_drift.json > default 80) ────────
    $toriThreshold = 80
    $toriRequired = $false
    try {
        $gatesDriftPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config\gates_drift.json"
        if (Test-Path $gatesDriftPath) {
            $gd = Get-Content $gatesDriftPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($gd.gates.tori_optional_threshold) { $toriThreshold = [int]$gd.gates.tori_optional_threshold }
            if ($null -ne $gd.gates.tori_required) { $toriRequired = [bool]$gd.gates.tori_required }
        }
    } catch {}
    $tori = [PSCustomObject]@{
        confluence_threshold = $toriThreshold
        required = $toriRequired
        timeframes = @("1W","1D","4H","1H")
    }

    # ── faro v3 (7-signal, hardcoded no scoring) ─────────────────────────────
    $faroLive = @{}
    try {
        $calibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\calibration_params_live.json"
        if (Test-Path $calibPath) {
            $cl = Get-Content $calibPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $faroLive = @{
                threshold_entrada = $cl.THRESHOLD_ENTRADA
                target_profit_pct = $cl.TARGET_PROFIT_PCT
                stop_loss_pct     = $cl.STOP_LOSS_PCT
                short_ratio       = $cl.SHORT_RATIO
            }
        }
    } catch {}
    $faro = [PSCustomObject]@{
        signals_needed  = 5
        signals_urgente = 6
        score_norm_base = 175
        live_params     = [PSCustomObject]$faroLive
    }

    # ── evolution registry (tunables + overlay vigente) ─────────────────────
    $evo = [PSCustomObject]@{ registry_size = 5; params = $null }
    try {
        if (Get-Command Get-EvolutionParams -ErrorAction SilentlyContinue) {
            $evo = [PSCustomObject]@{
                registry_size = @(Get-TunableRegistry).Count
                params = Get-EvolutionParams
            }
        }
    } catch {}

    # ── stops per-asset (calibracao nova 2026-07-09) ─────────────────────────
    $stops = [PSCustomObject]@{
        atr_multiplier = 2.5
        clamp_min = 0.02
        clamp_max = 0.12
        fallback_pct = 0.08
        atr_period = 14
    }

    # ── contexto pra correlacao ──────────────────────────────────────────────
    $regime = if ($global:MARKET_REGIME) { "$global:MARKET_REGIME" } else {
        $r = "UNKNOWN"
        try {
            $regPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\regime_state.json"
            if (Test-Path $regPath) {
                $rs = Get-Content $regPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($rs.current_regime) { $r = "$($rs.current_regime)" }
            }
        } catch {}
        $r
    }

    return [PSCustomObject]@{
        ts         = (Get-Date).ToUniversalTime().ToString("o")
        date       = (Get-Date).ToString("yyyy-MM-dd")
        regime     = $regime
        gem_safety = [PSCustomObject]$gs
        trailing   = $trailing
        tori       = $tori
        faro       = $faro
        evolution  = $evo
        stops      = $stops
    }
}


function Write-CalibrationSnapshot {
    [CmdletBinding()]
    param(
        [string] $JournalDir = ""
    )
    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else {
            Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
        }
    }

    try {
        $snap = Get-SystemCalibrationSnapshot
        $path = Join-Path $JournalDir "calibration_snapshots.jsonl"

        # Dedup diario: compara payload (sem ts) com a ultima linha do mesmo dia
        $payload = $snap | Select-Object -Property * -ExcludeProperty ts
        $payloadJson = $payload | ConvertTo-Json -Compress -Depth 6
        if (Test-Path $path) {
            $last = Get-Content $path -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($last) {
                try {
                    $lastObj = $last | ConvertFrom-Json
                    $lastPayload = $lastObj | Select-Object -Property * -ExcludeProperty ts
                    $lastJson = $lastPayload | ConvertTo-Json -Compress -Depth 6
                    if ($lastJson -eq $payloadJson) { return $true }  # nada mudou
                } catch {}
            }
        }

        Add-Content -Path $path -Value ($snap | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8

        # Supabase best-effort (mesma trilha do cerebro evolutivo)
        if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $rec = [PSCustomObject]@{
                    id = $snap.date
                    ts = $snap.ts
                    regime = $snap.regime
                    payload = ($snap | ConvertTo-Json -Compress -Depth 6)
                }
                Save-StateRecords -Table "calibration_snapshots" -Records @($rec) -PrimaryKey "id" | Out-Null
            } catch {}
        }
        return $true
    } catch {
        Write-Warning "[calibration_snapshot] falhou: $_"
        return $false
    }
}

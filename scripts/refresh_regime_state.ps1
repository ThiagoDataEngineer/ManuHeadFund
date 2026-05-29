# refresh_regime_state.ps1 -- Normaliza regime_state.json (Python output) para schema PS.
#
# PROBLEMA RESOLVIDO (B29 fix 2026-05-28):
#   Python (regime_change_monitor.py) escreve:
#     { timestamp, current_regime, prev_regime, changed, trigger_actions }
#
#   PS consumers esperam campos diferentes:
#     - mesa_agent.ps1              -> .regime (string direto)
#     - lib_mentor_gate_block.ps1   -> .regime = {phase, bias}  (via Build-MentorFullContext)
#     - lib_beta_cap_per_phase.ps1  -> .phase (halving format)
#     - Get-MarketRegimeFromCache   -> .current_regime (backward compat)
#
#   Resultado: mesa_drones.jsonl tinha regime="" em 99% das entradas.
#
# SOLUCAO:
#   Este script le o JSON Python e reescreve com todos os campos normalizados.
#   Executado:
#     - Pelo staleness engine (lib_staleness_engine.ps1) quando regime_state stale
#     - Pelo daemon_restart (diario 09:00 BRT)
#     - Manualmente: powershell -File scripts/refresh_regime_state.ps1
#
# SCHEMA SAIDA:
#   {
#     regime        : "BEAR_WEAK"       <- mesa_agent direto
#     phase         : "h24_p3_bear"     <- lib_beta_cap_per_phase
#     bias          : "BEAR_WEAK"       <- lib_mentor_gate_block
#     current_regime: "BEAR_WEAK"       <- backward compat
#     prev_regime   : "BEAR_WEAK"
#     changed       : false
#     updated_at    : "2026-05-28T13:00:00Z"
#     source        : "refresh_regime_state.ps1"
#   }
#
# TDD: tests/refresh_regime_state.Tests.ps1
# PS 5.1. UTF-8 BOM.

# ============================================================================
# _Get-PhaseFromHalvingMonths -- calcula phase halving pela data atual
# (duplicado de lib_beta_cap_per_phase.ps1 para evitar dependencia circular)
# ============================================================================
function _RRS_GetPhaseFromHalvingMonths {
    $halving2024 = [datetime]::new(2024, 4, 19, 0, 0, 0, [DateTimeKind]::Utc)
    $halving2028 = [datetime]::new(2028, 4, 15, 0, 0, 0, [DateTimeKind]::Utc)
    $now = (Get-Date).ToUniversalTime()

    if ($now -ge $halving2028) {
        $mph    = ($now - $halving2028).TotalDays / 30.5
        $prefix = "h28"
    } elseif ($now -ge $halving2024) {
        $mph    = ($now - $halving2024).TotalDays / 30.5
        $prefix = "h24"
    } else {
        $mph    = ($now - [datetime]::new(2020, 5, 11, 0, 0, 0, [DateTimeKind]::Utc)).TotalDays / 30.5
        $prefix = "h20"
    }

    if    ($mph -lt 6)  { return "${prefix}_p1_bull" }
    elseif ($mph -lt 12) { return "${prefix}_p2_top"  }
    elseif ($mph -lt 30) { return "${prefix}_p3_bear" }
    else                 { return "${prefix}_p4_rec"  }
}

# ============================================================================
# Invoke-RefreshRegimeState -- funcao principal (testavel isolada)
# ============================================================================
function Invoke-RefreshRegimeState {
    <#
    .SYNOPSIS
    Le regime_state.json (Python schema) e reescreve com campos normalizados para PS.

    .PARAMETER InputPath
    Caminho do JSON de entrada (Python output). Default: journal/regime_state.json

    .PARAMETER OutputPath
    Caminho de saida. Pode ser igual ao InputPath (in-place). Default: mesmo que InputPath.

    .OUTPUTS
    $true se sucesso, $false se falha (arquivo nao existe, JSON invalido, etc).
    #>
    [CmdletBinding()]
    param(
        [string]$InputPath  = "",
        [string]$OutputPath = ""
    )

    # Resolve paths default
    if (-not $InputPath) {
        $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $journalDir = Join-Path (Split-Path -Parent $here) "journal"
        $InputPath  = Join-Path $journalDir "regime_state.json"
    }
    if (-not $OutputPath) { $OutputPath = $InputPath }

    # Guarda leitura antes de qualquer escrita (in-place safe)
    if (-not (Test-Path $InputPath)) {
        Write-Warning "[refresh_regime_state] InputPath nao encontrado: $InputPath"
        return $false
    }

    try {
        $raw  = Get-Content $InputPath -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "[refresh_regime_state] JSON invalido em $InputPath : $($_.Exception.Message)"
        return $false
    }

    # Extrai current_regime com fallback
    $currentRegime = ""
    if ($data.PSObject.Properties["current_regime"] -and $data.current_regime) {
        $currentRegime = [string]$data.current_regime
    } elseif ($data.PSObject.Properties["regime"] -and $data.regime -and ($data.regime -is [string])) {
        $currentRegime = [string]$data.regime
    }
    if (-not $currentRegime) { $currentRegime = "UNKNOWN" }

    # Calcula phase halving pela data atual
    $phase = _RRS_GetPhaseFromHalvingMonths

    # Preserva campos Python originais + adiciona campos PS normalizados
    $normalized = [ordered]@{
        # Campos PS normalizados (novos)
        regime         = $currentRegime
        phase          = $phase
        bias           = $currentRegime
        updated_at     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source         = "refresh_regime_state.ps1"
        # Campos Python preservados (backward compat)
        current_regime = $currentRegime
        prev_regime    = if ($data.PSObject.Properties["prev_regime"]) { [string]$data.prev_regime } else { "" }
        changed        = if ($data.PSObject.Properties["changed"])     { [bool]$data.changed       } else { $false }
        timestamp      = if ($data.PSObject.Properties["timestamp"])   { [string]$data.timestamp   } else { "" }
    }

    try {
        $json = $normalized | ConvertTo-Json -Compress -Depth 4
        # Escrita atomica: temp file + rename (evita corromper se processo morrer no meio)
        $tmpPath = $OutputPath + ".tmp"
        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.Encoding]::UTF8)
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
        Rename-Item -Path $tmpPath -NewName (Split-Path $OutputPath -Leaf) -Force
        Write-Host ("[refresh_regime_state] OK regime={0} phase={1} -> {2}" -f $currentRegime, $phase, $OutputPath) -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "[refresh_regime_state] Falha ao escrever $OutputPath : $($_.Exception.Message)"
        if (Test-Path ($OutputPath + ".tmp")) { Remove-Item ($OutputPath + ".tmp") -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

# ============================================================================
# Entry point quando executado diretamente (nao dot-sourced)
# ============================================================================
if ($MyInvocation.InvocationName -ne '.') {
    $journalDir = if ($global:JOURNAL_DIR) {
        $global:JOURNAL_DIR
    } else {
        $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        Join-Path (Split-Path -Parent $here) "journal"
    }
    $regimePath = Join-Path $journalDir "regime_state.json"
    $ok = Invoke-RefreshRegimeState -InputPath $regimePath -OutputPath $regimePath
    if (-not $ok) {
        Write-Warning "[refresh_regime_state] Falha ao normalizar regime_state.json"
        exit 1
    }
    exit 0
}

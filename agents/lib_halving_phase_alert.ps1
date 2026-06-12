# lib_halving_phase_alert.ps1 -- Detecta mudanca de halving_phase + alerta Telegram.
#
# Validacao 14y BTC (2026-05-19):
#   phase_1_bull (0-12m)   : BULL_WEAK LONG ALLOWED (+1.72R Sharpe 11.4)
#   phase_2_top (12-18m)   : BULL_WEAK BLOCKED (-0.4R holdout 2025)
#   phase_3_bear (18-30m)  : OBSERVATION (dados insuficientes)
#   phase_4_recovery (30+) : BULL_WEAK LONG REDUCED
#
# Rodar diariamente no cron pra alertar quando muda. PS 5.1. UTF-8 BOM.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


$script:PHASE_IMPLICATIONS = @{
    "pre_halving"      = "Pre-halving: aguardar; capital em stablecoins ou BULL_STRONG only."
    "phase_1_bull"     = "Phase 1 (BULL primario, 0-12m): ALLOWED BULL_WEAK + soft trendline. Sharpe historico 11.4."
    "phase_2_top"      = "Phase 2 (TOP, 12-18m): BLOCK BULL_WEAK. Manter BULL_STRONG only. Cuidado distribuicao."
    "phase_3_bear"     = "Phase 3 (BEAR, 18-30m): OBSERVATION BULL_WEAK. Dados insuficientes. SHORT em BEAR_STRONG ok."
    "phase_4_recovery" = "Phase 4 (RECOVERY, 30+m): BULL_WEAK REDUCED. Soft trendline gate ativo. Posicoes menores."
}


function Get-PhaseStateFile {
    if ($global:__TEST_PHASE_FILE) { return $global:__TEST_PHASE_FILE }
    return (Join-Path $global:JOURNAL_DIR "halving_phase_state.json")
}


function Save-PhaseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Phase,
        [string] $StatePath = ""
    )
    if (-not $StatePath) { $StatePath = Get-PhaseStateFile }
    $dir = Split-Path $StatePath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = @{
        phase     = $Phase
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $json = $obj | ConvertTo-Json -Compress
    Set-Content -Path $StatePath -Value $json -Encoding UTF8
}


function Get-LastPhase {
    [CmdletBinding()]
    param([string] $StatePath = "")
    if (-not $StatePath) { $StatePath = Get-PhaseStateFile }
    if (-not (Test-Path $StatePath)) { return $null }
    try {
        $obj = Get-Content $StatePath -Encoding UTF8 | ConvertFrom-Json
        return $obj.phase
    } catch { return $null }
}


function Test-HalvingPhaseChanged {
    [CmdletBinding()]
    param(
        [string] $Previous,
        [Parameter(Mandatory)] [string] $Current
    )
    if (-not $Previous) { return $true }
    return ($Previous -ne $Current)
}


function Format-HalvingPhaseAlert {
    [CmdletBinding()]
    param(
        [string] $Previous,
        [Parameter(Mandatory)] [string] $Current
    )
    $impl = $script:PHASE_IMPLICATIONS[$Current]
    if (-not $impl) { $impl = "Phase nao mapeada." }
    if (-not $Previous) {
        $lines = @(
            "<b>HALVING PHASE - inicializacao</b>",
            "",
            "Atual: <code>$Current</code>",
            "",
            $impl,
            "",
            "Tracking ativo. Avisaremos em proxima transicao."
        )
    } else {
        $lines = @(
            "<b>HALVING PHASE MUDOU</b>",
            "",
            "$Previous --> <code>$Current</code>",
            "",
            $impl,
            "",
            "Halving 2024-04-19. Hoje: $((Get-Date).ToString('yyyy-MM-dd'))."
        )
    }
    return ($lines -join "`n")
}


function Invoke-HalvingPhaseCheck {
    # Roda diariamente no cron: detecta mudanca de phase + envia Telegram se mudou.
    [CmdletBinding()]
    param(
        [scriptblock] $SendTelegram = $null,
        [string] $StatePath = ""
    )
    $current = Get-HalvingPhase -DateBrt (Get-Date)
    $previous = Get-LastPhase -StatePath $StatePath
    $changed = Test-HalvingPhaseChanged -Previous $previous -Current $current
    if ($changed) {
        $msg = Format-HalvingPhaseAlert -Previous $previous -Current $current
        if ($SendTelegram) { & $SendTelegram $msg | Out-Null }
        Save-PhaseState -Phase $current -StatePath $StatePath
    }
    return @{
        previous = $previous
        current  = $current
        changed  = $changed
    }
}

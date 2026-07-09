# lib_mentor_wire.ps1 — Wire recalibração mentor pós-decisão
# 2026-07-08: intercepta decisão do mentor e aplica Invoke-MentorRecalibration
# Uso: carregado por signal_snapshots reader, signal_snapshot_executor, ou gem_loop
# quando precisar aplicar recalibração nas decisões já gravadas

# Load recalibration lib
$__recalibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_mentor_recalibration.ps1"
if (Test-Path $__recalibPath) { . $__recalibPath }

function Apply-MentorRecalibrationToSnapshot {
    # Recalibra um signal_snapshot que ja tem .decision preenchida
    # Entrada: snapshot com {decision, direction, regime, market, ...}
    # Saída: snapshot com decision eventualmente invertida + .recalibrated_from (se houve inversão)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [object] $Snapshot
    )
    process {
        if (-not $Snapshot -or -not $Snapshot.decision) { return $Snapshot }

        # Aplicar recalibração
        if (Get-Command Invoke-MentorRecalibration -ErrorAction SilentlyContinue) {
            $recal = Invoke-MentorRecalibration -MentorDecision $Snapshot
            return $recal
        }
        return $Snapshot
    }
}

function Recalibrate-SignalTriggersFile {
    # Relê signal_triggers.jsonl (já processados), aplica recalibração às decisões,
    # re-escreve apenas as que foram invertidas. Operação idempotente.
    param(
        [string]$FilePath = "journal/signal_triggers.jsonl"
    )
    if (-not (Test-Path $FilePath)) { return 0 }

    $recalCount = 0
    $lines = @(Get-Content $FilePath -ErrorAction SilentlyContinue)
    $updated = @()

    foreach ($line in $lines) {
        if (-not $line) { continue }
        $sig = $null
        try { $sig = $line | ConvertFrom-Json } catch { continue }
        if (-not $sig) { continue }

        $before = "$($sig.decision)"
        $sig = Apply-MentorRecalibrationToSnapshot -Snapshot $sig
        $after = "$($sig.decision)"

        if ($before -ne $after) {
            Write-Host "[WIRE] $($sig.market) $($sig.direction) $($sig.regime): $before → $after (recalibration)" -ForegroundColor Magenta
            $recalCount++
        }
        $updated += ($sig | ConvertTo-Json -Compress)
    }

    if ($recalCount -gt 0) {
        $updated | Set-Content $FilePath -Encoding UTF8 -Force
        Write-Host "Recalibration applied: $recalCount signals" -ForegroundColor Green
    }
    return $recalCount
}

# Export: se caller disser "Apply-MentorRecalibrationToSnapshot", tem disponível
Export-ModuleMember -Function Apply-MentorRecalibrationToSnapshot, Recalibrate-SignalTriggersFile

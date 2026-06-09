# lib_trailing_peak_update.ps1 — Atualiza peak em tempo real
# Se price > peak, move stop pra breakeven liberando ganho
# PS 5.1. UTF-8 BOM.

function Update-TrailingPeakLive {
    param(
        [string]$Market,
        [double]$CurrentPrice,
        [string]$TrailingFile = ""
    )

    if (-not $TrailingFile) {
        $TrailingFile = Join-Path (if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }) "trailing_positions.json"
    }

    if (-not (Test-Path $TrailingFile)) { return @{ updated=$false; reason="file_not_found" } }

    try {
        $content = Get-Content $TrailingFile -Raw
        $positions = $content | ConvertFrom-Json

        $updated = $false
        foreach ($pos in $positions) {
            if ($pos.market -eq $Market) {
                $oldPeak = [double]$pos.peak
                $newPeak = [math]::Max($oldPeak, $CurrentPrice)

                if ($newPeak -gt $oldPeak) {
                    # Atualizar peak
                    $pos.peak = $newPeak
                    $updated = $true
                }

                # Verificar phase advancement independente de novo peak
                # Se atingiu 1R (entry + 1×risk), move stop pra breakeven
                if ($pos.phase -eq 0 -and $newPeak -ge [double]$pos.entry * 1.05) {
                    $pos.stopCurrent = [double]$pos.entry
                    $pos.phase = 1
                    $updated = $true
                }

                # Se atingiu 2R, move pra trailing
                if ($pos.phase -eq 1 -and $newPeak -ge [double]$pos.entry * 1.10) {
                    $pos.stopCurrent = [math]::Round($newPeak * 0.97, 8)
                    $pos.phase = 2
                    $updated = $true
                }
            }
        }

        if ($updated) {
            $positions | ConvertTo-Json | Set-Content $TrailingFile -Encoding UTF8
            return @{ updated=$true; market=$Market; new_peak=$newPeak }
        }

        return @{ updated=$false; reason="no_change" }
    } catch {
        return @{ updated=$false; reason=$_.Exception.Message }
    }
}

function Get-MonusdtPeakStatus {
    param([string]$TrailingFile = "")

    if (-not $TrailingFile) {
        $TrailingFile = Join-Path (if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }) "trailing_positions.json"
    }

    if (-not (Test-Path $TrailingFile)) { return $null }

    try {
        $positions = Get-Content $TrailingFile -Raw | ConvertFrom-Json
        return $positions | Where-Object { $_.market -eq "MONUSDT" } | Select-Object -First 1
    } catch { return $null }
}

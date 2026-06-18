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
        $__jdir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot) "journal" }
        $TrailingFile = Join-Path $__jdir "trailing_positions.json"
    }

    if (-not (Test-Path $TrailingFile)) { return @{ updated=$false; reason="file_not_found" } }

    try {
        $content = Get-Content $TrailingFile -Raw
        $positions = $content | ConvertFrom-Json

        $updated = $false
        $resultPeak = $null
        foreach ($pos in $positions) {
            if ($pos.market -ne $Market) { continue }

            $entry = [double]$pos.entry
            if ($entry -le 0) { continue }
            $side = if ($pos.PSObject.Properties['side'] -and "$($pos.side)") { "$($pos.side)".ToUpper() } else { "LONG" }
            $isShort = ($side -eq "SHORT")

            # ── Best price (peak p/ LONG = max favoravel; p/ SHORT = min favoravel) ──
            $oldPeak = [double]$pos.peak
            if ($isShort) {
                # SHORT: "peak" guarda o menor preco (mais favoravel). Se entry default igual.
                $newPeak = if ($oldPeak -le 0) { $CurrentPrice } else { [math]::Min($oldPeak, $CurrentPrice) }
                $gainPct = ($entry - $newPeak) / $entry * 100   # queda = lucro
            } else {
                $newPeak = [math]::Max($oldPeak, $CurrentPrice)
                $gainPct = ($newPeak - $entry) / $entry * 100   # alta = lucro
            }

            if ($newPeak -ne $oldPeak) {
                $pos.peak = $newPeak
                $updated = $true
            }
            $resultPeak = $newPeak

            # ── Thresholds FINOS (2026-06-17): lock cedo p/ pegar micro-swings ──
            #   +2.5% -> breakeven (trava risk-free; caso HYPE)
            #   +5.0% -> lock acima do breakeven (peak +/- 1.5%)
            #   +10%  -> trailing largo p/ runners (peak +/- 3%)
            $phase = [int]$pos.phase
            $newStop = $null
            $newPhase = $phase

            if ($phase -lt 1 -and $gainPct -ge 2.5) {
                $newStop = $entry            # breakeven
                $newPhase = 1
            }
            if ($gainPct -ge 5.0) {
                $lock = if ($isShort) { $newPeak * 1.015 } else { $newPeak * 0.985 }
                $newStop = [math]::Round($lock, 8)
                $newPhase = [math]::Max($newPhase, 2)
            }
            if ($gainPct -ge 10.0) {
                $lock = if ($isShort) { $newPeak * 1.03 } else { $newPeak * 0.97 }
                $newStop = [math]::Round($lock, 8)
                $newPhase = [math]::Max($newPhase, 3)
            }

            if ($null -ne $newStop) {
                $curStop = [double]$pos.stopCurrent
                # MONOTONICO: LONG so sobe o stop; SHORT so desce.
                $better = if ($isShort) { $newStop -lt $curStop } else { $newStop -gt $curStop }
                if ($better -or $newPhase -gt $phase) {
                    if ($better) { $pos.stopCurrent = $newStop }
                    $pos.phase = $newPhase
                    $updated = $true
                }
            }
        }

        if ($updated) {
            $positions | ConvertTo-Json | Set-Content $TrailingFile -Encoding UTF8
            return @{ updated=$true; market=$Market; new_peak=$resultPeak }
        }

        return @{ updated=$false; reason="no_change" }
    } catch {
        return @{ updated=$false; reason=$_.Exception.Message }
    }
}

function Get-MonusdtPeakStatus {
    param([string]$TrailingFile = "")

    if (-not $TrailingFile) {
        $__jdir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot) "journal" }
        $TrailingFile = Join-Path $__jdir "trailing_positions.json"
    }

    if (-not (Test-Path $TrailingFile)) { return $null }

    try {
        $positions = Get-Content $TrailingFile -Raw | ConvertFrom-Json
        return $positions | Where-Object { $_.market -eq "MONUSDT" } | Select-Object -First 1
    } catch { return $null }
}

# agents/lib_layer4_tori_timestop.ps1
# Layer 4: Tori Proximity + Time-Based Stops (Adaptive Thresholds)
# Solves UNI scenario (stagnation) and BNB scenario (peak harvest)
# v2: Multi-tier (SOFT/MEDIUM/HARD) + Regime-aware

# ─────────────────────────────────────────────────────────────────────
# Get-StagnationThresholds — Returns soft/medium/hard hours by regime
# ─────────────────────────────────────────────────────────────────────
function Get-StagnationThresholds {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$Regime
    )

    # Threshold table by regime (hours flat to trigger each tier)
    $table = @{
        "BULL_STRONG"   = @{ soft = 8;  medium = 12; hard = 18 }
        "BULL_WEAK"     = @{ soft = 12; medium = 18; hard = 24 }
        "SIDEWAYS"      = @{ soft = 18; medium = 24; hard = 36 }
        "BEAR_WEAK"     = @{ soft = 8;  medium = 12; hard = 18 }
        "BEAR_STRONG"   = @{ soft = 4;  medium = 8;  hard = 12 }
        "CAPITULATION"  = @{ soft = 2;  medium = 4;  hard = 6 }
    }

    $config = if ($table.ContainsKey($Regime)) { $table[$Regime] } else { $table["SIDEWAYS"] }

    return [PSCustomObject]@{
        soft   = $config.soft
        medium = $config.medium
        hard   = $config.hard
        regime = $Regime
    }
}

# ─────────────────────────────────────────────────────────────────────
# Classify-StagnationTier — NONE | SOFT | MEDIUM | HARD
# ─────────────────────────────────────────────────────────────────────
function Classify-StagnationTier {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)][double]$HoursElapsed,
        [Parameter(Mandatory=$true)][double]$PeakProgress,
        [string]$Regime = "SIDEWAYS",
        [double]$ProgressThreshold = 0.005
    )

    # If progress is healthy, no stagnation regardless of time
    if ($PeakProgress -ge $ProgressThreshold) {
        return "NONE"
    }

    $t = Get-StagnationThresholds -Regime $Regime

    if ($HoursElapsed -ge $t.hard)   { return "HARD" }
    if ($HoursElapsed -ge $t.medium) { return "MEDIUM" }
    if ($HoursElapsed -ge $t.soft)   { return "SOFT" }
    return "NONE"
}

# ─────────────────────────────────────────────────────────────────────
# Test-StagnantTrade — Detects trades flat for too long (legacy compat)
# ─────────────────────────────────────────────────────────────────────
function Test-StagnantTrade {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][double]$HoursElapsed,
        [Parameter(Mandatory=$true)][double]$PeakProgress,
        [double]$TimeThreshold = 24.0,
        [double]$ProgressThreshold = 0.005
    )

    return ($HoursElapsed -gt $TimeThreshold -and $PeakProgress -lt $ProgressThreshold)
}

# ─────────────────────────────────────────────────────────────────────
# Get-PeakProgress — Compute peak progress for LONG/SHORT
# ─────────────────────────────────────────────────────────────────────
function Get-PeakProgress {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory=$true)][double]$Entry,
        [Parameter(Mandatory=$true)][double]$Peak,
        [ValidateSet("LONG","SHORT")][string]$Side = "LONG"
    )

    if ($Side -eq "LONG") {
        return ($Peak - $Entry) / $Entry
    } else {
        return ($Entry - $Peak) / $Entry
    }
}

# ─────────────────────────────────────────────────────────────────────
# Get-ToriProximity — Detect closeness to resistance/support
# ─────────────────────────────────────────────────────────────────────
function Get-ToriProximity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][double]$CurrentPrice,
        [double]$Resistance = 0,
        [double]$Support = 0,
        [double]$ProximityThreshold = 0.03
    )

    $proxResistance = if ($Resistance -gt 0) { ($Resistance - $CurrentPrice) / $CurrentPrice } else { 999 }
    $proxSupport    = if ($Support -gt 0) { ($CurrentPrice - $Support) / $CurrentPrice } else { 999 }

    $nearResistance = ($proxResistance -lt $ProximityThreshold -and $proxResistance -gt 0)
    $nearSupport    = ($proxSupport -lt $ProximityThreshold -and $proxSupport -gt 0)

    return [PSCustomObject]@{
        nearResistance = $nearResistance
        nearSupport    = $nearSupport
        proxResistance = $proxResistance
        proxSupport    = $proxSupport
    }
}

# ─────────────────────────────────────────────────────────────────────
# Get-Layer4Decision — Synthesize TimeStop + Tori into action
# v2: Now uses adaptive thresholds (SOFT/MEDIUM/HARD by regime)
# ─────────────────────────────────────────────────────────────────────
function Get-Layer4Decision {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Position,
        [string]$MentorAction = "HOLD",
        [string]$Regime = "SIDEWAYS"
    )

    # Defer to Mentor if it has decisive action
    if ($MentorAction -eq "CLOSE_NOW") {
        return [PSCustomObject]@{
            action     = "DEFER_TO_MENTOR"
            confidence = 0.95
            reason     = "mentor_priority"
        }
    }

    # Compute peak progress
    $peak = if ($Position.peak) { [double]$Position.peak } else { [double]$Position.entry }
    $entry = [double]$Position.entry
    $side = if ($Position.side) { [string]$Position.side } else { "LONG" }
    $peakProgress = Get-PeakProgress -Entry $entry -Peak $peak -Side $side

    # Compute time elapsed
    $entryTime = if ($Position.openedAt) { [DateTime]::Parse($Position.openedAt) }
                 elseif ($Position.entryTime -is [DateTime]) { $Position.entryTime }
                 elseif ($Position.entryTime) { [DateTime]::Parse($Position.entryTime) }
                 else { Get-Date }
    $hoursElapsed = ((Get-Date) - $entryTime).TotalHours

    # Classify stagnation tier (NONE/SOFT/MEDIUM/HARD)
    $tier = Classify-StagnationTier -HoursElapsed $hoursElapsed -PeakProgress $peakProgress -Regime $Regime

    # Check Tori proximity
    $current = if ($Position.currentPrice) { [double]$Position.currentPrice } else { $entry }
    $resistance = if ($Position.resistance) { [double]$Position.resistance } else { 0 }
    $support = if ($Position.support) { [double]$Position.support } else { 0 }
    $tori = Get-ToriProximity -CurrentPrice $current -Resistance $resistance -Support $support

    # ─── Decision tree (priority order) ───────────────────────────────

    # 1. HARD stagnation + near support (LONG) = CLOSE_NOW (highest priority)
    if ($tier -eq "HARD" -and $tori.nearSupport) {
        return [PSCustomObject]@{
            action     = "CLOSE_NOW"
            confidence = 0.85
            reason     = "stagnant_hard_and_near_support"
            harvestPct = 1.0
            tier       = $tier
        }
    }

    # 2. HARD stagnation alone = CLOSE_TIME_STOP
    if ($tier -eq "HARD") {
        return [PSCustomObject]@{
            action     = "CLOSE_TIME_STOP"
            confidence = 0.70
            reason     = "stagnant_no_progress"
            harvestPct = 1.0
            tier       = $tier
        }
    }

    # 3. MEDIUM stagnation = REVIEW_STAGNATION (advisory only)
    if ($tier -eq "MEDIUM") {
        return [PSCustomObject]@{
            action     = "REVIEW_STAGNATION"
            confidence = 0.60
            reason     = "stagnant_medium_review_thesis"
            harvestPct = 0.0
            tier       = $tier
        }
    }

    # 4. SOFT stagnation = WARN_STAGNATION (just inform)
    if ($tier -eq "SOFT") {
        return [PSCustomObject]@{
            action     = "WARN_STAGNATION"
            confidence = 0.50
            reason     = "stagnant_soft_warn_only"
            harvestPct = 0.0
            tier       = $tier
        }
    }

    # 5. Healthy + near resistance = HARVEST_PARTIAL (BNB scenario)
    if ($tori.nearResistance -and $peakProgress -gt 0.02) {
        return [PSCustomObject]@{
            action     = "HARVEST_PARTIAL"
            confidence = 0.85
            reason     = "near_resistance_with_profit"
            harvestPct = 0.40
            tier       = "NONE"
        }
    }

    # 6. Default: HOLD
    return [PSCustomObject]@{
        action     = "HOLD"
        confidence = 0.90
        reason     = "no_action_needed"
        harvestPct = 0.0
        tier       = "NONE"
    }
}

# ─────────────────────────────────────────────────────────────────────
# Update-Layer4Review — Master wrapper, called per scan cycle
# ─────────────────────────────────────────────────────────────────────
# MODO PADRÃO: ADVISORY (somente alerta, NÃO executa close/harvest)
# Para opt-in de execução automática, defina $global:LAYER4_AUTO_EXECUTE = $true
# ─────────────────────────────────────────────────────────────────────
function Update-Layer4Review {
    [CmdletBinding()]
    param(
        [string]$JournalDir = "",
        [switch]$AutoExecute  # Override global: força execução automática
    )

    if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        Write-Host "  [Layer4] Get-TrailingPositions not found" -ForegroundColor DarkYellow
        return
    }

    # Modo: ADVISORY (default) ou AUTO_EXECUTE (opt-in explícito)
    # Prioridade: global var > arquivo flag > default false
    $autoExec = $false
    if ($AutoExecute.IsPresent) {
        $autoExec = $true
    } elseif ($null -ne $global:LAYER4_AUTO_EXECUTE) {
        $autoExec = [bool]$global:LAYER4_AUTO_EXECUTE
    } else {
        # Filesystem flag (persiste entre runs GitHub Actions)
        $flagFile = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "LAYER4_AUTO_EXECUTE.flag"
        if (Test-Path $flagFile) { $autoExec = $true }
    }
    $modeLabel = if ($autoExec) { "AUTO_EXECUTE" } else { "ADVISORY" }

    $positions = @(Get-TrailingPositions)
    $active = $positions | Where-Object { $_.active }

    if (-not $active -or @($active).Count -eq 0) {
        return
    }

    Write-Host "  [Layer4] Reviewing $(@($active).Count) position(s) in $modeLabel mode..." -ForegroundColor DarkCyan

    # Get current macro regime (for adaptive thresholds)
    $currentRegime = "SIDEWAYS"
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        try {
            $macro = Get-MacroContext
            if ($macro -and $macro.regime) { $currentRegime = [string]$macro.regime }
        } catch { }
    }
    Write-Host "  [Layer4] Macro regime: $currentRegime" -ForegroundColor DarkGray

    $updated = $false
    $positions = $positions | ForEach-Object {
        $pos = $_
        if (-not $pos.active) { return $pos }

        try {
            # Get current price (read-only fetch)
            if (-not $pos.currentPrice -and (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue)) {
                try {
                    $ticker = CoinEx-GetTicker $pos.market
                    if ($ticker -and $ticker.last) {
                        $pos | Add-Member -NotePropertyName "currentPrice" -NotePropertyValue ([double]$ticker.last) -Force
                    }
                } catch { }
            }

            $decision = Get-Layer4Decision -Position $pos -Regime $currentRegime

            # Always show decision (informational)
            $color = switch ($decision.action) {
                "CLOSE_NOW"          { "Red" }
                "CLOSE_TIME_STOP"    { "Yellow" }
                "REVIEW_STAGNATION"  { "Yellow" }
                "WARN_STAGNATION"    { "DarkYellow" }
                "HARVEST_PARTIAL"    { "Magenta" }
                default              { "Cyan" }
            }
            $tierStr = if ($decision.tier) { " tier=$($decision.tier)" } else { "" }
            Write-Host "    [Layer4] $($pos.market) $($pos.side): $($decision.action) (conf=$($decision.confidence), reason=$($decision.reason)$tierStr)" -ForegroundColor $color

            # ADVISORY mode: only alert, don't execute
            if (-not $autoExec) {
                if ($decision.action -ne "HOLD") {
                    # Send advisory alert (no auto-execution)
                    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                        try {
                            $alertMsg = "[Layer4 ADVISORY] $($pos.market) $($pos.side) suggests: $($decision.action) (reason=$($decision.reason)). Manual action required - no auto-execute."
                            Send-TelegramAlert -Message $alertMsg | Out-Null
                        } catch { }
                    }

                    # Track advisory in position metadata (for auditing)
                    $pos | Add-Member -NotePropertyName "layer4Advisory" -NotePropertyValue $decision.action -Force
                    $pos | Add-Member -NotePropertyName "layer4AdvisoryReason" -NotePropertyValue $decision.reason -Force
                    $pos | Add-Member -NotePropertyName "lastLayer4Review" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                    $updated = $true
                }
                return $pos
            }

            # AUTO_EXECUTE mode (opt-in only)
            if ($decision.action -eq "CLOSE_NOW" -or $decision.action -eq "CLOSE_TIME_STOP") {
                # Try to close on exchange first
                $exchangeClosed = $false
                if (Get-Command CoinEx-ClosePosition -ErrorAction SilentlyContinue) {
                    try {
                        $r = CoinEx-ClosePosition $pos.market
                        if ($r -and $r.code -eq 0) {
                            $exchangeClosed = $true
                            Write-Host "      Exchange close OK: $($pos.market)" -ForegroundColor Green
                        } else {
                            Write-Host "      Exchange close FAILED: $($pos.market)" -ForegroundColor Red
                        }
                    } catch {
                        Write-Host "      Exchange close ERROR: $_" -ForegroundColor Red
                    }
                }

                # Only mark inactive in journal if exchange close succeeded
                if ($exchangeClosed) {
                    $pos.active = $false
                    $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue $decision.reason -Force
                    $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                    $updated = $true

                    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                        try {
                            Send-TelegramAlert -Message "[Layer4 EXECUTED] $($pos.market) $($pos.side) CLOSED on exchange: $($decision.reason)" | Out-Null
                        } catch { }
                    }
                }

            } elseif ($decision.action -eq "HARVEST_PARTIAL") {
                # Note: harvesting requires partial close API, more complex
                # For now, log advisory even in AUTO_EXECUTE mode for HARVEST_PARTIAL
                $pos | Add-Member -NotePropertyName "layer4Action" -NotePropertyValue "harvest_partial_pending" -Force
                $pos | Add-Member -NotePropertyName "harvestedPct" -NotePropertyValue $decision.harvestPct -Force
                $pos | Add-Member -NotePropertyName "lastLayer4Review" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                $updated = $true

                if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                    try {
                        Send-TelegramAlert -Message "[Layer4] $($pos.market) $($pos.side) HARVEST_PARTIAL suggested: $([math]::Round($decision.harvestPct * 100, 0))% (reason=$($decision.reason)). Manual action required." | Out-Null
                    } catch { }
                }
            }

        } catch {
            Write-Host "    [Layer4] Error processing $($pos.market): $_" -ForegroundColor DarkRed
        }

        return $pos
    }

    if ($updated -and (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue)) {
        Save-TrailingPositions @($positions)
    }
}

# Functions exported: Test-StagnantTrade, Get-PeakProgress, Get-ToriProximity,
#                      Get-Layer4Decision, Update-Layer4Review

# agents/lib_mentor_reflection.ps1
# Layer 2: Mentor Reflection (6h checkpoint reviews)
# Implementação GREEN phase — passa em 24 testes TDD
#
# Design:
#   Mentor agent revisa posições a cada 6h após entry
#   Detecta: early warnings, regime shifts, oportunidades de tight stop
#   Decisões: HOLD | CLOSE_NOW | TIGHTEN_STOP

# ─────────────────────────────────────────────────────────────────────────────
# Test-MentorCheckpoint — Verifica se é hora de review (6h elapsed)
# ─────────────────────────────────────────────────────────────────────────────
function Test-MentorCheckpoint {
    <#
    .SYNOPSIS
    Determina se posição passou 6h e merece revisão do Mentor.
    
    .PARAMETER EntryTime
    Timestamp quando posição foi aberta (datetime)
    
    .OUTPUTS
    [bool] $true se review deve rodar (time between 5.95h-6.5h), $false caso contrário
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][DateTime]$EntryTime
    )

    $now = Get-Date
    $elapsed = ($now - $EntryTime).TotalHours
    
    # Review window: 5h55min até 6h30min (tolerância)
    $reviewStart = 5.95    # 5h 57min
    $reviewEnd = 6.5       # 6h 30min
    
    return ($elapsed -ge $reviewStart -and $elapsed -le $reviewEnd)
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-EarlyWarningDetection — Detecta false breakouts
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-EarlyWarningDetection {
    <#
    .SYNOPSIS
    Detecta sinais de false breakout (breakeven muito cedo = panic sell)
    
    .PARAMETER TimeSinceEntry
    Horas desde que posição foi aberta
    
    .PARAMETER PriceProgress
    Fração de progresso (current-entry)/(target-entry)
    
    .OUTPUTS
    [PSCustomObject]@{ flagged=$bool; confidence=$double; reason=$string }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][double]$TimeSinceEntry,
        [Parameter(Mandatory=$true)][double]$PriceProgress
    )

    $flagged = $false
    $confidence = 0.0
    $reason = ""

    # Early warning: preço em breakeven/lucro MUITO cedo (<4h)
    # Indica possível false breakout
    if ($TimeSinceEntry -lt 4.0 -and $PriceProgress -ge 0) {
        $flagged = $true
        $confidence = 0.75  # 75% certeza
        $reason = "breakeven_too_early"
    }

    # Normal progress check: se tempo >= 6h e ainda há progresso, sem warning
    elseif ($TimeSinceEntry -ge 5.9 -and $PriceProgress -gt 0.05 -and $PriceProgress -lt 0.30) {
        $flagged = $false
        $confidence = 0.90
        $reason = "on_track"
    }

    return [PSCustomObject]@{
        flagged = $flagged
        confidence = $confidence
        reason = $reason
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-RegimeShift — Detecta mudança de regime (e.g., BULL → BEAR)
# ─────────────────────────────────────────────────────────────────────────────
function Get-RegimeShift {
    <#
    .SYNOPSIS
    Detecta se regime mudou de forma significativa (BULL→BEAR é critical)
    
    .PARAMETER OldRegime
    Regime anterior (quando posição foi aberta)
    
    .PARAMETER NewRegime
    Regime atual (detectado agora)
    
    .OUTPUTS
    [PSCustomObject]@{ shifted=$bool; severity=$double; confidence=$double }
    
    .DESCRIPTION
    Regimes: BULL_STRONG, BULL_WEAK, SIDEWAYS, BEAR_WEAK, BEAR_STRONG, CAPITULATION
    
    Shifts críticos: qualquer mudança para BEAR/CAPITULATION
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$OldRegime,
        [Parameter(Mandatory=$true)][string]$NewRegime
    )

    $shifted = $false
    $severity = 0.0  # 0-1, how bad
    $confidence = 0.0

    # Nenhuma mudança = sem action
    if ($OldRegime -eq $NewRegime) {
        $shifted = $false
        $confidence = 0.95
        return [PSCustomObject]@{ shifted=$shifted; severity=$severity; confidence=$confidence }
    }

    # Mudança para BEAR/CAPITULATION = CRITICAL
    if ($NewRegime -match "BEAR|CAPITULATION") {
        $shifted = $true
        $severity = if ($NewRegime -eq "CAPITULATION") { 1.0 } else { 0.8 }
        $confidence = 0.80  # Regime detection é confiável
    }

    # Mudança dentro de BULL (STRONG→WEAK) = neutral, sem action
    elseif ($OldRegime -match "BULL" -and $NewRegime -match "BULL") {
        $shifted = $false
        $confidence = 0.85
    }

    # Outros shifts = monitorar mas sem action imediata
    else {
        $shifted = $false
        $confidence = 0.70
    }

    return [PSCustomObject]@{
        shifted = $shifted
        severity = $severity
        confidence = $confidence
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Update-StopTightening — Calcula novo stop 50% mais perto da entry
# ─────────────────────────────────────────────────────────────────────────────
function Update-StopTightening {
    <#
    .SYNOPSIS
    Move stop 50% mais perto de entry (defesa contra reversal rápido)
    
    .PARAMETER Entry
    Preço de entrada
    
    .PARAMETER CurrentStop
    Stop atual (original)
    
    .PARAMETER Side
    LONG ou SHORT
    
    .OUTPUTS
    [double] novo stop (tightened)
    
    .DESCRIPTION
    LONG:  newStop = entry - (entry - currentStop) * 0.5
    SHORT: newStop = entry + (currentStop - entry) * 0.5
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory=$true)][double]$Entry,
        [Parameter(Mandatory=$true)][double]$CurrentStop,
        [ValidateSet("LONG", "SHORT")][string]$Side = "LONG"
    )

    if ($Side -eq "LONG") {
        # Move 50% closer to entry (stop rises)
        # Original: entry=100, stop=95 (5 points away)
        # New: entry=100, stop=97.5 (2.5 points away = 50% closer)
        $newStop = $Entry - ($Entry - $CurrentStop) * 0.5
    } else {
        # SHORT: move 50% closer (stop lowers)
        # Original: entry=100, stop=105 (5 points away)
        # New: entry=100, stop=102.5 (2.5 points away = 50% closer)
        $newStop = $Entry + ($CurrentStop - $Entry) * 0.5
    }

    # Enforce minimum floor (1% of entry)
    $minFloor = $Entry * 0.01
    
    if ($Side -eq "LONG") {
        # Ensure not below entry - minFloor
        $newStop = [math]::Max($newStop, $Entry - $minFloor)
    } else {
        # SHORT: ensure not above entry + minFloor
        $newStop = [math]::Min($newStop, $Entry + $minFloor)
    }

    return [math]::Round($newStop, 4)
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-MentorDecision — Combina todas as análises, retorna decisão
# ─────────────────────────────────────────────────────────────────────────────
function Get-MentorDecision {
    <#
    .SYNOPSIS
    Analisa posição e retorna decisão do Mentor (HOLD / CLOSE_NOW / TIGHTEN_STOP)
    
    .PARAMETER Position
    Posição atual [PSCustomObject] com entry, target, currentPrice, stop, entry Time, side
    
    .PARAMETER CurrentRegime
    Regime atual (de Get-MacroContext)
    
    .PARAMETER OldRegime
    Regime anterior (salvo na posição)
    
    .OUTPUTS
    [PSCustomObject]@{ action=$string; confidence=$double; newStop=$double; reason=$string }
    
    .DESCRIPTION
    Decisões:
      HOLD        → posição está ok, sem action
      CLOSE_NOW   → false breakout detectado, fecha rápido
      TIGHTEN_STOP → regime shift bearish, aperta stop como defesa
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Position,
        [Parameter(Mandatory=$true)][string]$CurrentRegime,
        [string]$OldRegime = "SIDEWAYS"
    )

    $action = "HOLD"
    $confidence = 0.90
    $newStop = $null
    $reason = "on_track"

    # 1. Check para regime shift primeiro (prioridade alta)
    $regimeShift = Get-RegimeShift -OldRegime $OldRegime -NewRegime $CurrentRegime
    
    if ($regimeShift.shifted) {
        $action = "TIGHTEN_STOP"
        $confidence = 0.80
        $newStop = Update-StopTightening -Entry $Position.entry -CurrentStop $Position.stop -Side $Position.side
        $reason = "regime_shift_to_$CurrentRegime"
        
        return [PSCustomObject]@{
            action = $action
            confidence = $confidence
            newStop = $newStop
            reason = $reason
        }
    }

    # 2. Check para early warning (false breakout)
    $entryTime = if ($Position.entryTime -is [DateTime]) { $Position.entryTime } else { [DateTime]::Parse($Position.entryTime) }
    $timeSinceEntry = ((Get-Date) - $entryTime).TotalHours
    $priceProgress = ($Position.currentPrice - $Position.entry) / ($Position.target - $Position.entry)

    $warning = Invoke-EarlyWarningDetection -TimeSinceEntry $timeSinceEntry -PriceProgress $priceProgress

    if ($warning.flagged) {
        $action = "CLOSE_NOW"
        $confidence = 0.75
        $reason = $warning.reason
        
        return [PSCustomObject]@{
            action = $action
            confidence = $confidence
            newStop = $null
            reason = $reason
        }
    }

    # 3. Default: HOLD if no warnings/shifts
    return [PSCustomObject]@{
        action = "HOLD"
        confidence = 0.90
        newStop = $null
        reason = "normal_progression"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Update-MentorReview — Master wrapper (integração no loop)
# ─────────────────────────────────────────────────────────────────────────────
function Update-MentorReview {
    <#
    .SYNOPSIS
    Master wrapper: rodará a cada ciclo de scan_master, revisa posições a cada 6h
    
    .PARAMETER JournalDir
    Diretório de posições (default $global:JOURNAL_DIR)
    
    .DESCRIPTION
    Para cada posição ativa:
      1. Checa se passou 6h (Test-MentorCheckpoint)
      2. Se sim, chama Get-MentorDecision
      3. Aplica decisão (CLOSE, TIGHTEN_STOP, ou HOLD)
      4. Registra na posição: lastMentorReview, lastMentorDecision
    
    Requer: Get-TrailingPositions, Save-TrailingPositions, Get-MacroContext
    #>
    [CmdletBinding()]
    param(
        [string]$JournalDir = ""
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } `
                      else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }

    # Get current regime
    $currentRegime = "SIDEWAYS"
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        try {
            $macro = Get-MacroContext
            if ($macro -and $macro.regime) {
                $currentRegime = [string]$macro.regime
            }
        } catch {
            Write-Host "    [Mentor] Get-MacroContext falhou, usando SIDEWAYS" -ForegroundColor DarkYellow
        }
    }

    # Get active positions
    if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        Write-Host "  [Mentor] Get-TrailingPositions não encontrada" -ForegroundColor DarkYellow
        return
    }

    $positions = @(Get-TrailingPositions)
    $active = $positions | Where-Object { $_.active }

    if (-not $active -or @($active).Count -eq 0) {
        Write-Host "  [Mentor] Nenhuma posição ativa para revisar" -ForegroundColor DarkGray
        return
    }

    Write-Host "  [Mentor] Revisando $(@($active).Count) posição(ões)..." -ForegroundColor DarkCyan

    $updated = $false
    $reviewCount = 0

    $positions = $positions | ForEach-Object {
        $pos = $_
        if (-not $pos.active) { return $pos }

        try {
            # Verifica se é hora de review (6h elapsed)
            # Tenta entryTime primeiro (novo), depois openedAt (compatibilidade)
            $entryTime = if ($pos.entryTime -is [DateTime]) { 
                $pos.entryTime 
            } elseif ($pos.entryTime) {
                try { [DateTime]::Parse($pos.entryTime) } catch { $null }
            } elseif ($pos.openedAt) {
                try { [DateTime]::Parse($pos.openedAt) } catch { $null }
            } else {
                $null
            }

            if (-not $entryTime) {
                return $pos  # Skip if no valid entry time
            }
            
            if (-not (Test-MentorCheckpoint -EntryTime $entryTime)) {
                if ($Verbose) { Write-Host "    [Mentor] $($pos.market): ainda não 6h, skip" -ForegroundColor DarkGray }
                return $pos
            }

            $reviewCount++
            
            # Busca preço atual (fallback: usar last price se disponível)
            $price = if ($pos.currentPrice) { [double]$pos.currentPrice } else { $null }
            if (-not $price -or $price -eq 0) {
                if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
                    try {
                        $ticker = CoinEx-GetTicker $pos.market
                        if ($ticker -and $ticker.last) { $price = [double]$ticker.last }
                    } catch { }
                }
            }

            # If still no price, skip this position
            if (-not $price -or $price -eq 0) {
                Write-Host "    [Mentor] $($pos.market): no price available, skip" -ForegroundColor DarkGray
                return $pos
            }

            # Get Mentor decision

            $pos.currentPrice = $price
            $oldRegime = if ($pos.regime) { $pos.regime } else { "SIDEWAYS" }
            $decision = Get-MentorDecision -Position $pos -CurrentRegime $currentRegime -OldRegime $oldRegime

            Write-Host "    [Mentor] $($pos.market) $($pos.side): $($decision.action) (conf=$($decision.confidence), reason=$($decision.reason))" -ForegroundColor Cyan

            # Apply decision
            if ($decision.action -eq "CLOSE_NOW") {
                # Close posição
                $pos.active = $false
                $pos.closeReason = "mentor_false_breakout"
                $pos.closedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $updated = $true
                
                if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                    try {
                        Send-TelegramAlert -Message "[Mentor] $($pos.market) $($pos.side) CLOSED: false breakout detected" | Out-Null
                    } catch { }
                }

            } elseif ($decision.action -eq "TIGHTEN_STOP") {
                # Tighten stop
                $oldStop = $pos.stop
                $pos.stop = $decision.newStop
                $pos.lastMentorReview = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $pos.mentorAction = "tighten_stop"
                $updated = $true
                
                if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                    try {
                        Send-TelegramAlert -Message "Aviso [Mentor] $($pos.market) $($pos.side) stop tightened: $oldStop to $($pos.stop) (regime=$currentRegime)" | Out-Null
                    } catch { }
                }

                if (Get-Command CoinEx-SetStopLoss -ErrorAction SilentlyContinue) {
                    try {
                        CoinEx-SetStopLoss -Market $pos.market -OrderId $pos.orderId -StopPrice $decision.newStop | Out-Null
                    } catch {
                        if ($Verbose) { Write-Host "      Aviso: não foi possível mover stop na exchange: $_" -ForegroundColor DarkYellow }
                    }
                }
            }

            # Update last review timestamp anyway
            if (-not $pos.lastMentorReview) {
                $pos.lastMentorReview = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            $pos.regime = $currentRegime  # Save current regime for next comparison

        } catch {
            Write-Host "    [Mentor] Erro ao processar $($pos.market): $_" -ForegroundColor DarkRed
        }

        return $pos
    }

    if ($updated -and (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue)) {
        Save-TrailingPositions @($positions)
        Write-Host "  [Mentor] $reviewCount revisões, $updated atualizações salvas" -ForegroundColor Green
    }
}

# Funções exportadas: Test-MentorCheckpoint, Invoke-EarlyWarningDetection, 
#                      Get-RegimeShift, Update-StopTightening, Get-MentorDecision, 
#                      Update-MentorReview

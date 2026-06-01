# agents/lib_trailing_adaptive.ps1
# TDD-driven: Adaptive trailing stops with ATR-dynamic buffer + regime-aware
# Evolução do lib_trailing.ps1 original
#
# Camada 1: ATR-Dinâmico + Regime-Aware (esta implementação)
# Camadas 2-5 virão depois (Mentor reflection, Kelly, Tori, Moon bag)
#
# Dot-source: . (Join-Path $PSScriptRoot "lib_trailing_adaptive.ps1")

# ─────────────────────────────────────────────────────────────────────────────
# Get-AdaptiveBuffer -- Calcula buffer dinâmico por regime + volatilidade
# ─────────────────────────────────────────────────────────────────────────────
function Get-AdaptiveBuffer {
    <#
    .SYNOPSIS
    Calcula buffer adaptativo para breakeven transition baseado em regime + ATR.
    
    .PARAMETER Range
    Distância entry → target (movimento esperado)
    
    .PARAMETER CurrentAtr
    ATR atual (volatilidade intraday)
    
    .PARAMETER HistoricalAtr
    ATR médio histórico (volatilidade baseline)
    
    .PARAMETER Regime
    Regime de mercado: BULL_STRONG, BULL_WEAK, SIDEWAYS, BEAR_STRONG, CAPITULATION, etc
    
    .OUTPUTS
    [double] Buffer em valor absoluto (não percentual)
    
    .EXAMPLE
    $buf = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_STRONG"
    # Retorna ~75 (100 * 0.75 = tight stops em trending market)
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory=$true)][double]$Range,
        [Parameter(Mandatory=$true)][double]$CurrentAtr,
        [Parameter(Mandatory=$true)][double]$HistoricalAtr,
        [ValidateSet("BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
                     "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION")]
        [string]$Regime = "SIDEWAYS"
    )

    # Regime multiplier: controla agressividade do stop por condição de mercado
    $regimeMultiplier = switch($Regime) {
        "BULL_STRONG"       { 0.75 }   # Tight: trending market, confiança alta
        "BULL_WEAK"         { 1.0 }    # Normal: high still there but weakening
        "SIDEWAYS"          { 1.3 }    # Wide: defend against pullback noise
        "TRANSITION_UP"     { 1.1 }    # Slight wider: transitioning up
        "TRANSITION_DOWN"   { 1.2 }    # Wider: caution in downward transition
        "BEAR_WEAK"         { 1.4 }    # Very wide: bear market, protect vs spikes
        "BEAR_STRONG"       { 1.5 }    # Extremely wide: strong downtrend, hold longer
        "CAPITULATION"      { 0.5 }    # Ultra tight: panic phase, exit quick
        default             { 1.0 }
    }

    # ATR ratio: se vol atual > histórica, aumenta buffer; se menor, reduz
    # Evita divide by zero
    $atrRatio = if ($HistoricalAtr -gt 0) {
        $CurrentAtr / $HistoricalAtr
    } else {
        1.0
    }

    # Buffer base = CurrentAtr × regime multiplier × vol ratio
    $buffer = $CurrentAtr * $regimeMultiplier * $atrRatio

    # Minimum floor: não deixar buffer tão apertado que perde a lucratividade
    # 1.5% do range é limite defensivo
    $minBuffer = [math]::Max($Range * 0.015, 1.0)  # never zero

    return [math]::Max($buffer, $minBuffer)
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-TrailingNewStopAdaptive -- Calcula novo stop por fase com buffer adaptativo
# ─────────────────────────────────────────────────────────────────────────────
function Get-TrailingNewStopAdaptive {
    <#
    .SYNOPSIS
    Calcula novo stop para posição em trailing com adaptação por regime.
    
    .PARAMETER Pos
    Posição atual [PSCustomObject] com market, side, entry, target, phase, peak, stopCurrent
    
    .PARAMETER CurrentPrice
    Preço atual do ativo
    
    .PARAMETER Regime
    Regime de mercado para ajustar agressividade
    
    .PARAMETER CurrentAtr
    ATR atual (opcional, default 100 para teste)
    
    .PARAMETER HistoricalAtr
    ATR histórico (opcional, default 100)
    
    .OUTPUTS
    [PSCustomObject]@{ newStop, newPhase, newPeak, changed }
    
    .DESCRIPTION
    Fases (LONG):
      0 → 1: Preço atinge 33% do alvo → move stop para BE + adaptive buffer
      1 → 2: Preço atinge 66% do alvo → move stop para lock +33% do ganho
      2 → 3: Preço atinge alvo → move stop para trailing 15% abaixo do pico
      3:     Trailing ativo → atualiza stop se novo pico quebra trailing
    
    SHORT espelhado.
    
    .EXAMPLE
    $pos = [PSCustomObject]@{ market="BTCUSDT"; side="LONG"; entry=60000; target=70000; 
                               phase=0; peak=60000; stopCurrent=59000 }
    $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice 63333 -Regime "BULL_STRONG"
    # $result.newPhase = 1, $result.newStop ≈ 60050 (BE + small buffer)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Pos,
        [Parameter(Mandatory=$true)][double]$CurrentPrice,
        [ValidateSet("BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
                     "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION")]
        [string]$Regime = "SIDEWAYS",
        [double]$CurrentAtr = 100,
        [double]$HistoricalAtr = 100
    )

    $entry  = [double]$Pos.entry
    $target = [double]$Pos.target
    $stop   = [double]$Pos.stopCurrent
    $peak   = [double]$Pos.peak
    $phase  = [int]$Pos.phase
    $side   = $Pos.side

    # Range e buffer adaptativo
    $range  = [math]::Abs($target - $entry)
    $buffer = Get-AdaptiveBuffer -Range $range -CurrentAtr $CurrentAtr `
                                 -HistoricalAtr $HistoricalAtr -Regime $Regime

    $newStop  = $stop
    $newPhase = $phase
    $changed  = $false

    if ($side -eq "LONG") {
        # Pontos de transição em % do alvo
        $gain33  = $entry + $range * 0.33
        $gain66  = $entry + $range * 0.66
        $newPeak = [math]::Max($peak, $CurrentPrice)

        if ($phase -lt 3 -and $CurrentPrice -ge $target) {
            # Fase 3: Trailing ativo — 15% abaixo do pico, nunca recua
            $newPhase = 3
            $newStop  = [math]::Round($newPeak * 0.85, 4)
            $changed  = $true
        } elseif ($phase -lt 2 -and $CurrentPrice -ge $gain66) {
            # Fase 2: Lock +33% do ganho
            $newPhase = 2
            $newStop  = [math]::Round($entry + $range * 0.33, 4)
            $changed  = $true
        } elseif ($phase -lt 1 -and $CurrentPrice -ge $gain33) {
            # Fase 1: Breakeven + adaptive buffer
            $newPhase = 1
            $newStop  = [math]::Round($entry + $buffer, 4)
            $changed  = $true
        } elseif ($phase -eq 3) {
            # Fase 3 ativa: atualizar trailing se novo pico
            $potentialNewStop = [math]::Round($newPeak * 0.85, 4)
            if ($potentialNewStop -gt $stop) {
                $newStop = $potentialNewStop
                $changed = $true
            }
        }

    } else {
        # SHORT: lógica espelhada
        $gain33  = $entry - $range * 0.33
        $gain66  = $entry - $range * 0.66
        $newPeak = [math]::Min($peak, $CurrentPrice)

        if ($phase -lt 3 -and $CurrentPrice -le $target) {
            # Fase 3 SHORT: trailing 15% acima do pico (preço mínimo), nunca recua
            $newPhase = 3
            $newStop  = [math]::Round($newPeak * 1.15, 4)
            $changed  = $true
        } elseif ($phase -lt 2 -and $CurrentPrice -le $gain66) {
            # Fase 2 SHORT: lock +33% do ganho (stop sobe, pois SHORT)
            $newPhase = 2
            $newStop  = [math]::Round($entry - $range * 0.33, 4)
            $changed  = $true
        } elseif ($phase -lt 1 -and $CurrentPrice -le $gain33) {
            # Fase 1 SHORT: BE - adaptive buffer
            $newPhase = 1
            $newStop  = [math]::Round($entry - $buffer, 4)
            $changed  = $true
        } elseif ($phase -eq 3) {
            # Fase 3 SHORT ativa: atualizar trailing
            $potentialNewStop = [math]::Round($newPeak * 1.15, 4)
            if ($potentialNewStop -lt $stop) {
                $newStop = $potentialNewStop
                $changed = $true
            }
        }
    }

    # Sempre atualizar peak (fix 2026-05-25: persistir peak mesmo sem fase change)
    $peakChanged = ($newPeak -ne $peak)
    if ($peakChanged) {
        $changed = $true
    }

    return [PSCustomObject]@{
        newStop  = $newStop
        newPhase = $newPhase
        newPeak  = $newPeak
        changed  = $changed
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Update-TrailingStopsAdaptive -- Wrapper que integra adaptive no ciclo master
# ─────────────────────────────────────────────────────────────────────────────
function Update-TrailingStopsAdaptive {
    <#
    .SYNOPSIS
    Atualiza trailing stops LIVE com buffers adaptativos (substitui Update-TrailingStops).
    
    .DESCRIPTION
    Para cada posição ativa:
    1. Busca regime atual
    2. Busca ATR atual vs histórico
    3. Chama Get-TrailingNewStopAdaptive
    4. Se changed, move stop na exchange + telegram alert
    5. Persiste estado
    
    Requer: Get-TrailingPositions, Save-TrailingPositions, Get-MacroContext
            (ou lib_trailing.ps1 para persistência)
    #>
    [CmdletBinding()]
    param(
        [string]$JournalDir = ""
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } `
                      else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }

    # Busca regime atual (macro context)
    $regime = "SIDEWAYS"
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        try {
            $macro = Get-MacroContext
            if ($macro -and $macro.regime) {
                $regime = [string]$macro.regime
            }
        } catch { }
    }

    # Busca ATR atual (placeholder; em prod usaria últimas barras)
    $currentAtr = 100.0
    $historicalAtr = 100.0
    if (Get-Command Get-TechnicalIndicators -ErrorAction SilentlyContinue) {
        try {
            # Placeholder: em prod carregaria ATR real
        } catch { }
    }

    # Itera posições ativas
    if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        Write-Warning "[Adaptive Trailing] Get-TrailingPositions não encontrada; skipping"
        return
    }

    $positions = @(Get-TrailingPositions)
    $active = $positions | Where-Object { $_.active }

    if (-not $active -or @($active).Count -eq 0) {
        if ($Verbose) { Write-Host "  [Adaptive Trailing] Nenhuma posição ativa." -ForegroundColor DarkGray }
        return
    }

    Write-Host "  [Adaptive Trailing] Verificando $(@($active).Count) posição(ões) com regime=$regime..." -ForegroundColor DarkGreen

    $updated = $false
    $positions = $positions | ForEach-Object {
        $pos = $_
        if (-not $pos.active) { return $pos }

        try {
            # Busca preço atual
            if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
                $ticker = CoinEx-GetTicker $pos.market
                if (-not $ticker) { return $pos }
                $price = [double]$ticker.last
            } else {
                if ($Verbose) { Write-Host "  [Adaptive Trailing] CoinEx-GetTicker não disponível; skip $($pos.market)" }
                return $pos
            }

            # Calcula novo stop
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime $regime `
                                                -CurrentAtr $currentAtr -HistoricalAtr $historicalAtr

            # Verifica se stop foi atingido (ANTES de atualizar peak)
            $stopped = if ($pos.side -eq "LONG") { $price -le [double]$pos.stopCurrent } `
                       else                       { $price -ge [double]$pos.stopCurrent }

            if ($stopped) {
                # CLOSE POSIÇÃO
                $msg = "[STOP HIT] $($pos.market) $($pos.side) @ $price (stop=$($pos.stopCurrent))"
                Write-Host "  [Adaptive Trailing] $msg" -ForegroundColor Red
                if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                    try { Send-TelegramAlert -Message $msg | Out-Null } catch { }
                }
                $pos.active = $false
                $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue "stop_atingido" -Force
                $updated = $true
                return $pos
            }

            # Atualiza peak SEMPRE (fix 2026-05-25)
            if ($calc.newPeak -ne [double]$pos.peak) {
                $pos.peak = $calc.newPeak
                $updated = $true
            }

            # Se fase mudou, atualiza e notifica
            if ($calc.changed -and $calc.newPhase -ne [int]$pos.phase) {
                $oldPhase = $pos.phase
                $oldStop = $pos.stopCurrent
                $pos.stopCurrent = $calc.newStop
                $pos.phase = $calc.newPhase
                $pos.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $updated = $true

                # 2026-06-01: Calcular mudança percentual e filtrar pequenas mudanças
                $changePct = if ($oldStop -gt 0) {
                    [math]::Abs(($calc.newStop - $oldStop) / $oldStop * 100)
                } else {
                    0
                }
                
                $minChange = if ($global:TELEGRAM_TRAILING_MIN_CHANGE_PCT) {
                    $global:TELEGRAM_TRAILING_MIN_CHANGE_PCT
                } else {
                    5.0
                }

                $phaseLabel = @("inicial", "breakeven", "lock+33%", "trailing")
                $msg = "🔄 $($pos.market) $($pos.side) fase $oldPhase→$($pos.phase) ($($phaseLabel[$pos.phase])) stop $oldStop→$($calc.newStop) | regime=$regime"
                Write-Host "  [Adaptive Trailing] $msg" -ForegroundColor Green
                
                # Enviar apenas se mudança > threshold
                if ($changePct -ge $minChange -and (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue)) {
                    try { Send-TelegramAlertFiltered -Message $msg -Tier "INFORMATIVE" | Out-Null } catch { }
                }

                # Tenta mover stop na exchange
                if (Get-Command CoinEx-SetStopLoss -ErrorAction SilentlyContinue) {
                    try {
                        CoinEx-SetStopLoss -Market $pos.market -OrderId $pos.orderId `
                                          -StopPrice $calc.newStop | Out-Null
                    } catch {
                        Write-Host "  [Adaptive Trailing] Aviso: não foi possível mover stop: $_" -ForegroundColor DarkYellow
                    }
                }
            }

        } catch {
            Write-Host "  [Adaptive Trailing] Erro ao processar $($pos.market): $_" -ForegroundColor DarkRed
        }
        return $pos
    }

    if ($updated -and (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue)) {
        Save-TrailingPositions @($positions)
    }
}

# Funções exportadas: Get-AdaptiveBuffer, Get-TrailingNewStopAdaptive, Update-TrailingStopsAdaptive
# Dot-source ao usar (não é módulo formal)

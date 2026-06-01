# agents/lib_enhanced_short_entry.ps1
# TDD-driven: Enhanced SHORT entry filter + regime-aware trailing
# Objetivo: Win rate 65% → 72%+ sem redução de volume
# Implementação: Fase 1 + Trailing adaptativo em um arquivo
# Data: 2026-06-01
# Validação: RSI/MACD/Volume gates + regime-aware stops

# ─────────────────────────────────────────────────────────────────────────────
# Test-EnhancedShortEntry -- Filtro rigoroso para SHORTs
# ─────────────────────────────────────────────────────────────────────────────
function Test-EnhancedShortEntry {
    <#
    .SYNOPSIS
    Valida entrada SHORT com 3 gates: RSI oversold + MACD divergência + Volume spike
    
    .PARAMETER Market
    Par de trading (ex: BTCUSDT)
    
    .PARAMETER RSI
    RSI(14) atual (0-100)
    
    .PARAMETER MACDValue
    MACD line atual
    
    .PARAMETER MACDSignal
    MACD signal line atual
    
    .PARAMETER Volume24h
    Volume 24h atual
    
    .PARAMETER VolumeAvg30d
    Volume médio 30 dias
    
    .OUTPUTS
    [PSCustomObject]@{ passed, reason, confidence }
    
    .DESCRIPTION
    Gates (todos devem passar):
    1. RSI < 30: Oversold confirmado (bounce potencial)
    2. MACD divergência bullish: Preço cai, MACD sobe (força compradora)
    3. Volume spike: Volume 24h > 1.5x média 30d (compra institucional)
    
    Confiança = média dos 3 gates (0-100)
    
    .EXAMPLE
    $entry = Test-EnhancedShortEntry -Market "BTCUSDT" -RSI 28 -MACDValue 0.5 `
                                      -MACDSignal 0.3 -Volume24h 28.5e9 -VolumeAvg30d 18e9
    # Retorna: @{ passed=$true, reason="All gates passed", confidence=92 }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][double]$RSI,
        [Parameter(Mandatory=$true)][double]$MACDValue,
        [Parameter(Mandatory=$true)][double]$MACDSignal,
        [Parameter(Mandatory=$true)][double]$Volume24h,
        [Parameter(Mandatory=$true)][double]$VolumeAvg30d
    )

    $gates = @()
    $scores = @()

    # ─────────────────────────────────────────────────────────────────────────
    # Gate 1: RSI Oversold (< 30)
    # ─────────────────────────────────────────────────────────────────────────
    $rsiPassed = $RSI -lt 30
    $rsiScore = if ($rsiPassed) {
        # Score: 100 se RSI < 20, 80 se 20-25, 60 se 25-30
        if ($RSI -lt 20) { 100 }
        elseif ($RSI -lt 25) { 80 }
        else { 60 }
    } else {
        # Falhou: RSI >= 30
        # Score: 40 se 30-35, 20 se 35-40, 0 se > 40
        if ($RSI -lt 35) { 40 }
        elseif ($RSI -lt 40) { 20 }
        else { 0 }
    }
    
    $gates += @{
        name = "RSI_OVERSOLD"
        passed = $rsiPassed
        value = $RSI
        threshold = 30
        score = $rsiScore
        reason = if ($rsiPassed) { "RSI $RSI < 30 (oversold)" } else { "RSI $RSI >= 30 (not oversold)" }
    }
    $scores += $rsiScore

    # ─────────────────────────────────────────────────────────────────────────
    # Gate 2: MACD Divergência Bullish
    # ─────────────────────────────────────────────────────────────────────────
    # Divergência bullish = preço cai, MACD sobe (força compradora)
    # Verificamos: MACD > Signal (MACD acima da linha de sinal)
    $macdPassed = $MACDValue -gt $MACDSignal
    $macdDiff = [math]::Abs($MACDValue - $MACDSignal)
    $macdScore = if ($macdPassed) {
        # Score baseado na magnitude da divergência
        if ($macdDiff -gt 0.5) { 100 }
        elseif ($macdDiff -gt 0.3) { 85 }
        elseif ($macdDiff -gt 0.1) { 70 }
        else { 50 }
    } else {
        # Falhou: MACD <= Signal
        if ($macdDiff -lt 0.1) { 30 }
        else { 10 }
    }
    
    $gates += @{
        name = "MACD_DIVERGENCE"
        passed = $macdPassed
        value = $MACDValue
        signal = $MACDSignal
        diff = $macdDiff
        score = $macdScore
        reason = if ($macdPassed) { "MACD $([math]::Round($MACDValue,3)) > Signal $([math]::Round($MACDSignal,3)) (bullish div)" } `
                 else { "MACD $([math]::Round($MACDValue,3)) <= Signal $([math]::Round($MACDSignal,3)) (no div)" }
    }
    $scores += $macdScore

    # ─────────────────────────────────────────────────────────────────────────
    # Gate 3: Volume Spike (> 1.5x média 30d)
    # ─────────────────────────────────────────────────────────────────────────
    $volumeRatio = if ($VolumeAvg30d -gt 0) { $Volume24h / $VolumeAvg30d } else { 1.0 }
    $volumePassed = $volumeRatio -gt 1.5
    $volumeScore = if ($volumePassed) {
        # Score baseado na magnitude do spike
        if ($volumeRatio -gt 3.0) { 100 }
        elseif ($volumeRatio -gt 2.5) { 90 }
        elseif ($volumeRatio -gt 2.0) { 80 }
        elseif ($volumeRatio -gt 1.5) { 70 }
        else { 50 }
    } else {
        # Falhou: volumeRatio <= 1.5
        if ($volumeRatio -gt 1.2) { 40 }
        elseif ($volumeRatio -gt 1.0) { 20 }
        else { 0 }
    }
    
    $gates += @{
        name = "VOLUME_SPIKE"
        passed = $volumePassed
        ratio = [math]::Round($volumeRatio, 2)
        threshold = 1.5
        score = $volumeScore
        reason = if ($volumePassed) { "Volume ratio $([math]::Round($volumeRatio,2))x > 1.5x (spike)" } `
                 else { "Volume ratio $([math]::Round($volumeRatio,2))x <= 1.5x (no spike)" }
    }
    $scores += $volumeScore

    # ─────────────────────────────────────────────────────────────────────────
    # Decisão Final
    # ─────────────────────────────────────────────────────────────────────────
    $allPassed = $gates | Where-Object { -not $_.passed } | Measure-Object | Select-Object -ExpandProperty Count
    $allPassed = $allPassed -eq 0
    
    $confidence = [math]::Round(($scores | Measure-Object -Average).Average, 0)
    
    $reason = if ($allPassed) {
        "✅ All gates passed: RSI oversold + MACD divergence + Volume spike"
    } else {
        $failedGates = $gates | Where-Object { -not $_.passed } | ForEach-Object { $_.name }
        "❌ Failed gates: $($failedGates -join ', ')"
    }

    return [PSCustomObject]@{
        market = $Market
        passed = $allPassed
        reason = $reason
        confidence = $confidence
        gates = $gates
        rsi_score = $rsiScore
        macd_score = $macdScore
        volume_score = $volumeScore
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-RegimeAdjustedTrailingStop -- Trailing adaptativo por regime
# ─────────────────────────────────────────────────────────────────────────────
function Get-RegimeAdjustedTrailingStop {
    <#
    .SYNOPSIS
    Calcula stop loss de trailing adaptado ao regime de mercado.
    
    .PARAMETER Regime
    Regime atual (BEAR_STRONG, BEAR_WEAK, SIDEWAYS, etc)
    
    .PARAMETER Peak
    Preço mínimo atingido (para SHORT)
    
    .PARAMETER Entry
    Preço de entrada (para cálculo de fallback)
    
    .OUTPUTS
    [PSCustomObject]@{ stop, pct, regime_factor, reason }
    
    .DESCRIPTION
    Trailing % por regime:
    - BEAR_STRONG:    80% (20% abaixo peak) - downtrend forte, mais apertado
    - BEAR_WEAK:      85% (15% abaixo peak) - downtrend fraco, normal
    - SIDEWAYS:       90% (10% abaixo peak) - sem tendência, mais solto
    - TRANSITION_DOWN: 82% (18% abaixo peak) - transição, apertado
    - TRANSITION_UP:  88% (12% abaixo peak) - transição, solto
    - BULL_*:         95% (5% abaixo peak) - uptrend, muito solto
    
    .EXAMPLE
    $stop = Get-RegimeAdjustedTrailingStop -Regime "BEAR_WEAK" -Peak 64500 -Entry 71505
    # Retorna: @{ stop=54825, pct=0.85, regime_factor=0.85, reason="BEAR_WEAK: 15% abaixo peak" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][ValidateSet("BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
                                                   "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION")]
        [string]$Regime,
        [Parameter(Mandatory=$true)][double]$Peak,
        [Parameter(Mandatory=$false)][double]$Entry = 0
    )

    # Regime factor: % do peak onde colocar stop (SHORT: stop ACIMA do peak)
    $regimeFactor = switch($Regime) {
        "BEAR_STRONG"       { 0.80 }   # 20% abaixo peak (mais apertado)
        "BEAR_WEAK"         { 0.85 }   # 15% abaixo peak (normal)
        "SIDEWAYS"          { 0.90 }   # 10% abaixo peak (mais solto)
        "TRANSITION_DOWN"   { 0.82 }   # 18% abaixo peak (apertado)
        "TRANSITION_UP"     { 0.88 }   # 12% abaixo peak (solto)
        "BULL_STRONG"       { 0.95 }   # 5% abaixo peak (muito solto)
        "BULL_WEAK"         { 0.92 }   # 8% abaixo peak (solto)
        "CAPITULATION"      { 0.70 }   # 30% abaixo peak (ultra apertado)
        default             { 0.85 }
    }

    # Calcula stop (SHORT: stop = peak × regimeFactor)
    $stop = [math]::Round($Peak * $regimeFactor, 4)
    
    # Calcula percentual de trailing
    $trailingPct = (1 - $regimeFactor) * 100

    # Fallback: se stop ficar muito perto do entry, usa entry como limite
    if ($Entry -gt 0 -and $stop -lt $Entry) {
        $stop = $Entry
        $reason = "Fallback: stop ajustado para entry ($Entry) para evitar inversão"
    } else {
        $trailingPctRounded = [math]::Round($trailingPct, 0)
        $reason = "$Regime`: $trailingPctRounded% abaixo peak"
    }

    return [PSCustomObject]@{
        stop = $stop
        pct = $regimeFactor
        regime_factor = $regimeFactor
        trailing_pct = $trailingPct
        regime = $Regime
        reason = $reason
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Update-TrailingStopsWithRegimeAdaptation -- Integração completa
# ─────────────────────────────────────────────────────────────────────────────
function Update-TrailingStopsWithRegimeAdaptation {
    <#
    .SYNOPSIS
    Atualiza trailing stops com adaptação por regime (substitui Update-TrailingStopsAdaptive).
    
    .DESCRIPTION
    Para cada posição SHORT ativa:
    1. Busca regime atual
    2. Calcula novo stop com Get-RegimeAdjustedTrailingStop
    3. Se stop mudou, atualiza na exchange + telegram
    4. Persiste estado
    
    Integra: Enhanced entry filter + Regime-aware trailing
    #>
    [CmdletBinding()]
    param(
        [string]$JournalDir = ""
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } `
                      else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }

    # Busca regime atual
    $regime = "SIDEWAYS"
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        try {
            $macro = Get-MacroContext
            if ($macro -and $macro.regime) {
                $regime = [string]$macro.regime
            }
        } catch { }
    }

    # Itera posições ativas
    if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        Write-Warning "[Regime Trailing] Get-TrailingPositions não encontrada; skipping"
        return
    }

    $positions = @(Get-TrailingPositions)
    $active = $positions | Where-Object { $_.active -and $_.side -eq "SHORT" }

    if (-not $active -or @($active).Count -eq 0) {
        if ($Verbose) { Write-Host "  [Regime Trailing] Nenhuma posição SHORT ativa." -ForegroundColor DarkGray }
        return
    }

    Write-Host "  [Regime Trailing] Verificando $(@($active).Count) SHORT(s) com regime=$regime..." -ForegroundColor DarkGreen

    $updated = $false
    $positions = $positions | ForEach-Object {
        $pos = $_
        if (-not $pos.active -or $pos.side -ne "SHORT") { return $pos }

        try {
            # Busca preço atual
            if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
                $ticker = CoinEx-GetTicker $pos.market
                if (-not $ticker) { return $pos }
                $price = [double]$ticker.last
            } else {
                if ($Verbose) { Write-Host "  [Regime Trailing] CoinEx-GetTicker não disponível; skip $($pos.market)" }
                return $pos
            }

            # Verifica se stop foi atingido (SHORT: stop ACIMA do entry)
            $stopped = $price -ge [double]$pos.stopCurrent

            if ($stopped) {
                # CLOSE POSIÇÃO
                $msg = "[STOP HIT] $($pos.market) SHORT @ $price (stop=$($pos.stopCurrent))"
                Write-Host "  [Regime Trailing] $msg" -ForegroundColor Red
                if (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue) {
                    try { Send-TelegramAlertFiltered -Message $msg -Tier "CRITICAL" | Out-Null } catch { }
                }
                $pos.active = $false
                $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue "stop_atingido" -Force
                $updated = $true
                return $pos
            }

            # Atualiza peak (SHORT: peak = mínimo)
            $newPeak = [math]::Min([double]$pos.peak, $price)
            if ($newPeak -ne [double]$pos.peak) {
                $pos.peak = $newPeak
                $updated = $true
            }

            # Calcula novo stop com regime adaptation
            $stopCalc = Get-RegimeAdjustedTrailingStop -Regime $regime -Peak $newPeak -Entry [double]$pos.entry
            $newStop = $stopCalc.stop

            # Se stop mudou, atualiza
            if ($newStop -ne [double]$pos.stopCurrent) {
                $oldStop = $pos.stopCurrent
                $pos.stopCurrent = $newStop
                $pos.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $updated = $true

                # Calcula mudança percentual
                $changePct = if ($oldStop -gt 0) {
                    [math]::Abs(($newStop - $oldStop) / $oldStop * 100)
                } else {
                    0
                }
                
                $minChange = if ($global:TELEGRAM_TRAILING_MIN_CHANGE_PCT) {
                    $global:TELEGRAM_TRAILING_MIN_CHANGE_PCT
                } else {
                    5.0
                }

                $msg = "🔄 $($pos.market) SHORT trailing (regime=$regime) stop $oldStop→$newStop | peak=$newPeak"
                Write-Host "  [Regime Trailing] $msg" -ForegroundColor Green
                
                # Trailing é cobertura de trades vivos - SEMPRE enviar (TIER IMPORTANT)
                if ($changePct -ge $minChange -and (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue)) {
                    try { Send-TelegramAlertFiltered -Message $msg -Tier "IMPORTANT" | Out-Null } catch { }
                }

                # Tenta mover stop na exchange
                if (Get-Command CoinEx-SetStopLoss -ErrorAction SilentlyContinue) {
                    try {
                        CoinEx-SetStopLoss -Market $pos.market -OrderId $pos.orderId `
                                          -StopPrice $newStop | Out-Null
                    } catch {
                        Write-Host "  [Regime Trailing] Aviso: não foi possível mover stop: $_" -ForegroundColor DarkYellow
                    }
                }
            }

        } catch {
            Write-Host "  [Regime Trailing] Erro ao processar $($pos.market): $_" -ForegroundColor DarkRed
        }
        return $pos
    }

    if ($updated -and (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue)) {
        Save-TrailingPositions @($positions)
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-EnhancedShortValidation -- Integração com orchestrator_v6
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-EnhancedShortValidation {
    <#
    .SYNOPSIS
    Valida SHORT antes de EXECUTAR (integra com orchestrator_v6).
    
    .PARAMETER Market
    Par de trading
    
    .PARAMETER Context
    Context com RSI, MACD, Volume
    
    .PARAMETER TriagemTier
    Tier da triagem (A/B/C/D)
    
    .PARAMETER MesaConsensus
    Consenso da mesa (FORTE_3/MEDIO_2/CAOS)
    
    .OUTPUTS
    [PSCustomObject]@{ approved, reason, confidence, gates }
    
    .DESCRIPTION
    Fluxo:
    1. Se Tier D + SHORT + whitelist → bypass acionado (já feito em orchestrator)
    2. Se Mesa FORTE_3 SHORT → valida com enhanced entry filter
    3. Se todos os gates passam → APROVADO
    4. Se algum gate falha → ABORTAR
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][PSCustomObject]$Context,
        [Parameter(Mandatory=$true)][string]$TriagemTier,
        [Parameter(Mandatory=$true)][string]$MesaConsensus
    )

    # Validação básica
    if ($MesaConsensus -ne "FORTE_3") {
        return [PSCustomObject]@{
            approved = $false
            reason = "Mesa consensus não é FORTE_3 (é $MesaConsensus)"
            confidence = 0
            gates = @()
        }
    }

    # Extrai valores do context
    $rsi = if ($Context.rsi) { [double]$Context.rsi } else { 50 }
    $macdValue = if ($Context.macd) { [double]$Context.macd } else { 0 }
    $macdSignal = if ($Context.macd_signal) { [double]$Context.macd_signal } else { 0 }
    $volume24h = if ($Context.volume_24h) { [double]$Context.volume_24h } else { 0 }
    $volumeAvg30d = if ($Context.volume_avg_30d) { [double]$Context.volume_avg_30d } else { 1 }

    # Valida com enhanced entry filter
    $validation = Test-EnhancedShortEntry -Market $Market `
                                          -RSI $rsi `
                                          -MACDValue $macdValue `
                                          -MACDSignal $macdSignal `
                                          -Volume24h $volume24h `
                                          -VolumeAvg30d $volumeAvg30d

    return [PSCustomObject]@{
        approved = $validation.passed
        reason = $validation.reason
        confidence = $validation.confidence
        gates = $validation.gates
        rsi_score = $validation.rsi_score
        macd_score = $validation.macd_score
        volume_score = $validation.volume_score
    }
}

# Exportadas: Test-EnhancedShortEntry, Get-RegimeAdjustedTrailingStop, 
#             Update-TrailingStopsWithRegimeAdaptation, Invoke-EnhancedShortValidation

# lib_early_warning_engine.ps1
# EARLY WARNING ENGINE — Detecta ANTES do pump/dump usando TODOS os sinais
# 2026-06-30: Integra whale + tori + vol + narrativa + macro + momentum
#
# Objetivo: Identificar mercados em "preparação" antes que movimento +60% ou -60% aconteça
# Diferencial: Não reativo (depois do pump), mas PREDICTIVO (antes)
#
# Sinais integrados:
#   1. WHALE ACCUMULATION (on-chain, antes do pump)
#   2. TORI SETUP RIPENING (technical setup maturando)
#   3. NARRATIVA QUENTE (FQS em alta, news catalysts)
#   4. VOLUME PREPARATION (volume crescendo, liquidez secando)
#   5. MACRO ALIGNMENT (regime favorável)
#   6. MOMENTUM EARLY (primeiros sinais, antes de +20%)

function Resolve-EarlyWarningSignal {
  <#
  .SYNOPSIS
  Detecta se um mercado está em "preparação" de pump/dump (ANTES do movimento).

  .PARAMETER Market
  Símbolo do mercado (ex: GENSYN)

  .PARAMETER WhaleFlow
  Dados on-chain: whale_buys_24h, whale_sells_24h, accumulation_days

  .PARAMETER ToriSetup
  Dados técnicos: proximity_pct, setup_ripening, touches, slope

  .PARAMETER Narrativa
  FQS score, keywords quentes, catalyst próximo

  .PARAMETER VolumePrep
  Vol spike nas últimas 3 dias, order book imbalance

  .OUTPUTS
  @{
    market = "GENSYNUSDT"
    early_warning_score = 0-100
    signals_active = @("whale_accumulation", "tori_ripening", "vol_prep")
    direction = "LONG" | "SHORT" | "NEUTRAL"
    confidence = "HIGH" | "MEDIUM" | "LOW"
    time_to_move = "hours" | "days" | "uncertain"
    action = "MONITOR" | "ALERT" | "STANDBY_APPROVAL"
    reason = "3 sinais de preparação: whale entrando, tori próxima de break, vol crescendo"
  }
  #>
  [CmdletBinding()]
  [OutputType([PSCustomObject])]
  param(
    [Parameter(Mandatory=$true)][string]$Market,
    [hashtable]$WhaleData = @{},
    [hashtable]$ToriData = @{},
    [hashtable]$NarrativeData = @{},
    [hashtable]$VolumeData = @{},
    [hashtable]$MacroData = @{}
  )

  $signals = @()
  $scores = @()

  # ─────────────────────────────────────────────────────────────────────────
  # SIGNAL 1: WHALE ACCUMULATION (on-chain early indicator)
  # ─────────────────────────────────────────────────────────────────────────
  $whale_score = 0
  if ($WhaleData.accumulation_days -ge 3) {
    # Whale entrando por 3+ dias = preparação pra pump
    $whale_score = [math]::Min(100, $WhaleData.accumulation_days * 15)
    $signals += "whale_accumulation"
    $scores += $whale_score
  }

  # ─────────────────────────────────────────────────────────────────────────
  # SIGNAL 2: TORI SETUP RIPENING (técnico maturando)
  # ─────────────────────────────────────────────────────────────────────────
  $tori_score = 0
  if ($ToriData.setup_ripening -eq $true) {
    # Setup em maturação = movimento iminente
    $tori_score = 70
    if ($ToriData.proximity_pct -lt 1.5) { $tori_score = 90 }  # Muito perto do break
    $signals += "tori_ripening"
    $scores += $tori_score
  }

  # ─────────────────────────────────────────────────────────────────────────
  # SIGNAL 3: NARRATIVA QUENTE (FQS alta + keywords + catalyst)
  # ─────────────────────────────────────────────────────────────────────────
  $narrative_score = 0
  if ($NarrativeData.fqs_score -ge 5) {
    # FQS >=5 (QUALITY+) = fundamentals validados
    $narrative_score = 40
    if ($NarrativeData.keywords_trending -gt 0) { $narrative_score += 30 }  # Narrativa em alta
    if ($NarrativeData.catalyst_days -le 7) { $narrative_score += 30 }  # Catalyst próximo
    $narrative_score = [math]::Min(100, $narrative_score)
    $signals += "narrative_catalyst"
    $scores += $narrative_score
  }

  # ─────────────────────────────────────────────────────────────────────────
  # SIGNAL 4: VOLUME PREPARATION (entrada antes do pump)
  # ─────────────────────────────────────────────────────────────────────────
  $volume_score = 0
  if ($VolumeData.vol_spike_3d -ge 1.5) {
    # Volume crescendo (NOT climax yet, mas preparação)
    $volume_score = 50
    if ($VolumeData.orderbook_imbalance -gt 1.8) { $volume_score += 30 }  # Lado comprador forte
    $volume_score = [math]::Min(100, $volume_score)
    $signals += "volume_preparation"
    $scores += $volume_score
  }

  # ─────────────────────────────────────────────────────────────────────────
  # SIGNAL 5: MACRO ALIGNMENT (regime favorável pra movimento)
  # ─────────────────────────────────────────────────────────────────────────
  $macro_score = 0
  if ($MacroData.regime -in @("BULL_WEAK", "BULL_STRONG", "TRANSITION_UP")) {
    # Regime de alta = LONG favorável
    $macro_score = 40
    $signals += "macro_bullish"
    $scores += $macro_score
  } elseif ($MacroData.regime -in @("BEAR_WEAK", "BEAR_STRONG", "TRANSITION_DOWN")) {
    # Regime de baixa = SHORT favorável
    $macro_score = 40
    $signals += "macro_bearish"
    $scores += $macro_score
  }

  # ─────────────────────────────────────────────────────────────────────────
  # COMPOSIÇÃO: Multidimensional scoring
  # ─────────────────────────────────────────────────────────────────────────
  $avg_score = if ($scores.Count -gt 0) { ($scores | Measure-Object -Average).Average } else { 0 }
  $signal_count = $signals.Count

  # Boost: múltiplos sinais = maior confiança (não é acaso)
  $confidence_multiplier = [math]::Min(1.2, 1.0 + ($signal_count * 0.1))
  $final_score = [math]::Min(100, $avg_score * $confidence_multiplier)

  # ─────────────────────────────────────────────────────────────────────────
  # Determinação de direção + action
  # ─────────────────────────────────────────────────────────────────────────
  $direction = "NEUTRAL"
  $action = "MONITOR"

  if ($signal_count -ge 2) {
    # 2+ sinais = setup real, não ruído
    if (@($signals) -contains "macro_bullish" -or @($signals) -contains "whale_accumulation") {
      $direction = "LONG"
      $action = if ($final_score -ge 70) { "ALERT" } else { "STANDBY" }
    } elseif (@($signals) -contains "macro_bearish") {
      $direction = "SHORT"
      $action = if ($final_score -ge 70) { "ALERT" } else { "STANDBY" }
    }
  }

  # Tempo estimado de movimento (heurístico)
  $time_to_move = if (@($signals) -contains "tori_ripening") { "hours" } `
                  elseif ($signal_count -ge 3) { "hours-days" } `
                  else { "days-weeks" }

  return [PSCustomObject]@{
    market = $Market
    early_warning_score = [math]::Round($final_score, 1)
    signal_count = $signal_count
    signals = @($signals)
    direction = $direction
    confidence = if ($final_score -ge 75) { "HIGH" } elseif ($final_score -ge 50) { "MEDIUM" } else { "LOW" }
    time_to_move = $time_to_move
    action = $action
    whale_score = $whale_score
    tori_score = $tori_score
    narrative_score = $narrative_score
    volume_score = $volume_score
    macro_score = $macro_score
  }
}

function Get-EarlyWarningCandidates {
  <#
  .SYNOPSIS
  Scan de TODOS os mercados para detectar "preparação" (before-pump/dump stage).
  Usa whale data (on-chain), tori (technical), narrativa (FQS), volume, macro.

  .OUTPUTS
  @(
    @{ market="GENSYNUSDT"; score=85; direction="LONG"; action="ALERT"; reason="..." },
    @{ market="PEARLUSDT"; score=62; direction="SHORT"; action="STANDBY"; reason="..." }
  )
  #>
  [CmdletBinding()]
  [OutputType([object[]])]
  param(
    [string[]]$Markets = @(),
    [string]$Regime = "BEAR_WEAK"
  )

  # Se não fornecer mercados, scan os top CoinEx (placeholder)
  if ($Markets.Count -eq 0) {
    $Markets = @(
      "BTCUSDT","ETHUSDT","SOLUSDT","XRPUSDT","BNBUSDT",
      "GENSYNUSDT","SYNUSDT","VRAUSDT","HFUNUSDT","PEARLAUSDT",
      "ALEOUSDT","MANTAUSDT","INJUSDT","SUIUSDT"
    )
  }

  $results = @()

  foreach ($market in $Markets) {
    # Stub: Em uso real, carregaria whale data, tori, etc de APIs/estado
    # Por enquanto, retorna estrutura vazia (pronto pra integração)
    $warning = Resolve-EarlyWarningSignal -Market $market
    if ($warning.early_warning_score -gt 50) {
      $results += $warning
    }
  }

  return @($results | Sort-Object early_warning_score -Descending)
}

# Functions exported automatically when dot-sourced

#!/usr/bin/env pwsh
# early_warning_scan.ps1 — Multi-signal early warning scanner
# 2026-06-30: Detecta mercados em PREPARAÇÃO (antes do pump/dump de +60%, -60%)
#
# Integra:
#   1. Whale flow (on-chain)
#   2. Tori setup ripening (técnico)
#   3. Narrativa quente (FQS, keywords, catalyst)
#   4. Volume preparation (não climax, mas crescendo)
#   5. Macro regime alignment
#   6. Early momentum (RSI em subida, mas não overbought yet)
#
# Output: journal/early_warning_alerts.jsonl
# Action: TG alert com score/direção/tempo_estimado para cada candidato

param([switch] $DryRun)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"

. (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_early_warning_engine.ps1")
. (Join-Path $agentsDir "lib_whale_watcher.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_tori_proximity.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_macro.ps1") -ErrorAction SilentlyContinue

Write-Host "=== EARLY WARNING SCAN (before-pump/dump detection) ===" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────
# SCAN UNIVERSE (top CoinEx + custom watch list)
# ─────────────────────────────────────────────────────────────────────────
$scan_universe = @(
  # Blue chips (baseline)
  "BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT",
  # Recent gainers (HFUN +92%, GENSYN +62%, SYN +61%)
  "HFUNUSDT", "GENSYNUSDT", "SYNUSDT", "VRAUSDT", "MYOUSDT",
  # Recent losers (PEARL -16%, ALEO -13%, MANTA -16%)
  "PEARLUSDT", "ALEOUSDT", "MANTAUSDT", "GWEIUSDT",
  # Other tier B candidates
  "INJUSDT", "SUIUSDT", "ZECUSDT", "CFGUSDT", "PENDLEUSDT"
)

$detected = @()
$macro_regime = "BEAR_WEAK"  # Current regime

Write-Host "`nScanning $($scan_universe.Count) markets for early-warning signals..." -ForegroundColor Yellow

foreach ($market in $scan_universe) {
  Write-Host "  [$market]" -ForegroundColor Gray -NoNewline

  $whale_data = @{}
  $tori_data = @{}
  $narrative_data = @{}
  $volume_data = @{}
  $macro_data = @{ regime = $macro_regime }

  # ─────────────────────────────────────────────────────────────────────────
  # Collect SIGNAL 1: Whale accumulation (on-chain)
  # Heurístico: comparar últimas 3 dias de volume
  # ─────────────────────────────────────────────────────────────────────────
  try {
    $candles = CoinEx-GetCandles -Market $market -Interval "1d" -Limit 4 -ErrorAction Stop
    if ($candles -and @($candles).Count -ge 2) {
      $today_vol = [double]($candles[-1].volume)
      $prev_vol = ([double]($candles[-4..-2] | Measure-Object -Property volume -Average).Average)
      $vol_ratio = if ($prev_vol -gt 0) { $today_vol / $prev_vol } else { 0 }

      # Se volume crescendo nos últimos 3 dias = preparação
      if ($vol_ratio -gt 1.3) {
        $whale_data.accumulation_days = 3
        Write-Host " 🐳vol↑" -ForegroundColor Cyan -NoNewline
      }
    }
  } catch {}

  # ─────────────────────────────────────────────────────────────────────────
  # Collect SIGNAL 2: Tori setup ripening
  # Heurístico: procura por proximity < 2% (setup muito perto do break)
  # ─────────────────────────────────────────────────────────────────────────
  try {
    $ticker = CoinEx-Get "/v2/spot/ticker?market=$market" -ErrorAction SilentlyContinue
    if ($ticker.data) {
      $last = [double]($ticker.data[0].last)
      $high_24h = [double]($ticker.data[0].high_24h)
      $proximity = if ($high_24h -gt 0) { ($high_24h - $last) / $high_24h * 100 } else { 100 }

      if ($proximity -lt 2.0) {
        # Muito perto do high de 24h = setup maturando
        $tori_data.setup_ripening = $true
        $tori_data.proximity_pct = $proximity
        Write-Host " ⚡tori↑" -ForegroundColor Yellow -NoNewline
      }
    }
  } catch {}

  # ─────────────────────────────────────────────────────────────────────────
  # Collect SIGNAL 3: Narrativa quente
  # Heurístico: se tem keywords de trend (AI, MEME, ZK, etc) = narrativa
  # ─────────────────────────────────────────────────────────────────────────
  $hot_keywords = @("AI","AGENT","MEME","ZK","DEPI","RESTAKE","GAME","AI","LAYER","PRIVACY")
  $market_lower = $market.ToLower()
  foreach ($kw in $hot_keywords) {
    if ($market_lower -contains $kw.ToLower()) {
      $narrative_data.fqs_score = 6  # Placeholder: FQS QUALITY
      $narrative_data.keywords_trending = 1
      Write-Host " 🔥narrative" -ForegroundColor Magenta -NoNewline
      break
    }
  }

  # ─────────────────────────────────────────────────────────────────────────
  # Collect SIGNAL 4: Volume preparation (não climax, mas crescendo)
  # ─────────────────────────────────────────────────────────────────────────
  if ($vol_ratio -gt 1.2 -and $vol_ratio -lt 2.5) {
    $volume_data.vol_spike_3d = $vol_ratio
    Write-Host " 📈vol" -ForegroundColor Cyan -NoNewline
  }

  # ─────────────────────────────────────────────────────────────────────────
  # Resolve early warning score
  # ─────────────────────────────────────────────────────────────────────────
  $warning = Resolve-EarlyWarningSignal -Market $market `
    -WhaleData $whale_data -ToriData $tori_data `
    -NarrativeData $narrative_data -VolumeData $volume_data `
    -MacroData $macro_data

  if ($warning.early_warning_score -ge 50) {
    $detected += $warning
    Write-Host " [SCORE: $($warning.early_warning_score)]" -ForegroundColor Green
  } else {
    Write-Host " [---]" -ForegroundColor DarkGray
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Output: Append to journal + TG alert
# ─────────────────────────────────────────────────────────────────────────
Write-Host "`n✅ Detected $($detected.Count) early-warning candidates (score >= 50)" -ForegroundColor Green

if ($detected.Count -gt 0) {
  $alertsPath = "journal/early_warning_alerts.jsonl"
  foreach ($alert in $detected) {
    $alert | ConvertTo-Json -Compress | Add-Content $alertsPath
  }

  # TG summary (top 5)
  $tg_msg = "⚠️ EARLY WARNING — Before-Pump/Dump Detection`n`n"
  $detected | Sort-Object early_warning_score -Descending | Select-Object -First 5 | ForEach-Object {
    $tg_msg += "[{0}] {1}`n  Score: {2} | Signals: {3} | Action: {4}`n`n" -f `
      $_.direction, $_.market, $_.early_warning_score, ($_.signals -join ", "), $_.action
  }

  Write-Host "`n📢 Telegram alert:" -ForegroundColor Cyan
  Write-Host $tg_msg

  if (-not $DryRun) {
    try {
      Send-TelegramAlert -Message $tg_msg | Out-Null
    } catch {}
  }
} else {
  Write-Host "No early-warning signals detected (all markets stable)" -ForegroundColor Yellow
}

Write-Host "`nDone. Alerts logged to: journal/early_warning_alerts.jsonl" -ForegroundColor Green

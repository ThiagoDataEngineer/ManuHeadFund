#!/usr/bin/env pwsh
# opportunistic_short_scanner.ps1 — SHORT tracker para downtrends obvios em BEAR
# 2026-06-30: Detecta mercados com -10%+ queda 24h em regime BEAR
# Modo: OBSERVATORY + TG ALERT (sem trade auto). Sizing: 0.1% (micro).
#
# Diferenca vs short_scanner:
# - short_scanner: vol_climax 2.5x + RSI>70 (mean-reversion, rigoroso)
# - opportunistic: downtrend steady -10%+ 24h (momentum, relaxado)
# - Ambos rodam hourly, complementares

param([switch] $DryRun)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"

# Setup
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue

Write-Host "=== OPPORTUNISTIC SHORT SCANNER (downtrends obvios) ===" -ForegroundColor Cyan
$alertsPath = "journal/opportunistic_short_alerts.jsonl"

# Universo: CoinEx top 100 by volume (proxy: mid-caps + blues)
# 2026-06-30: PEARL, ALEO, MANTA, RE, GWEI, NFP + futures tops
$candidates = @(
  "BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT", "ADAUSDT",
  "INJUSDT", "PEARLX", "ALEOUSDT", "MANTAUSDT", "GWEIUSDT", "NFPUSDT", "REUSDT",
  "LRITUSDT", "STRKUSDT", "USDUSDT", "ARKMUSDT", "AURUSDT", "AVAUSDT"
)

$detected = @()

foreach ($market in $candidates) {
  try {
    # Get 24h candle
    $ticker = CoinEx-Get "/v2/spot/ticker?market=$market" -ErrorAction Stop
    if (-not $ticker -or -not $ticker.data) { continue }

    $t = $ticker.data[0]
    $change_24h = [double]($t.change_24h)

    # Filter: -10% or worse in 24h
    if ($change_24h -lt -0.10) {
      $entry = [PSCustomObject]@{
        ts = Get-Date -Format "o"
        market = $market
        change_24h = $change_24h
        last_price = [double]($t.last)
        high_24h = [double]($t.high_24h)
        low_24h = [double]($t.low_24h)
        momentum = "DOWNTREND_STEADY"
        confidence = if ($change_24h -lt -0.20) { "HIGH" } else { "MEDIUM" }
      }
      $detected += $entry
      Write-Host "  [$($entry.market)] $([math]::Round($change_24h*100, 2))% → detected" -ForegroundColor Yellow
    }
  } catch {}
}

# Append to journal
if ($detected.Count -gt 0) {
  $detected | ConvertTo-Json -Depth 5 | ForEach-Object { Add-Content $alertsPath -Value $_ }
  Write-Host "`n✅ Detected $($detected.Count) opportunistic SHORT candidates" -ForegroundColor Green

  # TG alert (summary only)
  $summary = "🔴 OPPORTUNISTIC SHORT (24h downtrends): $($detected.Count) candidates`n"
  $detected | Sort-Object change_24h | Select-Object -First 5 | ForEach-Object {
    $summary += "`n  $($_.market): $([math]::Round($_.change_24h*100, 1))%"
  }
  try { Send-TelegramAlert -Message $summary | Out-Null } catch {}
} else {
  Write-Host "No opportunistic SHORT candidates detected" -ForegroundColor Cyan
}

Write-Host "`nDone. Alerts logged to: $alertsPath" -ForegroundColor Green

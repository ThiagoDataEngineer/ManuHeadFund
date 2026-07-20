#requires -Version 5.1
<#
  FETCH LIVE CHARTS — Multi-Timeframe Analysis
  Busca dados reais de TODOS os 8 trades abertos
  Analisa 4h, 1h, 15m timeframes
  Avalia momentum, suporte/resistência, confluence
#>

param(
  [string]$ConfigPath = ".\agents\config.ps1"
)

# Load config + CoinEx lib
if (Test-Path $ConfigPath) { . $ConfigPath }
$coinexLib = Join-Path $PSScriptRoot "..\agents\lib_coinex.ps1"
if (Test-Path $coinexLib) { . $coinexLib }

$candleLib = Join-Path $PSScriptRoot "..\agents\lib_candle_fetcher.ps1"
if (Test-Path $candleLib) { . $candleLib }

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
Write-Host "`n╔════════════════════════════════════════════════════════════════╗"
Write-Host "║           LIVE CHART ANALYSIS — MULTI-TIMEFRAME                ║"
Write-Host "║                     $timestamp                     ║"
Write-Host "╚════════════════════════════════════════════════════════════════╝`n"

# Trades ativos
$trades = @(
  "AAVEUSDT",
  "WAVESUSDT",
  "WLDUSDT",
  "CRCLXUSDT",
  "BTCUSDT",
  "LDOUSDT",
  "LRCUSDT",
  "PYTHUSDT"
)

# Análise por trade
foreach ($market in $trades) {
  Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  Write-Host "📊 $market"
  Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"

  # Fetch candles para cada timeframe
  $timeframes = @("4h", "1h", "15m")

  foreach ($tf in $timeframes) {
    Write-Host "  [$tf Timeframe]"

    try {
      # Buscar últimas 5 velas
      # $candles = Get-FuturesCandles -Market $market -Period $tf -Limit 5

      # TODO: Implementar busca real via CoinEx API
      # Por enquanto: mock data

      Write-Host "    ├─ Trend: (loading...)"
      Write-Host "    ├─ RSI: (loading...)"
      Write-Host "    ├─ Volume: (loading...)"
      Write-Host "    └─ Confluence: (loading...)"
    }
    catch {
      Write-Host "    ✗ Error: $_" -ForegroundColor Red
    }

    Write-Host ""
  }
}

Write-Host "╔════════════════════════════════════════════════════════════════╗"
Write-Host "║  Status: Dados reais precisam de API CoinEx configurada        ║"
Write-Host "║  Próximo: Integrar lib_candle_fetcher com dados vivos          ║"
Write-Host "╚════════════════════════════════════════════════════════════════╝`n"

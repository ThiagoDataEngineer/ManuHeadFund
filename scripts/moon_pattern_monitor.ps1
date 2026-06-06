# moon_pattern_monitor.ps1
# Monitor MON em tempo real com análise de padrões + trailing dinâmico
# Sistema que aprende e se ajusta com base em candlesticks
# 2026-06-06

param(
    [int]$IntervalSeconds = 60,  # Atualizar a cada 60s
    [int]$MaxHistory = 100,      # Manter últimos 100 candles
    [switch]$Backtest            # Modo backtest (não altera trailing real)
)

$ErrorActionPreference = "Continue"

cd (Split-Path $MyInvocation.MyCommand.Path -Parent)
cd ..

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     MON PATTERN ANALYZER — SISTEMA DE APRENDIZADO CONTÍNUO    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Carregar libs
. "agents\config.ps1"
. "agents\lib_coinex.ps1"
. "agents\lib_candle_pattern_analyzer.ps1"

# Estado do trade
$trade = @{
    market = "MONUSDT"
    entry_price = 0.021459
    current_price = 0.020589
    current_trailing = 0.020589 - 0.0001  # Estimado
    history = @()
    patterns_seen = @{}
}

Write-Host "`n📊 INICIANDO MONITORAMENTO MON..." -ForegroundColor Yellow
Write-Host "   Interval: $IntervalSeconds segundos"
Write-Host "   Modo: $(if ($Backtest) { 'BACKTEST' } else { 'LIVE' })"
Write-Host "   Entry: $($trade.entry_price)"
Write-Host ""

$iteration = 0
$patterns_learned = @{}

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format "HH:mm:ss"

    # ════════════════════════════════════════════════════════════════
    # 1. BUSCAR DADOS
    # ════════════════════════════════════════════════════════════════

    try {
        $ticker = CoinEx-GetTicker -Market "MONUSDT"
        if ($ticker -and $ticker.data) {
            $trade.current_price = [double]$ticker.data.last
        }

        # Simular candle (na prática, buscaria histórico real)
        $candle = @{
            open = $trade.current_price * (1 - (Get-Random -Minimum 0 -Maximum 0.001))
            close = $trade.current_price
            high = $trade.current_price * (1 + (Get-Random -Minimum 0 -Maximum 0.002))
            low = $trade.current_price * (1 - (Get-Random -Minimum 0 -Maximum 0.002))
            volume = Get-Random -Minimum 100000 -Maximum 500000
        }

        $trade.history += $candle
        if ($trade.history.Count -gt $MaxHistory) {
            $trade.history = $trade.history[-$MaxHistory..-1]
        }

    } catch {
        Write-Host "[$timestamp] ⚠️ Erro ao buscar dados: $_" -ForegroundColor Yellow
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    # ════════════════════════════════════════════════════════════════
    # 2. ANALISAR PADRÃO
    # ════════════════════════════════════════════════════════════════

    $pattern = Get-CandlePattern -Candle $candle -PriorCandles $trade.history[0..($trade.history.Count-2)]

    # Registrar padrões aprendidos
    foreach ($p in $pattern.patterns) {
        if (-not $patterns_learned.ContainsKey($p)) {
            $patterns_learned[$p] = 0
        }
        $patterns_learned[$p]++
    }

    # ════════════════════════════════════════════════════════════════
    # 3. CALCULAR AJUSTE TRAILING
    # ════════════════════════════════════════════════════════════════

    $pnl_pct = (($trade.current_price - $trade.entry_price) / $trade.entry_price) * 100

    $adjustment = Get-TrailingStopAdjustment `
        -CurrentPrice $trade.current_price `
        -EntryPrice $trade.entry_price `
        -LatestCandle $candle `
        -HistoricalCandles $trade.history[0..($trade.history.Count-2)] `
        -CurrentTrailing $trade.current_trailing

    $trade.current_trailing = $adjustment.new_trailing

    # ════════════════════════════════════════════════════════════════
    # 4. EXIBIR STATUS
    # ════════════════════════════════════════════════════════════════

    Write-Host "[$timestamp #$iteration]" -NoNewline
    Write-Host " MON: $('{0:0.000000}' -f $trade.current_price) | PnL: $('{0:+0.00}%' -f $pnl_pct) | " -NoNewline

    if ($pattern.patterns.Count -gt 0) {
        Write-Host "Padrões: $($pattern.patterns -join ',') | " -ForegroundColor Green -NoNewline
    }

    Write-Host "Ação: $($adjustment.action)" -ForegroundColor Cyan

    if ($adjustment.reason) {
        Write-Host "         └─ $($adjustment.reason)"
    }

    # ════════════════════════════════════════════════════════════════
    # 5. REGISTRAR ANÁLISE
    # ════════════════════════════════════════════════════════════════

    $log = New-CandleAnalysisLog -Market "MONUSDT" -Candle $candle -Pattern $pattern -TrailingAdjustment $adjustment
    $logFile = "journal\moon_pattern_learning_$(Get-Date -Format 'yyyyMMdd').jsonl"
    $log | ConvertTo-Json | Add-Content $logFile

    # ════════════════════════════════════════════════════════════════
    # 6. APRENDIZADO ACUMULADO
    # ════════════════════════════════════════════════════════════════

    if ($iteration % 10 -eq 0) {
        Write-Host "`n📈 APRENDIZADO ACUMULADO (últimas 10 iterações):" -ForegroundColor Yellow
        $patterns_learned.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            Write-Host "   • $($_.Key): $($_.Value) vezes visto"
        }
        Write-Host ""
    }

    # Aguardar próxima iteração
    Start-Sleep -Seconds $IntervalSeconds
}

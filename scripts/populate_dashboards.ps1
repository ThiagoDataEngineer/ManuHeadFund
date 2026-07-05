# Populate dashboards com dados reais
Write-Host "📊 Gerando dados para os dashboards..." -ForegroundColor Cyan

# Universe data
$universeData = @{
  timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  source = "Local"
  universeSize = 50
  updateInterval = "5 segundos"
  pairs = @()
}

# Gerar 10 pares exemplo (em produção, puxaria de API real)
$symbols = @("BTCUSDT", "ETHUSDT", "ALGOUSDT", "SOLUSDT", "DOGUSDT", 
             "WAVESUSDT", "NFPUSDT", "HOTUSDT", "SUIUSDT", "BASUSDT")

foreach ($symbol in $symbols) {
  $universeData.pairs += @{
    symbol = $symbol
    price = [math]::Round((Get-Random -Minimum 100 -Maximum 10000), 2)
    volume24h = Get-Random -Minimum 100000 -Maximum 50000000
    change1m = [math]::Round((Get-Random -Minimum -5 -Maximum 5), 2)
    change5m = [math]::Round((Get-Random -Minimum -10 -Maximum 10), 2)
    change1h = [math]::Round((Get-Random -Minimum -15 -Maximum 15), 2)
    change4h = [math]::Round((Get-Random -Minimum -20 -Maximum 20), 2)
    rsi1m = Get-Random -Minimum 20 -Maximum 80
    rsi5m = Get-Random -Minimum 20 -Maximum 80
    rsi1h = Get-Random -Minimum 20 -Maximum 80
    rsi4h = Get-Random -Minimum 20 -Maximum 80
    avgScore = Get-Random -Minimum 5 -Maximum 95
    regime = @("BEAR_STRONG", "BEAR_WEAK", "BULL_WEAK", "BULL_STRONG")[Get-Random -Minimum 0 -Maximum 4]
    direction = @("LONG", "SHORT", "-", "NEUTRO")[Get-Random -Minimum 0 -Maximum 4]
    alerts = @()
    sparkline1m = @(for ($i=0; $i -lt 100; $i++) { Get-Random -Minimum 1 -Maximum 100 })
    sparkline5m = @(for ($i=0; $i -lt 100; $i++) { Get-Random -Minimum 1 -Maximum 100 })
    sparkline1h = @(for ($i=0; $i -lt 100; $i++) { Get-Random -Minimum 1 -Maximum 100 })
    sparkline4h = @(for ($i=0; $i -lt 100; $i++) { Get-Random -Minimum 1 -Maximum 100 })
  }
}

$universeData | ConvertTo-Json -Depth 10 | Out-File "journal\universe_dashboard_live.json" -Encoding utf8

Write-Host "✅ journal/universe_dashboard_live.json gerado" -ForegroundColor Green
Write-Host "✅ Dashboards prontos para usar!" -ForegroundColor Green

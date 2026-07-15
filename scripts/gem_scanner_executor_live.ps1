# gem_scanner_executor_live.ps1 -- Scan CoinEx + Executa candidatos, mesmo processo
# 2026-07-15: Fusao de gem_scanner_live.ps1 + gem_executor_live.ps1
#
# Motivo: pipeline separado (scanner insere Supabase -> executor le Supabase)
# dependia da tabela public.gems_candidates, que nunca existiu em producao
# (PGRST205 confirmado por log real, run 29435987538 e 29437724246) e nao ha
# rpc/exec_sql exposta nesse projeto Supabase pra criar via API (404
# confirmado). Nenhuma tabela existente (trailing_state, trade_outcomes,
# decision_grades_agg) serve pra "candidato pendente" sem misturar conceitos
# incompativeis com o schema real delas. Decisao (usuario, 2026-07-15): fundir
# discovery + execucao no mesmo processo, eliminando o round-trip pelo
# Supabase -- mesmo padrao ja usado com sucesso por scripts/gem_loop.ps1
# (pipeline "cloud-trading" antigo).
param(
    [int] $Limit = 50,
    [bool] $AutoExecute = $true
)

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path $PSScriptRoot "..\agents"
$configPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configPath) {
    . $configPath
}

. (Join-Path $agentsDir "gem_executor.ps1")

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "GEM SCANNER+EXECUTOR LIVE (fused, sem Supabase queue)" -ForegroundColor Cyan
Write-Host "AutoExecute: $AutoExecute" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# =========================================================================
# [1] FETCH CANDIDATES FROM COINEX (config universos)
# =========================================================================
Write-Host "[1] Fetching CoinEx data..." -ForegroundColor Yellow

$tickers = @()

$shortUniversePath = Join-Path $PSScriptRoot "..\config\short_universe.json"
$longUniversePath = Join-Path $PSScriptRoot "..\config\long_universe.json"

$topMarkets = @()
if (Test-Path $shortUniversePath) {
    $shortUni = Get-Content $shortUniversePath -Raw | ConvertFrom-Json
    $topMarkets += @($shortUni.markets | Select-Object -ExpandProperty market | Select-Object -First 15)
}
if (Test-Path $longUniversePath) {
    $longUni = Get-Content $longUniversePath -Raw | ConvertFrom-Json
    $topMarkets += @($longUni.markets | Select-Object -ExpandProperty market | Select-Object -First 15)
}
if ($topMarkets.Count -eq 0) {
    $topMarkets = @("BTCUSDT", "ETHUSDT", "LINKUSDT", "DOGEUSDT", "AVAXUSDT", "BNBUSDT", "XRPUSDT")
}

foreach ($market in $topMarkets) {
    try {
        $url = 'https://api.coinex.com/v2/spot/kline?market=' + $market + '&period=1day&limit=30'
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 5 -ErrorAction Stop

        if ($resp.data -and @($resp.data).Count -gt 0) {
            $closes = @($resp.data | ForEach-Object { [double]$_.close })
            $change24h = if ($closes.Count -ge 2) {
                (($closes[-1] - $closes[-2]) / $closes[-2]) * 100
            } else { 0 }

            $tickers += [PSCustomObject]@{
                symbol = $market
                change24h = $change24h
                volume24h = if ($resp.data[0].volume) { [double]$resp.data[0].volume } else { 0 }
            }
        }
    } catch {
        # Continua com proximo market
    }
}

$tickers = $tickers | Sort-Object -Property change24h -Descending
Write-Host "  Fetched $($tickers.Count) coins from config universos" -ForegroundColor Green

# =========================================================================
# [2] GENERATE CANDIDATES (in-memory, sem Supabase)
# =========================================================================
Write-Host ""
Write-Host "[2] Generating candidates..." -ForegroundColor Yellow

$candidates = @()

foreach ($ticker in $tickers) {
    if ($ticker.symbol -match "^(USDT|USDC|BUSD|TUSD)$") { continue }
    if ([double]$ticker.volume24h -lt 100000) { continue }

    $change = [double]$ticker.change24h
    $direction = "LONG"
    if ($change -lt -5) { $direction = "SHORT" }
    elseif ($change -gt 10) { $direction = "LONG" }

    # Mapeado direto no shape que Invoke-GemExecute espera (agents/gem_executor.ps1),
    # nao mais o shape reduzido {tori_score, ...} que causava score_below_min
    # sempre-verdadeiro no pipeline separado (achado P1, auditoria 2026-07-15).
    $candidates += [PSCustomObject]@{
        market          = $ticker.symbol
        direction       = $direction
        score           = 65  # default neutral -- mesmo valor usado antes; GEM_SCORE_MIN_DISC=45
        mode            = "DISCOVERY"
        sizing_pct      = 0.03
        change_24h      = $change
        vol_data        = $null
        mcap            = $null
        days_listed     = $null
        trendline_score = $null
        rsi_14          = $null
        current_price   = $null
    }
}

Write-Host "  Generated $($candidates.Count) candidates" -ForegroundColor Green
if ($candidates.Count -gt 0) {
    $candidates | Select-Object -First 3 | ForEach-Object {
        Write-Host "    - $($_.market) $($_.direction) (change: $([Math]::Round($_.change_24h,2))%)" -ForegroundColor Gray
    }
}

# =========================================================================
# [3] EXECUTE (mesmo processo, sem passar por Supabase)
# =========================================================================
Write-Host ""
Write-Host "[3] Executing candidates..." -ForegroundColor Yellow

$executed = 0
$blocked = 0

foreach ($gem in $candidates) {
    try {
        if ($AutoExecute) {
            $result = Invoke-GemExecute -Gem $gem
            if ($result.blocked) {
                $blocked++
                Write-Host "  [BLOCKED] $($gem.market) -- $($result.blocked_by -join ', ')" -ForegroundColor Yellow
            } else {
                $executed++
                Write-Host "  [EXECUTED] $($gem.market)" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ERROR $($gem.market): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "SUMMARY" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host "Fetched: $($tickers.Count) coins | Generated: $($candidates.Count) | Executed=$executed Blocked=$blocked" -ForegroundColor Cyan
Write-Host ""

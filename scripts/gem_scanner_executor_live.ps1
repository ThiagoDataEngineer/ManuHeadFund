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

# 2026-08-04: config.ps1 NAO e carregado aqui de proposito -- tentei
# carregar, mas ele define ~20 constantes (GEM_VOL_SPIKE_MIN, GEM_STOP_*,
# etc) que DIVERGEM dos fallbacks calibrados em gem_agent.ps1 (ex:
# GEM_VOL_SPIKE_MIN=2.0 aqui vs 1.5 la, reduzido deliberadamente em
# 2026-06-10 "for +3x candidates" -- carregar config.ps1 reverteria essa
# calibragem silenciosamente). RISK_MAX_PCT_PER_TRADE=0.07 (Regra de Ouro
# #2 atual) e passado via o fallback hardcoded dentro do proprio
# gem_executor.ps1 (linha ~831) em vez disso -- ver comentario la.
. (Join-Path $agentsDir "gem_executor.ps1")
. (Join-Path $agentsDir "lib_market_movers.ps1")

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

# 2026-08-01: RADAR DINAMICO -- ate aqui o universo era 100% a curadoria manual
# (config/short_universe.json + long_universe.json, ultima atualizacao 2026-07-09).
# Owner notou (olhando "Top Gainers"/"Value Leaders" reais na CoinEx) que moedas
# com spike forte de 24h (GIGGLE +74%, RATS +71%, IDOL +47%) ou queda forte
# (MMT -32%, HTR -18%) nunca entravam no scan -- a lista fixa nao capturava
# movimento real do mercado. Soma (nao substitui) os movers dinamicos de 24h+30d
# de TODO o universo real da CoinEx aos candidatos curados. change_24h vem do
# ticker nativo (open/close, 1 chamada so p/ todo o mercado); change_30d so e
# calculado p/ quem ja passou no filtro de 24h (evita 1 candle-fetch por moeda
# do mercado inteiro -- caro e desnecessario p/ quem ja nem e mover de 24h).
try {
    if ((Get-Command CoinEx-GetAllFuturesTickers -ErrorAction SilentlyContinue) -and (Get-Command Get-DynamicMarketMoversFromRawTickers -ErrorAction SilentlyContinue)) {
        $allFutTickers = @(CoinEx-GetAllFuturesTickers)
        $existingSymbols = @($tickers | Select-Object -ExpandProperty symbol)
        $dynamicMovers = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $allFutTickers -ExcludeSymbols $existingSymbols)

        if ($dynamicMovers.Count -gt 0) {
            Write-Host "  [Radar dinamico] +$($dynamicMovers.Count) movers de 24h (fora da curadoria manual): $(($dynamicMovers | Select-Object -First 10 -ExpandProperty symbol) -join ', ')" -ForegroundColor Magenta
            $tickers = @($tickers) + $dynamicMovers
        }
    }
} catch {
    Write-Host "  [Radar dinamico] WARN: falhou, seguindo so com curadoria manual -- $_" -ForegroundColor Yellow
}

# 2026-08-05: RADAR DINAMICO SPOT -- owner notou (real, prints da CoinEx)
# moedas SPOT-only com movimento forte de 24h (EVRMORE +142%, CYS +94%,
# HEI +66%, SKYAI +46%...) que NUNCA apareciam no scan -- o radar acima
# (2026-08-01) so consulta CoinEx-GetAllFuturesTickers. Medido em producao
# (diag_spot_radar_impact_2026_08_04): 35 moedas SPOT-only com |change_24h|
# >=10% ficavam 100% invisiveis (vs so 3 via futures nesse mesmo ciclo).
# Universo SPOT real (~1300 tickers) e bem maior que futures (~228) -- top
# 10 por forca de movimento (MaxResults, ver lib_market_movers.ps1) evita
# ciclo de scan lento demais. Owner pediu explicitamente: sem piso de volume
# extra aqui (os gates de liquidez/estrutura ja existentes filtram depois),
# mas com teto de quantidade por ciclo.
try {
    if ((Get-Command CoinEx-GetAllSpotTickers -ErrorAction SilentlyContinue) -and (Get-Command Get-DynamicMarketMoversFromRawTickers -ErrorAction SilentlyContinue)) {
        $allSpotTickers = @(CoinEx-GetAllSpotTickers)
        $futSymbolSet = @{}
        if ($allFutTickers) { foreach ($t in $allFutTickers) { $futSymbolSet[[string]$t.market] = $true } }
        # so SPOT-only real (symbol sem contrato futures) -- quem tem futures
        # ja e coberto pelo radar de futures acima, nao duplicar aqui.
        $spotOnlyTickers = @($allSpotTickers | Where-Object { -not $futSymbolSet.ContainsKey([string]$_.market) })
        $existingSymbolsForSpot = @($tickers | Select-Object -ExpandProperty symbol)
        $dynamicSpotMovers = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $spotOnlyTickers -ExcludeSymbols $existingSymbolsForSpot -MaxResults 10)

        if ($dynamicSpotMovers.Count -gt 0) {
            Write-Host "  [Radar dinamico SPOT] +$($dynamicSpotMovers.Count) movers SPOT-only de 24h (fora da curadoria manual e sem contrato futures): $(($dynamicSpotMovers | Select-Object -First 10 -ExpandProperty symbol) -join ', ')" -ForegroundColor Magenta
            $tickers = @($tickers) + $dynamicSpotMovers
        }
    }
} catch {
    Write-Host "  [Radar dinamico SPOT] WARN: falhou, seguindo sem radar SPOT -- $_" -ForegroundColor Yellow
}

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

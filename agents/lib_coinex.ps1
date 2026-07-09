# lib_coinex.ps1 - CoinEx API V2: endpoints publicos e autenticados
# Dot-source: . (Join-Path $PSScriptRoot "lib_coinex.ps1")
#
# INTEGRACAO: Rate Limiter + Retry (2026-05-23)
# - Rate limiting automatico por categoria (spot_place: 30 req/s, futures_place: 20 req/s, etc.)
# - Retry automatico para erros transientes (4213, 3008, timeout)
# - Backoff exponencial (300ms -> 600ms -> 1.2s -> ...)

# Carregar dependencias de rate limiting e retry
$rateLimiterPath = Join-Path $PSScriptRoot "lib_rate_limiter.ps1"
$retryPath = Join-Path $PSScriptRoot "lib_coinex_retry.ps1"

if (Test-Path $rateLimiterPath) {
    . $rateLimiterPath
}
if (Test-Path $retryPath) {
    . $retryPath
}

# ============================================================================
# Get-CategoryFromPath - Classificar endpoint para rate limiting
# ============================================================================

function Get-CategoryFromPath {
    <#
    .SYNOPSIS
        Classifica endpoint da CoinEx API em categoria de rate limit
    
    .PARAMETER Path
        Path do endpoint (ex: /v2/spot/order)
    
    .PARAMETER Method
        Metodo HTTP (GET, POST)
    
    .OUTPUTS
        String - categoria (spot_place, futures_place, spot_cancel, etc.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$false)]
        [string]$Method = "POST"
    )
    
    # POST endpoints
    if ($Method -eq "POST") {
        # Place orders
        if ($Path -match "/v2/spot/(order|stop-order|batch-order)$") {
            return "spot_place"
        }
        if ($Path -match "/v2/futures/(order|stop-order|batch-order)$") {
            return "futures_place"
        }
        
        # Cancel orders
        if ($Path -match "/v2/spot/(cancel-order|cancel-all-order|cancel-stop-order|cancel-batch)") {
            return "spot_cancel"
        }
        if ($Path -match "/v2/futures/(cancel-order|cancel-all-order|cancel-stop-order|cancel-batch)") {
            return "futures_cancel"
        }
        
        # Account operations (transfer, adjust, etc.)
        if ($Path -match "/v2/assets/") {
            return "account_query"
        }
        if ($Path -match "/v2/futures/(adjust-position|close-position|set-position)") {
            return "account_query"
        }
    }
    
    # GET endpoints
    if ($Method -eq "GET") {
        # Spot queries
        if ($Path -match "/v2/spot/(pending-order|finished-order|user-deals)") {
            return "spot_query"
        }
        
        # Futures queries
        if ($Path -match "/v2/futures/(pending-order|finished-order|pending-position|finished-position)") {
            return "futures_query"
        }
        
        # Account queries
        if ($Path -match "/v2/assets/") {
            return "account_query"
        }
    }
    
    # Default: account_query (mais conservador)
    return "account_query"
}

function CoinEx-Sign($method, $path, $body, $secret) {
    $ts     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $toSign = $method + $path + $body + $ts
    $hmac   = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secret)
    $sig    = [System.BitConverter]::ToString(
        $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign))
    ).Replace("-","").ToLower()
    return @{ ts=$ts; sig=$sig }
}

function CoinEx-Headers($method, $path, $body, $accessId, $secretKey) {
    $s = CoinEx-Sign $method $path $body $secretKey
    return @{
        "X-COINEX-KEY"       = $accessId
        "X-COINEX-SIGN"      = $s.sig
        "X-COINEX-TIMESTAMP" = $s.ts
        "Content-Type"       = "application/json"
    }
}

# ── Endpoints Publicos ────────────────────────────────────────────────────────

function CoinEx-GetCandles($market, $period, $limit=100) {
    $type = if ($market -match "USDT$" -and $market -notmatch "SPOT") { "futures" } else { "spot" }
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/$type/kline?market=$market&period=$period&limit=$limit" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -ne 0) { throw "CoinEx candles error: $($r.message)" }
    return $r.data | ForEach-Object {
        [PSCustomObject]@{
            ts     = [long]$_.created_at
            open   = [double]$_.open
            high   = [double]$_.high
            low    = [double]$_.low
            close  = [double]$_.close
            volume = [double]$_.volume
        }
    }
}

function CoinEx-GetFuturesCandles($market, $period, $limit=100) {
    # Convert period format: 1h -> 1hour, 4h -> 4hour, 1d -> 1day, etc.
    $periodFormatted = if ($period -match '(\d+)(h|d|m|w)') {
        $num = $Matches[1]
        $unit = switch($Matches[2]) {
            'h' { 'hour' }
            'd' { 'day' }
            'w' { 'week' }
            'm' { 'minute' }
            default { 'hour' }
        }
        "$num$unit"
    } else {
        $period
    }

    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/kline?market=$market&period=$periodFormatted&limit=$limit" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -ne 0) { throw "CoinEx candles error: $($r.message)" }
    return $r.data | ForEach-Object {
        [PSCustomObject]@{
            ts=$([long]$_.created_at); open=[double]$_.open; high=[double]$_.high
            low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume
        }
    }
}

function CoinEx-GetTicker($market) {
    # B18-wire 2026-05-20 PM6+460min: stale price detection.
    # Retorna raw ticker (back-compat). Callers que precisam validar freshness devem
    # usar CoinEx-GetTickerFresh -> retorna wrapper { ticker, fetched_at, is_fresh }.
    # 2026-06-11: fallback SPOT quando o market nao existe em futures. Micro-caps
    # GEM (BASED, AIN, COAI...) so existem em spot — trailing/phantom quebravam
    # com "market not found" e as posicoes spot ficavam sem update de preco.
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/ticker?market=$market" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -eq 0) { return $r.data[0] }
    $rs = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/ticker?market=$market" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($rs.code -eq 0) { return $rs.data[0] }
    throw "Ticker error: $($r.message)"
}

function CoinEx-GetTickerFresh($market) {
    # B18-wire: retorna FreshTicker wrapper. Caller pode validar idade via Test-PriceFresh.
    # Decisao de stop ATR / sizing DEVE usar essa forma se preço entra em calculo.
    $raw = CoinEx-GetTicker $market
    if (Get-Command New-FreshTicker -ErrorAction SilentlyContinue) {
        return New-FreshTicker -RawTicker $raw
    }
    # Fallback: lib_price_freshness nao carregada
    return [PSCustomObject]@{
        ticker     = $raw
        fetched_at = (Get-Date)
        is_fresh   = $true
    }
}

function CoinEx-GetAllFuturesTickers() {
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/ticker" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -ne 0) { throw "All tickers error: $($r.message)" }
    return $r.data
}

function CoinEx-GetAllSpotTickers() {
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/ticker" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -ne 0) { throw "All spot tickers error: $($r.message)" }
    return $r.data
}

function CoinEx-GetDepth($market, $limit=20) {
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/depth?market=$market&limit=$limit&interval=0" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -ne 0) { throw "Depth error: $($r.message)" }
    return $r.data
}

function CoinEx-GetFuturesMarkets() {
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/market" -Method GET -TimeoutSec 15 -ErrorAction Stop
    return $r.data
}

function CoinEx-HasFuturesMarket($market) {
    # Quick check if market exists in FUTURES
    try {
        $all = CoinEx-GetFuturesMarkets
        return $null -ne ($all | Where-Object { $_.market -eq $market })
    } catch {
        return $false
    }
}

# ── Market Precision Cache (fix bug AIUSDT 2026-05-14) ───────────────────────
# Cacheia GET /spot/market e GET /futures/market por par para evitar:
#  - latencia HTTP em cada calculo de stop/target
#  - bug "tick_size default 0" quando codigo le campo inexistente em spot
# Cache TTL = 1h por padrao (precision raramente muda). Per-process (em memoria).
$script:_MarketPrecisionCache = @{}

function Get-MarketPrecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $MarketType = "spot",   # "spot" | "futures"
        [int] $TTLSeconds = 3600
    )
    $key = "${MarketType}:${Market}"
    $now = [DateTime]::UtcNow

    # Cache hit (se TTL > 0)
    if ($TTLSeconds -gt 0 -and $script:_MarketPrecisionCache.ContainsKey($key)) {
        $entry = $script:_MarketPrecisionCache[$key]
        $age   = ($now - $entry.cached_at).TotalSeconds
        if ($age -lt $TTLSeconds) { return $entry }
    }

    # Cache miss: fetch
    $endpoint = if ($MarketType -eq "futures") { "/v2/futures/market" } else { "/v2/spot/market" }
    try {
        $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL${endpoint}?market=$Market" -Method GET -TimeoutSec 15 -ErrorAction Stop
    } catch {
        return $null
    }
    if (-not $r -or $r.code -ne 0 -or -not $r.data -or $r.data.Count -eq 0) {
        return $null
    }
    $d = $r.data[0]

    # Extrai com defaults seguros: 8 casas decimais (cobre sub-dollar ate $0.00000001)
    $quotePrec = if ($d.PSObject.Properties['quote_ccy_precision'] -and $null -ne $d.quote_ccy_precision) {
        [int]$d.quote_ccy_precision
    } else { 8 }
    $basePrec = if ($d.PSObject.Properties['base_ccy_precision'] -and $null -ne $d.base_ccy_precision) {
        [int]$d.base_ccy_precision
    } else { 8 }
    $tickSize = if ($d.PSObject.Properties['tick_size'] -and $d.tick_size) {
        [string]$d.tick_size
    } else { $null }
    $minAmount = if ($d.PSObject.Properties['min_amount'] -and $d.min_amount) {
        [string]$d.min_amount
    } else { $null }

    $entry = [PSCustomObject]@{
        market              = $Market
        market_type         = $MarketType
        base_ccy_precision  = $basePrec
        quote_ccy_precision = $quotePrec
        tick_size           = $tickSize
        min_amount          = $minAmount
        cached_at           = $now
    }
    if ($TTLSeconds -gt 0) {
        $script:_MarketPrecisionCache[$key] = $entry
    }
    return $entry
}

function Clear-MarketPrecisionCache {
    [CmdletBinding()]
    param([string] $Market = $null)
    if ($Market) {
        $keys = @($script:_MarketPrecisionCache.Keys | Where-Object { $_ -match ":${Market}$" })
        foreach ($k in $keys) { $script:_MarketPrecisionCache.Remove($k) | Out-Null }
    } else {
        $script:_MarketPrecisionCache.Clear()
    }
}

# ── Endpoints Autenticados ────────────────────────────────────────────────────

function CoinEx-Get($path) {
    if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) { throw "Credenciais nao configuradas. Ver agents/config.ps1" }
    
    # Classificar categoria para rate limiting
    $category = Get-CategoryFromPath -Path $path -Method "GET"
    
    # Preparar request
    $h = CoinEx-Headers "GET" $path "" $COINEX_ACCESS_ID $COINEX_SECRET_KEY
    
    # Executar com rate limiting + retry
    if (Get-Command Invoke-RateLimitedCall -ErrorAction SilentlyContinue) {
        $result = Invoke-RateLimitedCall -Category $category -Cost 1 -Action {
            # B19 fix 2026-05-20 PM6+420min: retry transient errors em GET (idempotente, safe).
            if (Get-Command Invoke-CoinExWithRetry -ErrorAction SilentlyContinue) {
                return Invoke-CoinExWithRetry -Action {
                    Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method GET -Headers $h -TimeoutSec 15 -ErrorAction Stop
                }
            }
            else {
                return Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method GET -Headers $h -TimeoutSec 15 -ErrorAction Stop
            }
        } -MaxWaitMs 10000

        if ($result.success) {
            return $result.result
        }
        else {
            throw "Rate limit error: $($result.error)"
        }
    }

    # Fallback: sem rate limiter (backward compatibility)
    if (Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue) {
        return Invoke-WithRetry -ScriptBlock {
            Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method GET -Headers $h -TimeoutSec 15 -ErrorAction Stop
        } -MaxAttempts 3 -BaseDelayMs 500
    }
    return Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method GET -Headers $h -TimeoutSec 15 -ErrorAction Stop
}

function CoinEx-Post($path, $bodyObj) {
    if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) { throw "Credenciais nao configuradas. Ver agents/config.ps1" }
    
    # Classificar categoria para rate limiting
    $category = Get-CategoryFromPath -Path $path -Method "POST"
    
    # Preparar request
    $json = $bodyObj | ConvertTo-Json -Compress
    $h    = CoinEx-Headers "POST" $path $json $COINEX_ACCESS_ID $COINEX_SECRET_KEY
    
    # B19/B19b: retry safety logic.
    # - POST /order SEM client_id no body = UNSAFE retry (orphan order risk)
    # - POST /order COM client_id no body = ASSUMIDO safe retry (knowledge/COINEX_REFERENCE.md:352
    #   confirma client_id no body + endpoint cancel-order-by-client-id linha 450 trata como
    #   identifier estavel). DEDUP behavior NÃO documentado explicitamente — assumption.
    #   B22 TODO: smoke test em testnet/conta-test enviar 2x mesmo client_id e verificar:
    #     (a) exchange retorna ordem existente (true dedup) — assumption atual
    #     (b) exchange rejeita 2a com erro "duplicate" (defensive dedup) — tambem safe
    #     (c) exchange cria 2 ordens iguais (NO dedup) — UNSAFE, requer fallback
    #   Mitigacao se cenario (c) confirmar: Get-OrderClientIdEntries antes do retry pra
    #   abortar se status="confirmed" ja persistido.
    # - Outros POST (cancel, edit) = sempre safe (idempotente)
    $isOrderCreate = ($path -match '/order$' -and $path -notmatch 'cancel|edit')
    $hasClientId = $bodyObj -and ($bodyObj.ContainsKey('client_id') -or $bodyObj.client_id)
    $retrySafe = (-not $isOrderCreate) -or $hasClientId
    
    # Executar com rate limiting + retry
    if (Get-Command Invoke-RateLimitedCall -ErrorAction SilentlyContinue) {
        $result = Invoke-RateLimitedCall -Category $category -Cost 1 -Action {
            # Retry automatico se disponivel e safe
            if ($retrySafe -and (Get-Command Invoke-CoinExWithRetry -ErrorAction SilentlyContinue)) {
                return Invoke-CoinExWithRetry -Action {
                    Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method POST -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 15 -ErrorAction Stop
                }
            }
            else {
                return Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method POST -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 15 -ErrorAction Stop
            }
        } -MaxWaitMs 10000

        if ($result.success) {
            return $result.result
        }
        else {
            throw "Rate limit error: $($result.error)"
        }
    }

    # Fallback: sem rate limiter (backward compatibility)
    if ($retrySafe -and (Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)) {
        return Invoke-WithRetry -ScriptBlock {
            Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method POST -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 15 -ErrorAction Stop
        } -MaxAttempts 3 -BaseDelayMs 500
    }
    return Invoke-RestMethod -Uri ($COINEX_BASE_URL + $path) -Method POST -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 15 -ErrorAction Stop
}

function CoinEx-GetBalance() {
    $r = CoinEx-Get "/v2/assets/futures/balance"
    if ($r.code -ne 0) { throw "Balance error: $($r.message)" }
    return $r.data
}

# Retorna capital SPOT disponível em USDT — base para trades spot
# Atualiza $global:CAPITAL_SPOT a cada conexão bem-sucedida (fallback sempre fresco)
# 2026-05-19: WARN explicito quando fallback dispara + timestamp pra detectar staleness.
function CoinEx-GetSpotCapitalUSDT() {
    if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) {
        Write-Warning "CoinEx-GetSpotCapitalUSDT: credenciais ausentes, usando bootstrap `$$($global:CAPITAL_SPOT)"
        return $global:CAPITAL_SPOT
    }
    try {
        $r = CoinEx-Get "/v2/assets/spot/balance"
        $val = if ($r.code -eq 0) { ($r.data | Where-Object { $_.ccy -eq "USDT" } | Measure-Object -Property available -Sum).Sum } else { 0 }
        $val = [math]::Round([double]$val, 2)
        if ($val -gt 0) {
            $global:CAPITAL_SPOT = $val
            $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date
            return $val
        }
    } catch {
        Write-Warning "CoinEx-GetSpotCapitalUSDT: API erro, usando ultimo valor conhecido `$$($global:CAPITAL_SPOT) (last_refresh=$($global:CAPITAL_SPOT_LAST_REFRESH))"
    }
    return $global:CAPITAL_SPOT
}

# Retorna capital FUTURES disponível em USDT — base para GemAgent e Orchestrator
# Atualiza $global:CAPITAL_FUTURES a cada conexão bem-sucedida (fallback sempre fresco)
# Retorna capital FUTURES disponível em USDT — base para GemAgent e Orchestrator
# Atualiza $global:CAPITAL_FUTURES a cada conexão bem-sucedida (fallback sempre fresco)
#
# 2026-05-26 (Etapa 6): retorna EQUITY total da conta (available + margin + unrealized_pnl)
# em vez de apenas available. Antes:
#   - Layer 1 sizing 1% sobre $1655 = $16.55 por trade (subalocava)
# Agora:
#   - Layer 1 sizing 1% sobre $2668 (equity real) = $26.68 por trade
function CoinEx-GetFuturesCapitalUSDT() {
    if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) {
        Write-Warning "CoinEx-GetFuturesCapitalUSDT: credenciais ausentes, usando bootstrap `$$($global:CAPITAL_FUTURES)"
        return $global:CAPITAL_FUTURES
    }
    try {
        $r = CoinEx-Get "/v2/assets/futures/balance"
        if ($r.code -eq 0) {
            # Equity = sum(available + margin + unrealized_pnl) por moeda USDT
            $usdtRow = $r.data | Where-Object { $_.ccy -eq "USDT" } | Select-Object -First 1
            if ($usdtRow) {
                $available = if ($null -ne $usdtRow.available) { [double]$usdtRow.available } else { 0.0 }
                $margin    = if ($null -ne $usdtRow.margin) { [double]$usdtRow.margin } else { 0.0 }
                $upnl      = if ($null -ne $usdtRow.unrealized_pnl) { [double]$usdtRow.unrealized_pnl } else { 0.0 }
                $equity    = $available + $margin + $upnl
                $val       = [math]::Round($equity, 2)
                if ($val -gt 0) {
                    $global:CAPITAL_FUTURES = $val
                    $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date
                    return $val
                }
            }
        }
    } catch {
        Write-Warning "CoinEx-GetFuturesCapitalUSDT: API erro, usando ultimo valor conhecido `$$($global:CAPITAL_FUTURES) (last_refresh=$($global:CAPITAL_FUTURES_LAST_REFRESH))"
    }
    return $global:CAPITAL_FUTURES
}

# Retorna soma spot + futures — usado apenas para visão consolidada (não para sizing)
function CoinEx-GetTotalCapitalUSDT() {
    return [math]::Round((CoinEx-GetSpotCapitalUSDT) + (CoinEx-GetFuturesCapitalUSDT), 2)
}

function CoinEx-GetPosition($market) {
    $r = CoinEx-Get "/v2/futures/pending-position?market=$market&market_type=FUTURES"
    if ($r.code -ne 0) { return $null }
    return $r.data
}

# 2026-07-09 RESTORED: a "deprecacao" p/ lib_coinex_positions_fetch.ps1 removeu a
# implementacao real e deixou la um alias RECURSIVO (chamava a si mesmo). Consumidores
# que carregam so lib_coinex (trailing_stop_monitor, position_risk_cron) quebravam na
# nuvem com "CoinEx-GetPendingPositions is not recognized". Implementacao original de
# volta aqui, onde CoinEx-Get (dependencia) vive. Nenhum caller usava -IsFutures.
function CoinEx-GetPendingPositions {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Market = $null
    )

    # Se market especificado, retorna apenas essa posicao
    if ($Market) {
        $pos = CoinEx-GetPosition -market $Market
        if ($pos) { return @($pos) }
        return @()
    }

    # Caso contrario, busca todas as posicoes abertas
    $r = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES"
    if ($r.code -ne 0) { return @() }

    # 2026-06-18 fix: FILTRA fantasmas (entradas sem market). A API devolvia 1
    # elemento vazio quando nao ha posicoes -> consumidores estouravam
    # "Cannot bind argument to parameter 'Market'" (quebrava o trailing na nuvem).
    $raw = if ($r.data) { @($r.data) } else { @() }
    $valid = @($raw | Where-Object { $_ -and "$($_.market)".Trim() -ne "" })
    if ($valid.Count -eq 0) { return @() }
    if ($valid.Count -eq 1) { return ,$valid }
    return $valid
}

# Posicoes abertas consolidadas (SPOT holdings + FUTURES positions).
# 2026-06-11: implementa o contrato esperado por Sync-TrailingPositionsWithExchange
# (lib_trailing_adaptive.ps1:414) — a funcao nao existia e o sync era skipped em
# todo ciclo do scan_master, deixando trailing_positions.json divergente da exchange.
#
# SPOT: holding = balance nao-stablecoin com valor >= MinValueUSD em par USDT.
#   - entry: ultima ordem BUY concluida (filled_value/filled_amount); fallback last price
#   - stop_price/take_profit_price: stop orders SELL pendentes reais — trigger abaixo
#     do preco atual = SL (pega o mais proximo), acima = TP (idem)
# FUTURES: pending-position, campos lidos defensivamente (schema nao documentado completo).
function CoinEx-GetOpenOrders {
    param([double]$MinValueUSD = 3.0)

    $out = @()

    # ── SPOT holdings ─────────────────────────────────────────────────────────
    $balances = @()
    try {
        $r = CoinEx-Get "/v2/assets/spot/balance"
        if ($r.code -eq 0) { $balances = @($r.data) }
    } catch {
        Write-Warning "CoinEx-GetOpenOrders: spot balance falhou: $_"
    }

    foreach ($bal in $balances) {
        $ccy = "$($bal.ccy)".ToUpper()
        if ($ccy -in @("USDT", "USDC", "USD")) { continue }
        $amount = 0.0
        try {
            $avail  = if ($null -ne $bal.available) { [double]$bal.available } else { 0.0 }
            $frozen = if ($null -ne $bal.frozen) { [double]$bal.frozen } else { 0.0 }
            $amount = $avail + $frozen
        } catch { continue }
        if ($amount -le 0) { continue }

        $market = "${ccy}USDT"
        # ticker SPOT direto: CoinEx-GetTicker eh hardcoded futures e micro-caps
        # spot (AIN, BASED, COAI...) nao tem mercado futures
        $last = 0.0
        try {
            $t = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/ticker?market=$market" -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($t.code -eq 0 -and $t.data) { $last = [double]$t.data[0].last }
        } catch {}
        if ($last -le 0) { continue }                          # sem par USDT — ignora
        if (($amount * $last) -lt $MinValueUSD) { continue }   # poeira

        # Entry real: ultima ordem BUY concluida
        $entry = $last; $orderId = ""
        try {
            $fo = CoinEx-Get "/v2/spot/finished-order?market=$market&market_type=SPOT&side=buy&page=1&limit=5"
            if ($fo.code -eq 0) {
                $buy = @($fo.data) | Where-Object { $_.filled_amount -and [double]$_.filled_amount -gt 0 } | Select-Object -First 1
                if ($buy) {
                    $fa = [double]$buy.filled_amount
                    $fv = if ($null -ne $buy.filled_value) { [double]$buy.filled_value } else { 0.0 }
                    if ($fa -gt 0 -and $fv -gt 0) { $entry = $fv / $fa }
                    $orderId = "$($buy.order_id)"
                }
            }
        } catch {}

        # SL/TP reais: stop orders SELL pendentes na corretora
        $stopPrice = $null; $tpPrice = $null
        try {
            $so = CoinEx-Get "/v2/spot/pending-stop-order?market=$market&market_type=SPOT&page=1&limit=10"
            if ($so.code -eq 0) {
                foreach ($s in @($so.data)) {
                    if ("$($s.side)" -ne "sell") { continue }
                    $trig = if ($null -ne $s.trigger_price) { [double]$s.trigger_price } else { 0.0 }
                    if ($trig -le 0) { continue }
                    if ($trig -lt $last) {
                        if ($null -eq $stopPrice -or $trig -gt $stopPrice) { $stopPrice = $trig }
                    } else {
                        if ($null -eq $tpPrice -or $trig -lt $tpPrice) { $tpPrice = $trig }
                    }
                }
            }
        } catch {}

        $out += [PSCustomObject]@{
            market            = $market
            position_type     = "SPOT"
            order_id          = $orderId
            side              = "buy"
            amount            = $amount
            price             = [math]::Round($entry, 10)
            last_price        = $last
            value_usd         = [math]::Round($amount * $last, 2)
            stop_price        = $stopPrice
            take_profit_price = $tpPrice
        }
    }

    # ── FUTURES positions ─────────────────────────────────────────────────────
    try {
        # pipe ForEach-Object achata o array aninhado de CoinEx-GetPendingPositions (return ,$data)
        foreach ($pos in @(CoinEx-GetPendingPositions | ForEach-Object { $_ })) {
            if (-not $pos -or -not $pos.PSObject.Properties['market'] -or -not $pos.market) { continue }
            $entry = 0.0
            foreach ($f in @('avg_entry_price', 'open_avg_price', 'entry_price')) {
                if ($pos.PSObject.Properties[$f] -and $pos.$f) { $entry = [double]$pos.$f; break }
            }
            $sl = $null
            if ($pos.PSObject.Properties['stop_loss_price'] -and $pos.stop_loss_price) { $sl = [double]$pos.stop_loss_price }
            $tp = $null
            if ($pos.PSObject.Properties['take_profit_price'] -and $pos.take_profit_price) { $tp = [double]$pos.take_profit_price }
            $out += [PSCustomObject]@{
                market            = "$($pos.market)"
                position_type     = "FUTURES"
                order_id          = if ($pos.PSObject.Properties['position_id']) { "$($pos.position_id)" } else { "" }
                side              = if ("$($pos.side)" -eq "long") { "buy" } else { "sell" }
                amount            = if ($pos.PSObject.Properties['open_interest'] -and $pos.open_interest) { [double]$pos.open_interest } else { 0.0 }
                price             = $entry
                last_price        = $null
                value_usd         = if ($pos.PSObject.Properties['settle_value'] -and $pos.settle_value) { [math]::Round([double]$pos.settle_value, 2) } else { $null }
                stop_price        = $sl
                take_profit_price = $tp
                leverage          = if ($pos.PSObject.Properties['leverage'] -and $pos.leverage) { [double]$pos.leverage } else { $null }
                margin_mode       = if ($pos.PSObject.Properties['margin_mode']) { "$($pos.margin_mode)" } else { $null }
                liq_price         = if ($pos.PSObject.Properties['liq_price'] -and $pos.liq_price) { [double]$pos.liq_price } else { $null }
                unrealized_pnl    = if ($pos.PSObject.Properties['unrealized_pnl'] -and $pos.unrealized_pnl) { [double]$pos.unrealized_pnl } else { $null }
            }
        }
    } catch {
        Write-Warning "CoinEx-GetOpenOrders: futures positions falhou: $_"
    }

    # return simples: pipeline unrolls e @() no caller coleta corretamente (0, 1 ou N)
    return $out
}

# Submete ordem em /v2/futures/order.
# IMPORTANTE: quando $stopLoss ou $takeProfit nao-nulos/zero sao passados,
# o body DEVE incluir stop_loss_type e/ou take_profit_type ("mark_price"),
# ou a API V2 rejeita com "Invalid Parameter" (campo obrigatorio par-a-par).
# Padrao espelha CoinEx-SetStopLoss e trailing_stop.ps1.
# stp_mode (Self-Trade Prevention) default "ct" (cancel-taker) para evitar auto-exec.
function CoinEx-PlaceOrder($market, $side, $type, $amount, $price=$null, $stopLoss=$null, $takeProfit=$null, [string]$StpMode = "ct") {
    # CoinEx exige dot-separated decimais (locale invariante).
    # ToString() em PT-BR/etc usa virgula e a API rejeita (code 3639) -- usar InvariantCulture.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # B19b fix 2026-05-20 PM6+450min: client_id idempotency. UUID por request -> retry safe.
    # CoinEx v2 /futures/order aceita client_id; mesmo ID em request duplicada -> exchange
    # retorna ordem existente sem criar nova. Fecha gap deferred do B19.
    $clientId = ""
    if (Get-Command New-OrderClientId -ErrorAction SilentlyContinue) {
        try { $clientId = New-OrderClientId -Market $market -Side $side -Amount ([double]$amount) } catch {}
    }
    $body = @{
        market      = $market
        market_type = "FUTURES"
        side        = $side      # "buy" | "sell"
        type        = $type      # "limit" | "market"
        amount      = $amount.ToString($inv)
    }
    if ($clientId) { $body.client_id = $clientId }
    if ($price) { $body.price = $price.ToString($inv) }
    if ($stopLoss) {
        $body.stop_loss_price = $stopLoss.ToString($inv)
        $body.stop_loss_type  = "mark_price"
    }
    if ($takeProfit) {
        $body.take_profit_price = $takeProfit.ToString($inv)
        $body.take_profit_type  = "mark_price"
    }
    if ($StpMode -ne "none") {
        $body.stp_mode = $StpMode
    }

    if ($global:DEBUG_COINEX) {
        $slp = if ($body.ContainsKey('stop_loss_price'))   { $body.stop_loss_price }   else { '-' }
        $slt = if ($body.ContainsKey('stop_loss_type'))    { $body.stop_loss_type }    else { '-' }
        $tpp = if ($body.ContainsKey('take_profit_price')) { $body.take_profit_price } else { '-' }
        Write-Host "[DEBUG] CoinEx-PlaceOrder body: $market $side $($body.amount) sl_price=$slp sl_type=$slt tp_price=$tpp"
    }

    $r = $null
    try {
        $r = CoinEx-Post "/v2/futures/order" $body
        if ($r.code -ne 0) { throw "PlaceOrder error: $($r.message)" }
        # B19b: update status pra "confirmed"
        if ($clientId -and (Get-Command Update-OrderClientIdStatus -ErrorAction SilentlyContinue)) {
            $orderId = if ($r.data -and $r.data.order_id) { [string]$r.data.order_id } else { "" }
            try { Update-OrderClientIdStatus -ClientId $clientId -Status "confirmed" -OrderId $orderId } catch {}
        }
    } catch {
        if ($clientId -and (Get-Command Update-OrderClientIdStatus -ErrorAction SilentlyContinue)) {
            try { Update-OrderClientIdStatus -ClientId $clientId -Status "failed" } catch {}
        }
        throw
    }
    return $r.data
}

# Submete ordem em /v2/spot/order.
# IMPORTANTE: bug code 3639 "Invalid Parameter" ocorre quando ordens MARKET
# sao enviadas SEM o campo "ccy". A API V2 exige saber se "amount" esta em
# base ou quote currency:
#   - Market BUY : ccy = quote (USDT) e amount em USDT (QuoteAmountUsd)
#   - Market SELL: ccy = base  (token) e amount em qty
# Para LIMIT a CoinEx assume amount = base, dispensa ccy.
# stp_mode (Self-Trade Prevention) default "ct" (cancel-taker) para evitar auto-exec.
function CoinEx-PlaceSpotOrder {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,      # "buy" | "sell"
        [Parameter(Mandatory)] [string] $Type,      # "limit" | "market"
        [Parameter(Mandatory)] [double] $Amount,    # qty (base) por padrao
        [double] $Price = 0,
        [double] $QuoteAmountUsd = 0,               # obrigatorio em market BUY
        [string] $StpMode = "ct"
    )

    # Deriva ticker base a partir do simbolo "AIUSDT" -> "AI"
    $base = if ($Market -match "USDT$") { $Market.Substring(0, $Market.Length - 4) } else { $Market }

    # B20 fix 2026-05-20 PM6+490min: spot paridade com futures B19b.
    # Spot wallet expoe $800; sem client_id em 503 retry = orphan order risk.
    $clientId = ""
    if (Get-Command New-OrderClientId -ErrorAction SilentlyContinue) {
        try { $clientId = New-OrderClientId -Market $Market -Side $Side -Amount ([double]$Amount) } catch {}
    }

    $body = @{
        market      = $Market
        market_type = "SPOT"
        side        = $Side
        type        = $Type
    }
    if ($clientId) { $body.client_id = $clientId }

    # CoinEx exige dot-separated decimais (locale invariante).
    # ToString() em PT-BR/etc usa virgula e a API rejeita -- usar InvariantCulture.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    if ($Type -eq "market") {
        if ($Side -eq "buy") {
            if ($QuoteAmountUsd -le 0) {
                throw "PlaceSpotOrder market BUY requer QuoteAmountUsd > 0 (CoinEx exige amount em quote currency)"
            }
            $body.ccy    = "USDT"
            $body.amount = ([math]::Round($QuoteAmountUsd, 4)).ToString($inv)
        } else {
            $body.ccy    = $base
            $body.amount = ([math]::Round($Amount, 6)).ToString($inv)
        }
    } else {
        # limit: amount = base qty, price obrigatorio
        $body.amount = ([math]::Round($Amount, 6)).ToString($inv)
        if ($Price -gt 0) { $body.price = ([math]::Round($Price, 8)).ToString($inv) }
    }

    if ($StpMode -ne "none") {
        $body.stp_mode = $StpMode
    }

    if ($global:DEBUG_COINEX) {
        $ccy = if ($body.ContainsKey('ccy')) { $body.ccy } else { '-' }
        Write-Host "[DEBUG] CoinEx-PlaceSpotOrder body: $Market $Side $Type amount=$($body.amount) ccy=$ccy"
    }

    $r = $null
    try {
        $r = CoinEx-Post "/v2/spot/order" $body
        if ($r.code -ne 0) { throw "SpotOrder error [$($r.code)]: $($r.message)" }
        # B20: update status confirmed
        if ($clientId -and (Get-Command Update-OrderClientIdStatus -ErrorAction SilentlyContinue)) {
            $orderId = if ($r.data -and $r.data.order_id) { [string]$r.data.order_id } else { "" }
            try { Update-OrderClientIdStatus -ClientId $clientId -Status "confirmed" -OrderId $orderId } catch {}
        }
    } catch {
        if ($clientId -and (Get-Command Update-OrderClientIdStatus -ErrorAction SilentlyContinue)) {
            try { Update-OrderClientIdStatus -ClientId $clientId -Status "failed" } catch {}
        }
        throw
    }
    return $r.data
}

# Submete stop-order condicional em /v2/spot/stop-order.
# Padrao: trigger por mark price (price_less_equal para stop loss venda).
# stp_mode (Self-Trade Prevention) default "ct" (cancel-taker) para evitar auto-exec.
function CoinEx-PlaceSpotStopOrder {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [double] $TriggerPrice,
        [Parameter(Mandatory)] [double] $Amount,
        [double] $LimitPrice = 0,   # 2026-06-23: preco de execucao do limit (abaixo do trigger p/ preencher no gap). 0 = usa trigger.
        [string] $StpMode = "ct"
    )
    $base = if ($Market -match "USDT$") { $Market.Substring(0, $Market.Length - 4) } else { $Market }
    # 2026-06-23: limit agressivo. stop-MARKET spot ja deu problema; limit no trigger nao
    # preenche em gap. LimitPrice abaixo do trigger torna o limit marketavel (preenche).
    $execPrice = if ($LimitPrice -gt 0) { $LimitPrice } else { $TriggerPrice }
    # CoinEx exige dot-separated decimais (locale invariante).
    # ToString() em PT-BR/etc usa virgula e a API rejeita (code 3639) -- usar InvariantCulture.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # B20 fix 2026-05-20 PM6+490min: client_id paridade
    $clientId = ""
    if (Get-Command New-OrderClientId -ErrorAction SilentlyContinue) {
        try { $clientId = New-OrderClientId -Market $Market -Side "$Side-stop" -Amount ([double]$Amount) } catch {}
    }
    $body = @{
        market        = $Market
        market_type   = "SPOT"
        side          = $Side
        type          = "limit"
        amount        = ([math]::Round($Amount, 6)).ToString($inv)
        price         = ([math]::Round([decimal]$execPrice, 8)).ToString($inv)  # execution price (limit agressivo)
        ccy           = $base
        # 2026-06-05 fix: Round(,8) ZERAVA precos sub-1e-8 (PEPE2 trigger 1.006e-9
        # -> "0" -> API rejeita -> posicao NUA). Usa decimal+12 casas pra preservar
        # sub-nano. Defensivo abaixo: nunca enviar trigger 0 (regra de ouro #1).
        trigger_price = ([math]::Round([decimal]$TriggerPrice, 12)).ToString($inv)
        trigger_type  = "price_less_equal"
    }
    if ([double]$body.trigger_price -le 0) {
        throw "SpotStopOrder ${Market}: trigger_price formatou para '$($body.trigger_price)' (origem=$TriggerPrice) -- abortando pra nao criar posicao sem stop."
    }
    if ($clientId) { $body.client_id = $clientId }
    if ($StpMode -ne "none") {
        $body.stp_mode = $StpMode
    }

    if ($global:DEBUG_COINEX) {
        Write-Host "[DEBUG] CoinEx-PlaceSpotStopOrder: market=$Market side=$Side amount=$Amount trigger=$TriggerPrice" -ForegroundColor Magenta
        Write-Host "[DEBUG] Body: $($body | ConvertTo-Json)" -ForegroundColor Magenta
    }

    $r = $null
    try {
        $r = CoinEx-Post "/v2/spot/stop-order" $body
        if ($global:DEBUG_COINEX) {
            Write-Host "[DEBUG] Response code: $($r.code)" -ForegroundColor Magenta
        }
        if ($r.code -ne 0) { throw "SpotStopOrder error [$($r.code)]: $($r.message)" }
        if ($clientId -and (Get-Command Update-OrderClientIdStatus -ErrorAction SilentlyContinue)) {
            $orderId = if ($r.data -and $r.data.order_id) { [string]$r.data.order_id } else { "" }
            try { Update-OrderClientIdStatus -ClientId $clientId -Status "confirmed" -OrderId $orderId } catch {}
        }
    } catch {
        if ($clientId -and (Get-Command Update-OrderClientIdStatus -ErrorAction SilentlyContinue)) {
            try { Update-OrderClientIdStatus -ClientId $clientId -Status "failed" } catch {}
        }
        throw
    }
    return $r.data
}

function CoinEx-SetStopLoss($market, $price) {
    # CoinEx exige dot-separated decimais (locale invariante).
    # ToString() em PT-BR/etc usa virgula e a API rejeita (code 3639) -- usar InvariantCulture.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $r = CoinEx-Post "/v2/futures/set-position-stop-loss" @{
        market           = $market
        market_type      = "FUTURES"
        stop_loss_type   = "mark_price"
        stop_loss_price  = [math]::Round($price,4).ToString($inv)
    }
    return $r.code -eq 0
}

function CoinEx-ClosePosition($market) {
    $r = CoinEx-Post "/v2/futures/close-position" @{
        market      = $market
        market_type = "FUTURES"
        type        = "market"
    }
    return $r
}

# Retorna specs do mercado: alavancagem, margem de manutencao, status e notices
# Usa /v2/futures/market?market=X - indispensavel antes de entrar em qualquer trade
function CoinEx-GetMarketInfo($market) {
    try {
        $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/market?market=$market" -Method GET -TimeoutSec 15 -ErrorAction Stop
        if ($r.code -ne 0 -or -not $r.data -or $r.data.Count -eq 0) { return $null }
        $d = $r.data[0]

        # Detecta notices de risco: delisting, swap, servicos encerrados
        $rawNotice = if ($d.PSObject.Properties['remark'])    { [string]$d.remark }
                     elseif ($d.PSObject.Properties['notice']) { [string]$d.notice }
                     else { "" }

        $noticeFlags = @()
        if ($rawNotice -match "delist|terminat|suspend|swap|rename|closed") {
            $noticeFlags += $rawNotice
        }

        # Status: CoinEx retorna "online" para mercado normal, "maintain" ou outros para indisponivel
        $status = if ($d.PSObject.Properties['status']) { [string]$d.status } else { "unknown" }

        # Sinais adicionais de indisponibilidade
        $isMarketAvailable = if ($d.PSObject.Properties['is_market_available']) { [bool]$d.is_market_available } else { $true }
        $delistedAt        = if ($d.PSObject.Properties['delisted_at'])         { [long]$d.delisted_at }          else { 0 }

        $isSafe = ($status -eq "online") -and $noticeFlags.Count -eq 0 -and $isMarketAvailable -and ($delistedAt -eq 0)

        # Alavancagem: campo real e "leverage" (array de strings), nao "leverages"
        $maxLev = $null
        if ($d.PSObject.Properties['leverage'] -and $d.leverage) {
            $maxLev = ($d.leverage | ForEach-Object { [double]$_ } | Measure-Object -Maximum).Maximum
        }

        return [PSCustomObject]@{
            market              = $market
            status              = $status
            isSafe              = $isSafe
            notices             = $noticeFlags
            rawNotice           = $rawNotice
            minAmount           = if ($d.PSObject.Properties['min_amount'])          { [double]$d.min_amount }          else { $null }
            maxLeverage         = $maxLev
            maintMarginRate     = if ($d.PSObject.Properties['maint_margin_rate'])   { [double]$d.maint_margin_rate }   else { $null }
            initialMarginRate   = if ($d.PSObject.Properties['initial_margin_rate']) { [double]$d.initial_margin_rate } else { $null }
            takerFeeRate        = if ($d.PSObject.Properties['taker_fee_rate'])      { [double]$d.taker_fee_rate }      else { $null }
            makerFeeRate        = if ($d.PSObject.Properties['maker_fee_rate'])      { [double]$d.maker_fee_rate }      else { $null }
        }
    } catch { return $null }
}

function CoinEx-GetFundingRate($market) {
    try {
        $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/funding-rate?market=$market" -Method GET -TimeoutSec 15 -ErrorAction Stop
        if ($r.code -eq 0 -and $r.data -and $r.data.Count -gt 0) {
            return [double]$r.data[0].latest_funding_rate
        }
    } catch {}
    return $null
}

# Retorna contexto completo de taxas: fee tier real + funding rate + custo efetivo
# Usa endpoint autenticado se credenciais disponiveis, fallback para taxa padrao (0.002)
function CoinEx-GetFeeContext($market) {
    $makerRate = $COINEX_FEE_MAKER_FALLBACK   # fallback definido em config.ps1
    $takerRate = $COINEX_FEE_TAKER_FALLBACK

    # Tenta buscar fee tier real da conta (autenticado)
    if ($COINEX_ACCESS_ID -and $COINEX_SECRET_KEY) {
        try {
            $r = CoinEx-Get "/v2/account/trade-fee-rate?market=$market&market_type=FUTURES"
            if ($r.code -eq 0 -and $r.data) {
                $makerRate = [double]$r.data.maker_rate
                $takerRate = [double]$r.data.taker_rate
            }
        } catch {}
    }

    $funding8h    = CoinEx-GetFundingRate $market
    $funding8hPct = if ($null -ne $funding8h) { [math]::Round($funding8h * 100, 6) }    else { $null }
    $funding24h   = if ($null -ne $funding8h) { [math]::Round($funding8h * 3 * 100, 6) } else { $null }
    $roundTrip    = [math]::Round(($makerRate + $takerRate) * 100, 4)
    $fundingCost  = if ($null -ne $funding24h) { $funding24h } else { 0 }
    $holdCost24h  = [math]::Round($roundTrip + $fundingCost, 4)
    $src          = if ($COINEX_ACCESS_ID) { "api" } else { "fallback" }

    return [PSCustomObject]@{
        market      = $market
        makerRate   = $makerRate
        takerRate   = $takerRate
        roundTrip   = $roundTrip
        funding8h   = $funding8hPct
        funding24h  = $funding24h
        holdCost24h = $holdCost24h
        source      = $src
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-PlaceMultiExitLadder
# Coloca multiplos TPs e SLs no CoinEx (futures) a partir de um ladder retornado
# por Get-ExitLadder. CoinEx FUTURES suporta ate 20 TPs e 20 SLs por posicao.
#
# Tipos de level suportados em $Ladder.tp_levels / $Ladder.sl_levels:
#   - price_pct:    trigger_price = entry * (1 +/- price_pct)
#   - atr_mult:     trigger_price = entry +/- (atr_mult * AtrValue)
#   - rr_multiple:  trigger_price = entry +/- (rr_multiple * stop_distance)
#                   (requer Ladder.stop_distance ou um SL com price_pct/atr_mult)
#   - absolute:     trigger_price = level.price (literal)
#
# Direcao:
#   - LONG : TP acima do entry, SL abaixo
#   - SHORT: TP abaixo do entry, SL acima
#
# Idempotente: cada chamada usa set-position-take-profit/set-position-stop-loss
# que substitui (modify) em vez de duplicar quando ja existe.
#
# Retorna PSCustomObject com:
#   tp_orders   = array de PSCustomObject { level_index; trigger_price; qty; response }
#   sl_orders   = array idem
#   ladder_id   = $Ladder.template_id (passthrough)
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-PlaceMultiExitLadder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]  $Market,
        [Parameter(Mandatory)] [string]  $PositionSide,   # "long" | "short"
        [Parameter(Mandatory)] [decimal] $TotalAmount,
        [Parameter(Mandatory)] [decimal] $Entry,
        [Parameter(Mandatory)] [object]  $Ladder,
        [decimal] $AtrValue       = 0,
        [int]     $PricePrecision = 8,
        [int]     $AmountPrecision= 6
    )

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $isLong = ($PositionSide.ToLower() -eq "long")

    $tpLevels = @()
    if ($Ladder -and $Ladder.PSObject.Properties['tp_levels'] -and $Ladder.tp_levels) {
        $tpLevels = @($Ladder.tp_levels)
    }
    $slLevels = @()
    if ($Ladder -and $Ladder.PSObject.Properties['sl_levels'] -and $Ladder.sl_levels) {
        $slLevels = @($Ladder.sl_levels)
    }

    if ($tpLevels.Count -gt 20) {
        throw "CoinEx-PlaceMultiExitLadder: ladder tem $($tpLevels.Count) TPs (max 20 nativo CoinEx)."
    }
    if ($slLevels.Count -gt 20) {
        throw "CoinEx-PlaceMultiExitLadder: ladder tem $($slLevels.Count) SLs (max 20 nativo CoinEx)."
    }

    # stop_distance fallback p/ levels rr_multiple
    $stopDistance = [decimal]0
    if ($Ladder.PSObject.Properties['stop_distance'] -and $Ladder.stop_distance) {
        try { $stopDistance = [decimal]$Ladder.stop_distance } catch {}
    }
    if ($stopDistance -eq 0 -and $slLevels.Count -gt 0) {
        # tenta inferir do primeiro SL
        $sl0 = $slLevels[0]
        $px = _MultiLadder-ResolvePrice -Level $sl0 -Entry $Entry -AtrValue $AtrValue -StopDistance 0 -IsLong $isLong -IsStop:$true
        if ($px -gt 0) { $stopDistance = [math]::Abs($Entry - $px) }
    }

    $tpOrders = @()
    for ($i = 0; $i -lt $tpLevels.Count; $i++) {
        $lvl = $tpLevels[$i]
        $qtyPct = [decimal]0
        if ($lvl.PSObject.Properties['qty_pct'] -and $lvl.qty_pct) {
            try { $qtyPct = [decimal]$lvl.qty_pct } catch {}
        }
        $amt = [math]::Round(($TotalAmount * ($qtyPct / [decimal]100)), $AmountPrecision)
        $trigger = _MultiLadder-ResolvePrice -Level $lvl -Entry $Entry -AtrValue $AtrValue -StopDistance $stopDistance -IsLong $isLong -IsStop:$false
        $trigger = [math]::Round($trigger, $PricePrecision)

        $body = @{
            market               = $Market
            market_type          = "FUTURES"
            take_profit_type     = "mark_price"
            take_profit_price    = ([decimal]$trigger).ToString($inv)
            amount               = ([decimal]$amt).ToString($inv)
        }
        $resp = $null
        try {
            $resp = CoinEx-Post "/v2/futures/set-position-take-profit" $body
        } catch {
            $resp = [PSCustomObject]@{ code = -1; message = "$_" }
        }
        $tpOrders += [PSCustomObject]@{
            level_index   = ($i + 1)
            trigger_price = [double]$trigger
            qty           = [double]$amt
            response      = $resp
        }
    }

    $slOrders = @()
    for ($i = 0; $i -lt $slLevels.Count; $i++) {
        $lvl = $slLevels[$i]
        $qtyPct = [decimal]100
        if ($lvl.PSObject.Properties['qty_pct'] -and $lvl.qty_pct) {
            try { $qtyPct = [decimal]$lvl.qty_pct } catch {}
        }
        $amt = [math]::Round(($TotalAmount * ($qtyPct / [decimal]100)), $AmountPrecision)
        $trigger = _MultiLadder-ResolvePrice -Level $lvl -Entry $Entry -AtrValue $AtrValue -StopDistance $stopDistance -IsLong $isLong -IsStop:$true
        $trigger = [math]::Round($trigger, $PricePrecision)

        $body = @{
            market           = $Market
            market_type      = "FUTURES"
            stop_loss_type   = "mark_price"
            stop_loss_price  = ([decimal]$trigger).ToString($inv)
            amount           = ([decimal]$amt).ToString($inv)
        }
        $resp = $null
        try {
            $resp = CoinEx-Post "/v2/futures/set-position-stop-loss" $body
        } catch {
            $resp = [PSCustomObject]@{ code = -1; message = "$_" }
        }
        $slOrders += [PSCustomObject]@{
            level_index   = ($i + 1)
            trigger_price = [double]$trigger
            qty           = [double]$amt
            response      = $resp
        }
    }

    return [PSCustomObject]@{
        ladder_id = if ($Ladder.PSObject.Properties['template_id']) { $Ladder.template_id } else { "" }
        tp_orders = $tpOrders
        sl_orders = $slOrders
    }
}

# Helper: resolve trigger price baseado em type do level (contrato Haiku lib_exit_ladder)
# Aceita ambos schemas:
#   A) Haiku: { trigger=50, type='price_pct', qty_pct }  -> trigger eh % bruta (50 = +50%)
#   B) Legacy: { price_pct=0.50 | atr_mult=1.5 | rr_multiple=2 | price=0.15 }  -> fracoes
#
# Para 'price_pct' em schema Haiku, trigger pode ser positivo (TP) ou negativo (SL inicial).
# A direcao do offset eh aplicada por IsLong/IsStop conforme a posicao.
function _MultiLadder-ResolvePrice {
    param(
        [Parameter(Mandatory)] $Level,
        [Parameter(Mandatory)] [decimal] $Entry,
        [decimal] $AtrValue     = 0,
        [decimal] $StopDistance = 0,
        [Parameter(Mandatory)] [bool] $IsLong,
        [Parameter(Mandatory)] [bool] $IsStop
    )

    # Direcao do offset: TP em LONG = +; TP em SHORT = -; SL inverte.
    $dirLong = if ($IsStop) { -1 } else { 1 }
    $dir     = if ($IsLong) { $dirLong } else { -1 * $dirLong }

    # type explicito (Haiku schema) ou inferido a partir das chaves (legacy)
    $type = $null
    if ($Level.PSObject.Properties['type'] -and $Level.type) {
        $type = [string]$Level.type
    }
    if (-not $type) {
        if ($Level.PSObject.Properties['price_pct']     -and $Level.price_pct)     { $type = "price_pct" }
        elseif ($Level.PSObject.Properties['atr_mult']    -and $Level.atr_mult)    { $type = "atr_mult" }
        elseif ($Level.PSObject.Properties['rr_multiple'] -and $Level.rr_multiple) { $type = "rr_multiple" }
        elseif ($Level.PSObject.Properties['price']       -and $Level.price)       { $type = "absolute" }
    }

    # Resolve valor do trigger: prefere Haiku schema (campo 'trigger'), fallback nas chaves legacy
    function _PickTriggerValue {
        param($lvl, $field)
        if ($lvl.PSObject.Properties['trigger']) {
            return [decimal]$lvl.trigger
        }
        if ($lvl.PSObject.Properties[$field]) {
            return [decimal]$lvl.$field
        }
        return [decimal]0
    }

    switch ($type) {
        "price_pct" {
            $val = _PickTriggerValue -lvl $Level -field "price_pct"
            # Haiku: trigger=50 means +50% => 0.50; legacy: price_pct=0.50 already fraction
            # Detecta heuristicamente: se |val| > 1 assume escala percentual bruta (% pts)
            $pct = if ([math]::Abs($val) -gt 1) { $val / [decimal]100 } else { $val }
            # Sign: se trigger ja vem negativo (SL Haiku) anula a direcao -> abs() e deixa dir decidir.
            $pct = [math]::Abs($pct)
            return ($Entry * ([decimal]1 + ($dir * $pct)))
        }
        "atr_mult" {
            $m = _PickTriggerValue -lvl $Level -field "atr_mult"
            $m = [math]::Abs($m)
            return ($Entry + ($dir * $m * $AtrValue))
        }
        "rr_multiple" {
            $rr = _PickTriggerValue -lvl $Level -field "rr_multiple"
            $rr = [math]::Abs($rr)
            return ($Entry + ($dir * $rr * $StopDistance))
        }
        "absolute" {
            if ($Level.PSObject.Properties['price'] -and $Level.price) {
                return ([decimal]$Level.price)
            }
            return ([decimal]$Level.trigger)
        }
        default {
            throw "_MultiLadder-ResolvePrice: tipo de level desconhecido (level=$($Level | ConvertTo-Json -Compress))"
        }
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-CancelOrder - Cancelar ordem SPOT ou FUTURES por order_id
# TDD 2026-05-23: Implementado com testes em lib_coinex_cancel_order.Tests.ps1
# Rate limit: 60 req/s SPOT, 40 req/s FUTURES
# Idempotente: retry seguro (cancelar ordem ja cancelada retorna erro mas nao duplica)
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-CancelOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $OrderId,
        [string] $MarketType = "FUTURES"  # "SPOT" | "FUTURES"
    )

    # Validacao de MarketType
    if ($MarketType -notin @("SPOT", "FUTURES")) {
        throw "MarketType deve ser 'SPOT' ou 'FUTURES', recebido: $MarketType"
    }

    $endpoint = if ($MarketType -eq "SPOT") { "/v2/spot/cancel-order" } else { "/v2/futures/cancel-order" }

    # 2026-06-25 fix: API v2 exige order_id NUMERICO (mesmo bug ja corrigido em
    # CoinEx-CancelStopOrder 2026-06-05). Enviar como string retorna code=3639
    # "Invalid Parameter" e a ordem NUNCA cancela. Bateu ao cancelar o TP do FAI.
    $orderIdNum = $OrderId
    if ($OrderId -match '^\d+$') { $orderIdNum = [int64]$OrderId }
    $body = @{
        market      = $Market
        market_type = $MarketType
        order_id    = $orderIdNum
    }

    try {
        $r = CoinEx-Post $endpoint $body
        
        if ($r.code -eq 0) {
            # Sucesso
            return [PSCustomObject]@{
                success      = $true
                order_id     = if ($r.data -and $r.data.order_id) { $r.data.order_id } else { $OrderId }
                status       = if ($r.data -and $r.data.status) { $r.data.status } else { "cancelled" }
                market       = $Market
                market_type  = $MarketType
            }
        } else {
            # Erro da API (ordem nao existe, ja executada, etc)
            return [PSCustomObject]@{
                success       = $false
                error_code    = $r.code
                error_message = $r.message
                order_id      = $OrderId
                market        = $Market
            }
        }
    } catch {
        # Erro de rede ou outro
        return [PSCustomObject]@{
            success       = $false
            error_code    = -1
            error_message = $_.Exception.Message
            order_id      = $OrderId
            market        = $Market
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-CancelOrderByClientId - Cancelar ordem FUTURES por client_id
# TDD 2026-05-23: FUTURES only (SPOT nao tem endpoint equivalente)
# Rate limit: 40 req/s
# Util para cancelar ordem criada com New-OrderClientId sem saber order_id
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-CancelOrderByClientId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $ClientId
    )

    $endpoint = "/v2/futures/cancel-order-by-client-id"
    
    $body = @{
        market      = $Market
        market_type = "FUTURES"
        client_id   = $ClientId
    }

    try {
        $r = CoinEx-Post $endpoint $body
        
        if ($r.code -eq 0) {
            return [PSCustomObject]@{
                success   = $true
                client_id = $ClientId
                order_id  = if ($r.data -and $r.data.order_id) { $r.data.order_id } else { $null }
                status    = if ($r.data -and $r.data.status) { $r.data.status } else { "cancelled" }
                market    = $Market
            }
        } else {
            return [PSCustomObject]@{
                success       = $false
                error_code    = $r.code
                error_message = $r.message
                client_id     = $ClientId
                market        = $Market
            }
        }
    } catch {
        return [PSCustomObject]@{
            success       = $false
            error_code    = -1
            error_message = $_.Exception.Message
            client_id     = $ClientId
            market        = $Market
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-CancelStopOrder - Cancelar stop order (ordem condicional)
# TDD 2026-05-23: SPOT e FUTURES
# Rate limit: 60 req/s SPOT, 40 req/s FUTURES
# Stop orders sao ordens condicionais (trigger price) que ainda nao executaram
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-CancelStopOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $StopId,
        [string] $MarketType = "FUTURES"
    )

    if ($MarketType -notin @("SPOT", "FUTURES")) {
        throw "MarketType deve ser 'SPOT' ou 'FUTURES', recebido: $MarketType"
    }

    $endpoint = if ($MarketType -eq "SPOT") { "/v2/spot/cancel-stop-order" } else { "/v2/futures/cancel-stop-order" }
    
    # 2026-06-05 fix: API v2 exige stop_id NUMERICO. Enviar como string retorna
    # "Invalid Parameter" (code != 0) e o stop NUNCA cancela -> orphan stops.
    $stopIdNum = $StopId
    if ($StopId -match '^\d+$') { $stopIdNum = [int64]$StopId }
    $body = @{
        market      = $Market
        market_type = $MarketType
        stop_id     = $stopIdNum
    }

    try {
        $r = CoinEx-Post $endpoint $body
        
        if ($r.code -eq 0) {
            return [PSCustomObject]@{
                success     = $true
                stop_id     = $StopId
                status      = if ($r.data -and $r.data.status) { $r.data.status } else { "cancelled" }
                market      = $Market
                market_type = $MarketType
            }
        } else {
            return [PSCustomObject]@{
                success       = $false
                error_code    = $r.code
                error_message = $r.message
                stop_id       = $StopId
                market        = $Market
            }
        }
    } catch {
        return [PSCustomObject]@{
            success       = $false
            error_code    = -1
            error_message = $_.Exception.Message
            stop_id       = $StopId
            market        = $Market
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-CancelAllOrders - Cancelar TODAS as ordens de um mercado
# TDD 2026-05-23: SPOT e FUTURES
# Rate limit: 40 req/s SPOT, 20 req/s FUTURES
# CUIDADO: Cancela TODAS as ordens pendentes do mercado (nao apenas uma)
# Util para emergencias ou cleanup
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-CancelAllOrders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $MarketType = "FUTURES"
    )

    if ($MarketType -notin @("SPOT", "FUTURES")) {
        throw "MarketType deve ser 'SPOT' ou 'FUTURES', recebido: $MarketType"
    }

    $endpoint = if ($MarketType -eq "SPOT") { "/v2/spot/cancel-all-order" } else { "/v2/futures/cancel-all-order" }
    
    $body = @{
        market      = $Market
        market_type = $MarketType
    }

    try {
        $r = CoinEx-Post $endpoint $body
        
        if ($r.code -eq 0) {
            $cancelledCount = 0
            $orders = @()
            
            if ($r.data) {
                if ($r.data.PSObject.Properties['cancelled_count']) {
                    $cancelledCount = [int]$r.data.cancelled_count
                }
                if ($r.data.PSObject.Properties['orders']) {
                    $orders = @($r.data.orders)
                }
            }
            
            return [PSCustomObject]@{
                success         = $true
                cancelled_count = $cancelledCount
                orders          = $orders
                market          = $Market
                market_type     = $MarketType
            }
        } else {
            return [PSCustomObject]@{
                success       = $false
                error_code    = $r.code
                error_message = $r.message
                market        = $Market
            }
        }
    } catch {
        return [PSCustomObject]@{
            success       = $false
            error_code    = -1
            error_message = $_.Exception.Message
            market        = $Market
        }
    }
}

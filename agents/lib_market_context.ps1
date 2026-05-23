# lib_market_context.ps1 -- Macro context para painel Telegram approval.
#
# Versao A (2026-05-18): info contextual, nao multiplier automatico.
# User decide ajustar size manualmente vendo contexto.
#
# Contem:
# 1. Halving phase (determ., n=3 ciclos historicos)
# 2. ETF flow (preparado, fetch opcional via Farside Investors)
#
# NAO implementa: multipliers automaticos de sizing (precisa Versao C
# meta-labeling com 6m+ paper data antes).

# Halving dates historicos
$HALVING_2012 = [DateTime]::Parse("2012-11-28")
$HALVING_2016 = [DateTime]::Parse("2016-07-09")
$HALVING_2020 = [DateTime]::Parse("2020-05-11")
$HALVING_2024 = [DateTime]::Parse("2024-04-19")

# Peak month observado pos-halving (n=3 ciclos historicos)
$HALVING_PEAK_MONTHS = @(21, 17, 18)   # ciclos 1, 2, 3
$HALVING_PEAK_AVG    = 18.7            # media

function Get-HalvingPhase {
    [CmdletBinding()]
    param([DateTime]$AsOf = (Get-Date))

    $months = ($AsOf - $HALVING_2024).TotalDays / 30.44   # mes medio
    $months = [math]::Round($months, 1)

    # Fase nomeada
    $phase = if ($months -lt 0)   { "PRE_HALVING" }
             elseif ($months -le 6)  { "ACUMULACAO" }
             elseif ($months -le 18) { "MID_BULL" }
             elseif ($months -le 22) { "DISTRIBUTION_RISK" }
             elseif ($months -le 36) { "BEAR_TERRITORY" }
             else                    { "POST_CYCLE" }

    $verdict = switch ($phase) {
        "PRE_HALVING"        { "Acumulacao pre-halving (n/a)" }
        "ACUMULACAO"         { "Acumulacao pos-halving -- bull confirmation early stage" }
        "MID_BULL"           { "Mid-bull -- historicamente full size OK (3/3 ciclos)" }
        "DISTRIBUTION_RISK"  { "ALERTA: zona de pico historico (m 17-21) -- reduzir size" }
        "BEAR_TERRITORY"     { "Bear territory historico -- operar minimo ou parar" }
        "POST_CYCLE"         { "Post-cycle -- fora do framework historico" }
    }

    return [PSCustomObject]@{
        as_of               = $AsOf.ToString("yyyy-MM-dd")
        months_since_halving = $months
        phase               = $phase
        peak_month_historical_avg = $HALVING_PEAK_AVG
        peak_months_n3      = $HALVING_PEAK_MONTHS
        verdict             = $verdict
    }
}


function Get-MiningCostContext {
    <#
    .SYNOPSIS
        Mining cost capitulation signal (Versao A info-only).
        Compara preco BTC atual vs cost medio global pos-halving 2024.

        Historicamente (n=3 ciclos):
        - Ratio 0.91-0.95x = bottom forming (Dec 2018, Mar 2020, Nov 2022)
        - Ratio 1.0-1.1x = capitulation imminent (early warning)
        - Ratio > 1.3x = bull confirmation

        Cost estimado fixo: consensus 2025 pos-halving = ~$55k/BTC global.
        Atualizar trimestralmente conforme hashrate/energia mudam.
    #>
    [CmdletBinding()]
    param(
        [double]$BtcPriceUsd = 0,
        [double]$MiningCostGlobal = 55000.0,   # consensus pos-halving 2024
        [datetime]$AsOf = (Get-Date)
    )
    # Se nao passou preco, tenta CoinEx ticker
    if ($BtcPriceUsd -le 0) {
        try {
            if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
                $t = CoinEx-GetTicker "BTCUSDT"
                if ($t -and $t.last) { $BtcPriceUsd = [double]$t.last }
            }
        } catch {}
    }
    if ($BtcPriceUsd -le 0) {
        return [PSCustomObject]@{
            available = $false
            reason    = "BTC price unavailable"
        }
    }

    $ratio = $BtcPriceUsd / $MiningCostGlobal
    $status = if ($ratio -lt 0.91)    { "CAPITULATION_BOTTOM_LIKELY" }
              elseif ($ratio -lt 1.00) { "CAPITULATION_FORMING" }
              elseif ($ratio -lt 1.10) { "CAPITULATION_RISK_EARLY_WARNING" }
              elseif ($ratio -lt 1.30) { "MARGEM_FINA" }
              elseif ($ratio -lt 2.00) { "LUCRATIVO" }
              else                     { "MUITO_LUCRATIVO" }

    $verdict = switch ($status) {
        "CAPITULATION_BOTTOM_LIKELY"      { "Bottom historico em formacao -- consider buy aggressively (3/3 ciclos)" }
        "CAPITULATION_FORMING"            { "Miners em capitulacao iminente -- bottom forming" }
        "CAPITULATION_RISK_EARLY_WARNING" { "Early warning -- margem mineradora estreita" }
        "MARGEM_FINA"                     { "Margem mineradora fina -- atencao" }
        "LUCRATIVO"                       { "Mining lucrativo -- sem sinal capitulacao" }
        "MUITO_LUCRATIVO"                 { "Mining muito lucrativo -- topo possivel se halving phase confirmar" }
    }

    return [PSCustomObject]@{
        available           = $true
        as_of               = $AsOf.ToString("yyyy-MM-dd")
        btc_price_usd       = [math]::Round($BtcPriceUsd, 0)
        mining_cost_global  = $MiningCostGlobal
        ratio               = [math]::Round($ratio, 2)
        status              = $status
        verdict             = $verdict
        historical_bottoms  = @(
            @{ event = "Dec 2018";  ratio = 0.91 }
            @{ event = "Mar 2020";  ratio = 0.95 }
            @{ event = "Nov 2022";  ratio = 0.94 }
        )
    }
}


function Get-AllocationContext {
    <#
    .SYNOPSIS
        Contexto CoinEx balance live (capital fora NAO eh rastreado por privacy).

        2026-05-18 refactor: sistema agora opera apenas sobre o que ESTA na CoinEx.
        Sizing absoluto ($25-$100/trade) eh a unica regra. User gerencia capital
        fora manualmente (responsabilidade consciente FTX-lesson).

        Output simplificado:
        - coinex_balance_usd: USDT cash + assets convertidos
        - status: estimativa de "espaco" pra trades baseado em CoinEx live
    #>
    [CmdletBinding()]
    param([double]$CoinexBalanceUsd = 0)

    if ($CoinexBalanceUsd -le 0 -and (Get-Command CoinEx-GetTotalCapitalUSDT -ErrorAction SilentlyContinue)) {
        try { $CoinexBalanceUsd = [double](CoinEx-GetTotalCapitalUSDT) } catch {}
    }
    if ($CoinexBalanceUsd -le 0) {
        return [PSCustomObject]@{
            available = $false
            reason    = "CoinEx balance indisponivel"
        }
    }

    # Status baseado em CoinEx balance absoluto (sem ratio total).
    # Range relativo a sizing cap por trade.
    $maxSize = if ($global:LIVE_MAX_SIZE_USD) { [double]$global:LIVE_MAX_SIZE_USD } else { 100.0 }
    $sizingHeadroom = [math]::Round($CoinexBalanceUsd / $maxSize, 1)   # quantos trades max-size cabem

    $status = if ($CoinexBalanceUsd -lt 100)     { "MINIMAL" }
              elseif ($CoinexBalanceUsd -lt 500) { "LOW" }
              elseif ($CoinexBalanceUsd -lt 5000){ "OPERATIONAL" }
              else                               { "HIGH_CAPITAL" }
    $verdict = switch ($status) {
        "MINIMAL"      { "CoinEx balance baixo (< `$100) -- recarregar pra operar Mode 2" }
        "LOW"          { "CoinEx balance baixo (< `$500) -- cuidado com sizing" }
        "OPERATIONAL"  { "Balance OK para Mode 2 micro" }
        "HIGH_CAPITAL" { "Balance alto -- considerar reduzir exposicao exchange (FTX-lesson)" }
    }

    return [PSCustomObject]@{
        available           = $true
        coinex_balance_usd  = [math]::Round($CoinexBalanceUsd, 2)
        sizing_headroom     = $sizingHeadroom
        status              = $status
        verdict             = $verdict
    }
}


function Get-IntradayWindowContext {
    <#
    .SYNOPSIS
        Classifica hora UTC atual em janela de mercado (Asia/EU/US/Overlap).
        Versao A info-only: NAO altera logica de trading, so contextualiza no
        Telegram pra usuario coletar dados pra eventual Versao C (backtest formal).

        Janelas UTC (sessoes financeiras globais):
        - ASIA_OPEN:    00:00 - 07:00 UTC (Tokyo, Singapura, HK)
        - ASIA_EU_OVERLAP: 07:00 - 09:00 UTC
        - EU_OPEN:      09:00 - 13:00 UTC (London, Frankfurt)
        - EU_US_OVERLAP: 13:00 - 16:00 UTC (volume max global, NY+London)
        - US_OPEN:      16:00 - 21:00 UTC (NY afternoon)
        - LATE_NIGHT:   21:00 - 24:00 UTC (volume minimo)

        Volume tipico BTC (Coinbase/Binance flow data):
        - EU_US_OVERLAP: MAXIMO (~30% volume diario)
        - US_OPEN:       Alto (~25%)
        - EU_OPEN:       Medio-alto (~20%)
        - ASIA_OPEN:     Medio (~15%)
        - LATE_NIGHT:    Minimo (~5-10%)
    #>
    [CmdletBinding()]
    param([DateTime]$AsOf = (Get-Date).ToUniversalTime())

    $hour = $AsOf.Hour

    $window = if ($hour -lt 7)      { "ASIA_OPEN" }
              elseif ($hour -lt 9)  { "ASIA_EU_OVERLAP" }
              elseif ($hour -lt 13) { "EU_OPEN" }
              elseif ($hour -lt 16) { "EU_US_OVERLAP" }
              elseif ($hour -lt 21) { "US_OPEN" }
              else                  { "LATE_NIGHT" }

    $volumeTier = switch ($window) {
        "EU_US_OVERLAP"   { "MAX (~30% diario)" }
        "US_OPEN"         { "ALTO (~25%)" }
        "EU_OPEN"         { "MEDIO-ALTO (~20%)" }
        "ASIA_EU_OVERLAP" { "MEDIO (~17%)" }
        "ASIA_OPEN"       { "MEDIO (~15%)" }
        "LATE_NIGHT"      { "MINIMO (~5-10%)" }
    }

    $note = switch ($window) {
        "EU_US_OVERLAP"   { "Janela MM/HFT dominante -- spreads minimos mas stop hunts maiores" }
        "US_OPEN"         { "Volume alto pos-NY open -- liquidez OK pra entry" }
        "EU_OPEN"         { "Volume crescente -- mid-tier liquidez" }
        "ASIA_EU_OVERLAP" { "Transicao Asia->EU -- volume crescendo" }
        "ASIA_OPEN"       { "Volume Asia (retail dominante) -- slippage maior" }
        "LATE_NIGHT"      { "Volume minimo global -- evitar entries grandes" }
    }

    return [PSCustomObject]@{
        as_of        = $AsOf.ToString("HH:mm UTC")
        hour_utc     = $hour
        window       = $window
        volume_tier  = $volumeTier
        note         = $note
        # Versao C placeholder: edge_factor_versao_c = 1.0 default
        edge_factor  = 1.0
    }
}


function Get-WhaleAccumulationContext {
    <#
    .SYNOPSIS
        Whale accumulation via BitInfoCharts (free) + Bitcoin distribution proxy.
        Tenta API gratuita; fallback consulta manual.

        Free sources testados:
        - Glassnode community: charts so HTML (sem API)
        - BitInfoCharts: HTML, distribution top 100 addresses
        - blockchain.info/charts: free com JSON endpoints

        Versao A: usa blockchain.info como proxy de concentracao (n_unique_addresses).
        Cache 12h em journal/whale_cache.json.
    #>
    [CmdletBinding()]
    param([int]$DaysLookback = 30, [int]$CacheHours = 12)

    $cacheFile = "$PSScriptRoot\..\journal\whale_cache.json"
    if (Test-Path $cacheFile) {
        try {
            $cached = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cached.fetched_at) {
                $cacheDt = [DateTime]::Parse($cached.fetched_at)
                $ageH = ((Get-Date) - $cacheDt).TotalHours
                if ($ageH -lt $CacheHours) { return $cached }
            }
        } catch {}
    }

    # Tenta blockchain.info JSON (free, sem auth) -- n-unique-addresses ${DaysLookback}d
    try {
        $url = "https://api.blockchain.info/charts/n-unique-addresses?timespan=${DaysLookback}days&format=json&cors=true"
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 15 -ErrorAction Stop
        if ($r -and $r.values -and @($r.values).Count -ge 7) {
            $vals = @($r.values | ForEach-Object { [double]$_.y })
            $first = $vals[0]
            $last  = $vals[-1]
            $deltaPct = if ($first -gt 0) { [math]::Round((($last - $first)/$first)*100, 2) } else { 0 }
            $trend = if ($deltaPct -gt 5)     { "ADOPTION_UP" }
                     elseif ($deltaPct -gt -5){ "STABLE" }
                     else                     { "ADOPTION_DOWN" }
            $summary = "${deltaPct}% ${DaysLookback}d active addresses ($trend)"

            $result = [PSCustomObject]@{
                available    = $true
                source       = "blockchain.info /charts/n-unique-addresses"
                fetched_at   = (Get-Date).ToString("o")
                window_days  = $DaysLookback
                metric       = "unique_addresses_active"
                first_value  = [math]::Round($first, 0)
                last_value   = [math]::Round($last, 0)
                delta_pct    = $deltaPct
                trend        = $trend
                summary      = $summary
                caveat       = "Proxy de adoption/atividade; whale-specific exige Glassnode/CryptoQuant paid"
                url_manual   = "https://studio.glassnode.com/metrics?a=BTC&m=addresses.SupplyDistributionRelative"
            }
            try {
                $dir = Split-Path $cacheFile
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $result | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding UTF8
            } catch {}
            return $result
        }
    } catch {
        # Fall through pra unavailable
    }

    return [PSCustomObject]@{
        available     = $false
        reason        = "blockchain.info indisponivel ou sem dados"
        url_manual    = "https://studio.glassnode.com/metrics?a=BTC&m=addresses.SupplyDistributionRelative"
        url_alt       = "https://www.bitinfocharts.com/top-100-richest-bitcoin-addresses.html"
        caveat        = "Pos-ETF (2024+): whale signal misturado com cold storage IBIT/FBTC"
    }
}


function Get-EtfFlowContext {
    <#
    .SYNOPSIS
        Scrape ETF flow via Farside Investors (free HTML, sem auth).
        Cache 6h em journal/etf_flow_cache.json.
    #>
    [CmdletBinding()]
    param([int]$DaysLookback = 7, [int]$CacheHours = 6)

    $cacheFile = "$PSScriptRoot\..\journal\etf_flow_cache.json"
    if (Test-Path $cacheFile) {
        try {
            $cached = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cached.fetched_at) {
                $cacheDt = [DateTime]::Parse($cached.fetched_at)
                $ageH = ((Get-Date) - $cacheDt).TotalHours
                if ($ageH -lt $CacheHours) { return $cached }
            }
        } catch {}
    }

    try {
        $url = "https://farside.co.uk/btc/"
        # Farside bloqueia user-agent default (403). Usa UA browser-like.
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            "Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            "Accept-Language" = "en-US,en;q=0.5"
        }
        $r = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UseBasicParsing -Headers $headers -ErrorAction Stop
        if ($r.StatusCode -ne 200) {
            return [PSCustomObject]@{ available = $false; reason = "HTTP $($r.StatusCode)"; url_manual = $url }
        }
        $html = $r.Content
        # Tenta parser: row com DD MMM YYYY + valor numerico no final (Total column)
        $rxMatches = [regex]::Matches($html, "(\d{1,2}\s+\w{3}\s+\d{4})[^\d-]+?<td[^>]*>\(?(-?[\d,]+\.\d{1,2})\)?</td>\s*</tr>", "Singleline")
        $rows = @()
        foreach ($m in $rxMatches) {
            if ($m.Groups.Count -lt 3) { continue }
            try {
                $val = [double]($m.Groups[2].Value -replace ',','')
                $rows += @{ date = $m.Groups[1].Value; total_musd = $val }
            } catch {}
        }
        if ($rows.Count -lt 3) {
            return [PSCustomObject]@{ available = $false; reason = "parsing falhou ($($rows.Count) rows)"; url_manual = $url }
        }
        $recent = @($rows | Select-Object -First $DaysLookback)
        $sum = [math]::Round((($recent | Measure-Object -Property total_musd -Sum).Sum), 1)
        $direction = if ($sum -gt 500)      { "INFLOW_FORTE" }
                     elseif ($sum -gt 0)    { "INFLOW_LEVE" }
                     elseif ($sum -gt -500) { "OUTFLOW_LEVE" }
                     else                   { "OUTFLOW_FORTE" }
        $summary = "${sum}M USD ${DaysLookback}d ($direction)"

        $result = [PSCustomObject]@{
            available    = $true
            fetched_at   = (Get-Date).ToString("o")
            window_days  = $DaysLookback
            total_musd   = $sum
            direction    = $direction
            summary      = $summary
            url_manual   = $url
        }
        try {
            $dir = Split-Path $cacheFile
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $result | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding UTF8
        } catch {}
        return $result
    } catch {
        return [PSCustomObject]@{
            available = $false
            reason = "fetch failed: $($_.Exception.Message)"
            url_manual = "https://farside.co.uk/btc/"
        }
    }
}


function Format-MarketContextPanel {
    [CmdletBinding()]
    param(
        [PSObject]$HalvingPhase = $null,
        [PSObject]$EtfContext   = $null,
        [PSObject]$MiningContext = $null,
        [PSObject]$WhaleContext = $null,
        [PSObject]$IntradayContext = $null,
        [PSObject]$AllocationContext = $null
    )
    if (-not $HalvingPhase)     { $HalvingPhase     = Get-HalvingPhase }
    if (-not $EtfContext)       { $EtfContext       = Get-EtfFlowContext }
    if (-not $MiningContext)    { $MiningContext    = Get-MiningCostContext }
    if (-not $WhaleContext)     { $WhaleContext     = Get-WhaleAccumulationContext }
    if (-not $IntradayContext)  { $IntradayContext  = Get-IntradayWindowContext }
    if (-not $AllocationContext){ $AllocationContext= Get-AllocationContext }

    $e = $global:TG_EMOJI

    # Halving phase
    $phaseEmoji = switch ($HalvingPhase.phase) {
        "PRE_HALVING"        { $e.moon }
        "ACUMULACAO"         { $e.bulb }
        "MID_BULL"           { $e.sun }
        "DISTRIBUTION_RISK"  { $e.alert }
        "BEAR_TERRITORY"     { $e.snow }
        "POST_CYCLE"         { $e.moon }
        default              { "" }
    }
    $halvingLine = "$phaseEmoji <b>Halving:</b> mes $($HalvingPhase.months_since_halving)/36 -- $($HalvingPhase.phase)"
    $halvingNote = "<i>  $($HalvingPhase.verdict)</i>"

    # Mining cost
    $miningLine = if ($MiningContext.available) {
        $miningEmoji = switch ($MiningContext.status) {
            "CAPITULATION_BOTTOM_LIKELY"      { $e.fire }
            "CAPITULATION_FORMING"            { $e.alert }
            "CAPITULATION_RISK_EARLY_WARNING" { $e.alert }
            "MARGEM_FINA"                     { $e.bulb }
            "LUCRATIVO"                       { $e.check }
            "MUITO_LUCRATIVO"                 { $e.sun }
            default                           { "" }
        }
        $note = "<i>  $($MiningContext.verdict)</i>"
        "$miningEmoji <b>Mining:</b> `$$($MiningContext.btc_price_usd) / `$$($MiningContext.mining_cost_global) = $($MiningContext.ratio)x cost`n$note"
    } else {
        "$($e.gear) <b>Mining:</b> n/d ($($MiningContext.reason))"
    }

    # ETF (free via Farside scrape)
    $etfLine = if ($EtfContext.available) {
        $etfEmoji = switch ($EtfContext.direction) {
            "INFLOW_FORTE"  { $e.fire }
            "INFLOW_LEVE"   { $e.check }
            "OUTFLOW_LEVE"  { $e.bulb }
            "OUTFLOW_FORTE" { $e.alert }
            default         { $e.chart }
        }
        "$etfEmoji <b>ETF $($EtfContext.window_days)d:</b> $($EtfContext.summary)"
    } else {
        "$($e.chart) <b>ETF flow:</b> consulta manual ($($EtfContext.url_manual))"
    }

    # Whale (free via blockchain.info active addresses proxy)
    $whaleLine = if ($WhaleContext.available) {
        $whaleEmoji = switch ($WhaleContext.trend) {
            "ADOPTION_UP"    { $e.chartUp }
            "STABLE"         { $e.bulb }
            "ADOPTION_DOWN"  { $e.chartDn }
            default          { $e.search }
        }
        "$whaleEmoji <b>OnChain $($WhaleContext.window_days)d:</b> $($WhaleContext.summary)"
    } else {
        "$($e.search) <b>Whales:</b> consulta manual (Glassnode/CryptoQuant)"
    }

    # Intraday window
    $windowEmoji = switch ($IntradayContext.window) {
        "EU_US_OVERLAP"   { $e.fire }
        "US_OPEN"         { $e.sun }
        "EU_OPEN"         { $e.bulb }
        "ASIA_EU_OVERLAP" { $e.chartUp }
        "ASIA_OPEN"       { $e.moon }
        "LATE_NIGHT"      { $e.snow }
        default           { "" }
    }
    $intradayLine = "$windowEmoji <b>Janela:</b> $($IntradayContext.window) ($($IntradayContext.as_of)) -- vol $($IntradayContext.volume_tier)"
    $intradayNote = "<i>  $($IntradayContext.note)</i>"

    # CoinEx balance (capital fora NAO eh rastreado por privacy)
    $allocLine = if ($AllocationContext.available) {
        $allocEmoji = switch ($AllocationContext.status) {
            "MINIMAL"      { $e.alert }
            "LOW"          { $e.bulb }
            "OPERATIONAL"  { $e.check }
            "HIGH_CAPITAL" { $e.alert }
            default        { "" }
        }
        $allocBody = "$allocEmoji <b>CoinEx:</b> `$$($AllocationContext.coinex_balance_usd) (sizing headroom: $($AllocationContext.sizing_headroom)x) -- $($AllocationContext.status)"
        $allocNote = "<i>  $($AllocationContext.verdict)</i>"
        "$allocBody`n$allocNote"
    } else {
        ""
    }

    $msg = "$($e.bulb) <b>CONTEXTO MACRO</b> (info -- voce decide ajustar)`n$halvingLine`n$halvingNote`n$miningLine`n$etfLine`n$whaleLine`n$intradayLine`n$intradayNote"
    if ($allocLine) { $msg += "`n$allocLine" }
    return $msg
}

# lib_market_movers.ps1 -- Universo dinamico: top gainers/losers (vol spike real)
# 2026-06-09: prioriza moedas que estao se MOVENDO agora, nao lentas micro-caps.

# Get-PrioritizedMarkets (simples): movers (gainers+losers) primeiro, quiet depois
function Get-PrioritizedMarkets {
    param(
        [object[]]$AllMarkets,  # tickers com change_24h
        [double]$GainerThreshold = 10,
        [double]$LoserThreshold = -10
    )

    $gainers = @()
    $losers = @()
    $quiet = @()

    foreach ($m in $AllMarkets) {
        $c = if ($m.PSObject.Properties['change_24h'] -and $null -ne $m.change_24h) { [double]$m.change_24h } else { 0 }
        if ($c -ge $GainerThreshold) { $gainers += $m }
        elseif ($c -le $LoserThreshold) { $losers += $m }
        else { $quiet += $m }
    }

    return @($gainers + $losers + $quiet)
}

# 2026-08-01: radar duplo 24h + 30d (owner pediu apos notar que moedas com
# spike forte de 24h -- GIGGLE/RATS/IDOL na CoinEx -- nunca entravam no
# universo real de scan, que hoje e uma lista FIXA curada manualmente em
# config/short_universe.json + config/long_universe.json, sem ranking
# dinamico nenhum conectado). UNIAO (nao intersecao) dos movers de 24h e
# 30d -- pega tanto spike de curto prazo quanto tendencia de 30d sem spike
# forte hoje, sem duplicar ticker que e mover nos dois periodos.
function Get-PrioritizedMarketsDualRadar {
    param(
        [object[]]$AllMarkets,  # tickers com change_24h E change_30d
        [double]$GainerThreshold24h = 10,
        [double]$LoserThreshold24h = -10,
        [double]$GainerThreshold30d = 20,
        [double]$LoserThreshold30d = -20
    )

    $result = @()
    foreach ($m in $AllMarkets) {
        $c24 = if ($m.PSObject.Properties['change_24h'] -and $null -ne $m.change_24h) { [double]$m.change_24h } else { 0 }
        $c30 = if ($m.PSObject.Properties['change_30d'] -and $null -ne $m.change_30d) { [double]$m.change_30d } else { 0 }

        $isMover24h = ($c24 -ge $GainerThreshold24h) -or ($c24 -le $LoserThreshold24h)
        $isMover30d = ($c30 -ge $GainerThreshold30d) -or ($c30 -le $LoserThreshold30d)

        if ($isMover24h -or $isMover30d) { $result += $m }
    }

    return @($result)
}

# 2026-08-01: CoinEx nao expoe "variacao 30 dias" nativa no ticker (so 24h)
# -- calculo puro a partir de candles DIARIOS ja buscados (separado do
# fetch real, que faz I/O e chama CoinEx-GetCandles -period "1d" -limit 31).
# Ordena por ts antes de calcular (defensivo -- API pode nao garantir ordem).
function Get-Market30dChangeFromCandles {
    param([object[]]$Candles)

    $sorted = @($Candles | Sort-Object ts)
    if ($sorted.Count -lt 2) { return 0 }

    $oldest = $sorted[0]
    $newest = $sorted[-1]
    $oldClose = [double]$oldest.close
    if ($oldClose -eq 0) { return 0 }

    return (([double]$newest.close - $oldClose) / $oldClose) * 100
}

# 2026-08-01: transforma tickers CRUS da CoinEx (schema real: .market, .open,
# .close, .value) em movers dinamicos de 24h, excluindo simbolos ja presentes
# na curadoria manual (evita duplicata) e nao-USDT. Logica pura, testavel sem
# rede -- o fetch real (CoinEx-GetAllFuturesTickers) fica no script caller.
function Get-DynamicMarketMoversFromRawTickers {
    param(
        [object[]] $RawTickers,
        [string[]] $ExcludeSymbols = @(),
        [double] $GainerThreshold24h = 10,
        [double] $LoserThreshold24h = -10,
        # 2026-08-05: teto opcional de resultados, ordenado por forca de
        # movimento (|change_24h| desc) antes de truncar -- owner pediu ao
        # estender o radar dinamico pra SPOT (universo real >1000 tickers,
        # bem maior que FUTURES ~228) pra nao deixar o ciclo de scan lento
        # demais. Default 0 = sem teto, preserva 100% o comportamento atual
        # dos callers existentes (radar FUTURES, lib_short_universe.ps1).
        [int] $MaxResults = 0
    )

    $excludeSet = @{}
    foreach ($s in $ExcludeSymbols) { $excludeSet[$s] = $true }

    $normalized = @($RawTickers | ForEach-Object {
        $market = [string]$_.market
        $open  = if ($_.PSObject.Properties['open']  -and $_.open)  { [double]$_.open }  else { 0 }
        $close = if ($_.PSObject.Properties['close'] -and $_.close) { [double]$_.close } else { 0 }
        $change24h = if ($open -gt 0) { (($close - $open) / $open) * 100 } else { 0 }
        [PSCustomObject]@{
            symbol     = $market
            change_24h = $change24h
            change24h  = $change24h
            volume24h  = if ($_.PSObject.Properties['value'] -and $_.value) { [double]$_.value } else { 0 }
        }
    } | Where-Object { $_.symbol -like "*USDT" -and -not $excludeSet.ContainsKey($_.symbol) })

    # so 24h nesta fase (30d fica pro filtro subsequente, so p/ quem ja passou
    # aqui -- evita 1 candle-fetch por moeda do mercado inteiro).
    $movers = @(Get-PrioritizedMarketsDualRadar -AllMarkets $normalized `
        -GainerThreshold24h $GainerThreshold24h -LoserThreshold24h $LoserThreshold24h `
        -GainerThreshold30d ([double]::MaxValue) -LoserThreshold30d ([double]::MinValue))

    if ($MaxResults -gt 0 -and $movers.Count -gt $MaxResults) {
        $movers = @($movers | Sort-Object { [math]::Abs($_.change_24h) } -Descending | Select-Object -First $MaxResults)
    }

    return @($movers)
}

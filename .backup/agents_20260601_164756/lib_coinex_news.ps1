# lib_coinex_news.ps1 -- Item 12: tracker noticias CoinEx pra alimentar ladder
#
# Filtra brutal:
#   - listing  -> auto-cria DESCOBERTA no promotion_pipeline
#   - delisting -> auto-propoe demote
#   - fee/maintenance -> apenas log + Telegram opcional
#   - marketing/spotlight -> SKIP (80% e ruido)
#
# Funcoes:
#   Test-NewsKeyword          -- categoriza por tipo
#   Get-MarketsFromText       -- extrai tickers TICKERUSDT
#   Invoke-NewsArticleProcess -- pipeline action por article
#   Invoke-NewsScrapeFetch    -- (placeholder) fetch latest articles
#
# PS 5.1. UTF-8 BOM.

# Keyword regex por tipo (PT + EN)
$script:NEWS_KEYWORDS = @{
    listing    = @(
        'list(agem|ado|ar|ing)',
        'new pair', 'trading begins', 'trading opens',
        'sera listad', 'pre-listing', 'lancamento'
    )
    delisting  = @(
        'delist(agem|ado|ing)?', 'remover(emos)?', 'removed',
        'trading suspended', 'suspens(ao|ao do trading)',
        'deprecat(ed|ada)'
    )
    fee        = @(
        '\b(fee|taxa|comiss[aã]o)\b',
        'fee schedule', 'fee update', 'taxa atualiz'
    )
    maintenance = @(
        'manuten[cç][aã]o', 'maintenance', 'upgrade',
        'system maintenance', 'sistema (em|fora)'
    )
}


function Test-NewsKeyword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [ValidateSet("listing","delisting","fee","maintenance")] [string] $Type
    )
    if (-not $script:NEWS_KEYWORDS.ContainsKey($Type)) { return $false }
    $patterns = $script:NEWS_KEYWORDS[$Type]
    $lower = $Text.ToLower()
    foreach ($p in $patterns) {
        if ($lower -match $p) { return $true }
    }
    return $false
}


function Get-MarketsFromText {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Text)

    # Pattern: TICKER seguido de /USDT ou USDT
    # TICKER = 2-10 letras maiusculas
    $markets = @{}
    $re = [regex]::new('\b([A-Z]{2,10})(?:/|\\s*)USDT\b')
    $matches = $re.Matches($Text.ToUpper())
    foreach ($m in $matches) {
        $ticker = $m.Groups[1].Value
        if ($ticker -eq "USDT") { continue }   # USDT-USDT nao faz sentido
        $markets[($ticker + "USDT")] = $true
    }
    return @($markets.Keys)
}


function Invoke-NewsArticleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Article,
        [Parameter(Mandatory)] [string] $PipelinePath
    )
    $title = if ($Article.title) { $Article.title } else { "" }
    $content = if ($Article.content) { $Article.content } else { "" }
    $combined = "$title `n $content"

    $isListing   = Test-NewsKeyword -Text $combined -Type "listing"
    $isDelisting = Test-NewsKeyword -Text $combined -Type "delisting"
    $isFee       = Test-NewsKeyword -Text $combined -Type "fee"
    $isMaintenance = Test-NewsKeyword -Text $combined -Type "maintenance"

    if (-not ($isListing -or $isDelisting -or $isFee -or $isMaintenance)) {
        return [PSCustomObject]@{
            action = "skipped"
            reason = "no_keyword_match"
            markets = @()
        }
    }

    $markets = Get-MarketsFromText -Text $combined

    if ($isListing -and $markets.Count -gt 0) {
        # Auto-cria DESCOBERTA para cada market mencionado
        foreach ($mkt in $markets) {
            # Verifica se ja existe no pipeline (evita dupe)
            $existing = Get-PromotionState -Path $PipelinePath -Market $mkt
            if ($existing) { continue }
            Add-PromotionEvent -Path $PipelinePath -Market $mkt -Event "discovered" `
                -Source "news_feed" -Notes ("listing news: " + $title) | Out-Null
        }
        return [PSCustomObject]@{
            action = "added_discovery"
            markets = $markets
            article_url = $Article.url
        }
    }

    if ($isDelisting -and $markets.Count -gt 0) {
        return [PSCustomObject]@{
            action = "propose_demote"
            markets = $markets
            reason = "delisting_news"
            article_url = $Article.url
        }
    }

    if ($isFee) {
        return [PSCustomObject]@{
            action = "log_fee_change"
            reason = "fee_keyword"
            article_url = $Article.url
        }
    }

    if ($isMaintenance) {
        return [PSCustomObject]@{
            action = "log_maintenance"
            reason = "maintenance_keyword"
            article_url = $Article.url
        }
    }

    return [PSCustomObject]@{ action = "skipped"; reason = "fallthrough"; markets = @() }
}

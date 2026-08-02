# lib_short_universe.ps1 -- resolucao PURA do universo SHORT (observatorio).
#
# Motivo (2026-06-22): short_scanner lia SHORT tiers do per_asset_whitelist_*.json em
# journal/ -- que e gitignored e NAO existe no checkout cloud -> universe=0 sempre ->
# scanner saia na hora. Fallback git-tracked (config/short_universe.json) garante
# universo no cloud. Observatorio: o scanner so LOGA candidatos, nao executa ordem.

# Generico: resolve universo de markets a partir de tiers do whitelist; se vazio
# (caso cloud, journal/ gitignored), cai no fallback git-tracked (config/*.json).
function Resolve-TierUniverse {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        $Whitelist = $null,
        [string[]]$TierKeys = @(),
        $ConfigFallback = $null
    )

    $markets = @()

    if ($Whitelist) {
        foreach ($k in $TierKeys) {
            if ($Whitelist.PSObject.Properties[$k]) {
                foreach ($e in $Whitelist.$k) { if ($e -and $e.market) { $markets += $e.market } }
            }
        }
    }

    if ($markets.Count -eq 0 -and $ConfigFallback -and $ConfigFallback.PSObject.Properties['markets']) {
        foreach ($e in $ConfigFallback.markets) {
            $m = if ($e -is [string]) { $e } elseif ($e -and $e.market) { $e.market } else { $null }
            if ($m) { $markets += $m }
        }
    }

    return @($markets | Select-Object -Unique)
}

# Wrapper SHORT (tiers SHORT_TIER_A_LIVE + SHORT_TIER_B_PAPER).
function Resolve-ShortUniverse {
    [CmdletBinding()]
    [OutputType([string[]])]
    param($Whitelist = $null, $ConfigFallback = $null)
    return Resolve-TierUniverse -Whitelist $Whitelist `
        -TierKeys @('SHORT_TIER_A_LIVE','SHORT_TIER_B_PAPER') -ConfigFallback $ConfigFallback
}

# 2026-08-02: radar dinamico pro lado FUTURES/SHORT -- ate aqui so o
# gem_executor.ps1 (sempre SPOT, sem leverage) tinha radar dinamico de
# movers 24h/30d (commit f3fdef4, 2026-08-01). O short_scanner.ps1 (FUTURES
# real via config/short_universe.json, tier_a_live) continuava com lista
# fixa de 15 majors curados manualmente em 2026-07-09 -- confirmado real
# (comparando logs antes/depois do deploy de ontem) que o volume desse lado
# nao cresceu, causando a percepcao real do owner de "diminuiu futures,
# aumentou spot". Owner decidiu: movers dinamicos entram DIRETO no
# tier_a_live (execucao real), confiando nos gates de seguranca ja
# existentes (Tori >=80, Mesa, Mentor, sizing cap, funding-squeeze guard)
# pra filtrar risco -- mesmo tratamento que os 15 majors curados ja tem
# hoje, sem criar uma classe "paper-only" separada pros dinamicos.
#
# Depende de Get-DynamicMarketMoversFromRawTickers (agents/lib_market_movers.ps1,
# caller deve dot-source antes).
function Get-DynamicShortUniverseWithTierALive {
    [CmdletBinding()]
    param(
        [string[]] $CuratedMarkets = @(),
        [string[]] $CuratedTierALive = @(),
        [object[]] $RawTickers = @()
    )

    $dynamicMovers = @()
    if (@($RawTickers).Count -gt 0 -and (Get-Command Get-DynamicMarketMoversFromRawTickers -ErrorAction SilentlyContinue)) {
        $dynamicMovers = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $RawTickers -ExcludeSymbols $CuratedMarkets | Select-Object -ExpandProperty symbol)
    }

    $combinedMarkets = @(@($CuratedMarkets) + @($dynamicMovers) | Select-Object -Unique)
    $combinedTierALive = @(@($CuratedTierALive) + @($dynamicMovers) | Select-Object -Unique)

    return [PSCustomObject]@{
        markets     = $combinedMarkets
        tier_a_live = $combinedTierALive
    }
}

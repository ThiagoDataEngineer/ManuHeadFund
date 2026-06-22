# lib_short_universe.ps1 -- resolucao PURA do universo SHORT (observatorio).
#
# Motivo (2026-06-22): short_scanner lia SHORT tiers do per_asset_whitelist_*.json em
# journal/ -- que e gitignored e NAO existe no checkout cloud -> universe=0 sempre ->
# scanner saia na hora. Fallback git-tracked (config/short_universe.json) garante
# universo no cloud. Observatorio: o scanner so LOGA candidatos, nao executa ordem.

function Resolve-ShortUniverse {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        $Whitelist = $null,       # objeto parseado do per_asset_whitelist (pode ser $null)
        $ConfigFallback = $null   # objeto parseado do config/short_universe.json (pode ser $null)
    )

    $markets = @()

    if ($Whitelist) {
        foreach ($k in 'SHORT_TIER_A_LIVE','SHORT_TIER_B_PAPER') {
            if ($Whitelist.PSObject.Properties[$k]) {
                foreach ($e in $Whitelist.$k) { if ($e -and $e.market) { $markets += $e.market } }
            }
        }
    }

    # So usa o fallback git-tracked quando o whitelist nao trouxe nada (caso cloud).
    if ($markets.Count -eq 0 -and $ConfigFallback -and $ConfigFallback.PSObject.Properties['markets']) {
        foreach ($e in $ConfigFallback.markets) {
            $m = if ($e -is [string]) { $e } elseif ($e -and $e.market) { $e.market } else { $null }
            if ($m) { $markets += $m }
        }
    }

    return @($markets | Select-Object -Unique)
}

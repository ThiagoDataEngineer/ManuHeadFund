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

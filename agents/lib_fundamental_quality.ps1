# lib_fundamental_quality.ps1 -- Fundamental Quality Score (FQS) gate.
#
# 7 dimensoes binarias/scored (0 ou 1 cada) que somam FQS 0-7:
#   1. age_years         >= 3        (sobreviveu 1+ bear)
#   2. supply_capped     == true     (hard cap, deflacionario)
#   3. burn_active       == true     (deflation real)
#   4. utility_score     >= 0.5      (TVL/tx, app real)
#   5. concentration_top10 <= 0.5    (distribuido, top10 < 50% supply)
#   6. recovered_2021_ath == true    (resiliente bear 2022)
#   7. listing_years     >= 2        (estavel na exchange)
#
# Registry: journal/coin_registry.json (curated manual, ~30 markets pipeline).
# Score:
#   6-7 = BLUE_CHIP
#   4-5 = QUALITY
#   2-3 = SPECULATIVE
#   0-1 = AVOID
#
# Gate por tier:
#   GEM         : aceita BLUE_CHIP + QUALITY + SPECULATIVE (block AVOID)
#   TIER_B_PAPER: aceita BLUE_CHIP + QUALITY (block SPEC/AVOID)
#   TIER_A_LIVE : aceita BLUE_CHIP + QUALITY (block SPEC/AVOID)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Get-FundamentalScore {
    # V1.5 (2026-05-19 PM refino):
    #  1. age_years >= 3
    #  2. supply_capped TRUE OR (burn_net_deflation TRUE) -- ETH justice
    #  3. burn_active TRUE
    #  4. utility_score >= 0.5
    #  5. concentration_insider_pct <= 0.5 (excl CEX/custodial wallets)
    #  6. cycle_resilience: recovered_2021_ath TRUE OR age < 2 (N/A jovem nao penaliza)
    #  7. listing_years >= 2
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $RegistryPath = (Join-Path $global:JOURNAL_DIR "coin_registry.json")
    )
    if (-not (Test-Path $RegistryPath)) {
        return [PSCustomObject]@{ market=$Market; fqs=0; category="AVOID"; reason="no_registry" }
    }
    try {
        $reg = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ market=$Market; fqs=0; category="AVOID"; reason="registry_parse_error" }
    }

    # 2026-08-19: coin_registry.json (curadoria manual, git) so cobria ~68
    # moedas -- travava LONG FUTURES em coins liquidas reais (LINK/ADA/AVAX/etc)
    # so por AUSENCIA de cadastro, nao qualidade real. coin_registry_dynamic
    # (Supabase) e alimentado por job periodico (coingecko_enrichment.py
    # --supabase, ver docs/SETUP_SUPABASE_COIN_REGISTRY_DYNAMIC_2026_08_19.sql)
    # com dado FRESCO de mercado (age/supply/price/ath). So cobre os campos
    # derivaveis via CoinGecko -- burn_active/utility_score/concentration_top10
    # (julgamento curado manual) vem do registry estatico quando existir,
    # e ficam no default conservador (false/0) quando o market so existe no
    # dinamico. Dynamic e um OVERLAY sobre o estatico, nunca substitui: se o
    # market ja esta no JSON curado, os campos do JSON vencem (curadoria > auto).
    $dynEntry = $null
    if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
        try {
            $dynRows = @(Get-StateRecords -Table "coin_registry_dynamic" -Filter @{ market = $Market })
            if ($dynRows.Count -gt 0) { $dynEntry = $dynRows[0] }
        } catch {
            # Fail-safe: Supabase indisponivel nao deve bloquear o gate --
            # segue so com o registry estatico (comportamento pre-existente).
        }
    }

    $hasStatic = $null -ne $reg.PSObject.Properties[$Market]
    if (-not $hasStatic -and -not $dynEntry) {
        return [PSCustomObject]@{ market=$Market; fqs=0; category="AVOID"; reason="market_not_in_registry" }
    }

    $e = if ($hasStatic) { $reg.$Market } else { [PSCustomObject]@{} }
    if ($dynEntry) {
        # Overlay: campos dinamicos preenchem SO o que o estatico nao definiu.
        foreach ($prop in @("age_years","supply_capped","recovered_2021_ath","current_price_usd","ath_all_time_usd")) {
            $dynVal = $dynEntry.$prop
            $staticHas = $e.PSObject.Properties[$prop] -and $null -ne $e.$prop
            if (-not $staticHas -and $null -ne $dynVal) {
                if ($e.PSObject.Properties[$prop]) { $e.$prop = $dynVal }
                else { $e | Add-Member -MemberType NoteProperty -Name $prop -Value $dynVal -Force }
            }
        }
    }
    $fqs = 0
    $reasons = @()

    # 1. Age
    if ([double]$e.age_years -ge 3) { $fqs++; $reasons += "age_3y+" }

    # 2. Supply discipline (REFINO V1.5): capped OR burn-net-deflation
    $supplyOk = ($e.supply_capped -eq $true)
    $burnNetDeflation = $false
    if ($e.PSObject.Properties['burn_net_deflation']) {
        $burnNetDeflation = ($e.burn_net_deflation -eq $true)
    }
    if ($supplyOk -or $burnNetDeflation) {
        $fqs++
        $reasons += if ($supplyOk) { "supply_capped" } else { "burn_net_deflation" }
    }

    # 3. Burn active
    if ($e.burn_active -eq $true) { $fqs++; $reasons += "burn_active" }

    # 4. Utility
    if ([double]$e.utility_score -ge 0.5) { $fqs++; $reasons += "utility_high" }

    # 5. Concentration insider (REFINO V1.5): preferir concentration_insider_pct se existir
    $concentrationField = if ($e.PSObject.Properties['concentration_insider_pct']) {
        [double]$e.concentration_insider_pct
    } else {
        [double]$e.concentration_top10
    }
    if ($concentrationField -le 0.5) { $fqs++; $reasons += "concentration_ok" }

    # 6. Cycle resilience (REFINO V1.6): tres paths possiveis:
    #    a) recovered_2021_ath == $true (explicit ou manual_override) -> OK
    #    b) age < 2 -> young_NA_cycle (V1.5)
    #    c) current_price >= 0.5 * ath_all_time -> recovered_partial (50% recovery = resilient)
    $cycleOk = $false
    if ($e.recovered_2021_ath -eq $true) {
        $fqs++; $reasons += "recovered_ath"; $cycleOk = $true
    } elseif ([double]$e.age_years -lt 2) {
        $fqs++; $reasons += "young_NA_cycle"; $cycleOk = $true
    } elseif (-not $cycleOk -and $e.PSObject.Properties['current_price_usd'] -and $e.PSObject.Properties['ath_all_time_usd']) {
        $cp = [double]$e.current_price_usd
        $ath = [double]$e.ath_all_time_usd
        if ($ath -gt 0 -and ($cp / $ath) -ge 0.5) {
            $fqs++; $reasons += "recovered_partial"; $cycleOk = $true
        }
    }

    # 7. Listing
    if ([double]$e.listing_years -ge 2) { $fqs++; $reasons += "listing_stable" }

    $category = if ($fqs -ge 6) { "BLUE_CHIP" }
                elseif ($fqs -ge 4) { "QUALITY" }
                elseif ($fqs -ge 2) { "SPECULATIVE" }
                else { "AVOID" }

    return [PSCustomObject]@{
        market   = $Market
        fqs      = $fqs
        category = $category
        reasons  = [string[]]@($reasons)   # C6 fix: array contract PS 5.1
        details  = $e
        version  = "v1.6"
    }
}


function Test-FundamentalQualityGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $TargetTier,  # "GEM" | "TIER_B_PAPER" | "TIER_A_LIVE"
        [string] $RegistryPath = (Join-Path $global:JOURNAL_DIR "coin_registry.json")
    )
    $score = Get-FundamentalScore -Market $Market -RegistryPath $RegistryPath
    $cat = $score.category

    switch ($TargetTier) {
        "GEM"          { return ($cat -in @("BLUE_CHIP","QUALITY","SPECULATIVE")) }
        "TIER_B_PAPER" { return ($cat -in @("BLUE_CHIP","QUALITY")) }
        "TIER_A_LIVE"  { return ($cat -in @("BLUE_CHIP","QUALITY")) }
        default        { return $false }
    }
}

# lib_quant_whitelist.ps1 - Le per_asset_whitelist JSON e expoe Tier A/B/C ao
# scan_master/orchestrator. Substituicao quant-priorizada do scanner heuristico.
#
# Output JSON gerado por backtest/build_per_asset_whitelist.py em
# journal/per_asset_whitelist_<DATE>.json.

function Get-QuantWhitelistPath {
    [CmdletBinding()]
    param([string]$JournalDir = "")
    if (-not $JournalDir) {
        $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $JournalDir = Join-Path (Split-Path -Parent $here) "journal"
    }
    $candidates = Get-ChildItem -Path $JournalDir -Filter "per_asset_whitelist_*.json" `
                                 -ErrorAction SilentlyContinue |
                                 Sort-Object LastWriteTime -Descending
    if ($candidates -and @($candidates).Count -gt 0) {
        return @($candidates)[0].FullName
    }
    return $null
}


function Get-QuantWhitelist {
    [CmdletBinding()]
    param([string]$Path = "")
    if (-not $Path) { $Path = Get-QuantWhitelistPath }
    if (-not $Path -or -not (Test-Path $Path)) {
        return [PSCustomObject]@{
            TIER_A_LIVE  = @()
            TIER_B_PAPER = @()
            TIER_C_SKIP  = @()
            source       = $null
        }
    }
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        return [PSCustomObject]@{
            TIER_A_LIVE  = @($data.TIER_A_LIVE)
            TIER_B_PAPER = @($data.TIER_B_PAPER)
            TIER_C_SKIP  = @($data.TIER_C_SKIP)
            source       = $Path
        }
    } catch {
        Write-Warning "Get-QuantWhitelist: falha ao parsear $Path -- $($_.Exception.Message)"
        return [PSCustomObject]@{
            TIER_A_LIVE  = @()
            TIER_B_PAPER = @()
            TIER_C_SKIP  = @()
            source       = $Path
        }
    }
}


function Get-QuantWhitelistMarkets {
    [CmdletBinding()]
    param(
        [string] $Mode = "LIVE",   # LIVE | PAPER | ALL
        [string] $Path = ""
    )
    $wl = Get-QuantWhitelist -Path $Path
    $markets = @()
    if ($Mode -eq "LIVE" -or $Mode -eq "PAPER" -or $Mode -eq "ALL") {
        $markets += @($wl.TIER_A_LIVE | ForEach-Object { $_.market })
    }
    if ($Mode -eq "PAPER" -or $Mode -eq "ALL") {
        $markets += @($wl.TIER_B_PAPER | ForEach-Object { $_.market })
    }
    if ($Mode -eq "ALL") {
        $markets += @($wl.TIER_C_SKIP | ForEach-Object { $_.market })
    }
    return @($markets | Where-Object { $_ })
}


function Get-QuantWhitelistEntry {
    [CmdletBinding()]
    param([string]$Market, [string]$Path = "")
    $wl = Get-QuantWhitelist -Path $Path
    foreach ($pool in @($wl.TIER_A_LIVE, $wl.TIER_B_PAPER, $wl.TIER_C_SKIP)) {
        foreach ($e in $pool) {
            if ($e.market -eq $Market) { return $e }
        }
    }
    return $null
}


function Merge-QuantWhitelistIntoCandidates {
    [CmdletBinding()]
    param(
        [PSObject[]] $Candidates = @(),
        [string]     $Mode = "LIVE",
        [string]     $Path = ""
    )
    # FASE 4 p4 fix 2026-05-21: ler whitelist FULL pra preservar tier_level (1=A_LIVE, 2=B_PAPER).
    # Antes: Get-QuantWhitelistMarkets retornava so nomes -> sort downstream perdia info de tier.
    # Resultado: BTC/INJ entravam top-7 mas RENDER/XMR (Tier A) eram bumped por BCH/SKY (Tier B).
    $wl = Get-QuantWhitelist -Path $Path
    if (-not $wl) { return @($Candidates) }

    $tierAList = @($wl.TIER_A_LIVE | ForEach-Object { $_.market } | Where-Object { $_ })
    $tierBList = if ($Mode -eq "PAPER" -or $Mode -eq "ALL") {
        @($wl.TIER_B_PAPER | ForEach-Object { $_.market } | Where-Object { $_ })
    } else { @() }
    $forced = @(@($tierAList) + @($tierBList) | Select-Object -Unique)
    if (@($forced).Count -eq 0) { return @($Candidates) }

    # FASE 4 p5 fix 2026-05-21 sessao final: quando market forced JA EXISTE em
    # $Candidates (descoberta organica do scanner), AUGMENT os fields ao inves de skip.
    # Pre-fix: INJ apareceu organicamente cycle 11:29, ficou sem tier_level/source ->
    # scanner natural (tierLevel=99) -> bumped do top-7 atras dos 4 Tier A + Tier B forced.
    $existingByMkt = @{}
    foreach ($c in $Candidates) {
        $mktKey = if ($c.PSObject.Properties['market']) { $c.market } elseif ($c.PSObject.Properties['Market']) { $c.Market } else { $null }
        if ($mktKey) { $existingByMkt[$mktKey] = $c }
    }

    $extras = @()
    foreach ($m in $forced) {
        $entry = Get-QuantWhitelistEntry -Market $m -Path $Path
        $sharpe = if ($entry -and $entry.PSObject.Properties['sharpe']) { [double]$entry.sharpe } else { 0.0 }
        $tierLevel = if ($tierAList -contains $m) { 1 } else { 2 }
        $forcedSource = "quant_whitelist_$Mode"

        if ($existingByMkt.ContainsKey($m)) {
            # FASE 4 p5: augment existing scanner-natural entry with forced fields.
            # Preserve scanner volume/change reais; sobrescreve so source + tier_level.
            $existing = $existingByMkt[$m]
            if (-not $existing.PSObject.Properties['source'] -or $existing.source -notlike 'quant_whitelist_*') {
                Add-Member -InputObject $existing -MemberType NoteProperty -Name 'source' -Value $forcedSource -Force
            }
            if (-not $existing.PSObject.Properties['tier_level']) {
                Add-Member -InputObject $existing -MemberType NoteProperty -Name 'tier_level' -Value $tierLevel -Force
            }
            if (-not $existing.PSObject.Properties['quant_priority']) {
                Add-Member -InputObject $existing -MemberType NoteProperty -Name 'quant_priority' -Value $sharpe -Force
            }
        } else {
            # Market nao apareceu organicamente -> adiciona extra forced.
            $extras += [PSCustomObject]@{
                market           = $m
                marketType       = "FUTURES"   # Tier A/B LIVE eh sempre futures (validado curated)
                score            = 100         # forcado pra entrar no top
                change           = 0.0         # neutro (scanner real preenche se aparece naturalmente)
                volume           = 0.0
                quant_priority   = $sharpe
                tier_level       = $tierLevel  # FASE 4 p4: sort priority absoluto Tier A > B > scanner
                source           = $forcedSource
            }
        }
    }
    return @($Candidates + $extras)
}

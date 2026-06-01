# lib_market_blacklist.ps1 -- TTL-based market blacklist (E1 HARD_VETO mechanism).
#
# Mentor HARD_VETO veredict triggers blacklist:
#   Add-MarketBlacklist -Market X -TtlHours 24 -Reason "regime extremo"
#
# Scanners check antes de processar:
#   if (Test-MarketBlacklisted -Market X) { skip }
#
# Storage: JSONL append-only em journal/market_blacklist.jsonl
# Format: { market, added_at, expires_at, reason }
#
# Cleanup automatico: entries expirados ignorados em Test (lazy expire).
#
# Fail-soft: file unreachable -> Test returns $false (no block).
#
# PS 5.1. UTF-8 BOM.


$script:BLACKLIST_DEFAULT_PATH = $null


function _Init-BlacklistPath {
    if (-not $script:BLACKLIST_DEFAULT_PATH) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $script:BLACKLIST_DEFAULT_PATH = Join-Path $journalDir "market_blacklist.jsonl"
    }
}


function Add-MarketBlacklist {
    <#
    .SYNOPSIS
    Adiciona market ao blacklist com TTL.

    .PARAMETER Market
    Market symbol.

    .PARAMETER TtlHours
    Default 24h.

    .PARAMETER Reason
    Texto explicativo.

    .PARAMETER BlacklistPath
    Override path (testing).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $TtlHours = 24,
        [string] $Reason = "no_reason",
        [string] $BlacklistPath = ""
    )
    if ($BlacklistPath) { $script:BLACKLIST_DEFAULT_PATH = $BlacklistPath } else { _Init-BlacklistPath }
    $path = $script:BLACKLIST_DEFAULT_PATH

    $now = (Get-Date).ToUniversalTime()
    $entry = [ordered]@{
        market     = $Market
        added_at   = $now.ToString("o")
        expires_at = $now.AddHours($TtlHours).ToString("o")
        reason     = $Reason
        ttl_hours  = $TtlHours
    }
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}


function Test-MarketBlacklisted {
    <#
    .SYNOPSIS
    Verifica se market esta blacklisted atualmente (entry com expires_at > now).

    .DESCRIPTION
    Lazy expire: entries velhos sao ignorados (nao deletados — JSONL append-only).
    Multiple entries pro mesmo market: usa a MAIS RECENTE (greatest expires_at).

    Fail-soft: arquivo missing -> returns $false (no block).

    .OUTPUTS
    Bool — true se blacklisted, false caso contrario.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $BlacklistPath = "",
        [datetime] $NowUtc = (Get-Date).ToUniversalTime()
    )
    if ($BlacklistPath) { $script:BLACKLIST_DEFAULT_PATH = $BlacklistPath } else { _Init-BlacklistPath }
    $path = $script:BLACKLIST_DEFAULT_PATH

    if (-not (Test-Path $path)) { return $false }

    try {
        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                if ($obj.market -ne $Market) { continue }
                $expiresStr = $obj.expires_at
                if (-not $expiresStr) { continue }
                $expDt = $null
                try {
                    $expDt = [System.DateTimeOffset]::Parse($expiresStr, [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
                } catch { continue }
                if ($expDt -gt $NowUtc) {
                    return $true  # any active entry blacklists
                }
            } catch {}
        }
    } catch { return $false }
    return $false
}


function Get-BlacklistedMarkets {
    <#
    .SYNOPSIS
    Lista todos markets atualmente blacklisted (com entries activos).
    #>
    [CmdletBinding()]
    param(
        [string] $BlacklistPath = "",
        [datetime] $NowUtc = (Get-Date).ToUniversalTime()
    )
    if ($BlacklistPath) { $script:BLACKLIST_DEFAULT_PATH = $BlacklistPath } else { _Init-BlacklistPath }
    $path = $script:BLACKLIST_DEFAULT_PATH
    if (-not (Test-Path $path)) { return @() }

    $active = @{}
    try {
        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                if (-not $obj.market -or -not $obj.expires_at) { continue }
                $expDt = $null
                try {
                    $expDt = [System.DateTimeOffset]::Parse($obj.expires_at, [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
                } catch { continue }
                if ($expDt -gt $NowUtc) {
                    if ((-not $active.ContainsKey($obj.market)) -or ($active[$obj.market].expires -lt $expDt)) {
                        $active[$obj.market] = [PSCustomObject]@{
                            market = $obj.market
                            expires = $expDt
                            reason = $obj.reason
                        }
                    }
                }
            } catch {}
        }
    } catch { return @() }
    return @($active.Values)
}

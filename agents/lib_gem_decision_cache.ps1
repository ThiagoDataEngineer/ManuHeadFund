# lib_gem_decision_cache.ps1 -- B9 fix 2026-05-20 PM6+ with Tori confluence tracking
# TTL cache pra GEM decisions recentes: mesma (market,reason) dentro de N min = skip.
# Resolve loop de re-veto (DASH rejeitado 5x hoje com mesmo MCE_BLOCK 0.1823 -> ~$0.03 desperdicio).
#
# 2026-07-08 ENHANCEMENT: Track Tori confluence scores for failed entries
# Schema: journal/gem_recent_decisions.json
# [
#   {"market":"DASHUSDT", "reason":"MCE_BLOCK 0.1823", "tori_confluence":65, "ts":"2026-05-20T18:00:00Z"},
#   {"market":"BTCUSDT", "reason":"tori_confluence:75_lt_80", "tori_confluence":75, "ts":"2026-07-08T12:00:00Z"},
#   ...
# ]
#
# PS 5.1, UTF-8 BOM.

function _GemCache-Load {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8
        if (-not $raw -or $raw.Trim() -eq "") { return @() }
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { return @() }
        return @($data)
    } catch {
        return @()
    }
}

function _GemCache-Save {
    param([string] $Path, [array] $Entries)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    ($Entries | ConvertTo-Json -Depth 4 -Compress) | Out-File -FilePath $Path -Encoding UTF8 -Force
}

function _GemCache-NormReason {
    # Normaliza reason pra match: pega so o token/score, ignora floats variando.
    # "MCE_BLOCK 0.1823" e "MCE_BLOCK 0.1824" devem matchar.
    param([string] $Reason)
    if ($null -eq $Reason) { return "" }
    # Trunca floats em 2 decimais
    $norm = [regex]::Replace($Reason.ToLowerInvariant(), '(\d+\.\d{3,})', { param($m) [double]::Parse($m.Value, [System.Globalization.CultureInfo]::InvariantCulture).ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture) })
    return $norm.Trim()
}

function Add-GemRejection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Reason,
        [int] $ToriConfluenceScore = -1,   # 2026-07-08: optional Tori score tracking
        [string] $Direction = ""            # 2026-07-10 FIX: Add direction to prevent cache collision
    )
    $normReason = _GemCache-NormReason $Reason
    $entries = @(_GemCache-Load -Path $Path)
    # 2026-07-10 FIX #8: Dedup por (market, direction, normReason) — prevent XEMUSDT|LONG vs XEMUSDT|SHORT collision
    $cacheKey = if ($Direction) { "$Market|$Direction" } else { $Market }
    $entries = @($entries | Where-Object { -not ($_.cache_key -eq $cacheKey -and (_GemCache-NormReason $_.reason) -eq $normReason) })

    $newEntry = [PSCustomObject]@{
        market = $Market
        direction = $Direction                # 2026-07-10: track direction explicitly
        cache_key = $cacheKey                 # 2026-07-10: unique key with direction
        reason = $Reason
        ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    # Add Tori confluence score if provided
    if ($ToriConfluenceScore -ge 0) {
        $newEntry | Add-Member -NotePropertyName tori_confluence -NotePropertyValue $ToriConfluenceScore
    }

    $entries += $newEntry
    # Mantem so ultimos 200 entries (rolling)
    if ($entries.Count -gt 200) {
        $entries = $entries[-200..-1]
    }
    _GemCache-Save -Path $Path -Entries $entries
}

function Test-GemRecentlyRejected {
    <#
    .SYNOPSIS
    Verifica se market+direction foi rejeitado recentemente (TTL).
    .PARAMETER Direction
    2026-07-10 FIX #8: Include direction in lookup to prevent cache collision
    (XEMUSDT|LONG rejection should not block XEMUSDT|SHORT entry)
    .PARAMETER MatchReason
    Se true, exige reason normalizado igual (B9 strict). Se false (DEFAULT pos
    2026-05-21), match by market only. Reason era inconsistente entre write/read
    paths (tori_skip vs score=N mode=X) -> cache effectively dead. Em prod o
    intent eh "qualquer rejection recente -> skip cycle proximo".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [string] $Reason = "",
        [int] $TtlMinutes = 60,
        [switch] $MatchReason,
        [string[]] $BypassReasons = @(),
        [string] $Direction = ""  # 2026-07-10: Add direction parameter
    )
    if ($TtlMinutes -le 0) { return $false }
    $entries = @(_GemCache-Load -Path $Path)
    if ($entries.Count -eq 0) { return $false }
    $normReason = if ($Reason) { _GemCache-NormReason $Reason } else { "" }
    # 2026-07-10 FIX #8: Build cache_key with direction
    $cacheKey = if ($Direction) { "$Market|$Direction" } else { $Market }
    # 2026-06-17: razoes a IGNORAR (re-avaliar). Ex.: tori_skip quando CONVICTION_GATE on
    # -> o gem re-chega ao executor pro ensemble decidir override. Outras razoes
    # (conviction_low, sizing, etc) AINDA bloqueiam (evita loop de re-avaliacao).
    $bypassNorm = @($BypassReasons | ForEach-Object { _GemCache-NormReason $_ } | Where-Object { $_ })
    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-$TtlMinutes)
    foreach ($e in $entries) {
        # 2026-07-10 FIX #8: Match by cache_key (with direction) if available, fallback to market
        $entryKey = if ($e.cache_key) { $e.cache_key } else { $e.market }
        if ($entryKey -ne $cacheKey) { continue }
        if ($MatchReason -and ((_GemCache-NormReason $e.reason) -ne $normReason)) { continue }
        # Pula entradas cuja razao esta na lista de bypass (nao contam como bloqueio)
        if ($bypassNorm.Count -gt 0) {
            $eNorm = _GemCache-NormReason $e.reason
            $isBypassed = $false
            foreach ($b in $bypassNorm) { if ($eNorm -eq $b -or $eNorm -like "*$b*") { $isBypassed = $true; break } }
            if ($isBypassed) { continue }
        }
        try {
            $entryTs = [datetime]::Parse($e.ts, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
            if ($entryTs -ge $cutoff) { return $true }
        } catch {}
    }
    return $false
}

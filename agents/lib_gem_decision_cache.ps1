# lib_gem_decision_cache.ps1 -- B9 fix 2026-05-20 PM6+.
# TTL cache pra GEM decisions recentes: mesma (market,reason) dentro de N min = skip.
# Resolve loop de re-veto (DASH rejeitado 5x hoje com mesmo MCE_BLOCK 0.1823 -> ~$0.03 desperdicio).
#
# Schema: journal/gem_recent_decisions.json
# [
#   {"market":"DASHUSDT", "reason":"MCE_BLOCK 0.1823", "ts":"2026-05-20T18:00:00Z"},
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
        [Parameter(Mandatory)] [string] $Reason
    )
    $normReason = _GemCache-NormReason $Reason
    $entries = @(_GemCache-Load -Path $Path)
    # Dedup por (market, normReason): remove existente, adiciona novo timestamp
    $entries = @($entries | Where-Object { -not ($_.market -eq $Market -and (_GemCache-NormReason $_.reason) -eq $normReason) })
    $entries += [PSCustomObject]@{
        market = $Market
        reason = $Reason
        ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    # Mantem so ultimos 200 entries (rolling)
    if ($entries.Count -gt 200) {
        $entries = $entries[-200..-1]
    }
    _GemCache-Save -Path $Path -Entries $entries
}

function Test-GemRecentlyRejected {
    <#
    .SYNOPSIS
    Verifica se market foi rejeitado recentemente (TTL).
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
        [string[]] $BypassReasons = @()
    )
    if ($TtlMinutes -le 0) { return $false }
    $entries = @(_GemCache-Load -Path $Path)
    if ($entries.Count -eq 0) { return $false }
    $normReason = if ($Reason) { _GemCache-NormReason $Reason } else { "" }
    # 2026-06-17: razoes a IGNORAR (re-avaliar). Ex.: tori_skip quando CONVICTION_GATE on
    # -> o gem re-chega ao executor pro ensemble decidir override. Outras razoes
    # (conviction_low, sizing, etc) AINDA bloqueiam (evita loop de re-avaliacao).
    $bypassNorm = @($BypassReasons | ForEach-Object { _GemCache-NormReason $_ } | Where-Object { $_ })
    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-$TtlMinutes)
    foreach ($e in $entries) {
        if ($e.market -ne $Market) { continue }
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

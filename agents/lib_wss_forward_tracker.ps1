# lib_wss_forward_tracker.ps1 -- Forward validation: track WSS signals + realized outcomes.
#
# Caminho 2 (2026-05-23): Branch A v2 mostrou CI ainda inclui zero. Unico jeito de
# rejeitar/confirmar thesis eh OUTCOMES REAIS forward. Esta lib captura:
#   1. Cada signal Tier S triggered (Add-WssSignal)
#   2. After N bars, computa realized outcome (Resolve-WssSignal via cron)
#   3. Comparativo: predicted_lift (CI) vs realized_lift (real)
#
# Wire intentional: vol_climax_scanner.ps1 chama Add-WssSignal quando Tier S detected.
# Cron weekly: scripts/cron_wss_forward_audit.ps1 resolve + compara + alerta.
#
# Storage: journal/wss_forward_signals.jsonl append-only.
#
# PS 5.1. UTF-8 BOM.


$script:WSS_FWD_DEFAULT_PATH = $null

function _Init-WssFwdPath {
    if (-not $script:WSS_FWD_DEFAULT_PATH) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $script:WSS_FWD_DEFAULT_PATH = Join-Path $journalDir "wss_forward_signals.jsonl"
    }
}


function Add-WssSignal {
    <#
    .SYNOPSIS
    Registra signal Tier S forward-tracking. Idempotent (skip se ja existe).

    .PARAMETER Market
    Market symbol.

    .PARAMETER TriggeredAt
    Timestamp UTC quando signal disparou.

    .PARAMETER WssScore
    WSS computed (0-100).

    .PARAMETER EntryPrice
    Close price no signal bar.

    .PARAMETER BtcDrawdown
    BTC drawdown contexto.

    .PARAMETER BtcVol
    BTC vol_20d contexto.

    .PARAMETER WindowBars
    Bars pra resolver outcome (default 3 = matches WSS predicate).

    .PARAMETER PathOverride
    Testing only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $TriggeredAt = ((Get-Date).ToUniversalTime().ToString("o")),
        [double] $WssScore = 0,
        [double] $EntryPrice = 0,
        [Nullable[double]] $BtcDrawdown = $null,
        [Nullable[double]] $BtcVol = $null,
        [int] $WindowBars = 3,
        # 2026-05-23 Tier 2 Block 1 F.1: Side param SHORT support (default LONG backward compat)
        [ValidateSet("LONG","SHORT")] [string] $Side = "LONG",
        [string] $PathOverride = ""
    )
    if ($PathOverride) { $script:WSS_FWD_DEFAULT_PATH = $PathOverride } else { _Init-WssFwdPath }
    $path = $script:WSS_FWD_DEFAULT_PATH

    # Idempotency: skip se ja existe entry com mesmo (market, triggered_at_date, side)
    $tsDate = $TriggeredAt.Substring(0, 10)
    if (Test-Path $path) {
        try {
            $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue)
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $obj = $line | ConvertFrom-Json -ErrorAction Stop
                    $objSide = if ($obj.PSObject.Properties['side']) { $obj.side } else { "LONG" }
                    if ($obj.market -eq $Market -and $obj.triggered_at -like "$tsDate*" -and $objSide -eq $Side) {
                        return  # dup same direction same day, skip
                    }
                } catch {}
            }
        } catch {}
    }

    $entry = [ordered]@{
        market         = $Market
        triggered_at   = $TriggeredAt
        side           = $Side  # 2026-05-23 SHORT support
        wss_score      = $WssScore
        entry_price    = $EntryPrice
        btc_drawdown   = $BtcDrawdown
        btc_vol_20d    = $BtcVol
        window_bars    = $WindowBars
        status         = "pending"
        added_at       = (Get-Date).ToUniversalTime().ToString("o")
    }
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}


function Resolve-WssSignal {
    <#
    .SYNOPSIS
    Marca signal como resolved com outcome real.

    .PARAMETER Market
    Market.

    .PARAMETER TriggeredAtDate
    YYYY-MM-DD do signal original.

    .PARAMETER ExitPrice
    Max close em window_bars bars after entry.

    .PARAMETER RealizedPct
    Outcome % computed.

    .PARAMETER Hit
    Bool: $true se outcome > threshold (1.6% net default).

    .PARAMETER PathOverride
    Testing only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $TriggeredAtDate,
        [double] $ExitPrice = 0,
        [double] $RealizedPct = 0,
        [bool]   $Hit = $false,
        [string] $PathOverride = ""
    )
    if ($PathOverride) { $script:WSS_FWD_DEFAULT_PATH = $PathOverride } else { _Init-WssFwdPath }
    $path = $script:WSS_FWD_DEFAULT_PATH

    $entry = [ordered]@{
        market           = $Market
        triggered_at_date = $TriggeredAtDate
        status           = "resolved"
        exit_price       = $ExitPrice
        realized_pct     = [math]::Round($RealizedPct, 2)
        hit              = $Hit
        resolved_at      = (Get-Date).ToUniversalTime().ToString("o")
    }
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}


function Get-PendingWssSignals {
    <#
    .SYNOPSIS
    Lista signals pending (sem resolved correspondente).
    #>
    [CmdletBinding()]
    param([string] $PathOverride = "")
    if ($PathOverride) { $script:WSS_FWD_DEFAULT_PATH = $PathOverride } else { _Init-WssFwdPath }
    $path = $script:WSS_FWD_DEFAULT_PATH
    if (-not (Test-Path $path)) { return @() }

    $byKey = @{}
    try {
        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $key = if ($obj.status -eq "resolved") {
                    "$($obj.market)_$($obj.triggered_at_date)"
                } else {
                    "$($obj.market)_$($obj.triggered_at.Substring(0,10))"
                }
                if (-not $byKey.ContainsKey($key)) { $byKey[$key] = @{} }
                if ($obj.status -eq "pending") { $byKey[$key].pending = $obj }
                elseif ($obj.status -eq "resolved") { $byKey[$key].resolved = $obj }
            } catch {}
        }
    } catch { return @() }

    $pending = @()
    foreach ($k in $byKey.Keys) {
        if ($byKey[$k].pending -and -not $byKey[$k].resolved) {
            $pending += $byKey[$k].pending
        }
    }
    return @($pending)
}


function Get-WssForwardStats {
    <#
    .SYNOPSIS
    Computa stats de signals resolved: hit_rate, mean_realized_pct, n.

    .PARAMETER PathOverride
    Testing.
    #>
    [CmdletBinding()]
    param([string] $PathOverride = "")
    if ($PathOverride) { $script:WSS_FWD_DEFAULT_PATH = $PathOverride } else { _Init-WssFwdPath }
    $path = $script:WSS_FWD_DEFAULT_PATH

    $stats = [PSCustomObject]@{
        n_resolved = 0
        hit_count = 0
        hit_rate_pct = 0
        mean_realized_pct = 0
        n_pending = 0
    }
    if (-not (Test-Path $path)) { return $stats }

    $resolved = @()
    $pendingCount = 0
    $byKey = @{}
    try {
        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $key = if ($obj.status -eq "resolved") {
                    "$($obj.market)_$($obj.triggered_at_date)"
                } else {
                    "$($obj.market)_$($obj.triggered_at.Substring(0,10))"
                }
                if (-not $byKey.ContainsKey($key)) { $byKey[$key] = @{} }
                if ($obj.status -eq "pending") { $byKey[$key].pending = $obj }
                elseif ($obj.status -eq "resolved") { $byKey[$key].resolved = $obj }
            } catch {}
        }
    } catch { return $stats }

    foreach ($k in $byKey.Keys) {
        if ($byKey[$k].resolved) { $resolved += $byKey[$k].resolved }
        elseif ($byKey[$k].pending) { $pendingCount++ }
    }

    if ($resolved.Count -gt 0) {
        $stats.n_resolved = $resolved.Count
        $stats.hit_count = @($resolved | Where-Object { $_.hit }).Count
        $stats.hit_rate_pct = [math]::Round(($stats.hit_count / $stats.n_resolved) * 100, 1)
        $stats.mean_realized_pct = [math]::Round((@($resolved | ForEach-Object { [double]$_.realized_pct }) | Measure-Object -Average).Average, 2)
    }
    $stats.n_pending = $pendingCount
    return $stats
}

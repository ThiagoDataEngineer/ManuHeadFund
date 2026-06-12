# lib_watchdog_backoff.ps1 -- B16 fix 2026-05-20 PM6+390min.
#
# Backoff exponencial + kill switch pra evitar respawn-loop infinito.
# Antes: watchdog respawnaria 1000x/hora se processo morresse imediatamente apos start
# (bug de startup, lib quebrada, env var faltando).
# Agora: 2^N segundos entre tentativas, max ~512s. Apos 5 falhas consecutivas =
# kill switch (precisa intervencao manual: deletar state file).
#
# Schema: journal/watchdog_respawn_state.json
# {
#   "scan_master": {"failures": 3, "last_failure": "ISO", "killed": false},
#   "gem_loop":    {"failures": 0, "last_failure": null, "killed": false}
# }
#
# PS 5.1, UTF-8 BOM.

$script:WD_BACKOFF_BASE_SEC = 2     # 2^N seconds
$script:WD_BACKOFF_MAX_SEC  = 600   # 10min cap
$script:WD_DEFAULT_MAX_FAIL = 5     # kill switch threshold

function _WD-Load {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return [PSCustomObject]@{} }
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $raw -or $raw.Trim() -eq "") { return [PSCustomObject]@{} }
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $data) { return [PSCustomObject]@{} }
        return $data
    } catch {
        return [PSCustomObject]@{}
    }
}

function _WD-Save {
    param([string] $Path, $Data)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    ($Data | ConvertTo-Json -Depth 4) | Out-File -FilePath $Path -Encoding UTF8 -Force
}

function Add-RespawnFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ProcName
    )
    $data = _WD-Load -Path $Path
    if (-not $data.PSObject.Properties[$ProcName]) {
        $data | Add-Member -NotePropertyName $ProcName -NotePropertyValue ([PSCustomObject]@{
            failures = 0; last_failure = $null; killed = $false
        })
    }
    $entry = $data.$ProcName
    $entry.failures = [int]$entry.failures + 1
    $entry.last_failure = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    _WD-Save -Path $Path -Data $data
}

function Reset-RespawnState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ProcName
    )
    $data = _WD-Load -Path $Path
    if ($data.PSObject.Properties[$ProcName]) {
        $data.$ProcName.failures = 0
        $data.$ProcName.last_failure = $null
        $data.$ProcName.killed = $false
        _WD-Save -Path $Path -Data $data
    }
}

function Test-RespawnAllowed {
    <#
    .SYNOPSIS
        Verifica se respawn eh permitido agora (considera backoff + kill switch).
    .OUTPUTS
        PSCustomObject { allowed, wait_seconds, failures, killed_switch }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ProcName,
        [int] $MaxFailures = $script:WD_DEFAULT_MAX_FAIL
    )
    $data = _WD-Load -Path $Path
    if (-not $data.PSObject.Properties[$ProcName]) {
        # 1a vez — permite imediatamente
        return [PSCustomObject]@{
            allowed = $true
            wait_seconds = 0
            failures = 0
            killed_switch = $false
        }
    }
    $entry = $data.$ProcName
    $failures = [int]$entry.failures

    # Kill switch
    if ($failures -ge $MaxFailures) {
        return [PSCustomObject]@{
            allowed = $false
            wait_seconds = -1
            failures = $failures
            killed_switch = $true
        }
    }

    # Backoff exponencial
    $waitSec = [Math]::Min([Math]::Pow($script:WD_BACKOFF_BASE_SEC, $failures), $script:WD_BACKOFF_MAX_SEC)
    if (-not $entry.last_failure) {
        return [PSCustomObject]@{
            allowed = $true
            wait_seconds = 0
            failures = $failures
            killed_switch = $false
        }
    }
    try {
        $lastFail = [datetime]::Parse($entry.last_failure, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        $elapsed = ((Get-Date).ToUniversalTime() - $lastFail).TotalSeconds
        $remaining = $waitSec - $elapsed
        if ($remaining -le 0) {
            return [PSCustomObject]@{
                allowed = $true
                wait_seconds = 0
                failures = $failures
                killed_switch = $false
            }
        }
        return [PSCustomObject]@{
            allowed = $false
            wait_seconds = [int]$remaining
            failures = $failures
            killed_switch = $false
        }
    } catch {
        return [PSCustomObject]@{
            allowed = $true
            wait_seconds = 0
            failures = $failures
            killed_switch = $false
        }
    }
}

# agents/lib_state_store.ps1
# Generic state store abstraction with 2 backends: local JSON files OR Supabase REST.
#
# Why: GitHub Actions runs em Linux nao tem acesso a journal/ local. Para Layers 1-5
# rodarem 24/7 na nuvem, estado precisa morar em lugar compartilhado.
#
# Selection (priority order):
#   1. $global:STATE_STORE_BACKEND  (test override)
#   2. $env:STATE_STORE_BACKEND     (env)
#   3. journal/USE_SUPABASE_STATE.flag (filesystem)
#   4. default "local"
#
# API:
#   Test-StateBackend                      -> "local" | "supabase"
#   Get-StateRecords  -Table -Filter @{}   -> @(records...)
#   Save-StateRecords -Table -Records @() -PrimaryKey "field"
#   Remove-StateRecord -Table -PrimaryKey "field" -Value "..."
#
# PS 5.1 compatible. UTF-8 BOM tolerated.

$_stateAgentsDir = $PSScriptRoot
$_stateJournalDir = Join-Path (Split-Path $_stateAgentsDir -Parent) "journal"
$STATE_STORE_FLAG_FILE = Join-Path $_stateJournalDir "USE_SUPABASE_STATE.flag"
$VALID_BACKENDS = @("local", "supabase")

function Test-StateBackend {
    <#
    .SYNOPSIS
    Determine active state store backend.

    .OUTPUTS
    [string] "local" or "supabase"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Priority 1: global override (testing)
    if ($global:STATE_STORE_BACKEND) {
        $b = [string]$global:STATE_STORE_BACKEND
        if ($VALID_BACKENDS -contains $b) { return $b }
    }

    # Priority 2: env var
    if ($env:STATE_STORE_BACKEND) {
        $b = [string]$env:STATE_STORE_BACKEND
        if ($VALID_BACKENDS -contains $b) { return $b }
        # Invalid value falls through to default
    }

    # Priority 3: filesystem flag
    if (Test-Path $STATE_STORE_FLAG_FILE) {
        return "supabase"
    }

    # Default
    return "local"
}

# ─────────────────────────────────────────────────────────────────────
# Local backend (legacy back-compat: JSON file per table)
# ─────────────────────────────────────────────────────────────────────

function _Get-LocalStoreDir {
    if ($global:STATE_STORE_LOCAL_DIR) { return [string]$global:STATE_STORE_LOCAL_DIR }
    return $_stateJournalDir
}

function _Get-LocalTablePath {
    param([string]$Table)
    $dir = _Get-LocalStoreDir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return Join-Path $dir "${Table}.json"
}

function _Read-LocalTable {
    param([string]$Table)
    $path = _Get-LocalTablePath -Table $Table
    if (-not (Test-Path $path)) { return @() }

    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        if (-not $raw -or $raw.Trim().Length -eq 0) { return @() }
        $parsed = $raw | ConvertFrom-Json
    } catch {
        return @()
    }

    # PS 5.1 array unwrap recovery: handle nested arrays + {value=[],Count=N} wrappers
    $flat = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack

    if ($parsed -is [array]) {
        foreach ($x in $parsed) { $stack.Push($x) }
    } else {
        $stack.Push($parsed)
    }

    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        if ($null -eq $item) { continue }
        if ($item -is [array]) {
            foreach ($inner in $item) { $stack.Push($inner) }
            continue
        }
        if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
            foreach ($inner in $item) { $stack.Push($inner) }
            continue
        }
        if ($item.PSObject.Properties['value'] -and $item.PSObject.Properties['Count'] -and ($item.value -is [array])) {
            foreach ($inner in $item.value) { $stack.Push($inner) }
            continue
        }
        [void]$flat.Add($item)
    }

    return @($flat)
}

function _Write-LocalTable {
    param([string]$Table, [object[]]$Records)
    $path = _Get-LocalTablePath -Table $Table
    # Force array wrap to avoid PS 5.1 single-element unwrap
    if ($null -eq $Records) { $Records = @() }
    $payload = @($Records)
    $payload | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8 -Force
}

function _Local-Get {
    param([string]$Table, [hashtable]$Filter)
    $rows = @(_Read-LocalTable -Table $Table)
    if (-not $Filter -or $Filter.Count -eq 0) { return @($rows) }

    $filtered = @($rows | Where-Object {
        $row = $_
        $match = $true
        foreach ($k in $Filter.Keys) {
            $expected = $Filter[$k]
            $actual = $null
            if ($row.PSObject.Properties[$k]) { $actual = $row.$k }
            if ($actual -ne $expected) { $match = $false; break }
        }
        $match
    })
    return @($filtered)
}

function _Local-Save {
    param([string]$Table, [object[]]$Records, [string]$PrimaryKey)

    if ($null -eq $Records -or @($Records).Count -eq 0) { return }

    $existing = @(_Read-LocalTable -Table $Table)

    if ($PrimaryKey) {
        # Build set of new PK values
        $newKeys = New-Object System.Collections.Generic.HashSet[string]
        foreach ($r in $Records) {
            if ($r.PSObject.Properties[$PrimaryKey]) {
                [void]$newKeys.Add([string]$r.$PrimaryKey)
            }
        }
        # Keep existing rows whose PK is not in newKeys
        $kept = @($existing | Where-Object {
            -not ($_.PSObject.Properties[$PrimaryKey] -and $newKeys.Contains([string]$_.$PrimaryKey))
        })
        $combined = @($kept) + @($Records)
    } else {
        # No PK: append (caller responsible for dedup)
        $combined = @($existing) + @($Records)
    }

    _Write-LocalTable -Table $Table -Records $combined
}

function _Local-Remove {
    param([string]$Table, [string]$PrimaryKey, [string]$Value)
    $existing = @(_Read-LocalTable -Table $Table)
    $kept = @($existing | Where-Object {
        -not ($_.PSObject.Properties[$PrimaryKey] -and ([string]$_.$PrimaryKey) -eq $Value)
    })
    _Write-LocalTable -Table $Table -Records $kept
}

# ─────────────────────────────────────────────────────────────────────
# Supabase backend (REST PostgREST)
# ─────────────────────────────────────────────────────────────────────

function _Supabase-Headers {
    $url = $env:SUPABASE_URL
    $key = if ($env:SUPABASE_SERVICE_KEY) { $env:SUPABASE_SERVICE_KEY } else { $env:SUPABASE_ANON_KEY }
    if (-not $url -or -not $key) {
        throw "Supabase backend requires SUPABASE_URL + SUPABASE_(SERVICE|ANON)_KEY env vars"
    }
    return @{
        url = $url.TrimEnd("/")
        headers = @{
            "apikey"        = $key
            "Authorization" = "Bearer $key"
            "Content-Type"  = "application/json"
        }
    }
}

function _Supabase-Get {
    param([string]$Table, [hashtable]$Filter)
    $cfg = _Supabase-Headers
    $params = "select=*"
    if ($Filter -and $Filter.Count -gt 0) {
        foreach ($k in $Filter.Keys) {
            $v = $Filter[$k]
            # PostgREST eq operator
            $params += "&${k}=eq.$v"
        }
    }
    $uri = "$($cfg.url)/rest/v1/${Table}?${params}"
    try {
        $r = Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30
        return @($r)
    } catch {
        Write-Warning "[state_store] Supabase GET ${Table} failed: $_"
        return @()
    }
}

function _Supabase-Save {
    param([string]$Table, [object[]]$Records, [string]$PrimaryKey)
    if ($null -eq $Records -or @($Records).Count -eq 0) { return }
    $cfg = _Supabase-Headers
    $headers = @{} + $cfg.headers
    $headers["Prefer"] = "return=representation,resolution=merge-duplicates"

    $url = "$($cfg.url)/rest/v1/${Table}"
    if ($PrimaryKey) { $url += "?on_conflict=${PrimaryKey}" }

    # Convert PSCustomObjects to plain hashtables for JSON
    $payload = @()
    foreach ($r in $Records) {
        if ($r -is [hashtable]) {
            $payload += $r
        } else {
            $h = @{}
            foreach ($p in $r.PSObject.Properties) { $h[$p.Name] = $p.Value }
            $payload += $h
        }
    }

    $body = $payload | ConvertTo-Json -Depth 8 -Compress
    if (@($payload).Count -eq 1) {
        # Force array even for single record
        $body = "[" + $body + "]"
    }

    try {
        Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body -TimeoutSec 30 | Out-Null
    } catch {
        Write-Warning "[state_store] Supabase POST ${Table} failed: $_"
        throw
    }
}

function _Supabase-Remove {
    param([string]$Table, [string]$PrimaryKey, [string]$Value)
    $cfg = _Supabase-Headers
    $url = "$($cfg.url)/rest/v1/${Table}?${PrimaryKey}=eq.${Value}"
    try {
        Invoke-RestMethod -Uri $url -Method DELETE -Headers $cfg.headers -TimeoutSec 30 | Out-Null
    } catch {
        Write-Warning "[state_store] Supabase DELETE ${Table} failed: $_"
        throw
    }
}

# ─────────────────────────────────────────────────────────────────────
# Public dispatch API
# ─────────────────────────────────────────────────────────────────────

function Get-StateRecords {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory=$true)][string]$Table,
        [hashtable]$Filter = $null
    )
    $backend = Test-StateBackend
    switch ($backend) {
        "supabase" { return @(_Supabase-Get -Table $Table -Filter $Filter) }
        default    { return @(_Local-Get    -Table $Table -Filter $Filter) }
    }
}

function Save-StateRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$true)][object[]]$Records,
        [string]$PrimaryKey = ""
    )
    $backend = Test-StateBackend
    switch ($backend) {
        "supabase" { _Supabase-Save -Table $Table -Records $Records -PrimaryKey $PrimaryKey }
        default    { _Local-Save    -Table $Table -Records $Records -PrimaryKey $PrimaryKey }
    }
}

function Remove-StateRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$true)][string]$PrimaryKey,
        [Parameter(Mandatory=$true)][string]$Value
    )
    $backend = Test-StateBackend
    switch ($backend) {
        "supabase" { _Supabase-Remove -Table $Table -PrimaryKey $PrimaryKey -Value $Value }
        default    { _Local-Remove    -Table $Table -PrimaryKey $PrimaryKey -Value $Value }
    }
}

# Functions exported:
# - Test-StateBackend
# - Get-StateRecords
# - Save-StateRecords
# - Remove-StateRecord

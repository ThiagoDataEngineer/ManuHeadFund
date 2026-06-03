# agents/lib_supabase_management.ps1
# Encapsula chamadas a Supabase Management API (api.supabase.com).
#
# Diferente de lib_state_store.ps1 (PostgREST = DML em data) — aqui rodamos
# DDL (CREATE TABLE, ALTER, etc.) e ajustamos config (Exposed Schemas).
#
# Requer Personal Access Token (PAT) do tipo sbp_*.
# Geracao: https://supabase.com/dashboard/account/tokens
#
# Funcoes exportadas:
#   - Test-SupabasePat
#   - Invoke-SupabaseSql
#   - Get-SupabaseExposedSchemas
#   - Set-SupabaseExposedSchemas
#   - Add-SupabaseExposedSchema (idempotent)
#
# PS 5.1 compatible.

$SUPABASE_MGMT_API_BASE = "https://api.supabase.com"

function _Get-MgmtHeaders {
    param([string]$Pat)
    if (-not $Pat) { throw "PAT (Personal Access Token sbp_*) is required" }
    return @{
        "Authorization" = "Bearer $Pat"
        "Content-Type"  = "application/json"
    }
}

function Test-SupabasePat {
    <#
    .SYNOPSIS
    Validates a Supabase PAT by listing accessible projects.

    .OUTPUTS
    Array of projects (empty if PAT invalid).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory=$true)][string]$Pat
    )
    if (-not $Pat) { throw "Pat parameter is empty" }
    $headers = _Get-MgmtHeaders -Pat $Pat
    try {
        $r = Invoke-RestMethod -Uri "$SUPABASE_MGMT_API_BASE/v1/projects" -Method GET -Headers $headers -TimeoutSec 30
        return @($r)
    } catch {
        throw "PAT validation failed: $($_.Exception.Message)"
    }
}

function Invoke-SupabaseSql {
    <#
    .SYNOPSIS
    Run arbitrary SQL on a Supabase Postgres database via Management API.

    .PARAMETER Pat
    Supabase Personal Access Token (sbp_*).

    .PARAMETER ProjectRef
    Project reference (e.g., "urcqtpklpfyvizcgcsia").

    .PARAMETER Sql
    SQL statement(s) to execute. Multiple statements separated by ;

    .OUTPUTS
    Array of result rows (or empty for DDL).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory=$true)][string]$Pat,
        [Parameter(Mandatory=$true)][string]$ProjectRef,
        [Parameter(Mandatory=$true)][string]$Sql
    )
    if (-not $ProjectRef) { throw "ProjectRef is required" }
    if (-not $Sql)        { throw "Sql is required" }

    $headers = _Get-MgmtHeaders -Pat $Pat
    $body = @{ query = $Sql } | ConvertTo-Json -Depth 3
    $uri = "$SUPABASE_MGMT_API_BASE/v1/projects/$ProjectRef/database/query"

    try {
        $r = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -TimeoutSec 60
        return @($r)
    } catch {
        $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
        throw "SQL exec failed: $($_.Exception.Message). Body: $errBody"
    }
}

function Get-SupabaseExposedSchemas {
    <#
    .SYNOPSIS
    List schemas exposed via PostgREST REST API.

    .OUTPUTS
    Array of schema names (e.g., @("public", "manuheadfund")).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)][string]$Pat,
        [Parameter(Mandatory=$true)][string]$ProjectRef
    )
    $headers = _Get-MgmtHeaders -Pat $Pat
    $uri = "$SUPABASE_MGMT_API_BASE/v1/projects/$ProjectRef/postgrest"
    try {
        $r = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -TimeoutSec 30
        $raw = if ($r.db_schema) { [string]$r.db_schema } else { "public" }
        return @($raw -split "[,\s]+" | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    } catch {
        throw "GetExposedSchemas failed: $($_.Exception.Message)"
    }
}

function Set-SupabaseExposedSchemas {
    <#
    .SYNOPSIS
    Replaces the full list of exposed schemas via Management API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Pat,
        [Parameter(Mandatory=$true)][string]$ProjectRef,
        [Parameter(Mandatory=$true)][string[]]$Schemas
    )
    if (-not $Schemas -or @($Schemas).Count -eq 0) {
        throw "Schemas array is empty (would lock you out of REST). Provide at least 'public'."
    }
    $headers = _Get-MgmtHeaders -Pat $Pat
    $uri = "$SUPABASE_MGMT_API_BASE/v1/projects/$ProjectRef/postgrest"
    $payload = @{ db_schema = ($Schemas -join ", ") } | ConvertTo-Json -Depth 3

    try {
        $r = Invoke-RestMethod -Uri $uri -Method PATCH -Headers $headers -Body $payload -TimeoutSec 30
        return $r
    } catch {
        $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
        throw "SetExposedSchemas failed: $($_.Exception.Message). Body: $errBody"
    }
}

function Add-SupabaseExposedSchema {
    <#
    .SYNOPSIS
    Idempotent helper: ensures a single schema is in the exposed list.
    No-op when already exposed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Pat,
        [Parameter(Mandatory=$true)][string]$ProjectRef,
        [Parameter(Mandatory=$true)][string]$Schema
    )

    $current = @(Get-SupabaseExposedSchemas -Pat $Pat -ProjectRef $ProjectRef)
    if ($current -contains $Schema) {
        return [PSCustomObject]@{
            changed = $false
            schemas = $current
            message = "Schema '$Schema' already exposed."
        }
    }

    $next = @($current) + @($Schema)
    Set-SupabaseExposedSchemas -Pat $Pat -ProjectRef $ProjectRef -Schemas $next | Out-Null
    return [PSCustomObject]@{
        changed = $true
        schemas = $next
        message = "Schema '$Schema' added to exposed list."
    }
}

# Functions exported:
# - Test-SupabasePat
# - Invoke-SupabaseSql
# - Get-SupabaseExposedSchemas
# - Set-SupabaseExposedSchemas
# - Add-SupabaseExposedSchema

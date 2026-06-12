# lib_supabase_integration.ps1 -- Supabase Integration for Data Sync
# Provides functions to read/write data from Supabase tables

function Get-SupabaseConnection {
    param(
        [Parameter(Mandatory=$false)][string]$Url = $env:SUPABASE_URL,
        [Parameter(Mandatory=$false)][string]$ServiceKey = $env:SUPABASE_SERVICE_KEY
    )
    
    if (-not $Url) {
        throw "SUPABASE_URL environment variable not set"
    }
    if (-not $ServiceKey) {
        throw "SUPABASE_SERVICE_KEY environment variable not set"
    }
    
    return @{
        Url = $Url
        ServiceKey = $ServiceKey
        Headers = @{
            "Authorization" = "Bearer $ServiceKey"
            "Content-Type" = "application/json"
            "apikey" = $ServiceKey
        }
    }
}

function Get-SupabaseRecords {
    param(
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$false)][string]$Filter = "",
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    if (-not $Connection) {
        $Connection = Get-SupabaseConnection
    }
    
    $url = "$($Connection.Url)/rest/v1/$Table"
    if ($Filter) {
        $url += "?$Filter"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Get -ErrorAction Stop
        return $response
    }
    catch {
        Write-Warning "[Supabase] Error reading $Table : $_"
        return @()
    }
}

function Save-SupabaseRecords {
    param(
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$true)][PSCustomObject[]]$Records,
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    if (-not $Connection) {
        $Connection = Get-SupabaseConnection
    }
    
    if (-not $Records -or $Records.Count -eq 0) {
        return $true
    }
    
    $url = "$($Connection.Url)/rest/v1/$Table"
    $body = $Records | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Post -Body $body -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "[Supabase] Error writing to $Table : $_"
        return $false
    }
}

function Upsert-SupabaseRecords {
    param(
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$true)][PSCustomObject[]]$Records,
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    if (-not $Connection) {
        $Connection = Get-SupabaseConnection
    }
    
    if (-not $Records -or $Records.Count -eq 0) {
        return $true
    }
    
    $url = "$($Connection.Url)/rest/v1/$Table?on_conflict=id"
    $body = $Records | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Post -Body $body -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "[Supabase] Error upserting to $Table : $_"
        return $false
    }
}

function Get-FQSRegistry {
    param(
        [Parameter(Mandatory=$false)][string]$Market = "",
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    $filter = ""
    if ($Market) {
        $filter = "market=eq.$Market"
    }
    
    return Get-SupabaseRecords -Table "fqs_registry" -Filter $filter -Connection $Connection
}

function Get-ToriProximity {
    param(
        [Parameter(Mandatory=$false)][string]$Market = "",
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    $filter = ""
    if ($Market) {
        $filter = "market=eq.$Market"
    }
    
    return Get-SupabaseRecords -Table "tori_proximity" -Filter $filter -Connection $Connection
}

function Get-AlphaHistory {
    param(
        [Parameter(Mandatory=$false)][string]$Market = "",
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    $filter = ""
    if ($Market) {
        $filter = "market=eq.$Market"
    }
    
    return Get-SupabaseRecords -Table "alpha_history" -Filter $filter -Connection $Connection
}

function Get-BetaHistory {
    param(
        [Parameter(Mandatory=$false)][string]$Market = "",
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    $filter = ""
    if ($Market) {
        $filter = "market=eq.$Market"
    }
    
    return Get-SupabaseRecords -Table "beta_history" -Filter $filter -Connection $Connection
}

function Get-DrawdownHistory {
    param(
        [Parameter(Mandatory=$false)][string]$Market = "",
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    $filter = ""
    if ($Market) {
        $filter = "market=eq.$Market"
    }
    
    return Get-SupabaseRecords -Table "drawdown_history" -Filter $filter -Connection $Connection
}

function Get-RegimeState {
    param(
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    return Get-SupabaseRecords -Table "regime_state" -Connection $Connection
}

function Get-DSRGlobal {
    param(
        [Parameter(Mandatory=$false)][PSCustomObject]$Connection = $null
    )
    
    return Get-SupabaseRecords -Table "dsr_global" -Connection $Connection
}

Write-Host "[Supabase Integration] Module loaded" -ForegroundColor Green

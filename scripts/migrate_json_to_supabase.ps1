# migrate_json_to_supabase.ps1 -- Migrate JSON data to Supabase
# Reads local JSON files and populates Supabase tables

param(
    [Parameter(Mandatory=$false)][string]$SupabaseUrl = $env:SUPABASE_URL,
    [Parameter(Mandatory=$false)][string]$ServiceKey = $env:SUPABASE_SERVICE_KEY,
    [Parameter(Mandatory=$false)][string]$JournalPath = "journal"
)

if (-not $SupabaseUrl) {
    throw "SUPABASE_URL environment variable not set"
}
if (-not $ServiceKey) {
    throw "SUPABASE_SERVICE_KEY environment variable not set"
}

# Load Supabase integration library
. "$PSScriptRoot\..\agents\lib_supabase_integration.ps1"

$connection = @{
    Url = $SupabaseUrl
    ServiceKey = $ServiceKey
    Headers = @{
        "Authorization" = "Bearer $ServiceKey"
        "Content-Type" = "application/json"
        "apikey" = $ServiceKey
    }
}

$migratedCount = 0
$totalCount = 0

# Migrate FQS Registry from coin_registry.json
Write-Host "Migrating FQS Registry..." -ForegroundColor Cyan
$coinRegistryPath = Join-Path $JournalPath "coin_registry.json"
if (Test-Path $coinRegistryPath) {
    try {
        $coinRegistry = Get-Content $coinRegistryPath -Raw | ConvertFrom-Json
        $fqsRecords = @()
        
        foreach ($market in $coinRegistry.PSObject.Properties.Name) {
            $coin = $coinRegistry.$market
            $fqsRecords += @{
                market = $market
                fqs_score = $coin.fqs_score
                fqs_category = $coin.fqs_category
                quality_tier = $coin.quality_tier
                blue_chip = $coin.blue_chip
            }
        }
        
        if ($fqsRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "fqs_registry" -Records $fqsRecords -Connection $connection
            Write-Host "✓ Migrated $($fqsRecords.Count) FQS records" -ForegroundColor Green
            $migratedCount += $fqsRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating FQS Registry: $_"
    }
}
$totalCount += 1

# Migrate TORI Proximity from tori_proximity_state.json
Write-Host "Migrating TORI Proximity..." -ForegroundColor Cyan
$toriPath = Join-Path $JournalPath "tori_proximity_state.json"
if (Test-Path $toriPath) {
    try {
        $toriData = Get-Content $toriPath -Raw | ConvertFrom-Json
        $toriRecords = @()
        
        foreach ($market in $toriData.PSObject.Properties.Name) {
            $tori = $toriData.$market
            $toriRecords += @{
                market = $market
                support_level = $tori.support_level
                resistance_level = $tori.resistance_level
                proximity_score = $tori.proximity_score
            }
        }
        
        if ($toriRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "tori_proximity" -Records $toriRecords -Connection $connection
            Write-Host "✓ Migrated $($toriRecords.Count) TORI records" -ForegroundColor Green
            $migratedCount += $toriRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating TORI Proximity: $_"
    }
}
$totalCount += 1

# Migrate Alpha History from alpha_hist.json
Write-Host "Migrating Alpha History..." -ForegroundColor Cyan
$alphaPath = Join-Path $JournalPath "alpha_hist.json"
if (Test-Path $alphaPath) {
    try {
        $alphaData = Get-Content $alphaPath -Raw | ConvertFrom-Json
        $alphaRecords = @()
        
        foreach ($market in $alphaData.PSObject.Properties.Name) {
            $alpha = $alphaData.$market
            $alphaRecords += @{
                market = $market
                alpha_score = $alpha.alpha_score
                timestamp = $alpha.timestamp
            }
        }
        
        if ($alphaRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "alpha_history" -Records $alphaRecords -Connection $connection
            Write-Host "✓ Migrated $($alphaRecords.Count) Alpha records" -ForegroundColor Green
            $migratedCount += $alphaRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating Alpha History: $_"
    }
}
$totalCount += 1

# Migrate Beta History from beta_vs_btc.json
Write-Host "Migrating Beta History..." -ForegroundColor Cyan
$betaPath = Join-Path $JournalPath "beta_vs_btc.json"
if (Test-Path $betaPath) {
    try {
        $betaData = Get-Content $betaPath -Raw | ConvertFrom-Json
        $betaRecords = @()
        
        foreach ($market in $betaData.PSObject.Properties.Name) {
            $beta = $betaData.$market
            $betaRecords += @{
                market = $market
                beta_vs_btc = $beta.beta_vs_btc
                beta_category = $beta.beta_category
            }
        }
        
        if ($betaRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "beta_history" -Records $betaRecords -Connection $connection
            Write-Host "✓ Migrated $($betaRecords.Count) Beta records" -ForegroundColor Green
            $migratedCount += $betaRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating Beta History: $_"
    }
}
$totalCount += 1

# Migrate Drawdown History from tier_a_drawdown_*.json (latest)
Write-Host "Migrating Drawdown History..." -ForegroundColor Cyan
$drawdownFiles = Get-ChildItem -Path $JournalPath -Filter "tier_a_drawdown_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($drawdownFiles) {
    try {
        $drawdownData = Get-Content $drawdownFiles.FullName -Raw | ConvertFrom-Json
        $drawdownRecords = @()
        
        foreach ($market in $drawdownData.PSObject.Properties.Name) {
            $drawdown = $drawdownData.$market
            $drawdownRecords += @{
                market = $market
                max_drawdown = $drawdown.max_drawdown
                drawdown_category = $drawdown.drawdown_category
            }
        }
        
        if ($drawdownRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "drawdown_history" -Records $drawdownRecords -Connection $connection
            Write-Host "✓ Migrated $($drawdownRecords.Count) Drawdown records" -ForegroundColor Green
            $migratedCount += $drawdownRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating Drawdown History: $_"
    }
}
$totalCount += 1

# Migrate Regime State from regime_state.json
Write-Host "Migrating Regime State..." -ForegroundColor Cyan
$regimePath = Join-Path $JournalPath "regime_state.json"
if (Test-Path $regimePath) {
    try {
        $regimeData = Get-Content $regimePath -Raw | ConvertFrom-Json
        $regimeRecords = @()
        
        foreach ($market in $regimeData.PSObject.Properties.Name) {
            $regime = $regimeData.$market
            $regimeRecords += @{
                market = $market
                regime = $regime.regime
                phase = $regime.phase
                bias = $regime.bias
            }
        }
        
        if ($regimeRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "regime_state" -Records $regimeRecords -Connection $connection
            Write-Host "✓ Migrated $($regimeRecords.Count) Regime records" -ForegroundColor Green
            $migratedCount += $regimeRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating Regime State: $_"
    }
}
$totalCount += 1

# Migrate DSR Global from dsr_global.json
Write-Host "Migrating DSR Global..." -ForegroundColor Cyan
$dsrPath = Join-Path $JournalPath "dsr_global.json"
if (Test-Path $dsrPath) {
    try {
        $dsrData = Get-Content $dsrPath -Raw | ConvertFrom-Json
        $dsrRecords = @()
        
        foreach ($market in $dsrData.PSObject.Properties.Name) {
            $dsr = $dsrData.$market
            $dsrRecords += @{
                market = $market
                dsr_score = $dsr.dsr_score
                dsr_category = $dsr.dsr_category
            }
        }
        
        if ($dsrRecords.Count -gt 0) {
            Save-SupabaseRecords -Table "dsr_global" -Records $dsrRecords -Connection $connection
            Write-Host "✓ Migrated $($dsrRecords.Count) DSR records" -ForegroundColor Green
            $migratedCount += $dsrRecords.Count
        }
    }
    catch {
        Write-Warning "✗ Error migrating DSR Global: $_"
    }
}
$totalCount += 1

Write-Host "`n✅ Migration complete!" -ForegroundColor Green
Write-Host "Total records migrated: $migratedCount" -ForegroundColor Green
Write-Host "Tables processed: $totalCount" -ForegroundColor Green

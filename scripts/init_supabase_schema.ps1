# init_supabase_schema.ps1 -- Initialize Supabase Schema for ManuHeadFund
# Creates all required tables and indexes

param(
    [Parameter(Mandatory=$false)][string]$SupabaseUrl = $env:SUPABASE_URL,
    [Parameter(Mandatory=$false)][string]$ServiceKey = $env:SUPABASE_SERVICE_KEY
)

if (-not $SupabaseUrl) {
    throw "SUPABASE_URL environment variable not set"
}
if (-not $ServiceKey) {
    throw "SUPABASE_SERVICE_KEY environment variable not set"
}

$headers = @{
    "Authorization" = "Bearer $ServiceKey"
    "Content-Type" = "application/json"
    "apikey" = $ServiceKey
}

function Execute-SQL {
    param(
        [Parameter(Mandatory=$true)][string]$SQL
    )
    
    $url = "$SupabaseUrl/rest/v1/rpc/exec_sql"
    $body = @{ sql = $SQL } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ErrorAction Stop
        Write-Host "✓ SQL executed successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "✗ SQL execution failed: $_"
        return $false
    }
}

# Create schema
Write-Host "Creating manuheadfund schema..." -ForegroundColor Cyan
$schemaSql = @"
CREATE SCHEMA IF NOT EXISTS manuheadfund;
"@
Execute-SQL -SQL $schemaSql

# Create fqs_registry table
Write-Host "Creating fqs_registry table..." -ForegroundColor Cyan
$fqsSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.fqs_registry (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    fqs_score NUMERIC,
    fqs_category TEXT,
    quality_tier TEXT,
    blue_chip BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fqs_market ON manuheadfund.fqs_registry(market);
"@
Execute-SQL -SQL $fqsSql

# Create tori_proximity table
Write-Host "Creating tori_proximity table..." -ForegroundColor Cyan
$toriSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.tori_proximity (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    support_level NUMERIC,
    resistance_level NUMERIC,
    proximity_score NUMERIC,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tori_market ON manuheadfund.tori_proximity(market);
"@
Execute-SQL -SQL $toriSql

# Create alpha_history table
Write-Host "Creating alpha_history table..." -ForegroundColor Cyan
$alphaSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.alpha_history (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL,
    alpha_score NUMERIC,
    timestamp TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(market, timestamp)
);
CREATE INDEX IF NOT EXISTS idx_alpha_market ON manuheadfund.alpha_history(market);
"@
Execute-SQL -SQL $alphaSql

# Create beta_history table
Write-Host "Creating beta_history table..." -ForegroundColor Cyan
$betaSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.beta_history (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    beta_vs_btc NUMERIC,
    beta_category TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_beta_market ON manuheadfund.beta_history(market);
"@
Execute-SQL -SQL $betaSql

# Create drawdown_history table
Write-Host "Creating drawdown_history table..." -ForegroundColor Cyan
$drawdownSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.drawdown_history (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    max_drawdown NUMERIC,
    drawdown_category TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_drawdown_market ON manuheadfund.drawdown_history(market);
"@
Execute-SQL -SQL $drawdownSql

# Create regime_state table
Write-Host "Creating regime_state table..." -ForegroundColor Cyan
$regimeSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.regime_state (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    regime TEXT,
    phase TEXT,
    bias TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_regime_market ON manuheadfund.regime_state(market);
"@
Execute-SQL -SQL $regimeSql

# Create dsr_global table
Write-Host "Creating dsr_global table..." -ForegroundColor Cyan
$dsrSql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.dsr_global (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    dsr_score NUMERIC,
    dsr_category TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_dsr_market ON manuheadfund.dsr_global(market);
"@
Execute-SQL -SQL $dsrSql

Write-Host "`n✅ Schema initialization complete!" -ForegroundColor Green
Write-Host "Tables created: fqs_registry, tori_proximity, alpha_history, beta_history, drawdown_history, regime_state, dsr_global" -ForegroundColor Green

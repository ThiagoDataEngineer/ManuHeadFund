# scripts/init_supabase_schema.ps1
# Initialize Supabase schema for ManuHeadFund trading system
# Creates all necessary tables in manuheadfund schema
#
# Usage:
#   .\init_supabase_schema.ps1 -Pat "sbp_xxx" -ProjectRef "abc123"
#
# Requires:
#   - SUPABASE_URL env var (or -SupabaseUrl param)
#   - SUPABASE_SERVICE_KEY env var (or -ServiceKey param)

param(
    [string]$Pat = $env:SUPABASE_PAT,
    [string]$ProjectRef = $env:SUPABASE_PROJECT_REF,
    [string]$SupabaseUrl = $env:SUPABASE_URL,
    [string]$ServiceKey = $env:SUPABASE_SERVICE_KEY
)

$ErrorActionPreference = "Stop"

# Load lib_supabase_management if available
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$libPath = Join-Path $agentsDir "lib_supabase_management.ps1"
if (Test-Path $libPath) {
    . $libPath
} else {
    Write-Warning "lib_supabase_management.ps1 not found, using basic REST calls"
}

function Invoke-SupabaseSqlDirect {
    param(
        [Parameter(Mandatory)] [string]$Sql,
        [string]$Url = $SupabaseUrl,
        [string]$Key = $ServiceKey
    )
    
    if (-not $Url -or -not $Key) {
        throw "SUPABASE_URL and SUPABASE_SERVICE_KEY required"
    }
    
    $headers = @{
        "Authorization" = "Bearer $Key"
        "Content-Type" = "application/json"
        "apikey" = $Key
    }
    
    $body = @{ query = $Sql } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$Url/rest/v1/rpc/sql" -Method POST -Headers $headers -Body $body
        return $response
    } catch {
        Write-Error "SQL execution failed: $_"
        throw
    }
}

# SQL to create schema and tables
$sqlStatements = @(
    # Create schema
    "CREATE SCHEMA IF NOT EXISTS manuheadfund;",
    
    # fqs_registry table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.fqs_registry (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  fqs INTEGER NOT NULL,
  category TEXT NOT NULL,
  age_years INTEGER,
  supply_capped BOOLEAN,
  burn_active BOOLEAN,
  utility_score NUMERIC(3,2),
  concentration_top10 NUMERIC(3,2),
  recovered_2021_ath BOOLEAN,
  listing_years INTEGER,
  notes TEXT,
  current_price_usd NUMERIC(20,8),
  ath_all_time_usd NUMERIC(20,8),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@,
    
    # tori_proximity table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.tori_proximity (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  valid BOOLEAN NOT NULL DEFAULT FALSE,
  side TEXT,
  price NUMERIC(20,8),
  action_line NUMERIC(20,8),
  proximity_pct NUMERIC(5,2),
  touches INTEGER,
  slope_deg NUMERIC(6,2),
  rsi NUMERIC(5,2),
  vol_drying BOOLEAN,
  setup_ripening BOOLEAN,
  take_profit NUMERIC(20,8),
  stop_loss NUMERIC(20,8),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@,
    
    # alpha_history table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.alpha_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  alpha_score NUMERIC(3,2),
  win_rate NUMERIC(3,2),
  n_samples INTEGER DEFAULT 0,
  avg_alpha NUMERIC(5,2),
  losing_to_btc BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@,
    
    # beta_history table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.beta_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  beta NUMERIC(5,4) NOT NULL,
  window_days INTEGER DEFAULT 180,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@,
    
    # drawdown_history table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.drawdown_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  price NUMERIC(20,8),
  peak_7d NUMERIC(20,8),
  vs_peak_pct NUMERIC(5,2),
  status TEXT,
  flag_streak INTEGER DEFAULT 0,
  level TEXT,
  pct24h NUMERIC(5,2),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@,
    
    # regime_state table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.regime_state (
  id BIGSERIAL PRIMARY KEY,
  phase TEXT NOT NULL,
  bias TEXT,
  btc_drawdown_pct NUMERIC(5,2),
  macro_context TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@,
    
    # dsr_global table
    @"
CREATE TABLE IF NOT EXISTS manuheadfund.dsr_global (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL,
  dsr NUMERIC(5,4),
  n_trials INTEGER DEFAULT 0,
  sharpe_30d NUMERIC(5,2),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(market, updated_at)
);
"@,
    
    # Create indexes
    "CREATE INDEX IF NOT EXISTS idx_fqs_registry_market ON manuheadfund.fqs_registry(market);",
    "CREATE INDEX IF NOT EXISTS idx_fqs_registry_category ON manuheadfund.fqs_registry(category);",
    "CREATE INDEX IF NOT EXISTS idx_fqs_registry_updated ON manuheadfund.fqs_registry(updated_at DESC);",
    
    "CREATE INDEX IF NOT EXISTS idx_tori_proximity_market ON manuheadfund.tori_proximity(market);",
    "CREATE INDEX IF NOT EXISTS idx_tori_proximity_valid ON manuheadfund.tori_proximity(valid);",
    "CREATE INDEX IF NOT EXISTS idx_tori_proximity_updated ON manuheadfund.tori_proximity(updated_at DESC);",
    
    "CREATE INDEX IF NOT EXISTS idx_alpha_history_market ON manuheadfund.alpha_history(market);",
    "CREATE INDEX IF NOT EXISTS idx_alpha_history_updated ON manuheadfund.alpha_history(updated_at DESC);",
    
    "CREATE INDEX IF NOT EXISTS idx_beta_history_market ON manuheadfund.beta_history(market);",
    "CREATE INDEX IF NOT EXISTS idx_beta_history_updated ON manuheadfund.beta_history(updated_at DESC);",
    
    "CREATE INDEX IF NOT EXISTS idx_drawdown_history_market ON manuheadfund.drawdown_history(market);",
    "CREATE INDEX IF NOT EXISTS idx_drawdown_history_status ON manuheadfund.drawdown_history(status);",
    "CREATE INDEX IF NOT EXISTS idx_drawdown_history_updated ON manuheadfund.drawdown_history(updated_at DESC);",
    
    "CREATE INDEX IF NOT EXISTS idx_regime_state_updated ON manuheadfund.regime_state(updated_at DESC);",
    
    "CREATE INDEX IF NOT EXISTS idx_dsr_global_market ON manuheadfund.dsr_global(market);",
    "CREATE INDEX IF NOT EXISTS idx_dsr_global_updated ON manuheadfund.dsr_global(updated_at DESC);"
)

Write-Host "=== Supabase Schema Initialization ===" -ForegroundColor Cyan
Write-Host "URL: $SupabaseUrl" -ForegroundColor Gray
Write-Host "Schema: manuheadfund" -ForegroundColor Gray
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($sql in $sqlStatements) {
    if ([string]::IsNullOrWhiteSpace($sql)) { continue }
    
    $shortSql = if ($sql.Length -gt 60) { $sql.Substring(0, 60) + "..." } else { $sql }
    Write-Host "Executing: $shortSql" -ForegroundColor Gray -NoNewline
    
    try {
        if (Get-Command Invoke-SupabaseSql -ErrorAction SilentlyContinue) {
            Invoke-SupabaseSql -Pat $Pat -ProjectRef $ProjectRef -Sql $sql | Out-Null
        } else {
            Invoke-SupabaseSqlDirect -Sql $sql | Out-Null
        }
        Write-Host " ✓" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Success: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

if ($failCount -eq 0) {
    Write-Host ""
    Write-Host "✓ Schema initialization complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Migrate data from JSON files to Supabase"
    Write-Host "2. Update PowerShell code to use state_store backend"
    Write-Host "3. Configure GitHub Actions to write to Supabase"
    Write-Host "4. Enable RLS policies for security"
} else {
    Write-Host ""
    Write-Host "✗ Some operations failed. Check errors above." -ForegroundColor Red
    exit 1
}

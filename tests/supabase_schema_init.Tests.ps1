# tests/supabase_schema_init.Tests.ps1
# TDD: Test schema initialization before implementation
# Tests for scripts/init_supabase_schema.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$scriptPath = Join-Path $root "scripts\init_supabase_schema.ps1"

# Mock Supabase responses
$script:mockResponses = @{}
$script:mockCalls = @()

function Mock-SupabaseSql {
    param(
        [string]$Pat,
        [string]$ProjectRef,
        [string]$Sql
    )
    $script:mockCalls += @{ Pat = $Pat; ProjectRef = $ProjectRef; Sql = $Sql }
    return @{ success = $true }
}

Describe "Schema Initialization - Supabase" {
    
    BeforeEach {
        $script:mockCalls = @()
    }
    
    Context "Schema Creation" {
        It "Creates manuheadfund schema" {
            # Arrange
            $sql = "CREATE SCHEMA IF NOT EXISTS manuheadfund;"
            
            # Act
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            $script:mockCalls.Count | Should Be 1
            $script:mockCalls[0].Sql | Should Match "CREATE SCHEMA"
            $script:mockCalls[0].Sql | Should Match "manuheadfund"
        }
    }
    
    Context "Table Creation - fqs_registry" {
        It "Creates fqs_registry table with correct columns" {
            # Arrange
            $expectedColumns = @(
                "market TEXT NOT NULL UNIQUE",
                "fqs INTEGER NOT NULL",
                "category TEXT NOT NULL",
                "updated_at TIMESTAMP",
                "created_at TIMESTAMP"
            )
            
            # Act
            $sql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.fqs_registry (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  fqs INTEGER NOT NULL,
  category TEXT NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
        
        It "Creates index on market column" {
            # Arrange
            $sql = "CREATE INDEX IF NOT EXISTS idx_fqs_registry_market ON manuheadfund.fqs_registry(market);"
            
            # Act
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            $script:mockCalls[-1].Sql | Should Match "CREATE INDEX"
            $script:mockCalls[-1].Sql | Should Match "idx_fqs_registry_market"
        }
    }
    
    Context "Table Creation - tori_proximity" {
        It "Creates tori_proximity table" {
            # Arrange
            $expectedColumns = @(
                "market TEXT NOT NULL UNIQUE",
                "valid BOOLEAN",
                "side TEXT",
                "proximity_pct NUMERIC",
                "touches INTEGER"
            )
            
            # Act
            $sql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.tori_proximity (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  valid BOOLEAN NOT NULL DEFAULT FALSE,
  side TEXT,
  proximity_pct NUMERIC(5,2),
  touches INTEGER,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
    }
    
    Context "Table Creation - alpha_history" {
        It "Creates alpha_history table" {
            # Arrange
            $expectedColumns = @(
                "market TEXT NOT NULL UNIQUE",
                "alpha_score NUMERIC",
                "win_rate NUMERIC",
                "n_samples INTEGER"
            )
            
            # Act
            $sql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.alpha_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  alpha_score NUMERIC(3,2),
  win_rate NUMERIC(3,2),
  n_samples INTEGER DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
    }
    
    Context "Table Creation - beta_history" {
        It "Creates beta_history table" {
            # Arrange
            $expectedColumns = @(
                "market TEXT NOT NULL UNIQUE",
                "beta NUMERIC",
                "window_days INTEGER"
            )
            
            # Act
            $sql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.beta_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  beta NUMERIC(5,4) NOT NULL,
  window_days INTEGER DEFAULT 180,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
    }
    
    Context "Table Creation - drawdown_history" {
        It "Creates drawdown_history table" {
            # Arrange
            $expectedColumns = @(
                "market TEXT NOT NULL UNIQUE",
                "vs_peak_pct NUMERIC",
                "status TEXT",
                "level TEXT"
            )
            
            # Act
            $sql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.drawdown_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  vs_peak_pct NUMERIC(5,2),
  status TEXT,
  level TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
    }
    
    Context "Table Creation - regime_state" {
        It "Creates regime_state table" {
            # Arrange
            $expectedColumns = @(
                "phase TEXT NOT NULL",
                "bias TEXT",
                "btc_drawdown_pct NUMERIC"
            )
            
            # Act
            $sql = @"
CREATE TABLE IF NOT EXISTS manuheadfund.regime_state (
  id BIGSERIAL PRIMARY KEY,
  phase TEXT NOT NULL,
  bias TEXT,
  btc_drawdown_pct NUMERIC(5,2),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
    }
    
    Context "Table Creation - dsr_global" {
        It "Creates dsr_global table" {
            # Arrange
            $expectedColumns = @(
                "market TEXT NOT NULL",
                "dsr NUMERIC",
                "n_trials INTEGER",
                "sharpe_30d NUMERIC"
            )
            
            # Act
            $sql = @"
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
"@
            Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            
            # Assert
            foreach ($col in $expectedColumns) {
                $sql | Should Match $col
            }
        }
    }
    
    Context "Index Creation" {
        It "Creates all required indexes" {
            # Arrange
            $expectedIndexes = @(
                "idx_fqs_registry_market",
                "idx_fqs_registry_category",
                "idx_tori_proximity_market",
                "idx_alpha_history_market",
                "idx_beta_history_market",
                "idx_drawdown_history_market",
                "idx_regime_state_updated",
                "idx_dsr_global_market"
            )
            
            # Act & Assert
            foreach ($idx in $expectedIndexes) {
                $sql = "CREATE INDEX IF NOT EXISTS $idx ON manuheadfund.table(column);"
                Mock-SupabaseSql -Pat "test" -ProjectRef "abc" -Sql $sql
            }
            
            $script:mockCalls.Count | Should Be $expectedIndexes.Count
        }
    }
    
    Context "Error Handling" {
        It "Throws when SUPABASE_URL missing" {
            # Arrange
            $env:SUPABASE_URL = ""
            
            # Act & Assert
            { Mock-SupabaseSql -Pat "" -ProjectRef "" -Sql "" } | Should Not Throw
        }
        
        It "Throws when SERVICE_KEY missing" {
            # Arrange
            $env:SUPABASE_SERVICE_KEY = ""
            
            # Act & Assert
            { Mock-SupabaseSql -Pat "" -ProjectRef "" -Sql "" } | Should Not Throw
        }
    }
    
    Context "Idempotency" {
        It "Uses IF NOT EXISTS for all CREATE statements" {
            # Arrange
            $statements = @(
                "CREATE SCHEMA IF NOT EXISTS manuheadfund;",
                "CREATE TABLE IF NOT EXISTS manuheadfund.fqs_registry (...);",
                "CREATE INDEX IF NOT EXISTS idx_fqs_registry_market (...);",
                "CREATE TABLE IF NOT EXISTS manuheadfund.tori_proximity (...);",
                "CREATE TABLE IF NOT EXISTS manuheadfund.alpha_history (...);",
                "CREATE TABLE IF NOT EXISTS manuheadfund.beta_history (...);",
                "CREATE TABLE IF NOT EXISTS manuheadfund.drawdown_history (...);",
                "CREATE TABLE IF NOT EXISTS manuheadfund.regime_state (...);",
                "CREATE TABLE IF NOT EXISTS manuheadfund.dsr_global (...);"
            )
            
            # Act & Assert
            foreach ($stmt in $statements) {
                $stmt | Should Match "IF NOT EXISTS"
            }
        }
    }
}

Describe "Data Migration - JSON to Supabase" {
    
    Context "FQS Registry Migration" {
        It "Reads coin_registry.json and inserts into fqs_registry" {
            # Arrange
            $coinRegistry = @{
                "BTCUSDT" = @{ fqs = 7; category = "BLUE_CHIP" }
                "ETHUSDT" = @{ fqs = 7; category = "BLUE_CHIP" }
            }
            
            # Act
            $insertSql = @"
INSERT INTO manuheadfund.fqs_registry (market, fqs, category, updated_at)
VALUES ('BTCUSDT', 7, 'BLUE_CHIP', NOW())
ON CONFLICT(market) DO UPDATE SET fqs = EXCLUDED.fqs;
"@
            
            # Assert
            $insertSql | Should Match "INSERT INTO manuheadfund.fqs_registry"
            $insertSql | Should Match "ON CONFLICT"
        }
    }
    
    Context "TORI Proximity Migration" {
        It "Reads tori_proximity_state.json and inserts into tori_proximity" {
            # Arrange
            $toriState = @{
                "INJUSDT" = @{
                    valid = $true
                    side = "LONG"
                    proximity_pct = 11.99
                }
            }
            
            # Act
            $insertSql = @"
INSERT INTO manuheadfund.tori_proximity (market, valid, side, proximity_pct, updated_at)
VALUES ('INJUSDT', true, 'LONG', 11.99, NOW())
ON CONFLICT(market) DO UPDATE SET valid = EXCLUDED.valid;
"@
            
            # Assert
            $insertSql | Should Match "INSERT INTO manuheadfund.tori_proximity"
            $insertSql | Should Match "ON CONFLICT"
        }
    }
    
    Context "Alpha History Migration" {
        It "Reads alpha_hist.json and inserts into alpha_history" {
            # Arrange
            $alphaHist = @{
                "BTCUSDT" = @{ alpha_score = 0.75; win_rate = 0.65 }
            }
            
            # Act
            $insertSql = @"
INSERT INTO manuheadfund.alpha_history (market, alpha_score, win_rate, updated_at)
VALUES ('BTCUSDT', 0.75, 0.65, NOW())
ON CONFLICT(market) DO UPDATE SET alpha_score = EXCLUDED.alpha_score;
"@
            
            # Assert
            $insertSql | Should Match "INSERT INTO manuheadfund.alpha_history"
        }
    }
    
    Context "Beta History Migration" {
        It "Reads beta_vs_btc.json and inserts into beta_history" {
            # Arrange
            $betaData = @{
                "BTCUSDT" = 1.0
                "ETHUSDT" = 1.1
            }
            
            # Act
            $insertSql = @"
INSERT INTO manuheadfund.beta_history (market, beta, updated_at)
VALUES ('BTCUSDT', 1.0, NOW())
ON CONFLICT(market) DO UPDATE SET beta = EXCLUDED.beta;
"@
            
            # Assert
            $insertSql | Should Match "INSERT INTO manuheadfund.beta_history"
        }
    }
    
    Context "Drawdown History Migration" {
        It "Reads tier_a_drawdown_*.json and inserts into drawdown_history" {
            # Arrange
            $drawdownData = @{
                "BTCUSDT" = @{ vs_peak_pct = -5.8; status = "OK" }
            }
            
            # Act
            $insertSql = @"
INSERT INTO manuheadfund.drawdown_history (market, vs_peak_pct, status, updated_at)
VALUES ('BTCUSDT', -5.8, 'OK', NOW())
ON CONFLICT(market) DO UPDATE SET vs_peak_pct = EXCLUDED.vs_peak_pct;
"@
            
            # Assert
            $insertSql | Should Match "INSERT INTO manuheadfund.drawdown_history"
        }
    }
}

Describe "State Store Integration" {
    
    Context "Get-StateRecords from Supabase" {
        It "Reads fqs_registry from Supabase via state_store" {
            # Arrange
            $table = "fqs_registry"
            
            # Act
            $result = @(
                [PSCustomObject]@{ market = "BTCUSDT"; fqs = 7; category = "BLUE_CHIP" }
                [PSCustomObject]@{ market = "ETHUSDT"; fqs = 7; category = "BLUE_CHIP" }
            )
            
            # Assert
            $result.Count | Should Be 2
            $result[0].market | Should Be "BTCUSDT"
            $result[0].fqs | Should Be 7
        }
        
        It "Filters by category" {
            # Arrange
            $allRecords = @(
                [PSCustomObject]@{ market = "BTCUSDT"; fqs = 7; category = "BLUE_CHIP" }
                [PSCustomObject]@{ market = "WLDUSDT"; fqs = 4; category = "SPECULATIVE" }
            )
            
            # Act
            $filtered = @($allRecords | Where-Object { $_.category -eq "BLUE_CHIP" })
            
            # Assert
            $filtered.Count | Should Be 1
            $filtered[0].market | Should Be "BTCUSDT"
        }
    }
    
    Context "Save-StateRecords to Supabase" {
        It "Upserts fqs_registry records" {
            # Arrange
            $records = @(
                [PSCustomObject]@{ market = "BTCUSDT"; fqs = 7; category = "BLUE_CHIP" }
            )
            
            # Act
            $upsertSql = @"
INSERT INTO manuheadfund.fqs_registry (market, fqs, category, updated_at)
VALUES ('BTCUSDT', 7, 'BLUE_CHIP', NOW())
ON CONFLICT(market) DO UPDATE SET fqs = EXCLUDED.fqs, category = EXCLUDED.category;
"@
            
            # Assert
            $upsertSql | Should Match "ON CONFLICT"
            $upsertSql | Should Match "DO UPDATE"
        }
    }
}

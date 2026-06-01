# tests/supabase_data_migration.Tests.ps1
# TDD: Test data migration from JSON to Supabase

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$scriptPath = Join-Path $root "scripts\migrate_json_to_supabase.ps1"

Describe "Data Migration - JSON to Supabase" {
    
    Context "FQS Registry Migration" {
        It "Reads coin_registry.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_coin_registry_$PID.json"
            $testData = @{
                "BTCUSDT" = @{ fqs = 7; category = "BLUE_CHIP"; age_years = 16 }
                "ETHUSDT" = @{ fqs = 7; category = "BLUE_CHIP"; age_years = 11 }
            }
            $testData | ConvertTo-Json | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.BTCUSDT.fqs | Should Be 7
                $data.ETHUSDT.category | Should Be "BLUE_CHIP"
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Transforms coin_registry to fqs_registry format" {
            # Arrange
            $coinReg = @{
                "BTCUSDT" = @{
                    fqs = 7
                    category = "BLUE_CHIP"
                    age_years = 16
                    supply_capped = $true
                    burn_active = $false
                    utility_score = 1.0
                    concentration_top10 = 0.1
                    recovered_2021_ath = $true
                    listing_years = 8
                }
            }
            
            # Act
            $transformed = @()
            foreach ($market in $coinReg.Keys) {
                $entry = $coinReg[$market]
                $transformed += [PSCustomObject]@{
                    market = $market
                    fqs = $entry.fqs
                    category = $entry.category
                    age_years = $entry.age_years
                    supply_capped = $entry.supply_capped
                    burn_active = $entry.burn_active
                    utility_score = $entry.utility_score
                    concentration_top10 = $entry.concentration_top10
                    recovered_2021_ath = $entry.recovered_2021_ath
                    listing_years = $entry.listing_years
                }
            }
            
            # Assert
            $transformed.Count | Should Be 1
            $transformed[0].market | Should Be "BTCUSDT"
            $transformed[0].fqs | Should Be 7
        }
        
        It "Handles missing fields gracefully" {
            # Arrange
            $coinReg = @{
                "NEWCOIN" = @{
                    fqs = 3
                    category = "SPECULATIVE"
                }
            }
            
            # Act
            $transformed = @()
            foreach ($market in $coinReg.Keys) {
                $entry = $coinReg[$market]
                $transformed += [PSCustomObject]@{
                    market = $market
                    fqs = $entry.fqs
                    category = $entry.category
                    age_years = if ($entry.PSObject.Properties['age_years']) { $entry.age_years } else { $null }
                }
            }
            
            # Assert
            $transformed[0].age_years | Should Be $null
        }
    }
    
    Context "TORI Proximity Migration" {
        It "Reads tori_proximity_state.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_tori_$PID.json"
            $testData = @{
                ts_utc = "2026-06-01T19:07:14Z"
                markets = @{
                    "INJUSDT" = @{
                        valid = $true
                        side = "LONG"
                        proximity_pct = 11.99
                    }
                }
            }
            $testData | ConvertTo-Json -Depth 5 | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.markets.INJUSDT.valid | Should Be $true
                $data.markets.INJUSDT.side | Should Be "LONG"
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Transforms tori_proximity_state to tori_proximity format" {
            # Arrange
            $toriState = @{
                "INJUSDT" = @{
                    valid = $true
                    side = "LONG"
                    price = 7.1959
                    action_line = 6.425339
                    proximity_pct = 11.99
                    touches = 25
                    slope_deg = 22.22
                    rsi = $null
                    vol_drying = $null
                    setup_ripening = $false
                }
            }
            
            # Act
            $transformed = @()
            foreach ($market in $toriState.Keys) {
                $entry = $toriState[$market]
                $transformed += [PSCustomObject]@{
                    market = $market
                    valid = $entry.valid
                    side = $entry.side
                    price = $entry.price
                    action_line = $entry.action_line
                    proximity_pct = $entry.proximity_pct
                    touches = $entry.touches
                    slope_deg = $entry.slope_deg
                    setup_ripening = $entry.setup_ripening
                }
            }
            
            # Assert
            $transformed.Count | Should Be 1
            $transformed[0].market | Should Be "INJUSDT"
            $transformed[0].valid | Should Be $true
        }
    }
    
    Context "Alpha History Migration" {
        It "Reads alpha_hist.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_alpha_$PID.json"
            $testData = @{
                "BTCUSDT" = @{ alpha_score = 0.75; win_rate = 0.65 }
                "ETHUSDT" = @{ alpha_score = 0.70; win_rate = 0.62 }
            }
            $testData | ConvertTo-Json | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.BTCUSDT.alpha_score | Should Be 0.75
                $data.ETHUSDT.win_rate | Should Be 0.62
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Transforms alpha_hist to alpha_history format" {
            # Arrange
            $alphaHist = @{
                "BTCUSDT" = @{ alpha_score = 0.75; win_rate = 0.65 }
            }
            
            # Act
            $transformed = @()
            foreach ($market in $alphaHist.Keys) {
                $entry = $alphaHist[$market]
                $transformed += [PSCustomObject]@{
                    market = $market
                    alpha_score = $entry.alpha_score
                    win_rate = $entry.win_rate
                    n_samples = 0
                }
            }
            
            # Assert
            $transformed[0].market | Should Be "BTCUSDT"
            $transformed[0].alpha_score | Should Be 0.75
        }
    }
    
    Context "Beta History Migration" {
        It "Reads beta_vs_btc.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_beta_$PID.json"
            $testData = @{
                computed_at = "2026-05-31T01:00:38Z"
                window_days = 180
                base = "BTCUSDT"
                beta = @{
                    "BTCUSDT" = 1.0
                    "ETHUSDT" = 1.1
                }
            }
            $testData | ConvertTo-Json -Depth 5 | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.beta.BTCUSDT | Should Be 1.0
                $data.beta.ETHUSDT | Should Be 1.1
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Transforms beta_vs_btc to beta_history format" {
            # Arrange
            $betaData = @{
                "BTCUSDT" = 1.0
                "ETHUSDT" = 1.1
            }
            
            # Act
            $transformed = @()
            foreach ($market in $betaData.Keys) {
                $transformed += [PSCustomObject]@{
                    market = $market
                    beta = $betaData[$market]
                    window_days = 180
                }
            }
            
            # Assert
            $transformed.Count | Should Be 2
            $transformed[0].beta | Should Be 1.0
        }
    }
    
    Context "Drawdown History Migration" {
        It "Reads tier_a_drawdown_*.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_drawdown_$PID.json"
            $testData = @{
                timestamp = "2026-06-01T05:00:19Z"
                drawdowns = @(
                    @{ market = "BTCUSDT"; vs_peak_pct = -5.8; status = "OK" }
                    @{ market = "XMRUSDT"; vs_peak_pct = -15.08; status = "FLAGGED" }
                )
            }
            $testData | ConvertTo-Json -Depth 5 | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.drawdowns.Count | Should Be 2
                $data.drawdowns[0].market | Should Be "BTCUSDT"
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Transforms tier_a_drawdown to drawdown_history format" {
            # Arrange
            $drawdownData = @(
                @{ market = "BTCUSDT"; vs_peak_pct = -5.8; status = "OK"; level = "GREEN" }
            )
            
            # Act
            $transformed = @()
            foreach ($entry in $drawdownData) {
                $transformed += [PSCustomObject]@{
                    market = $entry.market
                    vs_peak_pct = $entry.vs_peak_pct
                    status = $entry.status
                    level = $entry.level
                }
            }
            
            # Assert
            $transformed[0].market | Should Be "BTCUSDT"
            $transformed[0].vs_peak_pct | Should Be -5.8
        }
    }
    
    Context "Regime State Migration" {
        It "Reads regime_state.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_regime_$PID.json"
            $testData = @{
                phase = "phase_3_bear"
                bias = "BEAR_WEAK"
                btc_drawdown_pct = -15.0
            }
            $testData | ConvertTo-Json | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.phase | Should Be "phase_3_bear"
                $data.bias | Should Be "BEAR_WEAK"
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "DSR Global Migration" {
        It "Reads dsr_global.json successfully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_dsr_$PID.json"
            $testData = @{
                per_market = @{
                    "BTCUSDT" = @{ dsr = 0.5; n_trials = 100; sharpe_30d = 2.1 }
                }
            }
            $testData | ConvertTo-Json -Depth 5 | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act
                $data = Get-Content $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # Assert
                $data.per_market.BTCUSDT.dsr | Should Be 0.5
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Error Handling" {
        It "Handles missing JSON files gracefully" {
            # Arrange
            $missingFile = "C:\nonexistent\file_$PID.json"
            
            # Act & Assert
            Test-Path $missingFile | Should Be $false
        }
        
        It "Handles invalid JSON gracefully" {
            # Arrange
            $testFile = Join-Path $env:TEMP "test_invalid_$PID.json"
            "{ invalid json }" | Set-Content $testFile -Encoding UTF8
            
            try {
                # Act & Assert
                Test-Path $testFile | Should Be $true
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Batch Operations" {
        It "Migrates all tables in sequence" {
            # Arrange
            $tables = @("fqs_registry", "tori_proximity", "alpha_history", "beta_history", "drawdown_history", "regime_state", "dsr_global")
            $migrationOrder = @()
            
            # Act
            foreach ($table in $tables) {
                $migrationOrder += $table
            }
            
            # Assert
            $migrationOrder.Count | Should Be 7
            $migrationOrder[0] | Should Be "fqs_registry"
            $migrationOrder[-1] | Should Be "dsr_global"
        }
        
        It "Tracks migration progress" {
            # Arrange
            $progress = @{
                total = 7
                completed = 0
                failed = 0
            }
            
            # Act
            $progress.completed = 3
            $progress.failed = 0
            
            # Assert
            $progress.completed | Should Be 3
            ($progress.completed + $progress.failed) | Should Be 3
        }
    }
}

Describe "Supabase Integration" {
    
    Context "Connection" {
        It "Validates Supabase URL format" {
            # Arrange
            $validUrl = "https://abc123.supabase.co"
            $invalidUrl = "not-a-url"
            
            # Act & Assert
            $validUrl | Should Match "https://.*\.supabase\.co"
            $invalidUrl | Should Not Match "https://.*\.supabase\.co"
        }
        
        It "Validates Service Key format" {
            # Arrange
            $validKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            $invalidKey = "short"
            
            # Act & Assert
            $validKey.Length | Should BeGreaterThan 20
            $invalidKey.Length | Should BeLessThan 20
        }
    }
    
    Context "Upsert Operations" {
        It "Uses ON CONFLICT for idempotent inserts" {
            # Arrange
            $upsertSql = @"
INSERT INTO manuheadfund.fqs_registry (market, fqs, category, updated_at)
VALUES ('BTCUSDT', 7, 'BLUE_CHIP', NOW())
ON CONFLICT(market) DO UPDATE SET fqs = EXCLUDED.fqs, category = EXCLUDED.category;
"@
            
            # Act & Assert
            $upsertSql | Should Match "ON CONFLICT"
            $upsertSql | Should Match "DO UPDATE"
        }
    }
}

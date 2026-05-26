# lib_trailing.ps1 — state_store integration TDD
#
# Etapa 2.2 — Refactor Get-TrailingPositions / Save-TrailingPositions para
# usar state_store quando $global:TRAILING_USE_STATE_STORE = $true.
#
# Default: legacy file (TRAILING_FILE) — back-compat total.
# Opt-in: state_store backend (local ou supabase) via global flag.
#
# pk_id calculation:
#   - Legacy/Standard:  pk_id = market
#   - Moon Bag:         pk_id = "{market}:{moonBagKind}" (harvest|moon)

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")

# Mock CoinEx-GetTicker para evitar dependencia em rede em tests
function CoinEx-GetTicker {
    param($market)
    return [PSCustomObject]@{ last = 100.0 }
}
function Send-TelegramAlert {
    param($Message)
    return $true
}

. (Join-Path $agentsDir "lib_trailing.ps1")

Describe "lib_trailing: state_store opt-in via global flag" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ts_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
        $global:TRAILING_USE_STATE_STORE = $true
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_LOCAL_DIR, TRAILING_USE_STATE_STORE -Scope Global -ErrorAction SilentlyContinue
    }

    It "Save-TrailingPositions writes to state_store table 'trailing_positions'" {
        $pos = [PSCustomObject]@{
            market = "BTCUSDT"; side = "LONG"; entry = 50000; stop = 49000; target = 52000
            phase = 0; peak = 50000; stopCurrent = 49000; active = $true
            openedAt = "2026-05-25 12:00:00"; updatedAt = "2026-05-25 12:00:00"
        }
        Save-TrailingPositions -Positions @($pos)

        $rows = @(Get-StateRecords -Table "trailing_positions")
        $rows.Count | Should Be 1
        $rows[0].market | Should Be "BTCUSDT"
    }

    It "Get-TrailingPositions reads from state_store table" {
        $pos = [PSCustomObject]@{
            market = "ETHUSDT"; side = "LONG"; entry = 3000; stop = 2900; target = 3200
            phase = 0; peak = 3000; stopCurrent = 2900; active = $true
            openedAt = "2026-05-25 12:00:00"; updatedAt = "2026-05-25 12:00:00"
        }
        Save-TrailingPositions -Positions @($pos)

        $back = @(Get-TrailingPositions)
        $back.Count | Should Be 1
        $back[0].market | Should Be "ETHUSDT"
    }

    It "Round-trip: save 2 positions then get returns 2" {
        $a = [PSCustomObject]@{ market = "BTCUSDT"; side="LONG"; entry=50000; stop=49000; target=52000; phase=0; peak=50000; stopCurrent=49000; active=$true; openedAt="ts"; updatedAt="ts" }
        $b = [PSCustomObject]@{ market = "ETHUSDT"; side="LONG"; entry=3000;  stop=2900;  target=3200;  phase=0; peak=3000;  stopCurrent=2900;  active=$true; openedAt="ts"; updatedAt="ts" }
        Save-TrailingPositions -Positions @($a, $b)

        $back = @(Get-TrailingPositions)
        $back.Count | Should Be 2
    }

    It "Update preserves other positions (PK-based upsert)" {
        $a = [PSCustomObject]@{ market = "BTCUSDT"; side="LONG"; entry=50000; stop=49000; target=52000; phase=0; peak=50000; stopCurrent=49000; active=$true; openedAt="ts"; updatedAt="ts" }
        $b = [PSCustomObject]@{ market = "ETHUSDT"; side="LONG"; entry=3000;  stop=2900;  target=3200;  phase=0; peak=3000;  stopCurrent=2900;  active=$true; openedAt="ts"; updatedAt="ts" }
        Save-TrailingPositions -Positions @($a, $b)

        # Update only BTC
        $aUpdated = [PSCustomObject]@{ market = "BTCUSDT"; side="LONG"; entry=50000; stop=49500; target=52000; phase=1; peak=51000; stopCurrent=49500; active=$true; openedAt="ts"; updatedAt="ts2" }
        Save-TrailingPositions -Positions @($aUpdated, $b)

        $back = @(Get-TrailingPositions)
        $back.Count | Should Be 2
        $btc = $back | Where-Object { $_.market -eq "BTCUSDT" }
        $btc.phase | Should Be 1
        $btc.stopCurrent | Should Be 49500
    }

    It "Moon Bag legs: 2 entries with same market but different moonBagKind" {
        $harvest = [PSCustomObject]@{
            market = "BNBUSDT"; side="LONG"; entry=647; stop=634; target=679
            phase=0; peak=647; stopCurrent=634; active=$true
            openedAt="ts"; updatedAt="ts"
            moonBagPairId = "abc"; moonBagKind = "harvest"
        }
        $moon = [PSCustomObject]@{
            market = "BNBUSDT"; side="LONG"; entry=647; stop=582; target=841
            phase=0; peak=647; stopCurrent=582; active=$true
            openedAt="ts"; updatedAt="ts"
            moonBagPairId = "abc"; moonBagKind = "moon"
        }
        Save-TrailingPositions -Positions @($harvest, $moon)

        $back = @(Get-TrailingPositions)
        $back.Count | Should Be 2

        # Count harvest + moon legs (PS 5.1 Where-Object PSObject filter)
        $harvestCount = 0
        $moonCount = 0
        foreach ($p in $back) {
            if ($p.PSObject.Properties['moonBagKind']) {
                if ([string]$p.moonBagKind -eq "harvest") { $harvestCount++ }
                if ([string]$p.moonBagKind -eq "moon")    { $moonCount++ }
            }
        }
        $harvestCount | Should Be 1
        $moonCount    | Should Be 1
    }
}

Describe "lib_trailing: legacy file path (default behavior)" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "tslc_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $script:savedTrailingFile = $script:TRAILING_FILE
        # Simulate redirecting TRAILING_FILE to tmpDir for isolation
        $script:TRAILING_FILE = Join-Path $script:tmpDir "trailing_positions.json"
        # Ensure global flag is OFF (default)
        Remove-Variable -Name TRAILING_USE_STATE_STORE -Scope Global -ErrorAction SilentlyContinue
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        $script:TRAILING_FILE = $script:savedTrailingFile
    }

    It "Default: writes to legacy TRAILING_FILE not state_store" {
        $pos = [PSCustomObject]@{ market="ABC"; side="LONG"; entry=1; stop=0.9; target=1.5; phase=0; peak=1; stopCurrent=0.9; active=$true; openedAt="ts"; updatedAt="ts" }
        Save-TrailingPositions -Positions @($pos)
        Test-Path $script:TRAILING_FILE | Should Be $true
    }
}

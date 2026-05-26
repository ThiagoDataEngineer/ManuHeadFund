# lib_moon_bag.ps1 — state_store integration TDD
#
# Etapa 2.3 — Refactor para Add-MoonBagPair, Get-MoonBagPositions e Update-MoonBagReview
# usarem state_store (via lib_trailing wrapper Save-TrailingPositions / Get-TrailingPositions)
# quando $global:TRAILING_USE_STATE_STORE = $true.
#
# Default: legacy file (journal/trailing_positions.json) — back-compat total.
# Opt-in: state_store backend.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")

# Mocks dependencias
function CoinEx-GetTicker { param($market) return [PSCustomObject]@{ last = 100.0 } }
function Send-TelegramAlert { param($Message) return $true }

. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_moon_bag.ps1")

Describe "Moon Bag with state_store: opt-in respect" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "mbss_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
        $global:TRAILING_USE_STATE_STORE = $true
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_LOCAL_DIR, TRAILING_USE_STATE_STORE -Scope Global -ErrorAction SilentlyContinue
    }

    It "Add-MoonBagPair writes 2 legs to state_store table 'trailing_positions'" {
        Add-MoonBagPair -Market "BNBUSDT" -Side "LONG" -Entry 647 -Size 1000 | Out-Null

        $rows = @(Get-StateRecords -Table "trailing_positions")
        $rows.Count | Should Be 2
    }

    It "Add-MoonBagPair: harvest leg has correct target +5%" {
        Add-MoonBagPair -Market "BTCUSDT" -Side "LONG" -Entry 50000 -Size 1000 | Out-Null

        $rows = @(Get-StateRecords -Table "trailing_positions")
        $harvest = $null
        foreach ($r in $rows) {
            if ([string]$r.moonBagKind -eq "harvest") { $harvest = $r }
        }
        $harvest | Should Not BeNullOrEmpty
        $harvest.target | Should Be 52500
    }

    It "Add-MoonBagPair: moon leg has correct stop -10%" {
        Add-MoonBagPair -Market "ETHUSDT" -Side "LONG" -Entry 3000 -Size 1000 | Out-Null

        $rows = @(Get-StateRecords -Table "trailing_positions")
        $moon = $null
        foreach ($r in $rows) {
            if ([string]$r.moonBagKind -eq "moon") { $moon = $r }
        }
        $moon | Should Not BeNullOrEmpty
        $moon.stop | Should Be 2700
    }

    It "Get-MoonBagPositions reads from state_store and filters by moonBagKind" {
        Add-MoonBagPair -Market "SOLUSDT" -Side "LONG" -Entry 100 -Size 500 | Out-Null

        $mbPositions = @(Get-MoonBagPositions)
        $mbPositions.Count | Should Be 2

        $kinds = @()
        foreach ($p in $mbPositions) {
            if ($p.PSObject.Properties['moonBagKind']) {
                $kinds += [string]$p.moonBagKind
            }
        }
        ($kinds -contains "harvest") | Should Be $true
        ($kinds -contains "moon") | Should Be $true
    }

    It "Get-MoonBagPositions ignores non-moonBag rows" {
        # Add a regular trailing position (no moonBagKind)
        $regular = [PSCustomObject]@{
            market = "REGULAR"; side = "LONG"
            entry = 100; stop = 95; target = 110
            phase = 0; peak = 100; stopCurrent = 95; active = $true
            openedAt = "ts"; updatedAt = "ts"
        }
        Save-TrailingPositions -Positions @($regular)

        # Add a moon bag pair
        Add-MoonBagPair -Market "MOONBAG" -Side "LONG" -Entry 200 -Size 500 | Out-Null

        $mb = @(Get-MoonBagPositions)
        $mb.Count | Should Be 2  # Apenas as 2 legs do moon bag, nao a regular

        $markets = @()
        foreach ($p in $mb) { $markets += [string]$p.market }
        ($markets -contains "MOONBAG") | Should Be $true
        ($markets -contains "REGULAR") | Should Be $false
    }

    It "ActiveOnly filter respeitado" {
        Add-MoonBagPair -Market "ACT1" -Side "LONG" -Entry 100 -Size 500 | Out-Null

        # Mark all positions inactive directly via state_store
        $allRows = @(Get-StateRecords -Table "trailing_positions")
        $deactivated = @()
        foreach ($r in $allRows) {
            $copy = [PSCustomObject]@{}
            foreach ($prop in $r.PSObject.Properties) {
                $copy | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            }
            $copy.active = $false
            $deactivated += $copy
        }
        Save-StateRecords -Table "trailing_positions" -Records $deactivated -PrimaryKey "pk_id"

        $activeOnly = @(Get-MoonBagPositions -ActiveOnly)
        $activeOnly.Count | Should Be 0

        $all = @(Get-MoonBagPositions)
        $all.Count | Should Be 2
    }

    It "Two markets with Moon Bag: 4 legs total, no PK collision" {
        Add-MoonBagPair -Market "AAA" -Side "LONG" -Entry 100 -Size 500 | Out-Null
        Add-MoonBagPair -Market "BBB" -Side "LONG" -Entry 200 -Size 500 | Out-Null

        $all = @(Get-MoonBagPositions)
        $all.Count | Should Be 4

        # Each market has both legs
        $aaaCount = 0; $bbbCount = 0
        foreach ($p in $all) {
            if ([string]$p.market -eq "AAA") { $aaaCount++ }
            if ([string]$p.market -eq "BBB") { $bbbCount++ }
        }
        $aaaCount | Should Be 2
        $bbbCount | Should Be 2
    }
}

Describe "Moon Bag legacy file (default off-flag)" {

    BeforeEach {
        # Ensure flag is OFF
        Remove-Variable -Name TRAILING_USE_STATE_STORE -Scope Global -ErrorAction SilentlyContinue
    }

    It "Without flag: Add-MoonBagPair still works via legacy path" {
        $tmpJournal = Join-Path $env:TEMP "mb_legacy_$PID_$(Get-Random).json"
        try {
            $r = Add-MoonBagPair -Market "LEG" -Side "LONG" -Entry 100 -Size 500 -JournalPath $tmpJournal
            $r.harvest | Should Not BeNullOrEmpty
            $r.moon | Should Not BeNullOrEmpty
            Test-Path $tmpJournal | Should Be $true
        } finally {
            if (Test-Path $tmpJournal) { Remove-Item $tmpJournal -Force }
        }
    }
}

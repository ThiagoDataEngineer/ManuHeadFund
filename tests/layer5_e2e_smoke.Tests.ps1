# Smoke test E2E: Register-PositionTrailing decide caminho correto
# em condicoes que simulam o fluxo real do scan_master.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_trailing.ps1")  # Add-TrailingPosition real
. (Join-Path $agentsDir "lib_moon_bag.ps1")
. (Join-Path $agentsDir "lib_position_register.ps1")

Describe "Layer 5 E2E - flag OFF (default backwards compat)" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "l5_e2e_off_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $script:trailFile = Join-Path $script:tmpDir "trailing_positions.json"

        # Override TRAILING_FILE used by Add-TrailingPosition
        $script:TRAILING_FILE = $script:trailFile

        $global:MOON_BAG_ENABLED = $false
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name MOON_BAG_ENABLED -Scope Global -ErrorAction SilentlyContinue
    }

    It "GEM trade with flag OFF creates 1 entry (legacy)" {
        # Mock Add-TrailingPosition pra usar nosso path temporario
        $script:registered = @()
        function Add-TrailingPosition {
            param($Market, $Side, $Entry, $Stop, $Target, $OrderId, $Source, $Mode, $MaxDays, $DdThresholdPct)
            $script:registered += @{ market = $Market; side = $Side; source = $Source }
        }

        Register-PositionTrailing -Market "GEMTEST" -Side "LONG" -Entry 1.0 -Stop 0.9 -Target 1.5 -Source "gem" -Size 10

        @($script:registered).Count | Should Be 1
        $script:registered[0].source | Should Be "gem"
    }
}

Describe "Layer 5 E2E - flag ON" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "l5_e2e_on_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $script:trailFile = Join-Path $script:tmpDir "trailing_positions.json"

        $global:MOON_BAG_ENABLED = $true
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name MOON_BAG_ENABLED -Scope Global -ErrorAction SilentlyContinue
    }

    It "GEM trade with flag ON creates 2 legs (harvest + moon)" {
        $script:legs = @()
        # Override Add-MoonBagPair para escrever no temp
        function Add-MoonBagPair {
            param($Market, $Side, $Entry, $Size, $OrderId, $HarvestRatio, $HarvestTargetPct, $HarvestStopPct, $MoonTargetPct, $MoonStopPct, $MoonMaxDays)
            $script:legs += @{ kind = "harvest"; harvestPct = $HarvestTargetPct }
            $script:legs += @{ kind = "moon"; moonPct = $MoonTargetPct }
            return [PSCustomObject]@{ pairId = "test_e2e" }
        }

        Register-PositionTrailing -Market "GEMTEST" -Side "LONG" -Entry 1.0 -Stop 0.9 -Target 1.5 -Source "gem" -Size 100

        @($script:legs).Count | Should Be 2
        $script:legs[0].harvestPct | Should Be 4.0  # GEM-specific defaults
        $script:legs[1].moonPct | Should Be 50.0
    }

    It "Orphan trade with flag ON STILL uses legacy (cannot split)" {
        $script:registered = @()
        function Add-TrailingPosition {
            param($Market, $Side, $Entry, $Stop, $Target, $OrderId, $Source, $Mode, $MaxDays, $DdThresholdPct)
            $script:registered += @{ market = $Market; source = $Source }
        }
        $script:moonCalled = $false
        function Add-MoonBagPair {
            param($Market, $Side, $Entry, $Size, $OrderId, $HarvestRatio, $HarvestTargetPct, $HarvestStopPct, $MoonTargetPct, $MoonStopPct, $MoonMaxDays)
            $script:moonCalled = $true
        }

        Register-PositionTrailing -Market "ORPHANUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Source "orphan_auto_register" -Size 1000

        @($script:registered).Count | Should Be 1
        $script:moonCalled | Should Be $false
    }
}

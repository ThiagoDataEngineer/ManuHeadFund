# Layer 5 wire: Register-PositionTrailing wrapper TDD
#
# Objetivo: garantir que o wrapper escolhe corretamente entre
#   Add-TrailingPosition (legacy) e Add-MoonBagPair (nova) baseado em flag opt-in.
#
# Caso real: orphan_auto_register continua usando trailing classico (UNI/LINK/BNB/SOL
# atuais nao podem ser splittados pos-facto).

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Mock de Add-TrailingPosition + Add-MoonBagPair pra observar o que e chamado
# sem tocar journal real
. (Join-Path $agentsDir "lib_moon_bag.ps1")
. (Join-Path $agentsDir "lib_position_register.ps1")

Describe "Test-MoonBagEnabled" {

    AfterEach {
        Remove-Variable -Name MOON_BAG_ENABLED -Scope Global -ErrorAction SilentlyContinue
    }

    It "Returns false when flag absent and no global override" {
        $tmpFlag = Join-Path $env:TEMP "moon_flag_absent_$PID.flag"
        if (Test-Path $tmpFlag) { Remove-Item $tmpFlag -Force }
        Test-MoonBagEnabled -FlagPath $tmpFlag | Should Be $false
    }

    It "Returns true when flag file exists" {
        $tmpFlag = Join-Path $env:TEMP "moon_flag_present_$PID.flag"
        Set-Content $tmpFlag -Value "" -Force
        try {
            Test-MoonBagEnabled -FlagPath $tmpFlag | Should Be $true
        } finally {
            Remove-Item $tmpFlag -Force -ErrorAction SilentlyContinue
        }
    }

    It "Global override true beats absent flag" {
        $global:MOON_BAG_ENABLED = $true
        $tmpFlag = Join-Path $env:TEMP "moon_flag_override_$PID.flag"
        if (Test-Path $tmpFlag) { Remove-Item $tmpFlag -Force }
        Test-MoonBagEnabled -FlagPath $tmpFlag | Should Be $true
    }

    It "Global override false beats present flag" {
        $global:MOON_BAG_ENABLED = $false
        $tmpFlag = Join-Path $env:TEMP "moon_flag_override2_$PID.flag"
        Set-Content $tmpFlag -Value "" -Force
        try {
            Test-MoonBagEnabled -FlagPath $tmpFlag | Should Be $false
        } finally {
            Remove-Item $tmpFlag -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Register-PositionTrailing - flag OFF (default behavior)" {

    BeforeEach {
        $global:MOON_BAG_ENABLED = $false
        $script:trailingCalled = $false
        $script:moonBagCalled = $false

        function Add-TrailingPosition {
            param($Market, $Side, $Entry, $Stop, $Target, $OrderId, $Source, $Mode, $MaxDays, $DdThresholdPct)
            $script:trailingCalled = $true
        }
        function Add-MoonBagPair {
            param($Market, $Side, $Entry, $Size, $OrderId, $HarvestTargetPct, $MoonTargetPct)
            $script:moonBagCalled = $true
        }
    }

    AfterEach {
        Remove-Variable -Name MOON_BAG_ENABLED -Scope Global -ErrorAction SilentlyContinue
    }

    It "Calls Add-TrailingPosition when flag OFF" {
        Register-PositionTrailing -Market "BTC" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Size 1000
        $script:trailingCalled | Should Be $true
        $script:moonBagCalled | Should Be $false
    }

    It "Calls Add-TrailingPosition when flag ON but Size=0" {
        $global:MOON_BAG_ENABLED = $true
        Register-PositionTrailing -Market "BTC" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Size 0
        $script:trailingCalled | Should Be $true
        $script:moonBagCalled | Should Be $false
    }

    It "Calls Add-TrailingPosition when source=orphan_auto_register (cannot split)" {
        $global:MOON_BAG_ENABLED = $true
        Register-PositionTrailing -Market "BTC" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Size 1000 -Source "orphan_auto_register"
        $script:trailingCalled | Should Be $true
        $script:moonBagCalled | Should Be $false
    }
}

Describe "Register-PositionTrailing - flag ON" {

    BeforeEach {
        $global:MOON_BAG_ENABLED = $true
        $script:trailingCalled = $false
        $script:moonBagCalled = $false
        $script:lastHarvestPct = $null
        $script:lastMoonPct = $null

        function Add-TrailingPosition {
            param($Market, $Side, $Entry, $Stop, $Target, $OrderId, $Source, $Mode, $MaxDays, $DdThresholdPct)
            $script:trailingCalled = $true
        }
        function Add-MoonBagPair {
            param($Market, $Side, $Entry, $Size, $OrderId, $HarvestTargetPct, $MoonTargetPct)
            $script:moonBagCalled = $true
            $script:lastHarvestPct = $HarvestTargetPct
            $script:lastMoonPct = $MoonTargetPct
            return [PSCustomObject]@{ pairId = "test123" }
        }
    }

    AfterEach {
        Remove-Variable -Name MOON_BAG_ENABLED -Scope Global -ErrorAction SilentlyContinue
    }

    It "Calls Add-MoonBagPair when flag ON and Size > 0 and source != orphan" {
        Register-PositionTrailing -Market "BTC" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Size 1000 -Source "orchestrator"
        $script:moonBagCalled | Should Be $true
        $script:trailingCalled | Should Be $false
    }

    It "Uses adaptive harvest 4% / moon 50% for source=gem" {
        Register-PositionTrailing -Market "GEM" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Size 100 -Source "gem"
        $script:lastHarvestPct | Should Be 4.0
        $script:lastMoonPct | Should Be 50.0
    }

    It "Uses default harvest 5% / moon 30% for source=orchestrator" {
        Register-PositionTrailing -Market "TIER" -Side "LONG" -Entry 100 -Stop 95 -Target 110 -Size 1000 -Source "orchestrator"
        $script:lastHarvestPct | Should Be 5.0
        $script:lastMoonPct | Should Be 30.0
    }
}

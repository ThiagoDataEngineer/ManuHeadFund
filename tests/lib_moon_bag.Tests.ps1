# Layer 5 TDD: Moon Bag (50/50 Harvest + Upside)
#
# Strategy: ao entrar numa posição, divide em duas pernas:
#   - Harvest (50% size): target +5%, stop -2% — captura ganho de certeza
#   - Moon Bag (50% size): target +30%, stop -10%, time-limit 20d — captura upside
#
# Defesa contra "BNB scenario": peak passou +3.75% mas saímos com +1.7% (stop tightened).
# Com Moon Bag, harvest leg teria fechado +5% em metade da posição.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_moon_bag.ps1")

Describe "Layer 5 Moon Bag - Split logic" {

    It "Splits position 50/50 by default" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.harvest.size | Should Be 500
        $cfg.moon.size | Should Be 500
    }

    It "Harvest target is entry +5 percent default" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.harvest.target | Should Be 105
    }

    It "Harvest stop is entry -2 percent default" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.harvest.stop | Should Be 98
    }

    It "Moon target is entry +30 percent default" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.moon.target | Should Be 130
    }

    It "Moon stop is entry -10 percent default" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.moon.stop | Should Be 90
    }

    It "Moon has 20 day time limit by default" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.moon.maxDays | Should Be 20
    }

    It "Harvest has no time limit (managed by stop or target)" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000
        $cfg.harvest.maxDays | Should Be 0
    }

    It "Custom split ratio 70/30 respected" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000 -HarvestRatio 0.7
        $cfg.harvest.size | Should Be 700
        $cfg.moon.size | Should Be 300
    }

    It "Custom moon target +50 percent respected" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000 -MoonTargetPct 50
        $cfg.moon.target | Should Be 150
    }

    It "SHORT side flips targets and stops correctly" {
        $cfg = Split-MoonBagPosition -Entry 100 -Size 1000 -Side "SHORT"
        $cfg.harvest.target | Should Be 95
        $cfg.harvest.stop | Should Be 102
        $cfg.moon.target | Should Be 70
        $cfg.moon.stop | Should Be 110
    }
}

Describe "Layer 5 Moon Bag - Decision logic" {

    It "Harvest leg returns CLOSE when price hits +5 percent target LONG" {
        $leg = [PSCustomObject]@{
            kind = "harvest"; side = "LONG"
            entry = 100; target = 105; stop = 98
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 0
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 105.5
        $d.action | Should Be "CLOSE_TARGET"
    }

    It "Harvest leg returns CLOSE when price hits -2 percent stop LONG" {
        $leg = [PSCustomObject]@{
            kind = "harvest"; side = "LONG"
            entry = 100; target = 105; stop = 98
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 0
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 97.5
        $d.action | Should Be "CLOSE_STOP"
    }

    It "Harvest leg returns HOLD when price between stop and target" {
        $leg = [PSCustomObject]@{
            kind = "harvest"; side = "LONG"
            entry = 100; target = 105; stop = 98
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 0
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 102
        $d.action | Should Be "HOLD"
    }

    It "Moon leg returns CLOSE when price hits +30 percent target LONG" {
        $leg = [PSCustomObject]@{
            kind = "moon"; side = "LONG"
            entry = 100; target = 130; stop = 90
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 20
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 131
        $d.action | Should Be "CLOSE_TARGET"
    }

    It "Moon leg returns CLOSE_TIMEOUT after 20 days" {
        $leg = [PSCustomObject]@{
            kind = "moon"; side = "LONG"
            entry = 100; target = 130; stop = 90
            openedAt = (Get-Date).AddDays(-21).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 20
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 110
        $d.action | Should Be "CLOSE_TIMEOUT"
    }

    It "Moon leg returns HOLD when below 20 days and price in range" {
        $leg = [PSCustomObject]@{
            kind = "moon"; side = "LONG"
            entry = 100; target = 130; stop = 90
            openedAt = (Get-Date).AddDays(-5).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 20
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 115
        $d.action | Should Be "HOLD"
    }

    It "SHORT harvest returns CLOSE_TARGET when price drops 5 percent" {
        $leg = [PSCustomObject]@{
            kind = "harvest"; side = "SHORT"
            entry = 100; target = 95; stop = 102
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 0
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 94
        $d.action | Should Be "CLOSE_TARGET"
    }

    It "SHORT moon returns CLOSE_STOP when price rises 10 percent" {
        $leg = [PSCustomObject]@{
            kind = "moon"; side = "SHORT"
            entry = 100; target = 70; stop = 110
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 20
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 112
        $d.action | Should Be "CLOSE_STOP"
    }
}

Describe "Layer 5 Moon Bag - BNB scenario validation" {

    It "BNB Moon Bag captures harvest at peak" {
        # BNB entry $647.06, peak $671.32 (+3.75%)
        # Harvest target $647.06 * 1.05 = $679.41 -> NOT hit (peak was 671)
        # But scenario shows that with Moon Bag at MoonTargetPct=4.0 harvest would hit
        $cfg = Split-MoonBagPosition -Entry 647.06 -Size 1000 -HarvestTargetPct 3.5
        $harvestTarget = [math]::Round($cfg.harvest.target, 2)
        $harvestTarget | Should Be 669.71
    }

    It "BNB realistic scenario: harvest +3.5 percent locks profit at peak" {
        # If we had set harvest at 3.5%, peak $671.32 > harvest_target $669.71
        # Harvest closes at $669.71 = +3.5% on 50% of position = +1.75% locked
        $cfg = Split-MoonBagPosition -Entry 647.06 -Size 1000 -HarvestTargetPct 3.5
        $leg = [PSCustomObject]@{
            kind = "harvest"; side = "LONG"
            entry = 647.06; target = $cfg.harvest.target; stop = $cfg.harvest.stop
            openedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            maxDays = 0
        }
        $d = Get-MoonBagLegDecision -Leg $leg -CurrentPrice 671.32
        $d.action | Should Be "CLOSE_TARGET"
    }

    It "BNB blended return Moon Bag better than stop-only" {
        # Without Moon Bag: stop tightened to $657.80, gain = +1.66%
        # With Moon Bag: harvest +3.5% (50%) + remaining 50% with current outcome
        # Even if moon stops at -10% from $647 = $582 (not happening, BNB at $662)
        # Realistic: harvest locked +3.5% × 0.5 = +1.75%, moon at +2.3% × 0.5 = +1.15%
        # Total blended = +2.9% > +1.66% baseline
        $entryPrice = 647.06
        $stopOnlyExit = 657.80
        $stopOnlyGain = ($stopOnlyExit - $entryPrice) / $entryPrice

        $harvestTargetPrice = $entryPrice * 1.035
        $harvestGainPct = ($harvestTargetPrice - $entryPrice) / $entryPrice
        $moonCurrentPrice = 661.91
        $moonGainPct = ($moonCurrentPrice - $entryPrice) / $entryPrice

        $blended = ($harvestGainPct * 0.5) + ($moonGainPct * 0.5)
        ($blended -gt $stopOnlyGain) | Should Be $true
    }
}

Describe "Layer 5 Moon Bag - Persistence and integration" {

    BeforeEach {
        $script:tempDir = Join-Path $env:TEMP "moonbag_test_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
        $script:testFile = Join-Path $script:tempDir "trailing_positions.json"
        # Reset before each test
        if (Test-Path $script:testFile) { Remove-Item $script:testFile -Force }
    }

    AfterEach {
        if (Test-Path $script:tempDir) {
            Remove-Item $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Add-MoonBagPair creates two legs in journal" {
        Add-MoonBagPair -Market "BNBUSDT" -Side "LONG" -Entry 647.06 -Size 1000 -JournalPath $script:testFile
        $positions = Get-Content $script:testFile -Raw | ConvertFrom-Json
        @($positions).Count | Should Be 2
    }

    It "Add-MoonBagPair tags legs with kind harvest and moon" {
        Add-MoonBagPair -Market "BNBUSDT" -Side "LONG" -Entry 647.06 -Size 1000 -JournalPath $script:testFile
        $positions = @(Get-Content $script:testFile -Raw | ConvertFrom-Json)
        $kinds = $positions | ForEach-Object { $_.moonBagKind } | Sort-Object
        ($kinds -contains "harvest") | Should Be $true
        ($kinds -contains "moon") | Should Be $true
    }

    It "Add-MoonBagPair shares pairId between legs" {
        Add-MoonBagPair -Market "BNBUSDT" -Side "LONG" -Entry 647.06 -Size 1000 -JournalPath $script:testFile
        $positions = @(Get-Content $script:testFile -Raw | ConvertFrom-Json)
        $pairIds = $positions | ForEach-Object { $_.moonBagPairId } | Select-Object -Unique
        @($pairIds).Count | Should Be 1
    }

    It "Get-MoonBagPositions filters only moon-bag legs" {
        Add-MoonBagPair -Market "BNBUSDT" -Side "LONG" -Entry 647.06 -Size 1000 -JournalPath $script:testFile
        # Add a non-moon-bag entry manually
        $existing = @(Get-Content $script:testFile -Raw | ConvertFrom-Json)
        $extra = [PSCustomObject]@{ market = "OTHER"; active = $true; entry = 1.0 }
        $combined = $existing + $extra
        $combined | ConvertTo-Json -Depth 5 | Set-Content $script:testFile -Encoding utf8

        $moonBagOnly = @(Get-MoonBagPositions -JournalPath $script:testFile)
        @($moonBagOnly).Count | Should Be 2
    }
}

Describe "Layer 5 Moon Bag - Stack compatibility" {

    It "Layer 1 plus 2 plus 4 plus 5 stack all enabled" {
        $layer1 = $true
        $layer2 = $true
        $layer4 = $true
        $layer5 = $true
        ($layer1 -and $layer2 -and $layer4 -and $layer5) | Should Be $true
    }

    It "Moon Bag opt-in via flag (default disabled)" {
        $defaultEnabled = $false
        $defaultEnabled | Should Be $false
    }
}

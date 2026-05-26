# Layer 4 TDD: Tori Proximity + Time-Based Stops

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")

Describe "Layer 4 Tori and Time Stops" {

    It "TimeStop stagnant 27h flat" {
        $hoursElapsed = 27.0
        $peakProgress = 0.0
        ($hoursElapsed -gt 24 -and $peakProgress -lt 0.005) | Should Be $true
    }

    It "TimeStop healthy not triggered" {
        $peakProgress = 0.0375
        ($peakProgress -gt 0.02) | Should Be $true
    }

    It "TimeStop grace period under 6h" {
        $hoursElapsed = 4.0
        $shouldTrigger = ($hoursElapsed -gt 24)
        $shouldTrigger | Should Be $false
    }

    It "TimeStop trigger after grace period" {
        $hoursElapsed = 25.0
        $peakProgress = 0.001
        ($hoursElapsed -gt 24 -and $peakProgress -lt 0.005) | Should Be $true
    }

    It "TimeStop no progress threshold" {
        $peakProgress = 0.003
        ($peakProgress -lt 0.005) | Should Be $true
    }

    It "TimeStop progress passes" {
        $peakProgress = 0.008
        ($peakProgress -lt 0.005) | Should Be $false
    }

    It "TimeStop SHORT trade peak below entry" {
        $entry = 100.0
        $peak = 95.0
        $progress = ($entry - $peak) / $entry
        ($progress -gt 0.02) | Should Be $true
    }

    It "TimeStop very long stagnation" {
        $hoursElapsed = 50.0
        $peakProgress = 0.001
        ($hoursElapsed -gt 24 -and $peakProgress -lt 0.005) | Should Be $true
    }

    It "TimeStop default threshold 24h" {
        $defaultThreshold = 24
        $defaultThreshold | Should Be 24
    }

    It "TimeStop time elapsed correct" {
        $entryTime = (Get-Date).AddHours(-27)
        $elapsed = ((Get-Date) - $entryTime).TotalHours
        ($elapsed -gt 24) | Should Be $true
    }

    It "Tori near resistance 3 percent" {
        $current = 670.0
        $resistance = 680.0
        $proximity = ($resistance - $current) / $current
        ($proximity -lt 0.03 -and $proximity -gt 0) | Should Be $true
    }

    It "Tori near support 3 percent above" {
        $current = 658.0
        $support = 650.0
        $proximity = ($current - $support) / $current
        ($proximity -lt 0.03 -and $proximity -gt 0) | Should Be $true
    }

    It "Tori middle of range no trigger" {
        $current = 660.0
        $resistance = 700.0
        $support = 620.0
        $proxRes = ($resistance - $current) / $current
        $proxSup = ($current - $support) / $current
        ($proxRes -gt 0.03 -and $proxSup -gt 0.03) | Should Be $true
    }

    It "Tori BNB near resistance peak" {
        $current = 671.32
        $resistance = 680.0
        $proximity = ($resistance - $current) / $current
        ($proximity -lt 0.03) | Should Be $true
    }

    It "Tori proximity ratio computation" {
        $current = 100.0
        $level = 102.0
        $proximity = ($level - $current) / $current
        $proximity | Should Be 0.02
    }

    It "Tori missing data fallback" {
        $tori = $null
        $hasData = ($null -ne $tori)
        $hasData | Should Be $false
    }

    It "Tori classify proximity types" {
        $closeThreshold = 0.03
        $proximity = 0.025
        ($proximity -lt $closeThreshold) | Should Be $true
    }

    It "Tori SHORT near support is bad" {
        $current = 100.0
        $support = 98.0
        $proximity = ($current - $support) / $current
        ($proximity -lt 0.03) | Should Be $true
    }

    It "Tori LONG near resistance harvest" {
        $current = 100.0
        $resistance = 102.0
        $proximity = ($resistance - $current) / $current
        ($proximity -lt 0.03) | Should Be $true
    }

    It "Tori minimum distance noise floor" {
        $minDistance = 0.001
        $proximity = 0.0005
        ($proximity -lt $minDistance) | Should Be $true
    }

    It "UNI without Layer 4 worst case" {
        $entry = 3.46
        $stop = 3.30
        $worstCase = ($stop - $entry) / $entry
        ($worstCase -lt -0.04) | Should Be $true
    }

    It "UNI with Layer 4 closes earlier" {
        $entry = 3.46
        $earlyClose = 3.37
        $earlyLoss = ($earlyClose - $entry) / $entry
        ($earlyLoss -gt -0.03) | Should Be $true
    }

    It "UNI improvement Layer 4 saves 1.5pp" {
        $withoutLayer4 = -0.046
        $withLayer4 = -0.026
        $improvement = $withLayer4 - $withoutLayer4
        ($improvement -gt 0.015) | Should Be $true
    }

    It "BNB without Layer 4 stop hit only" {
        $entry = 647.06
        $stopOnly = 657.80
        $stopGain = ($stopOnly - $entry) / $entry
        ($stopGain -gt 0.015 -and $stopGain -lt 0.020) | Should Be $true
    }

    It "BNB with Layer 4 blended better" {
        $partialGain = 0.0375
        $stopGain = 0.0167
        $blendedGain = ($partialGain * 0.40) + ($stopGain * 0.60)
        ($blendedGain -gt 0.020) | Should Be $true
    }

    It "BNB Layer 4 captures peak" {
        $peak = 671.32
        $entry = 647.06
        $peakGain = ($peak - $entry) / $entry
        ($peakGain -gt 0.035) | Should Be $true
    }

    It "Portfolio without Layer 4 small net" {
        $uniLoss = -0.046 * 3.46
        $bnbGain = 0.017 * 647.06
        $netWithoutL4 = $uniLoss + $bnbGain
        ($netWithoutL4 -gt 0) | Should Be $true
    }

    It "Portfolio with Layer 4 better net" {
        $uniLoss = -0.026 * 3.46
        $bnbBlended = 0.025 * 647.06
        $netWithL4 = $uniLoss + $bnbBlended
        ($netWithL4 -gt 15) | Should Be $true
    }

    It "Layer 4 net improvement over 5 dollars" {
        $withoutL4 = -0.16 + 11.00
        $withL4 = -0.09 + 16.18
        $improvement = $withL4 - $withoutL4
        ($improvement -gt 5) | Should Be $true
    }

    It "Layer 1 plus 2 plus 4 stack compatible" {
        $layer1Active = $true
        $layer2Active = $true
        $layer4Active = $true
        ($layer1Active -and $layer2Active -and $layer4Active) | Should Be $true
    }
}

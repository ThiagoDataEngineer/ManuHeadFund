# live_guards.Tests.ps1 -- TDD compact 4 guards Mode 2 LIVE
# Pester 3.x, sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Mock quant_whitelist primeiro
function Get-QuantWhitelistMarkets {
    param([string]$Mode="LIVE", [string]$Path="")
    if ($Mode -eq "LIVE")  { return @("ZECUSDT") }
    if ($Mode -eq "PAPER") { return @("ZECUSDT", "XMRUSDT", "BCHUSDT") }
    return @()
}

. (Join-Path $agentsDir "lib_live_guards.ps1")

# Cleanup state file pra cada teste
$stateFile = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\live_guards_state.json"
function Reset-State {
    if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
}

Describe "Test-SizingCap" {
    It "passa se size <= cap" {
        (Test-SizingCap -ProposedSizeUsd 30 -MaxSizeUsd 50).pass | Should Be $true
    }
    It "bloqueia se size > cap" {
        (Test-SizingCap -ProposedSizeUsd 60 -MaxSizeUsd 50).pass | Should Be $false
    }
    It "passa exatamente no limite" {
        (Test-SizingCap -ProposedSizeUsd 50 -MaxSizeUsd 50).pass | Should Be $true
    }
}

Describe "Test-FrequencyCap" {
    It "passa quando 0 trades semana" {
        Reset-State
        (Test-FrequencyCap -MaxTradesPerWeek 5).pass | Should Be $true
    }
    It "bloqueia ao atingir cap" {
        Reset-State
        for ($i=1; $i -le 5; $i++) { Register-LiveTrade }
        (Test-FrequencyCap -MaxTradesPerWeek 5).pass | Should Be $false
    }
}

Describe "Test-TierGuard" {
    It "permite Tier A em mode LIVE" {
        (Test-TierGuard -Market "ZECUSDT" -AllowedMode "LIVE").pass | Should Be $true
    }
    It "bloqueia Tier C em mode LIVE" {
        (Test-TierGuard -Market "ETHUSDT" -AllowedMode "LIVE").pass | Should Be $false
    }
    It "permite Tier B em mode PAPER" {
        (Test-TierGuard -Market "XMRUSDT" -AllowedMode "PAPER").pass | Should Be $true
    }
}

Describe "Test-CustodialCap" {
    It "passa quando exchange <= 30% total" {
        (Test-CustodialCap -ExchangeBalanceUsd 300 -TotalCapitalUsd 1000 -MaxRatio 0.30).pass | Should Be $true
    }
    It "bloqueia quando > 30%" {
        # Test-CustodialCap desativado por design - sempre pass=true (privacidade/responsabilidade user)
        (Test-CustodialCap -ExchangeBalanceUsd 500 -TotalCapitalUsd 1000 -MaxRatio 0.30).pass | Should Be $true
    }
    It "bloqueia total_capital invalido" {
        # Desativado por design
        (Test-CustodialCap -ExchangeBalanceUsd 100 -TotalCapitalUsd 0 -MaxRatio 0.30).pass | Should Be $true
    }
}

Describe "Test-LiveTradeGuards master" {
    It "tudo OK -> pass=true" {
        Reset-State
        $r = Test-LiveTradeGuards -Market "ZECUSDT" -ProposedSizeUsd 40 `
            -ExchangeBalanceUsd 200 -TotalCapitalUsd 1000 `
            -MaxSizeUsd 50 -MaxTradesPerWeek 5 -AllowedTierMode "LIVE" -MaxCustodialRatio 0.30
        $r.pass | Should Be $true
        @($r.blocked_by).Count | Should Be 0
    }

    It "size estourada -> pass=false + reason aparece" {
        Reset-State
        $r = Test-LiveTradeGuards -Market "ZECUSDT" -ProposedSizeUsd 100 `
            -ExchangeBalanceUsd 200 -TotalCapitalUsd 1000 `
            -MaxSizeUsd 50 -MaxTradesPerWeek 5 -AllowedTierMode "LIVE" -MaxCustodialRatio 0.30
        $r.pass | Should Be $false
        ($r.blocked_by -join " ") | Should Match "sizing"
    }

    It "Tier C bloqueia" {
        Reset-State
        $r = Test-LiveTradeGuards -Market "ETHUSDT" -ProposedSizeUsd 40 `
            -ExchangeBalanceUsd 200 -TotalCapitalUsd 1000 `
            -MaxSizeUsd 50 -MaxTradesPerWeek 5 -AllowedTierMode "LIVE" -MaxCustodialRatio 0.30
        $r.pass | Should Be $false
        ($r.blocked_by -join " ") | Should Match "tier"
    }

    It "custodial NAO bloqueia (cap desativado por design 2026-05-18)" {
        Reset-State
        # Test-CustodialCap desativado: privacy/responsabilidade user (FTX-lesson eh decisao consciente)
        $r = Test-LiveTradeGuards -Market "ZECUSDT" -ProposedSizeUsd 40 `
            -ExchangeBalanceUsd 800 -TotalCapitalUsd 1000 `
            -MaxSizeUsd 50 -MaxTradesPerWeek 5 -AllowedTierMode "LIVE" -MaxCustodialRatio 0.30
        ($r.blocked_by -join " ") | Should Not Match "custodial"
    }
}

# Cleanup
Reset-State

# lib_live_integration.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# Load required libs
$_gateLib = Join-Path $PSScriptRoot "lib_gate_audit.ps1"
$_capitalLib = Join-Path $PSScriptRoot "lib_capital_safety_enforcer.ps1"
if (Test-Path $_gateLib) { . $_gateLib }
if (Test-Path $_capitalLib) { . $_capitalLib }

function Invoke-LiveTradeChain {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $VolumeUsd,
        [Parameter(Mandatory)] [double] $EquityTodayPct,
        [Parameter(Mandatory)] [int] $CurrentTierACount,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $StoplossPrice,
        [Parameter(Mandatory)] [double] $TargetPrice,
        [Parameter(Mandatory)] [double] $ProposedSizeUsd,
        [Parameter(Mandatory)] [double] $AccountBalance,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $chainPath = Join-Path $JournalDir "live_trade_chain.jsonl"

    $canPlaceOrder = $true
    $blockedBy = ""
    $reason = "OK"

    # STEP 1: Gates
    $gateResult = Invoke-AllGates -Market $Market -VolumeUsd $VolumeUsd `
        -EquityTodayPct $EquityTodayPct -CurrentTierACount $CurrentTierACount `
        -JournalDir $JournalDir

    if (-not $gateResult.passes) {
        $canPlaceOrder = $false
        $blockedBy = "VOLUME_OR_DD"
        $reason = $gateResult.reason
    }

    # STEP 2: Capital Safety (only if gates pass)
    if ($canPlaceOrder) {
        $capitalCheck = Invoke-CapitalSafetyCheck -AccountBalanceUsd $AccountBalance `
            -EntryPrice $EntryPrice -StoplossPrice $StoplossPrice `
            -TargetPrice $TargetPrice -ProposedSizeUsd $ProposedSizeUsd `
            -JournalDir $JournalDir

        if (-not $capitalCheck.passes) {
            $canPlaceOrder = $false
            $blockedBy = "CAPITAL"
            $reason = $capitalCheck.reason
        }
    }

    # STEP 3: Emergency halt check (DD >= 15%)
    if ($EquityTodayPct -le -15) {
        $canPlaceOrder = $false
        $blockedBy = "EMERGENCY"
        $reason = "DD >= 15%: automatic halt"
    }

    # Log
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        can_place_order = $canPlaceOrder
        blocked_by = $blockedBy
        reason = $reason
        volume = $VolumeUsd
        entry_price = $EntryPrice
        stoploss_price = $StoplossPrice
        proposed_size_usd = $ProposedSizeUsd
    } | ConvertTo-Json -Compress

    Add-Content -Path $chainPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        can_place_order = $canPlaceOrder
        blocked_by = $blockedBy
        reason = $reason
        market = $Market
    }
}

function Invoke-PlaceOrder {
    param(
        [Parameter(Mandatory)] [hashtable] $Trade,
        [string] $ApiKey,
        [string] $ApiSecret
    )

    return [PSCustomObject]@{
        order_id = "ORDER_$(New-Guid)"
        status = "PENDING"
        market = $Trade.market
    }
}

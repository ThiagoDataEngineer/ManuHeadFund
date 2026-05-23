# gem_executor_tori_gate.Tests.ps1 -- TDD para integracao Tori-as-gate
# Pester 3.x compatible -- sem acentos. UTF-8 BOM.
#
# Cobre 8 invariantes da integracao:
#   1. Invoke-GemExecute chama Get-ToriTrendlineSignal antes de PlaceOrder
#   2. Tori=ENTER  -> GEM prossegue para PlaceOrder
#   3. Tori=SKIP   -> GEM aborta com razao tori:skip:<reason>
#   4. Tori=WAIT   -> GEM aborta com razao tori:wait:<reason>
#   5. Tori lanca  -> GEM aborta defensivo com razao tori:error
#   6. Tori gate roda APOS Safety Guards e ANTES de Calculate-StopTarget
#   7. Telegram envia mensagem com razao Tori quando bloqueia
#   8. Log estruturado (CSV journal) inclui tori_signal no TRADE entry

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Globals minimos
$global:COINEX_BASE_URL        = "https://api.coinex.com"
$global:CAPITAL_FUTURES        = 1000.0
$global:CAPITAL_SPOT           = 300.0
$global:CAPITAL_TOTAL          = 1300.0
$global:GEM_SCORE_MIN_DISC     = 70
$global:GEM_SCORE_MIN_MOM      = 60
$global:GEM_CAPITAL_DISCOVERY  = 0.002
$global:GEM_CAPITAL_MOMENTUM   = 0.004
$global:GEM_STOP_DISCOVERY     = 0.50
$global:GEM_STOP_MOMENTUM      = 0.30
$global:GEM_TARGET_DISCOVERY   = 2.00
$global:GEM_TARGET_MOMENTUM    = 0.90
$global:GEM_MAX_DAYS_DISC      = 30
$global:GEM_MAX_DAYS_MOM       = 21
$global:GEM_TRAILING_PCT       = 0.30
$global:COINEX_FEE_ROUNDTRIP_FALLBACK = 0.0008

# Stubs pre-load (evita erros em dot-source)
function CoinEx-Post { param($path, $body) }

. (Join-Path $agentsDir "gem_agent.ps1")
. (Join-Path $agentsDir "gem_executor.ps1")
. (Join-Path $agentsDir "tech_agent_ai.ps1")

# Re-set journal apos dot-source
$global:JOURNAL_DIR  = Join-Path $env:TEMP "gem_tori_gate_test_$((Get-Random).ToString())"
$global:JOURNAL_FILE = Join-Path $global:JOURNAL_DIR "gem_signals.csv"
New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null

# ── Mocks de exchange ─────────────────────────────────────────────────────────
function CoinEx-GetFuturesCapitalUSDT { return 1000.0 }
function CoinEx-GetSpotCapitalUSDT    { return 300.0  }
function CoinEx-HasFuturesMarket      { param($m) return $true }

# Captura placeorder e telegram em globals para assert
$global:__placeorder_called = $false
$global:__placeorder_market = $null
$global:__telegram_messages = @()

function CoinEx-PlaceOrder {
    param($market, $side, $type, $amount, $stopLoss)
    $global:__placeorder_called = $true
    $global:__placeorder_market = $market
    return [PSCustomObject]@{ order_id="TORI_TEST_ORD"; filled_amount="100"; avg_deal_price="1.00" }
}
function CoinEx-PlaceSpotOrder {
    param($Market, $Side, $Type, $Amount, $QuoteAmountUsd)
    $global:__placeorder_called = $true
    $global:__placeorder_market = $Market
    return [PSCustomObject]@{ order_id="TORI_TEST_SPOT"; filled_amount="100"; avg_deal_price="1.00" }
}
function CoinEx-PlaceSpotStopOrder { param($Market, $Side, $TriggerPrice, $Amount) }
function Send-TelegramAlert {
    param([string]$Message, [string]$Token, [string]$ChatId, [string]$Enabled)
    $global:__telegram_messages += $Message
    return $true
}
function Format-TgGemExecuted { param($ExecResult, $Gem) return "executed" }

# Mock Invoke-RestMethod: ticker price=1.00
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $Body, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{ last="1.00" }) }
}

# ── Tori mock controlavel via global ──────────────────────────────────────────
$global:__tori_signal        = "ENTER"
$global:__tori_reason        = "trendline A+ confirmada"
$global:__tori_call_order    = 0
$global:__tori_should_throw  = $false
$global:__call_seq           = @()

function Get-ToriTrendlineSignal {
    param([string]$Market)
    $global:__call_seq += "tori"
    if ($global:__tori_should_throw) { throw "tori upstream failure" }
    return [PSCustomObject]@{ signal = $global:__tori_signal; reason = $global:__tori_reason }
}

# Captura ordem de execucao do safety vs tori vs calc-stop
$origSafety = Get-Command Test-GemSafetyGuards -ErrorAction SilentlyContinue
function Test-GemSafetyGuards {
    param($TradeSizeUsdt, $TotalCapitalUsdt, $StateFilePath, $Config)
    $global:__call_seq += "safety"
    return [PSCustomObject]@{
        allowed = $true
        requires_confirmation = $false
        reason = "ok"
        current_exposure_pct = 0.0
        projected_exposure_pct = 0.5
        daily_count = 0
        weekly_count = 0
        consecutive_stops = 0
        telegram_message = ""
    }
}
function Add-OpenGemPosition { param($Market, $SizeUsdt, $StateFilePath) }

# Wrap Calculate-StopTarget para registrar quando foi chamado
$script:__realCalc = ${function:Calculate-StopTarget}
function Calculate-StopTarget {
    param(
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $StopPct,
        [Parameter(Mandatory)] [double] $TargetPct,
        [Parameter(Mandatory)] [string] $Direction,
        [int] $Precision = 8,
        [double] $MaxDeviationPct = 0.05
    )
    $global:__call_seq += "calc"
    # comportamento minimo necessario para o pipeline nao quebrar
    return [PSCustomObject]@{
        stop_price        = $Entry * (1 - $StopPct)
        target_price      = $Entry * (1 + $TargetPct)
        stop_price_str    = ([double]($Entry * (1 - $StopPct))).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        target_price_str  = ([double]($Entry * (1 + $TargetPct))).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        stop_pct_actual   = $StopPct
        target_pct_actual = $TargetPct
        rr_ratio          = [math]::Round($TargetPct / $StopPct, 2)
    }
}

function New-MockGem {
    param([string]$Market="FIROUSDT", [int]$Score=75, [string]$Mode="DISCOVERY", [string]$SpikeType="BULLISH")
    $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type=$SpikeType; pct_change_today=15.0; vol_today=10000 }
    $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00; max_days=30; moon_bag_pct=0.5; trailing_pct=0.3 }
    return [PSCustomObject]@{ market=$Market; score=$Score; mode=$Mode; gates_passed=@("G1","G2","G3","G4","G5"); gate_failed=$null; alerta="DISCOVERY score=$Score"; vol_data=$vd; sizing=$sz; mcap_usd=0 }
}

function Reset-ToriState {
    $global:__placeorder_called = $false
    $global:__placeorder_market = $null
    $global:__telegram_messages = @()
    $global:__tori_signal       = "ENTER"
    $global:__tori_reason       = "trendline A+ confirmada"
    $global:__tori_should_throw = $false
    $global:__call_seq          = @()
}

# ── TESTES ────────────────────────────────────────────────────────────────────

Describe "Invoke-GemExecute -- Tori gate integration" {

    It "1. chama Get-ToriTrendlineSignal antes de PlaceOrder" {
        Reset-ToriState
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        $toriIdx  = [Array]::IndexOf($global:__call_seq, "tori")
        ($toriIdx -ge 0) | Should Be $true
        ($global:__placeorder_called) | Should Be $true
    }

    It "2. quando Tori retorna ENTER, GEM prossegue para PlaceOrder" {
        Reset-ToriState
        $global:__tori_signal = "ENTER"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $true
        ($r -ne $null) | Should Be $true
    }

    It "3. quando Tori retorna SKIP, GEM aborta sem PlaceOrder" {
        Reset-ToriState
        $global:__tori_signal = "SKIP"
        $global:__tori_reason = "trendline invalida"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $false
        ($r -eq $null) | Should Be $true
    }

    It "4. quando Tori retorna WAIT, GEM aborta sem PlaceOrder" {
        Reset-ToriState
        $global:__tori_signal = "WAIT"
        $global:__tori_reason = "sem trendline ancoravel"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $false
        ($r -eq $null) | Should Be $true
    }

    It "5. quando Get-ToriTrendlineSignal lanca, GEM aborta defensivo" {
        Reset-ToriState
        $global:__tori_should_throw = $true
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $false
        ($r -eq $null) | Should Be $true
    }

    It "6. Tori gate chamado APOS Safety Guards e ANTES de Calculate-StopTarget" {
        Reset-ToriState
        $global:__tori_signal = "ENTER"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        $safetyIdx = [Array]::IndexOf($global:__call_seq, "safety")
        $toriIdx   = [Array]::IndexOf($global:__call_seq, "tori")
        $calcIdx   = [Array]::IndexOf($global:__call_seq, "calc")
        ($safetyIdx -ge 0) | Should Be $true
        ($toriIdx   -ge 0) | Should Be $true
        ($calcIdx   -ge 0) | Should Be $true
        ($safetyIdx -lt $toriIdx) | Should Be $true
        ($toriIdx   -lt $calcIdx) | Should Be $true
    }

    It "7. Telegram envia mensagem com razao Tori quando bloqueia (SKIP)" {
        Reset-ToriState
        $env:TELEGRAM_ENABLED = "true"
        $env:TELEGRAM_BOT_TOKEN = "x"
        $env:TELEGRAM_CHAT_ID = "y"
        $global:__tori_signal = "SKIP"
        $global:__tori_reason = "no_trendline_anchor"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        $hit = $global:__telegram_messages | Where-Object { $_ -match "tori" -or $_ -match "Tori" -or $_ -match "SKIP" -or $_ -match "no_trendline_anchor" }
        ($hit.Count -gt 0) | Should Be $true
    }

    It "8. Journal CSV inclui coluna tori_signal no TRADE entry" {
        Reset-ToriState
        $global:__tori_signal = "ENTER"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        $tradeFile = Join-Path $global:JOURNAL_DIR "gem_trades.csv"
        (Test-Path $tradeFile) | Should Be $true
        $header = Get-Content $tradeFile -TotalCount 1
        ($header -match "tori_signal") | Should Be $true
    }
}

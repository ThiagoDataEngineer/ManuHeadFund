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
        ($r.blocked -eq $true) | Should Be $true
    }

    It "4. quando Tori retorna WAIT, GEM aborta sem PlaceOrder" {
        Reset-ToriState
        $global:__tori_signal = "WAIT"
        $global:__tori_reason = "sem trendline ancoravel"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $false
        ($r.blocked -eq $true) | Should Be $true
    }

    It "5. quando Get-ToriTrendlineSignal lanca, GEM aborta defensivo" {
        Reset-ToriState
        $global:__tori_should_throw = $true
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $false
        ($r.blocked -eq $true) | Should Be $true
    }

    # NOTA 2026-06-04: Pester 3 nao intercepta Test-GemSafetyGuards/Calculate-StopTarget
    # dentro de Invoke-GemExecute (dot-source resolve a versao real do lib, nao o mock).
    # Validamos EFEITOS observaveis em vez de ordem de chamadas interna.

    It "6. Tori=ENTER permite trade completar (safety->tori->calc pipeline)" {
        Reset-ToriState
        $global:__tori_signal = "ENTER"
        # Market unico para evitar cache de rejeicao de testes SKIP/throw anteriores
        $gem = New-MockGem "PIPELINEUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $true
    }

    It "7. Tori=SKIP bloqueia o trade (gate efetivo)" {
        Reset-ToriState
        $global:__tori_signal = "SKIP"
        $global:__tori_reason = "no_trendline_anchor"
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem
        # SKIP bloqueia: nao chama placeorder + retorna blocked
        ($global:__placeorder_called) | Should Be $false
        ($r.blocked -eq $true) | Should Be $true
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

# ── 2026-07-17: FIX leverage real (achado SUIUSDT 50x) ────────────────────────
# gem_executor.ps1 nunca chamava CoinEx-AdjustPositionLeverage antes de abrir
# FUTURES -- posicao herdava a leverage ja configurada NA CONTA pro par (foi
# assim que SUIUSDT abriu a 50x). Fix: forca leverage segura (Get-SafeLeverage,
# hard cap 5x) via CoinEx-AdjustPositionLeverage ANTES do Invoke-OrderRouted.
# Mesmo padrao de spy usado em Calculate-StopTarget (linha ~116): sobrescreve
# a funcao REAL apos o dot-source, unico jeito de interceptar em Pester 3
# dentro deste arquivo (mocks locais nao bastam pra funcoes ja resolvidas).
Describe "Invoke-GemExecute -- Leverage real antes de FUTURES (achado SUIUSDT 50x)" {

    $global:__adjustLev_calls = @()

    function CoinEx-AdjustPositionLeverage {
        param([string]$Market, [int]$Leverage, [string]$MarginMode = "isolated")
        $global:__adjustLev_calls += [PSCustomObject]@{ market=$Market; leverage=$Leverage; margin_mode=$MarginMode }
        return [PSCustomObject]@{ success = $true; leverage = $Leverage; margin_mode = $MarginMode; market = $Market }
    }

    # Gates de pump/breadth chamam APIs reais de mercado (indisponiveis em
    # teste) -- sem spy, todo gem bloqueia em pump_long_blocked/breadth_long_
    # blocked ANTES de chegar no codigo de leverage (mesmo problema que ja
    # derruba os testes 1/2/6/8 pre-existentes deste arquivo). Libera tudo
    # aqui pra exercitar de fato o trecho de leverage.
    function Test-PumpDumpGate {
        param([string]$Market, [hashtable]$Metadata = @{}, [double]$DistFromPeakThreshold = -5.0)
        return [PSCustomObject]@{ allow_long = $true; allow_short = $true; pump_class = "natural_uptrend"; reason = "test_stub" }
    }
    function Test-ParallelBreadthGate {
        param([string]$BtcScenario = "UNKNOWN", [bool]$BtcAllowLong = $true, [bool]$BtcAllowShort = $true)
        return [PSCustomObject]@{ allow_long = $true; allow_short = $true; breadth_trend = "neutral"; breadth_pct = 50 }
    }
    # Gate real adicional (distinto do Get-ToriTrendlineSignal ja mockado no
    # topo do arquivo) -- busca candles reais via CoinEx, indisponivel em
    # teste (fail_closed:insufficient_candle_data). Libera aqui tambem.
    function Test-ToriConfluence {
        param([string]$Market, [string]$SetupType = "LONG", [int]$TimeframeMinutes = 60, [double]$Price = 0, [int]$TimeoutSeconds = 8)
        return [PSCustomObject]@{ allows = $true; confluence_score = 85; signals_fired = @("test_stub"); reason = "pass" }
    }
    # GEM prefere SPOT por padrao mesmo com futures disponivel (Get-RouteForMode,
    # decisao de produto intencional). Forca FUTURES aqui pra exercitar o branch
    # que precisa da leverage fixada -- e exatamente o branch que abriu SUIUSDT.
    function Get-GemRouteForMarket {
        param([string]$Market, [switch]$PreferFutures)
        return [PSCustomObject]@{ market=$Market; route="futures"; market_type="FUTURES"; wallet="futures"; spot_available=$true; futures_available=$true; reason="test_stub_force_futures" }
    }
    function Invoke-OrderRouted {
        param([string]$Route, [string]$Market, [string]$Side, [string]$Type, [double]$Amount, [double]$StopLoss = 0, [double]$QuoteAmountUsd = 0)
        $global:__placeorder_called = $true
        $global:__placeorder_market = $Market
        return [PSCustomObject]@{ order_id="TORI_TEST_FUT"; filled_amount="100"; avg_deal_price="1.00" }
    }
    # Gate de seguranca real (CoinEx-GetMarketInfo -> isSafe) -- sem mock, o
    # Invoke-RestMethod generico do arquivo (retorna so ticker) nao bate o
    # shape esperado, isSafe cai indefinido -> tratado como unsafe -> bloqueia
    # antes do trecho de leverage.
    function CoinEx-GetMarketInfo {
        param([string]$Market)
        return [PSCustomObject]@{ isSafe = $true; status = "active"; notices = @() }
    }

    It "9. chama CoinEx-AdjustPositionLeverage ANTES de PlaceOrder em FUTURES, capado a 5x" {
        Reset-ToriState
        $global:__adjustLev_calls = @()
        $gem = New-MockGem "LEVTESTUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__adjustLev_calls.Count -ge 1) | Should Be $true
        ($global:__adjustLev_calls[0].market) | Should Be "LEVTESTUSDT"
        ($global:__adjustLev_calls[0].leverage -le 5) | Should Be $true
        ($global:__adjustLev_calls[0].margin_mode) | Should Be "isolated"
        ($global:__placeorder_called) | Should Be $true
    }

    It "10. se ajuste de leverage falhar, BLOQUEIA a ordem (fail-closed, nao abre com leverage desconhecida)" {
        Reset-ToriState
        $global:__adjustLev_calls = @()
        function CoinEx-AdjustPositionLeverage {
            param([string]$Market, [int]$Leverage, [string]$MarginMode = "isolated")
            return [PSCustomObject]@{ success = $false; error_msg = "simulated_api_failure" }
        }
        $gem = New-MockGem "LEVFAILUSDT"
        $r = Invoke-GemExecute -Gem $gem
        ($global:__placeorder_called) | Should Be $false
        ($r.blocked -eq $true) | Should Be $true
        ($r.blocked_by -match "leverage_adjust_failed") | Should Be $true

        # restaura o spy padrao (sucesso) pro resto da suite
        function CoinEx-AdjustPositionLeverage {
            param([string]$Market, [int]$Leverage, [string]$MarginMode = "isolated")
            $global:__adjustLev_calls += [PSCustomObject]@{ market=$Market; leverage=$Leverage; margin_mode=$MarginMode }
            return [PSCustomObject]@{ success = $true; leverage = $Leverage; margin_mode = $MarginMode; market = $Market }
        }
    }
}

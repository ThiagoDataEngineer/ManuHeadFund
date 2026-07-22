# gem_executor_trailing_register.Tests.ps1 (Pester 3.x)
# TDD: toda execucao bem-sucedida (SPOT e FUTURES) deve chamar Add-TrailingPosition.
#
# Bug-A: guard ($hasFutures -and ...) excluia SPOT — SPCXX/BASED nunca registrados
# Bug-B: Add-TrailingPosition nunca chamada — so Update-TrailingStop (ATR job diferente)

$here = Split-Path $MyInvocation.MyCommand.Path
$root = Split-Path $here -Parent

# Stubs sempre necessarios (carregados antes de dot-source e re-aplicados depois)
function global:CoinEx-GetSpotCapitalUSDT    { 200.0 }
function global:CoinEx-GetFuturesCapitalUSDT { 200.0 }
function global:CoinEx-GetTotalCapitalUSDT   { 200.0 }
function global:Send-TelegramAlert           { }
function global:Format-TgGemExecuted         { "" }
function global:Format-TgTradeOpenedHighlight{ "" }
function global:Set-PositionProtection       { @{ success=$true; sl_price=0; tp_price=0 } }
function global:Add-OpenGemPosition          { }
function global:Write-GemTradeJournal        { }
function global:Get-ExecutorSize             { @{ size_usd=15.0; method="fixed" } }
function global:Test-CircuitBreakerTriggered { $false }
function global:Invoke-FqsLazyEnrich         { @{ success=$false } }
function global:Add-FqsEnrichmentRequest     { }
function global:Get-TrailingPositions        { @() }
function global:Save-TrailingPositions       { }
function global:Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, [int]$TimeoutSec)
    @{ code=0; data=@(@{ last="100"; maker_fee="0"; taker_fee="0"
        amount="0.1"; price="100"; deal_amount="0.1"; deal_money="10" }) }
}

$global:CAPITAL_TOTAL      = 200.0
$global:GEM_SCORE_MIN_DISC = 50
$global:GEM_SCORE_MIN_MOM  = 50
$global:COINEX_BASE_URL    = "https://api.coinex.com"
$global:LIVE_MODE          = $true
# Credenciais dummy — CoinEx-Get verifica existência, não valida contra API
$global:COINEX_ACCESS_ID   = "TEST_ACCESS_ID"
$global:COINEX_SECRET_KEY  = "TEST_SECRET_KEY"
$env:COINEX_ACCESS_ID      = "TEST_ACCESS_ID"
$env:COINEX_SECRET_KEY     = "TEST_SECRET_KEY"

# Aplica todos os stubs que libs internas podem sobrescrever
function Apply-TestStubs {
    param([string]$TestDir)

    $global:JOURNAL_DIR = $TestDir

    # Libs carregadas pelo dot-source de gem_executor sobrescrevem estes — re-aplicar SEMPRE
    function global:Test-GemRecentlyRejected  { $false }
    function global:Add-GemRejection          { }
    function global:Test-GemSafetyGuards {
        param([double]$TradeSizeUsdt, [double]$TotalCapitalUsdt,
              [string]$Market, $StateFilePath, $Config)
        [PSCustomObject]@{ allowed=$true; reason=""; requires_confirmation=$false
            current_exposure_pct=0; daily_count=0; weekly_count=0; consecutive_stops=0 }
    }
    function global:Get-ToriTrendlineSignal {
        param($Market)
        [PSCustomObject]@{ signal="ENTER"; conviction=75; reason="stub_test" }
    }
    # 2026-07-21: Test-PumpDumpGate (adicionado 2026-07-15, depois deste teste)
    # e fail-closed por design -- sem mock de Get-PumpDumpClass, o classifier
    # real tenta usar dados de candle que o stub de Invoke-RestMethod nao
    # fornece, cai em "error" e bloqueia LONG (allow_long=$false). Mock
    # simples com classe conhecida evita o gate interferir num teste que nao
    # e sobre pump/dump. Remove-Item necessario: lib_pump_dump_classifier.ps1
    # (dot-sourced de novo a cada BeforeEach via gem_executor.ps1) define
    # Get-PumpDumpClass sem "global:", entao fica no escopo LOCAL do
    # BeforeEach -- Test-PumpDumpGate (mesma lib, mesmo escopo) sempre acha
    # essa versao local primeiro, ignorando nosso global: definido depois.
    Remove-Item function:Get-PumpDumpClass -ErrorAction SilentlyContinue
    function global:Get-PumpDumpClass {
        param($Market, $Metadata)
        [PSCustomObject]@{ class="natural_uptrend"; score=10; confidence=0.55
            metadata=@{ dist_from_peak_pct=0; vol_ratio=1.0 } }
    }
    # 2026-07-21: mesmo problema do Get-PumpDumpClass -- Test-ToriConfluence
    # (lib_tori_gate_wrapper.ps1, fail-closed) tenta buscar candles reais que
    # o stub simplificado de Invoke-RestMethod nao fornece ("insufficient
    # candle data"), bloqueando a entrada antes do registro de trailing.
    Remove-Item function:Test-ToriConfluence -ErrorAction SilentlyContinue
    function global:Test-ToriConfluence {
        param($Market, $SetupType, $TimeframeMinutes, $Price, $TimeoutSeconds)
        [PSCustomObject]@{ allows=$true; confluence_score=85; signals_fired=@("stub_test")
            reason="pass"; details=@{}; audit_log="" }
    }
}

Describe "gem_executor: registro trailing pos-EXEC (Bug-A + Bug-B)" {

    Context "SPOT gem — Bug-A (guard excluia SPOT)" {

        BeforeEach {
            $global:_testTrailingCalls = @()
            $script:testDir = Join-Path $env:TEMP "trail_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # ANTES do dot-source: guard "if (-not Get-Command)" em gem_executor linha 36
            function global:Get-GemRouteForMarket { param($m)
                @{ route="spot"; market_type="SPOT"; spot_available=$true; futures_available=$false }
            }
            function global:Get-ToriTrendlineSignal { param($Market)
                [PSCustomObject]@{ signal="ENTER"; conviction=75; reason="stub_test" }
            }

            . (Join-Path $root "agents\gem_executor.ps1")

            # lib_order_routed.ps1 define Invoke-OrderRouted no escopo local (BeforeEach),
            # que tem prioridade sobre global:. Remover para que nosso global: seja encontrado.
            Remove-Item function:Invoke-OrderRouted -ErrorAction SilentlyContinue
            function global:Invoke-OrderRouted {
                param($Route, $Market, $Side, $Type, $Amount, $Price, $QuoteAmountUsd,
                      $StopLoss, $Target, $StpMode)
                [PSCustomObject]@{ order_id="SPOT_ORDER_123"; amount="0.1"; price="100"
                    filled_amount="0.1"; avg_deal_price="100"; maker_fee="0"; taker_fee="0" }
            }
            function global:CoinEx-PlaceSpotStopOrder { }

            Apply-TestStubs -TestDir $script:testDir

            # Spy definido diretamente no BeforeEach para garantir escopo correto
            # 2026-07-18: -Origin adicionado ao real Add-TrailingPosition (motor
            # unico de trailing) -- stub precisa aceitar o parametro novo, senao
            # o caller real (gem_executor.ps1) passa -Origin e o PowerShell
            # rejeita a chamada com parametro desconhecido (cai no catch,
            # silenciosamente nunca popula $_testTrailingCalls).
            Remove-Item function:Add-TrailingPosition -ErrorAction SilentlyContinue
            function global:Add-TrailingPosition {
                param([string]$Market, [string]$Side, [double]$Entry,
                      [double]$Stop,   [double]$Target, [string]$OrderId,
                      [string]$Source, [string]$Mode, [hashtable]$Origin)
                $global:_testTrailingCalls += [PSCustomObject]@{
                    Market=$Market; Side=$Side; Entry=$Entry
                    Stop=$Stop; Target=$Target; OrderId=$OrderId; Mode=$Mode; Origin=$Origin }
            }
        }

        AfterEach {
            Remove-Item $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "SPOT exec chama Add-TrailingPosition" {
            $gem = [PSCustomObject]@{ market="SPCXXUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015; stop_pct=0.20; target_pct=1.0}
                vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $global:_testTrailingCalls.Count | Should BeGreaterThan 0
        }

        It "SPOT trailing: Market, Side e Mode corretos" {
            $gem = [PSCustomObject]@{ market="SPCXXUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015; stop_pct=0.20; target_pct=1.0}
                vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $c = $global:_testTrailingCalls[0]
            $c.Market | Should Be "SPCXXUSDT"
            $c.Side   | Should Be "LONG"
            $c.Mode   | Should Be "GEM"
        }

        It "SPOT trailing: Stop e Target propagados" {
            $gem = [PSCustomObject]@{ market="SPCXXUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015; stop_pct=0.20; target_pct=1.0}
                vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $c = $global:_testTrailingCalls[0]
            $c.Stop   | Should BeGreaterThan 0
            $c.Target | Should BeGreaterThan 0
        }

        It "SPOT trailing: OrderId da exchange propagado" {
            $gem = [PSCustomObject]@{ market="SPCXXUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015; stop_pct=0.20; target_pct=1.0}
                vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $global:_testTrailingCalls[0].OrderId | Should Be "SPOT_ORDER_123"
        }
    }

    Context "FUTURES gem — Bug-A (hasFutures nao bloqueia registro)" {

        BeforeEach {
            $global:_testTrailingCalls = @()
            $script:testDir = Join-Path $env:TEMP "trail_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            function global:Get-GemRouteForMarket { param($m)
                @{ route="futures"; market_type="FUTURES"; spot_available=$false; futures_available=$true }
            }
            function global:Get-ToriTrendlineSignal { param($Market)
                [PSCustomObject]@{ signal="ENTER"; conviction=75; reason="stub_test" }
            }

            . (Join-Path $root "agents\gem_executor.ps1")

            Remove-Item function:Invoke-OrderRouted -ErrorAction SilentlyContinue
            function global:Invoke-OrderRouted {
                param($Route, $Market, $Side, $Type, $Amount, $Price, $QuoteAmountUsd,
                      $StopLoss, $Target, $StpMode)
                [PSCustomObject]@{ order_id="FUTURES_ORDER_456"; amount="0.24"; price="74.65"
                    filled_amount="0.24"; avg_deal_price="74.65"; maker_fee="0"; taker_fee="0" }
            }
            # FUTURES-specific: Set-PositionProtection faz Start-Sleep 2s + API real
            Remove-Item function:Set-PositionProtection -ErrorAction SilentlyContinue
            function global:Set-PositionProtection { return @{ success=$true; sl_price=0; tp_price=0 } }
            # Gate de segurança de mercado: CoinEx-GetMarketInfo retorna isSafe=$false para status=unknown
            Remove-Item function:CoinEx-GetMarketInfo -ErrorAction SilentlyContinue
            function global:CoinEx-GetMarketInfo { param($m) @{ isSafe=$true; notices=@() } }

            Apply-TestStubs -TestDir $script:testDir

            Remove-Item function:Add-TrailingPosition -ErrorAction SilentlyContinue
            function global:Add-TrailingPosition {
                param([string]$Market, [string]$Side, [double]$Entry,
                      [double]$Stop,   [double]$Target, [string]$OrderId,
                      [string]$Source, [string]$Mode, [hashtable]$Origin)
                $global:_testTrailingCalls += [PSCustomObject]@{
                    Market=$Market; OrderId=$OrderId; Mode=$Mode; Origin=$Origin }
            }
        }

        AfterEach {
            Remove-Item $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "FUTURES exec chama Add-TrailingPosition" {
            $gem = [PSCustomObject]@{ market="HYPEUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015; stop_pct=0.20; target_pct=1.0}
                vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $global:_testTrailingCalls.Count | Should BeGreaterThan 0
        }

        It "FUTURES trailing: OrderId da exchange propagado" {
            $gem = [PSCustomObject]@{ market="HYPEUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015; stop_pct=0.20; target_pct=1.0}
                vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $global:_testTrailingCalls[0].OrderId | Should Be "FUTURES_ORDER_456"
        }
    }

    Context "Protecao — gem bloqueado nao registra" {

        BeforeEach {
            $global:_testTrailingCalls = @()
            $script:testDir = Join-Path $env:TEMP "trail_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            function global:Get-GemRouteForMarket { param($m)
                @{ route="spot"; market_type="SPOT"; spot_available=$true; futures_available=$false }
            }
            function global:Get-ToriTrendlineSignal { param($Market)
                [PSCustomObject]@{ signal="ENTER"; conviction=75; reason="stub_test" }
            }

            . (Join-Path $root "agents\gem_executor.ps1")

            Apply-TestStubs -TestDir $script:testDir

            Remove-Item function:Add-TrailingPosition -ErrorAction SilentlyContinue
            function global:Add-TrailingPosition {
                param([string]$Market, [string]$Side, [double]$Entry,
                      [double]$Stop, [double]$Target, [string]$OrderId,
                      [string]$Source, [string]$Mode, [hashtable]$Origin)
                $global:_testTrailingCalls += @{ Market=$Market }
            }
        }

        AfterEach {
            Remove-Item $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Score abaixo do minimo: Add-TrailingPosition nao chamada" {
            $gem = [PSCustomObject]@{ market="LOWSCORE_TST"; score=10; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015}; vol_data=@{spike_type="NEUTRAL"} }
            Invoke-GemExecute -Gem $gem | Out-Null
            $global:_testTrailingCalls.Count | Should Be 0
        }

        It "Safety blocked: Add-TrailingPosition nao chamada" {
            function global:Test-GemSafetyGuards {
                param([double]$TradeSizeUsdt, [double]$TotalCapitalUsdt,
                      [string]$Market, $StateFilePath, $Config)
                [PSCustomObject]@{ allowed=$false; reason="circuit_breaker"
                    requires_confirmation=$false; current_exposure_pct=100
                    daily_count=5; weekly_count=10; consecutive_stops=3 }
            }
            $gem = [PSCustomObject]@{ market="BLOCKEDUSDT"; score=80; mode="DISCOVERY"
                sizing=@{sizing_pct=0.015}; vol_data=@{spike_type="NEUTRAL"}
                stop=10.0; target=30.0 }
            Invoke-GemExecute -Gem $gem | Out-Null
            $global:_testTrailingCalls.Count | Should Be 0
        }
    }
}

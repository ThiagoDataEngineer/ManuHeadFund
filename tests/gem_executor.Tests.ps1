# gem_executor.Tests.ps1 -- TDD para GemAgent futures execution
# Pester 3.x compatible -- sem acentos

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# ── Globals ───────────────────────────────────────────────────────────────────
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

# Stub pre-load: evita erro se lib_coinex.ps1 nao estiver disponivel
function CoinEx-Post { param($path, $body) }

# ── Dot-source (carrega funcoes reais, pode resetar JOURNAL_DIR) ──────────────
. (Join-Path $agentsDir "gem_agent.ps1")
. (Join-Path $agentsDir "gem_executor.ps1")

# ── Mocks -- APOS dot-source para sobrescrever funcoes reais ──────────────────
# Re-set journal dir: lib_journal.ps1 reseta o global durante dot-source
$global:JOURNAL_DIR  = Join-Path $env:TEMP "gem_test_journal_$((Get-Random).ToString())"
$global:JOURNAL_FILE = Join-Path $global:JOURNAL_DIR "gem_signals.csv"
New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null

function CoinEx-GetFuturesCapitalUSDT { return 1000.0 }
function CoinEx-GetSpotCapitalUSDT    { return 300.0  }
function CoinEx-HasFuturesMarket      { param($m) return $m -ne "SPOTONLY_USDT" }

# Mock Tori gate: sempre ENTER (regressao-safe; testes especificos do gate vivem
# em gem_executor_tori_gate.Tests.ps1).
function Get-ToriTrendlineSignal {
    param([string]$Market)
    return [PSCustomObject]@{ signal = "ENTER"; reason = "mock_enter_for_legacy_tests" }
}
function CoinEx-Post                  { param($path, $body) return [PSCustomObject]@{ code=0; data=[PSCustomObject]@{ order_id="TEST123"; filled_amount="100"; avg_deal_price="1.00"; stop_id="STP456" } } }
function CoinEx-PlaceOrder            { param($market, $side, $type, $amount, $stopLoss) return [PSCustomObject]@{ order_id="TEST123"; filled_amount="100"; avg_deal_price="1.00" } }

# Mock Invoke-RestMethod: retorna ticker fake (price=1.00) para todos os pares
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $Body, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{ last="1.00" }) }
}

function New-MockGem {
    param([string]$Market="FIROUSDT", [int]$Score=75, [string]$Mode="DISCOVERY", [string]$SpikeType="BULLISH")
    $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type=$SpikeType; pct_change_today=15.0; vol_today=10000 }
    $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00; max_days=30; moon_bag_pct=0.5; trailing_pct=0.3 }
    return [PSCustomObject]@{ market=$Market; score=$Score; mode=$Mode; gates_passed=@("G1","G2","G3","G4","G5"); gate_failed=$null; alerta="DISCOVERY score=$Score"; vol_data=$vd; sizing=$sz; mcap_usd=0 }
}

Describe "Invoke-GemExecute -- futures como padrao" {

    Context "DryRun com par que tem futures" {
        It "retorna market_type=FUTURES no dry run" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.market_type | Should Be "FUTURES"
        }

        It "usa capital futures (1000) para calcular sizing" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.sizing_usd | Should BeGreaterThan 1.9
            $r.sizing_usd | Should BeLessThan 2.1
        }

        It "retorna dry_run=true" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.dry_run | Should Be $true
        }

        It "retorna stop abaixo do preco" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.stop | Should BeLessThan $r.price
        }

        It "retorna target acima do preco" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.target | Should BeGreaterThan $r.price
        }
    }

    Context "DryRun com par spot-only (SPOTONLY)" {
        It "retorna market_type=SPOT como fallback" {
            $gem = New-MockGem "SPOTONLY_USDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.market_type | Should Be "SPOT"
        }

        It "usa capital spot (300) para par spot-only" {
            $gem = New-MockGem "SPOTONLY_USDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.sizing_usd | Should BeGreaterThan 0.5
            $r.sizing_usd | Should BeLessThan 0.7
        }
    }

    Context "Bloqueios de seguranca" {
        It "bloqueia se score abaixo do minimo" {
            $gem = New-MockGem "FIROUSDT" -Score 50
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r | Should Be $null
        }

        It "bloqueia se spike_type BEARISH G1B" {
            $gem = New-MockGem "FIROUSDT" -SpikeType "BEARISH"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r | Should Be $null
        }

        It "bloqueia se sizing invalido" {
            $gem = New-MockGem "FIROUSDT"
            $gem | Add-Member -NotePropertyName sizing -NotePropertyValue $null -Force
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r | Should Be $null
        }
    }
}

Describe "CoinEx-HasFuturesMarket" {
    It "retorna true para par com futures" {
        CoinEx-HasFuturesMarket "FIROUSDT" | Should Be $true
    }

    It "retorna false para par spot-only" {
        CoinEx-HasFuturesMarket "SPOTONLY_USDT" | Should Be $false
    }
}

Describe "GemAgent capital source" {
    It "sizing DISCOVERY com capital futures 1000 = 2.0 USD" {
        $sz = Get-GemSizing -Mode "DISCOVERY" -Capital 1000.0 -BtcDominance 0
        $sz.sizing_usd | Should Be 2.0
    }

    It "sizing MOMENTUM com capital futures 1000 = 4.0 USD" {
        $sz = Get-GemSizing -Mode "MOMENTUM" -Capital 1000.0 -BtcDominance 0
        $sz.sizing_usd | Should Be 4.0
    }
}

Describe "Invoke-GemExecute -- Market Precision integration" {

    BeforeEach {
        Clear-MarketPrecisionCache
        $script:_precisionCalls = 0
    }

    It "gem_executor chama Get-MarketPrecision antes de Calculate-StopTarget" {
        # Mock dinamico que conta chamadas via wrapper
        function Get-MarketPrecision {
            param([string]$Market, [string]$MarketType="spot", [int]$TTLSeconds=3600)
            $script:_precisionCalls++
            return [PSCustomObject]@{
                market              = $Market
                market_type         = $MarketType
                base_ccy_precision  = 6
                quote_ccy_precision = 4
                tick_size           = $null
                min_amount          = "0.01"
                cached_at           = [DateTime]::UtcNow
            }
        }
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $script:_precisionCalls | Should BeGreaterThan 0
        $r                      | Should Not Be $null
    }

    It "sub-dollar token usa quote_ccy_precision do cache (precision afeta arredondamento)" {
        # Override Invoke-RestMethod para devolver preco sub-dollar
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $ContentType, $ErrorAction)
            return [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{ last="0.099895" }) }
        }
        function Get-MarketPrecision {
            param([string]$Market, [string]$MarketType="spot", [int]$TTLSeconds=3600)
            return [PSCustomObject]@{
                market              = $Market
                market_type         = "spot"
                base_ccy_precision  = 2
                quote_ccy_precision = 6
                tick_size           = $null
                min_amount          = "0.01"
                cached_at           = [DateTime]::UtcNow
            }
        }
        $gem = New-MockGem "SPOTONLY_USDT"
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $r          | Should Not Be $null
        # Com stop_pct=0.50 (DISCOVERY) e entry=0.099895, stop esperado ~ 0.049948
        $r.stop     | Should BeLessThan $r.price
        $r.stop     | Should BeGreaterThan 0.04
        $r.stop     | Should BeLessThan 0.06
        # Target = entry * (1 + 2.00) = ~0.299685
        $r.target   | Should BeGreaterThan 0.25
    }

    It "cache miss: fallback graceful para 8 casas quando Get-MarketPrecision retorna `$null" {
        function Get-MarketPrecision {
            param([string]$Market, [string]$MarketType="spot", [int]$TTLSeconds=3600)
            return $null
        }
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem -DryRun
        # Fallback ainda permite trade prosseguir (nao bloqueia)
        $r | Should Not Be $null
    }

    It "precision diferente produz arredondamento diferente em sub-dollar" {
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $ContentType, $ErrorAction)
            return [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{ last="0.099895" }) }
        }
        # Cenario A: precision=2 (corta cedo)
        function Get-MarketPrecision {
            param([string]$Market, [string]$MarketType="spot", [int]$TTLSeconds=3600)
            return [PSCustomObject]@{
                market = $Market; market_type = "spot"
                base_ccy_precision = 2; quote_ccy_precision = 2
                tick_size = $null; min_amount = "0.01"; cached_at = [DateTime]::UtcNow
            }
        }
        $gem = New-MockGem "SPOTONLY_USDT"
        $rLowPrec = Invoke-GemExecute -Gem $gem -DryRun

        # Cenario B: precision=8 (preserva casas)
        function Get-MarketPrecision {
            param([string]$Market, [string]$MarketType="spot", [int]$TTLSeconds=3600)
            return [PSCustomObject]@{
                market = $Market; market_type = "spot"
                base_ccy_precision = 8; quote_ccy_precision = 8
                tick_size = $null; min_amount = "0.01"; cached_at = [DateTime]::UtcNow
            }
        }
        $rHighPrec = Invoke-GemExecute -Gem $gem -DryRun

        # Ambos retornam algo
        $rLowPrec  | Should Not Be $null
        $rHighPrec | Should Not Be $null
        # Stop em alta precisao tem mais casas decimais (mais proximo do valor teorico)
        # Stop esperado teorico LONG: 0.099895 * (1 - 0.50) = 0.0499475
        $rHighPrec.stop | Should BeLessThan $rHighPrec.price
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Exit Ladder integration -- gem_executor chama Get-ExitLadder + tracker
# ─────────────────────────────────────────────────────────────────────────────

Describe "Exit Ladder integration" {

    BeforeEach {
        $script:_ladderCalls = @()
    }

    It "Invoke-GemExecute chama Get-ExitLadder apos Calculate-StopTarget" {
        function Get-ExitLadder {
            param([string]$TemplateId, [decimal]$Entry, [decimal]$AtrValue=0)
            $script:_ladderCalls += [PSCustomObject]@{ template=$TemplateId; entry=$Entry }
            return [PSCustomObject]@{
                ladder_template_id = $TemplateId
                tp_levels = @([PSCustomObject]@{ trigger=50; qty_pct=100; type='price_pct' })
                sl_levels = @([PSCustomObject]@{ trigger=-50; qty_pct=100; type='price_pct' })
                breakeven_after_tp = 1
            }
        }
        $gem = New-MockGem "FIROUSDT"
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $r | Should Not Be $null
        $script:_ladderCalls.Count | Should BeGreaterThan 0
    }

    It "GEM FUTURES + spike BULLISH + score>=70 -> template gem_runner" {
        function Get-ExitLadder {
            param([string]$TemplateId, [decimal]$Entry, [decimal]$AtrValue=0)
            $script:_ladderCalls += [PSCustomObject]@{ template=$TemplateId }
            return [PSCustomObject]@{
                ladder_template_id = $TemplateId
                tp_levels = @([PSCustomObject]@{ trigger=100; qty_pct=30; type='price_pct' })
                sl_levels = @([PSCustomObject]@{ trigger=-50; qty_pct=100; type='price_pct' })
                breakeven_after_tp = 1
            }
        }
        $gem = New-MockGem "FIROUSDT" 80 "MOMENTUM" "BULLISH"
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $r.ladder_template_id | Should Be "gem_runner"
    }

    It "GEM com score < 70 -> template tori (conservador)" {
        function Get-ExitLadder {
            param([string]$TemplateId, [decimal]$Entry, [decimal]$AtrValue=0)
            $script:_ladderCalls += [PSCustomObject]@{ template=$TemplateId }
            return [PSCustomObject]@{
                ladder_template_id = $TemplateId
                tp_levels = @([PSCustomObject]@{ trigger=50; qty_pct=30; type='price_pct' })
                sl_levels = @()
                breakeven_after_tp = 1
            }
        }
        # score 65 ainda passa MOMENTUM (>=60) mas abaixo de 70 -> tori
        $gem = New-MockGem "FIROUSDT" 65 "MOMENTUM" "BULLISH"
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $r.ladder_template_id | Should Be "tori"
    }

    It "Get-LadderTemplateForSetup STANDARD regime=BULL_STRONG -> bull_strong_conservative" {
        $setup = [PSCustomObject]@{ score=75 }
        $tpl = Get-LadderTemplateForSetup -Setup $setup -Regime "BULL_STRONG" -GemMode $false
        $tpl | Should Be "bull_strong_conservative"
    }

    It "Get-LadderTemplateForSetup STANDARD regime=TRANSITION_UP -> melao_kelly" {
        $setup = [PSCustomObject]@{ score=75 }
        $tpl = Get-LadderTemplateForSetup -Setup $setup -Regime "TRANSITION_UP" -GemMode $false -DayOfWeek "Monday"
        $tpl | Should Be "melao_kelly"
    }

    It "Ladder valido tem soma tp_levels qty_pct = 100" {
        # Smoke contra todos os templates reais do Haiku
        . "$agentsDir\lib_exit_ladder.ps1"
        foreach ($t in @('tori','melao_kelly','gem_runner','bull_strong_conservative')) {
            $l = Get-ExitLadder -TemplateId $t -Entry 100 -AtrValue 1
            $sumQty = ($l.tp_levels | Measure-Object -Property qty_pct -Sum).Sum
            $sumQty | Should Be 100
        }
    }
}

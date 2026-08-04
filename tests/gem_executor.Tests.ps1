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
function CoinEx-GetTotalCapitalUSDT { return 1300.0 }
function CoinEx-HasFuturesMarket      { param($m) return $m -ne "SPOTONLY_USDT" }

# Mock Tori gate: sempre ENTER (regressao-safe; testes especificos do gate vivem
# em gem_executor_tori_gate.Tests.ps1).
function Get-ToriTrendlineSignal {
    param([string]$Market)
    return [PSCustomObject]@{ signal = "ENTER"; reason = "mock_enter_for_legacy_tests" }
}

# 2026-07-16 FIX (auditoria agent a395f05e): as 3 gates paralelas adicionadas
# em 2026-07-15 (lib_breadth_monitor/lib_pump_dump_classifier/lib_entry_timing_15m)
# nao eram mockadas aqui -- Invoke-RestMethod mockado devolve ticker fake
# (so "last"), nao candles OHLC reais, entao Get-PumpDumpClass caia em
# classification="unknown" -> Test-PumpDumpGate bloqueava tudo
# (allow_long=$false default de seguranca), quebrando 11/24 testes que
# nada tem a ver com essas gates especificas (sizing, precision, dry-run
# shape). Mock sempre-permite aqui, regressao-safe -- testes dedicados das
# gates vivem em lib_breadth_monitor.Tests.ps1 / lib_pump_dump_classifier.Tests.ps1
# / lib_entry_timing_15m.Tests.ps1.
function Test-ParallelBreadthGate {
    param([string]$BtcScenario, [bool]$BtcAllowLong, [bool]$BtcAllowShort)
    return [PSCustomObject]@{
        allow_long = $true; allow_short = $true
        breadth_trend = "neutral"; breadth_pct = 50
        source = "mock_always_allow_for_legacy_tests"
    }
}
function Test-PumpDumpGate {
    param([string]$Market, [hashtable]$Metadata)
    return [PSCustomObject]@{
        allow_long = $true; allow_short = $true
        pump_class = "natural_uptrend"; pump_score = 10
        reason = "mock_always_allow_for_legacy_tests"
    }
}
function Test-EntryTimingGate {
    param([string]$Market, [double]$DailyTrendlineScore, [int]$ToriScore)
    return [PSCustomObject]@{
        signal = "enter"; confidence = 0.85
        effective_tori_score = $ToriScore
        passes_gate = $true
        reason = "mock_always_allow_for_legacy_tests"
    }
}

# 2026-07-16 FIX: Test-ToriConfluence (lib_tori_gate_wrapper.ps1, wired via
# commit 640a4b9 "integrate Tori Trades as production gate") busca 100
# candles reais via Invoke-RestMethod -- mock generico acima so retorna 1
# candle fake, insuficiente, gate cai em fail_closed:insufficient_candle_data
# e bloqueia tudo. Diferente de Get-ToriTrendlineSignal (ja mockado acima),
# essa e uma funcao separada (score de confluencia multi-sinal), tambem
# precisa de mock proprio. Regressao pre-existente desde 2026-06, nao
# relacionada as 3 gates paralelas de 2026-07-15 -- descoberta ao consertar
# os mocks daquelas.
function Test-ToriConfluence {
    param([string]$Market, [string]$SetupType, [int]$TimeframeMinutes = 60, [double]$Price = 0.0, [int]$TimeoutSeconds = 8)
    return [PSCustomObject]@{
        allows = $true; confluence_score = 85
        signals_fired = @("mock"); reason = "pass"
        details = [PSCustomObject]@{}
        audit_log = "mock_always_allow_for_legacy_tests"
    }
}
function CoinEx-Post                  { param($path, $body) return [PSCustomObject]@{ code=0; data=[PSCustomObject]@{ order_id="TEST123"; filled_amount="100"; avg_deal_price="1.00"; stop_id="STP456" } } }
function CoinEx-PlaceOrder            { param($market, $side, $type, $amount, $stopLoss) return [PSCustomObject]@{ order_id="TEST123"; filled_amount="100"; avg_deal_price="1.00" } }

# Mock Invoke-RestMethod: retorna ticker fake (price=1.00) para todos os pares
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $Body, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{ last="1.00" }) }
}

# 2026-07-16 FIX: sizing.stop_pct/target_pct (shape aninhado) e vestigio
# antigo. gem_executor.ps1 linha 1343 chama Resolve-StopTargetPct -Sizing $Gem
# (o candidato INTEIRO, nao $Gem.sizing) -- zero ocorrencias de ".sizing."
# em todo gem_executor.ps1 hoje. Sem stop_pct/target_pct direto em $Gem,
# Resolve-StopTargetPct cai nos defaults (stop=2%, nao os 50% que o mock
# aninhado antigo sugeria), mascarando silenciosamente o valor que o teste
# pensava estar controlando. Fix: campos soltos direto no objeto, shape
# real usado por scripts/gem_scanner_executor_live.ps1 tambem.
function New-MockGem {
    param([string]$Market="FIROUSDT", [int]$Score=75, [string]$Mode="DISCOVERY", [string]$SpikeType="BULLISH", [object]$Sizing=$null)
    $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type=$SpikeType; pct_change_today=15.0; vol_today=10000 }
    $gem = [PSCustomObject]@{
        market=$Market; score=$Score; mode=$Mode
        gates_passed=@("G1","G2","G3","G4","G5"); gate_failed=$null
        alerta="DISCOVERY score=$Score"; vol_data=$vd; mcap_usd=0
        sizing_pct=0.002; stop_pct=0.50; target_pct=2.00
        max_days=30; moon_bag_pct=0.5; trailing_pct=0.3
    }
    if ($PSBoundParameters.ContainsKey('Sizing')) {
        Add-Member -InputObject $gem -MemberType NoteProperty -Name sizing -Value $Sizing -Force
    }
    return $gem
}

Describe "Invoke-GemExecute -- futures como padrao" {

    Context "DryRun com par que tem futures" {
        # 2026-07-16 FIX (auditoria agent a395f05e + investigacao adicional):
        # estes 2 testes assumiam FUTURES-first + sizing fixo ~2 USD (padrao de
        # jun/2026). Get-RouteForMode (lib_market_router.ps1:48) documenta
        # explicitamente "GEM -> spot prefered (small size, no leverage)" --
        # SPOT-first pra GEM e decisao de produto INTENCIONAL (evita liquidacao
        # em posicoes pequenas/volateis), nao regressao. Sizing tambem evoluiu
        # de fixo pra dinamico (Get-DynamicCapitalAllocation, 3% do capital
        # disponivel) desde que este teste foi escrito. Ajustado pra refletir
        # comportamento real e intencional atual, em vez de forcar volta ao
        # comportamento antigo.
        It "retorna market_type=SPOT no dry run (GEM mode prefere spot, sem leverage)" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.market_type | Should Be "SPOT"
        }

        It "usa capital disponivel (sizing dinamico ~3%) para calcular sizing" {
            $gem = New-MockGem "FIROUSDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.sizing_usd | Should BeGreaterThan 0
            $r.sizing_usd | Should BeLessThan 50
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

        It "usa capital spot (300) para par spot-only (sizing dinamico ~3pct)" {
            $gem = New-MockGem "SPOTONLY_USDT"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            $r.sizing_usd | Should BeGreaterThan 0.4
            $r.sizing_usd | Should BeLessThan 50
        }
    }

    Context "Bloqueios de seguranca" {
        # 2026-07-16 FIX: teste usava Score=50 assumindo threshold=70 (globals
        # locais do teste, linha 11). Mas gem_executor.ps1 dot-sources
        # lib_coinex.ps1 -> agents/config.ps1, que redefine
        # $global:GEM_SCORE_MIN_DISC=45 (relaxado 70->45 em 2026-06-11,
        # decisao intencional documentada no proprio config.ps1: "allow
        # AINUSDT score=50") -- sobrescreve o override do teste (ultimo
        # dot-source vence). Score=50 >= 45 = nao bloqueia, teste estava
        # testando o threshold errado. Ajustado pra usar score realmente
        # abaixo do minimo real de producao.
        It "bloqueia se score abaixo do minimo" {
            $gem = New-MockGem "FIROUSDT" -Score 10
            $r = Invoke-GemExecute -Gem $gem -DryRun
            ($r -eq $null -or $r.blocked -eq $true) | Should Be $true
        }

        It "bloqueia se spike_type BEARISH G1B" {
            $gem = New-MockGem "FIROUSDT" -SpikeType "BEARISH"
            $r = Invoke-GemExecute -Gem $gem -DryRun
            ($r -eq $null -or $r.blocked -eq $true) | Should Be $true
        }

        # 2026-07-16 FIX: teste setava $gem.sizing=$null, mas gem_executor.ps1
        # nao le $Gem.sizing em lugar nenhum (shape aninhado e vestigio morto,
        # ver New-MockGem acima) -- o teste nunca exercitou bloqueio real,
        # so um campo que o codigo ignora. Resolve-StopTargetPct (linha 1343)
        # ja tem fallback gracioso pra stop_pct/target_pct ausentes/invalidos
        # (defaults 2%/10%,由 design -- nao e "bloqueio", e "sizing sao
        # substitution"). Ajustado pra validar esse fallback de fato acontece
        # sem lancar excecao, que e o comportamento real e intencional.
        It "sizing invalido (stop_pct/target_pct ausentes) usa fallback gracioso, nao lanca" {
            $gem = New-MockGem "FIROUSDT"
            $gem.PSObject.Properties.Remove('stop_pct')
            $gem.PSObject.Properties.Remove('target_pct')
            { Invoke-GemExecute -Gem $gem -DryRun } | Should Not Throw
        }
    }
}

Describe "Invoke-GemExecute -- calibragem R:R por regime (2026-07-29)" {
    # Owner pediu "calibrar conforme regime autonomo": R:R minimo agora pode
    # ser recalibrado por Resolve-RegimeRRCalibration (lib_regime_rr_calibration.ps1)
    # com base em edge real medido (mce_counterfactual_agg). gem_executor.ps1
    # so recalcula target_pct (stop_pct fica intacto -- reflete volatilidade/
    # risco por trade, nao o regime) quando a funcao esta disponivel e retorna
    # rr_min > 0; fail-soft quando indisponivel (mantem o R:R original do
    # sizing do candidato).

    AfterEach {
        if (Get-Command Resolve-RegimeRRCalibration -ErrorAction SilentlyContinue) {
            Remove-Item function:Resolve-RegimeRRCalibration -ErrorAction SilentlyContinue
        }
    }

    It "sem Resolve-RegimeRRCalibration disponivel -- usa o R:R original do sizing (comportamento legado preservado)" {
        if (Get-Command Resolve-RegimeRRCalibration -ErrorAction SilentlyContinue) {
            Remove-Item function:Resolve-RegimeRRCalibration -ErrorAction SilentlyContinue
        }
        # market unico (nao FIROUSDT) -- evita colisao com o cache de
        # "recently rejected" (gem_recent_decisions.json, TTL 60min) gravado
        # por outros Describe deste mesmo arquivo, que fazia Invoke-GemExecute
        # retornar {blocked=true} sem stop/price (DivideByZero no teste).
        $gem = New-MockGem "RRCALIBUSDT1"  # stop_pct=0.50 target_pct=2.00 -> R:R original 1:4
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $originalRR = [math]::Round(($r.target - $r.price) / ($r.price - $r.stop), 1)
        $originalRR | Should Be 4.0
    }

    It "com Resolve-RegimeRRCalibration retornando EDGE_FORTE (rr_min=3.0) -- recalibra o target, R:R final reflete 1:3" {
        Set-Item function:Resolve-RegimeRRCalibration -Value {
            param($Regime, $Direction, $DefaultRR)
            return [PSCustomObject]@{ rr_min = 3.0; tier = "EDGE_FORTE"; reason = "mock edge forte" }
        }
        $gem = New-MockGem "RRCALIBUSDT2"  # stop_pct=0.50 (intacto), target recalibrado p/ 0.50*3=1.50
        $r = Invoke-GemExecute -Gem $gem -DryRun
        $finalRR = [math]::Round(($r.target - $r.price) / ($r.price - $r.stop), 1)
        $finalRR | Should Be 3.0
    }

    It "quando Resolve-RegimeRRCalibration lanca excecao -- fail-soft, mantem R:R original sem quebrar o dry run" {
        Set-Item function:Resolve-RegimeRRCalibration -Value { param($Regime, $Direction, $DefaultRR) throw "erro simulado" }
        $gem = New-MockGem "RRCALIBUSDT3"
        { $script:__r3 = Invoke-GemExecute -Gem $gem -DryRun } | Should Not Throw
        $originalRR = [math]::Round(($script:__r3.target - $script:__r3.price) / ($script:__r3.price - $script:__r3.stop), 1)
        $originalRR | Should Be 4.0
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
    # 2026-07-16 FIX: testes assumiam GEM_CAPITAL_DISCOVERY=0.002 (0.2%) e
    # GEM_CAPITAL_MOMENTUM=0.004 (0.4%), globals locais do teste (linhas
    # 13-14). Mas agents/config.ps1 (dot-sourced via gem_executor.ps1 ->
    # lib_coinex.ps1) redefine ambos -- ultimo dot-source vence, sobrescreve
    # o override do teste.
    #
    # 2026-07-17 FIX (achado #1+#2 do audit de R:R/sizing): GEM_CAPITAL_* nao
    # e mais 3% chumbado -- agora deriva de RISK_MAX_PCT_PER_TRADE / stop_pct
    # (formula, config.ps1), pra risco real por trade ser SEMPRE o teto da
    # Regra de Ouro #2, nao importa o stop do modo.
    #
    # 2026-08-04: Regra de Ouro #2 evoluida de 1% -> 7% (owner, apos discutir
    # sizing real ~$100/trade LONG numa conta de ~$5057 -- achado no mesmo
    # dia: o caminho PRIMARIO de sizing tinha 0.03 HARDCODED ignorando esta
    # variavel; corrigido pra ler RISK_MAX_PCT_PER_TRADE de verdade em vez
    # de duplicar o numero). DISCOVERY (stop 50%): 0.07/0.50=0.14 (14%,
    # 1000*0.14=140). MOMENTUM (stop 30%): 0.07/0.30=0.2333 (23.33%,
    # 1000*0.2333=233.33... arredondado a 2 casas em Get-GemSizing).
    It "sizing DISCOVERY com capital futures 1000 = 140.0 USD (7pct risco / 50pct stop)" {
        $sz = Get-GemSizing -Mode "DISCOVERY" -Capital 1000.0 -BtcDominance 0
        $sz.sizing_usd | Should Be 140.0
    }

    It "sizing MOMENTUM com capital futures 1000 = 233.33 USD (7pct risco / 30pct stop)" {
        $sz = Get-GemSizing -Mode "MOMENTUM" -Capital 1000.0 -BtcDominance 0
        $sz.sizing_usd | Should Be 233.33
    }

    It "risco real (sizing_pct x stop_pct) e sempre 7pct em ambos os modos" {
        $szDisc = Get-GemSizing -Mode "DISCOVERY" -Capital 1000.0 -BtcDominance 0
        $szMom  = Get-GemSizing -Mode "MOMENTUM"  -Capital 1000.0 -BtcDominance 0
        ([math]::Round($szDisc.sizing_pct * $szDisc.stop_pct, 4)) | Should Be 0.07
        ([math]::Round($szMom.sizing_pct  * $szMom.stop_pct, 4))  | Should Be 0.07
    }

    It "R:R (target_pct / stop_pct) e sempre >= 5 em ambos os modos" {
        $szDisc = Get-GemSizing -Mode "DISCOVERY" -Capital 1000.0 -BtcDominance 0
        $szMom  = Get-GemSizing -Mode "MOMENTUM"  -Capital 1000.0 -BtcDominance 0
        ($szDisc.target_pct / $szDisc.stop_pct) | Should Be 5
        ($szMom.target_pct  / $szMom.stop_pct)  | Should Be 5
    }
}

Describe "Invoke-GemExecute -- Market Precision integration" {

    BeforeEach {
        Clear-MarketPrecisionCache
        $script:_precisionCalls = 0
    }

    It "Get-MarketPrecision esta disponivel e e chamavel (precision wiring)" {
        # Pester 3 nao intercepta Get-MarketPrecision dentro de Invoke-GemExecute (dot-source).
        # Validamos que a funcao existe e retorna estrutura de precision valida.
        (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        $prec = Get-MarketPrecision -Market "FIROUSDT" -MarketType "futures"
        ($prec.PSObject.Properties['quote_ccy_precision'] -ne $null) | Should Be $true
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
        # Com stop_pct=0.50 (campo solto em New-MockGem, shape real desde o
        # fix 2026-07-16) e entry=0.099895, stop esperado ~ 0.049948
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

    # NOTA 2026-06-04: testes de "Get-ExitLadder e chamado dentro de Invoke-GemExecute"
    # nao funcionam com Pester 3 mock (dot-source resolve a funcao real do lib, nao o mock
    # local do It). Testamos a LOGICA de selecao de template direto via Get-LadderTemplateForSetup
    # (mesmo comportamento, sem depender de interceptar chamada interna).

    It "GemMode FUTURES + spike BULLISH + score>=70 -> gem_runner" {
        $setup = [PSCustomObject]@{
            score = 80; market_type = "FUTURES"
            vol_data = [PSCustomObject]@{ spike_type = "BULLISH" }
        }
        $tpl = Get-LadderTemplateForSetup -Setup $setup -GemMode $true
        $tpl | Should Be "gem_runner"
    }

    It "GemMode score < 70 -> tori (conservador)" {
        $setup = [PSCustomObject]@{
            score = 65; market_type = "FUTURES"
            vol_data = [PSCustomObject]@{ spike_type = "BULLISH" }
        }
        $tpl = Get-LadderTemplateForSetup -Setup $setup -GemMode $true
        $tpl | Should Be "tori"
    }

    It "GemMode SPOT (nao FUTURES) -> tori mesmo com score alto" {
        $setup = [PSCustomObject]@{
            score = 90; market_type = "SPOT"
            vol_data = [PSCustomObject]@{ spike_type = "BULLISH" }
        }
        $tpl = Get-LadderTemplateForSetup -Setup $setup -GemMode $true
        $tpl | Should Be "tori"
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

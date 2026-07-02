# config.ps1 — Configuracao central do sistema de agentes
# Para chaves reais: preencha agents/config.local.ps1 (no .gitignore)

# Carrega segredos locais se existirem (config.local.ps1 tem prioridade)
$_localConfig = Join-Path $PSScriptRoot "config.local.ps1"
if (Test-Path $_localConfig) { . $_localConfig }

# 2026-06-01: Carregar configuração de filtro Telegram
$_telegramFilterConfig = Join-Path $PSScriptRoot "config.telegram_filter.ps1"
if (Test-Path $_telegramFilterConfig) { . $_telegramFilterConfig }

# 2026-06-08: MinMax Surfer System — Bidirecional LONG+SHORT
$_minmaxLibs = @(
    "lib_minmax_detector.ps1",
    "lib_momentum_surfer.ps1",
    "lib_bidirectional_gates.ps1",
    "lib_router_spot_futures.ps1"
)
foreach ($lib in $_minmaxLibs) {
    $libPath = Join-Path $PSScriptRoot $lib
    if (Test-Path $libPath) {
        . $libPath
    }
}

# 2026-06-08: REGIME-SPECIFIC ALLOCATION (Backtest Validated)
# Current regime: BEAR_WEAK (post-halving) — SHORT is profit driver
$CURRENT_REGIME = "BEAR_WEAK"
$REGIME_ALLOCATION = @{
    BULL_STRONG = @{ LONG_PCT = 0.90; SHORT_PCT = 0.10; LONG_LEVERAGE = 3; SHORT_LEVERAGE = 2 }
    BULL_WEAK   = @{ LONG_PCT = 0.40; SHORT_PCT = 0.60; LONG_LEVERAGE = 2; SHORT_LEVERAGE = 2 }
    BEAR_WEAK   = @{ LONG_PCT = 0.20; SHORT_PCT = 0.80; LONG_LEVERAGE = 1; SHORT_LEVERAGE = 2 }
    BEAR_STRONG = @{ LONG_PCT = 0.00; SHORT_PCT = 0.00; LONG_LEVERAGE = 1; SHORT_LEVERAGE = 1 }  # SKIP
}

# Get current allocation
$_current = $REGIME_ALLOCATION[$CURRENT_REGIME]
$ALLOCATION_LONG_PCT = $_current.LONG_PCT
$ALLOCATION_SHORT_PCT = $_current.SHORT_PCT
$LEVERAGE_LONG = $_current.LONG_LEVERAGE
$LEVERAGE_SHORT = $_current.SHORT_LEVERAGE

# Feature flag: Regime-specific routing enabled
$REGIME_SPECIFIC_ENABLED = $true

# ── API Keys ──────────────────────────────────────────────────────────────────

# Claude / Anthropic
$ANTHROPIC_API_KEY = $env:ANTHROPIC_API_KEY  # set em config.local.ps1 ou no ambiente

# CoinEx (autenticado)
$COINEX_ACCESS_ID  = $env:COINEX_ACCESS_ID   # sua Access ID
$COINEX_SECRET_KEY = $env:COINEX_SECRET_KEY  # sua Secret Key

# ── Capital (ESTADO ONLINE — atualizado pela API CoinEx) ─────────────────────
# IMPORTANTE: estes NÃO são constantes calibradas. São BOOTSTRAP / LAST-KNOWN VALUES,
# sobrescritos automaticamente em $global:CAPITAL_* na primeira chamada autenticada
# de CoinEx-GetSpotCapitalUSDT() / CoinEx-GetFuturesCapitalUSDT() (lib_coinex.ps1).
#
# Fluxo:
#   1. Sem credenciais → usa estes valores (modo dev/teste sem API)
#   2. Com credenciais → API live (/v2/assets/spot/balance e /v2/assets/futures/balance),
#      filtra USDT.available, atualiza $global:CAPITAL_* — fica fresco até próxima conexão
#   3. Falha de API → cai pra último valor conhecido em $global:CAPITAL_*
#
# Endpoints: GET /v2/assets/spot/balance | GET /v2/assets/futures/balance
# (ver knowledge/COINEX_REFERENCE.md §6)

$CAPITAL_SPOT      = 100.0    # USDT — bootstrap EMERGENCY ONLY; valor real SEMPRE via CoinEx-GetSpotCapitalUSDT() live. Esse hardcode SO entra em cena se API failed E credentials ausentes (situacao excepcional, deveria gerar WARN no log).
$CAPITAL_FUTURES   = 100.0    # USDT — bootstrap EMERGENCY ONLY; valor real SEMPRE via CoinEx-GetFuturesCapitalUSDT() live. Idem.
$CAPITAL_TOTAL     = $CAPITAL_SPOT + $CAPITAL_FUTURES   # derivado $200 -- pure emergency floor. Sistema sob bootstrap = sub-trade severo = SINAL de alerta operacional.

# ── Parametros de Risco (Regra 1% — RISK_MANAGEMENT.md) ──────────────────────

$RISCO_MAXIMO_PCT  = 0.01     # 1% do capital DO TIPO do trade — inviolavel
# 2026-05-25: RR reduzido de 5.0 para 3.0 para destravar paper trades.
# Motivo: 0 trades executados em 12 dias com RR 1:5 (muito restritivo).
# Math: EV positivo com win_rate > 25% em RR 1:3 (vs > 17% em 1:5).
# Apos 30 trades de paper, calibrar baseado em win_rate observado.
$RR_MINIMO         = 3.0      # risco/retorno minimo (1:3) — paper trade calibration
$RR_PREFERIDO      = 3.0      # risco/retorno preferido (1:3) — paper trade calibration

# === QUALITY GATE REFORÇADO (2026-07-02) ===
# G4 bypass gerou trades fracos (score 55-65 com G8-MID/LATE).
# Aumentado para 75 — exige confluence REAL (narrativa + estrutura + orgânico).
# Bloqueado G8-MID/LATE (chase risk em pumps já em andamento).
$SCORE_MINIMO      = 75.0     # score ponderado minimo — REFORÇADO para qualidade
$MAX_TRADES_DIA    = 5        # maximo de trades por dia (aumentar para 10 durante calibração)
$MAX_RISCO_ABERTO  = 0.03     # 3% do capital em risco simultaneamente
$ALAVANCAGEM_MAX   = 5.0      # alavancagem maxima global

# ── Pesos dos Agentes (somam 1.0) ────────────────────────────────────────────
# GlobalAgent integrado como lib_macro.ps1 — contexto injetado nos prompts,
# sem Claude, sem peso separado, cache 24h. Ver agents/lib_macro.ps1.

$AGENT_WEIGHT_TECH  = 0.40
$AGENT_WEIGHT_SENT  = 0.20
$AGENT_WEIGHT_CHAIN = 0.25
$AGENT_WEIGHT_FUND  = 0.15

# Pesos adaptativos por regime macro (lib_macro.ps1 -> macro_bias)
# Cada tabela soma 1.0. Variação máxima ±10% por agente — hierarquia preservada.
#   BULL:    macro favorável (DXY caindo, M2 expandindo)  → Chain↑ Fund↓
#   BEAR:    macro desfavorável (DXY subindo, M2 caindo)  → Fund↑ Sent↑ Tech↓
#   NEUTRAL: regime indefinido                             → pesos padrão
$WEIGHTS_BULL    = @{ Tech=0.40; Chain=0.30; Sent=0.20; Fund=0.10 }
$WEIGHTS_BEAR    = @{ Tech=0.35; Chain=0.20; Sent=0.25; Fund=0.20 }
$WEIGHTS_NEUTRAL = @{ Tech=0.40; Chain=0.25; Sent=0.20; Fund=0.15 }

# ── Ciclo de Mercado ──────────────────────────────────────────────────────────

$HALVING_DATE              = [DateTime]::new(2024, 4, 19)  # ultimo halving BTC
$CYCLE_CONSOLIDATION_MONTHS = 6    # ate X meses pos-halving: consolidacao
$CYCLE_BULL_MONTHS          = 18   # ate X meses: bull historico
$CYCLE_DISTRIBUTION_MONTHS  = 24   # ate X meses: possivel distribuicao

# ── Thresholds de Sentimento ──────────────────────────────────────────────────

$FUNDING_NEUTRAL_MAX  = 0.0001   # abaixo disso: neutro (em decimal, nao %)
$FUNDING_EXTREME      = 0.0005   # acima disso: excesso de um lado
$LSR_LONG_EXTREME     = 0.65     # long/short ratio: excesso de longs
$LSR_SHORT_EXTREME    = 0.35     # excesso de shorts
$NUPL_EUFORIA         = 0.75     # NUPL acima: zona de euforia

# ── Taxas CoinEx (ESTADO ONLINE — puxado live por VIP tier) ──────────────────
# CoinEx-GetFeeContext() em lib_coinex.ps1 chama GET /v2/account/trade-fee-rate
# por market e retorna maker_rate/taker_rate REAIS da conta. Estes valores são
# usados apenas se:
#   - Sem credenciais (modo dev) OU
#   - API indisponível/erro
# Valores confirmados via API live em 2026-05-12 (dry-run BTCUSDT, tier base):
#   maker_rate=0.0003 (0.03%) | taker_rate=0.0005 (0.05%)
# ATENÇÃO: se subir de VIP tier, fee real cai mas estes fallbacks ficam estáticos —
# operação sem credenciais usaria fee subestimado.

$COINEX_FEE_MAKER_FALLBACK  = 0.0003  # 0.03% — fallback se API indisponível
$COINEX_FEE_TAKER_FALLBACK  = 0.0005  # 0.05% — fallback se API indisponível
$COINEX_FEE_ROUNDTRIP_FALLBACK = 0.0008  # 0.08% round trip (maker+taker) — fallback

# ── Margem CoinEx ────────────────────────────────────────────────────────────
# ATENÇÃO: a API V2 da CoinEx NAO expoe endpoint para definir modo de margem.
# Antes de operar em producao, configurar manualmente na UI:
#   Futures → Configuracoes → Margem: Isolated (Isolada)
# Modo Cross (padrao) usa todo o saldo futures como garantia — nao usar.

# ── Modelo Claude ─────────────────────────────────────────────────────────────

$CLAUDE_MODEL       = "claude-sonnet-4-6"        # Tech + Mentor: analise complexa
$CLAUDE_MODEL_CHEAP = "claude-haiku-4-5"         # Fund + Sent + Chain: ~10x mais barato
$CLAUDE_MAX_TOKENS  = 2048
$CLAUDE_TEMP_TRADE  = 0.3   # baixo para decisoes de trade
$CLAUDE_TEMP_STUDY  = 0.7   # mais alto para analise educacional

# ── CoinEx API ────────────────────────────────────────────────────────────────

$COINEX_BASE_URL    = "https://api.coinex.com"
$COINEX_MARKET_TYPE = "FUTURES"

# ── Timeframes padrao ─────────────────────────────────────────────────────────

$TF_HTF    = "4hour"   # tendencia macro
$TF_MTF    = "1hour"   # estrutura e setup
$TF_LTF    = "15min"   # entrada

# ── Tori Proximity (VALIDATED 2026-05-23 TDD) ────────────────────────────────
# Trendline bounce strategy - optimized configuration
# Validated improvement: +77.6pp/ano (median +0.70% → +5.00%)
# Statistical significance: p=0.0087
# Expected: 74.5% win rate, 23.4 signals/year

$TORI_ENABLED = $true          # Enable Tori proximity scanner
$TORI_PAPER_MODE = $true       # PAPER mode (no real trades) - 30 days validation

# Trendline configuration (VALIDATED)
$TORI_MIN_TOUCHES = 3          # Minimum 3 touches (knowledge-based)
$TORI_SLOPE_MIN = 5.0          # Minimum slope (degrees)
$TORI_SLOPE_MAX = 35.0         # Maximum slope (degrees)
$TORI_PROXIMITY_MIN = -3.0     # Minimum proximity (%)
$TORI_PROXIMITY_MAX = 5.0      # Maximum proximity (%)

# Regime filter (VALIDATED: +2.50pp improvement)
$TORI_REGIME_FILTER = "OTHER"  # Only trade in "other years" (consolidation)
$TORI_OTHER_YEARS = @(2012, 2016, 2019, 2023, 2026, 2027, 2028, 2029, 2030)
$TORI_BULL_YEARS = @(2013, 2017, 2020, 2021, 2024, 2025)  # Avoid (median -0.25%)
$TORI_BEAR_YEARS = @(2014, 2015, 2018, 2022)              # Avoid (median -3.18%)

# Take-profit (VALIDATED: +4.30pp improvement, p=0.0087)
$TORI_TAKE_PROFIT_PCT = 5.0    # Exit at +5% (validated)
$TORI_STOP_LOSS_PCT = 2.0      # Stop-loss -2% below trendline
$TORI_MAX_HOLD_DAYS = 20       # h20 (20 days max hold)

# Monitoring
$TORI_CHECK_INTERVAL_MIN = 15  # Check every 15 minutes
# Note: TORI_STATE_FILE e TORI_SIGNALS_FILE definidos abaixo, apos $JOURNAL_DIR

# ── Diretorio de Journal ──────────────────────────────────────────────────────

$JOURNAL_DIR  = Join-Path $PSScriptRoot (Join-Path ".." "journal")
$JOURNAL_FILE = Join-Path $JOURNAL_DIR "trades.csv"
$LOG_DIR      = Join-Path $PSScriptRoot (Join-Path ".." "logs")

# Tori files (precisam de $JOURNAL_DIR)
$TORI_STATE_FILE   = Join-Path $JOURNAL_DIR "tori_proximity_state.json"
$TORI_SIGNALS_FILE = Join-Path $JOURNAL_DIR "tori_paper_signals.jsonl"

# ── GemAgent — Micro-Caps Explosivos (SPOT, pipeline independente) ────────────

# Deteccao de volume spike (Gate 1)
$GEM_VOL_SPIKE_MIN    = 2.0       # minimo 2.0x volume medio para spike

# Filtros de mercado (Gates 2-3)
$GEM_MCAP_DISCOVERY   = 2000000.0   # mcap <= $2M: modo DISCOVERY
$GEM_MCAP_MOMENTUM    = 20000000.0  # mcap <= $20M: modo MOMENTUM (acima: ignorar)
$GEM_LISTING_DAYS_MAX = 10          # Gate 5: max dias desde listagem (novidade)

# Sizing por modo (% do capital total)
# 2026-05-20 PM4: aumentado 0.2->0.5% e 0.4->0.8% por math realista.
#   Math antes: $5.52/trade DISCOVERY = EV ~$14/mes (10 trades), nao move ponteiro $2762.
#   Math agora: $13.81/trade DISCOVERY = EV ~$34/mes, ainda 2.5x abaixo de RISK_MAXIMO_PCT 1%.
#   Drawdown max 10 stops seguidos = 2.5% capital (vs golden rule 1% per trade respected).
$GEM_CAPITAL_DISCOVERY = 0.005  # 0.5% para DISCOVERY (altissimo risco)
$GEM_CAPITAL_MOMENTUM  = 0.008  # 0.8% para MOMENTUM

# Stop e target por modo (fracao do preco de entrada)
$GEM_STOP_DISCOVERY   = 0.50   # -50% DISCOVERY
$GEM_STOP_MOMENTUM    = 0.30   # -30% MOMENTUM
$GEM_TARGET_DISCOVERY = 2.00   # +200% DISCOVERY (R:R implicito 1:4)
$GEM_TARGET_MOMENTUM  = 0.90   # +90%  MOMENTUM

# Duracao maxima de posicao (dias corridos)
$GEM_MAX_DAYS_DISC    = 30
$GEM_MAX_DAYS_MOM     = 21
$GEM_TRAILING_PCT     = 0.30   # trailing stop: 30% abaixo do pico

# Score minimo para abertura de posicao
$GEM_SCORE_MIN_DISC   = 45     # DISCOVERY: 2026-06-11 relaxed 55→45 (allow AINUSDT score=50)
$GEM_SCORE_MIN_MOM    = 40     # MOMENTUM: 2026-06-11 relaxed 45→40

# Acumulacao organica — thresholds (Gate 6)
$GEM_CV_ORGANIC_MIN   = 0.5    # coef. variacao de volume: heterogeneidade minima
$GEM_WASH_MAX_PCT     = 0.40   # max 40% de candles suspeitos de wash
$GEM_GREEN_RATIO_MIN  = 0.65   # min 65% de candles de alta (compradores dominantes)
$GEM_WICK_RATIO_MAX   = 2.5    # max ratio sombra/corpo (pressao vendedora)

# Range minimo para pre-filtro (Gate 1 complementar)
$GEM_RANGE_MIN_PCT    = 0.15   # variacao minima de 15% no dia

# ── LLM Quota Optimization (2026-05-26) ──────────────────────────────────────
# Groq free tier: 14.4K reqs/dia (muito restritivo com 3 drones Mesa).
# Solução: aumentar intervalo scan_master 5min → 30min (6x redução de ciclos).
# + rate limiter agressivo: skip trivial momentum (SMA flat) sem chamar Mesa.
# Resultado: ~2.4K reqs/dia (sustentável 14 dias com Groq free).

$LLM_QUOTA_MODE        = "OPTIMIZED"    # "OPTIMIZED" | "AGGRESSIVE"
$SCAN_MASTER_INTERVAL_MIN = 30          # Intervalo padrão (5min → 30min)
$MESA_SKIP_FLATLINE_SMA = $true        # Skip Mesa se SMA flat (<2% mudança)
$MESA_RATE_LIMIT_MS    = 2000           # Min 2s entre drones (reduz burst)
$RATE_LIMIT_ENABLED    = $true          # Master toggle para rate limiting

# ── Criar diretorios se nao existirem ────────────────────────────────────────

@($JOURNAL_DIR, $LOG_DIR) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# FARO V3 (2026-06-02)
$global:FARO_V3_ENABLED = $true
$global:FARO_V3_MODE = "AGGRESSIVE_SCALP"       # Optimized for $300/day on $5k
$global:FARO_V3_CAPITAL_PCT = 0.005             # 0.5% per position ($2.50 per trade on $500)
$global:FARO_V3_POSITION_RISK = 0.02            # -2% hard stop (capital loss = -$2.50 per stop hit)
$global:FARO_V3_MIN_SIGNAL_COUNT = 4            # Require 4/7 signals (calibrated for LIVE data)
$global:FARO_V3_MIN_SCORE = 30                  # Score must be 30+ (parallelized: 101 coins ready)
$global:FARO_V3_TARGET1 = 0.03                  # +3% first exit (close 20%, ultra-fast)
$global:FARO_V3_TARGET2 = 0.08                  # +8% second exit (close 30%)
$global:FARO_V3_TARGET3 = 0.20                  # +20% third exit (close remaining)
$global:FARO_V3_TRAILING_STOP = 0.04            # Trail by 4% after TARGET1
$global:FARO_V3_MAX_POSITIONS = 20              # Allow 20 concurrent scalps (max $50 at risk)
$global:FARO_V3_TIMEOUT_HOURS = 3               # Exit ALL positions after 3h timeout
$global:FARO_V3_MARGIN_ENABLED = $true          # 1.5x-2.0x margin on 6/7 signals only
$global:FARO_V3_MARGIN_MAX = 2.0                # Max 2x leverage cap (capital safety)
$global:FARO_V3_MICRO_CAP_ONLY = $true          # Skip top 100 by market cap
$global:FARO_V3_ENGINE_FREQUENCY_HOURS = 3      # Scan every 3h (8 scans/day = 80 signals/day)

# SHORT AGGRESSIVE OVERRIDE (2026-06-02 paralelização)
$global:GEM_BETA_CAP_BEAR_STRONG = 1.4    # Liberar SHORT (era 1.2 no regime)

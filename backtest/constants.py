"""
constants.py — Single Source of Truth para constantes BUSINESS_RULE
Espelhado em docs/CONSTANTS.md (revisão 2026-05-16).

Uso:
    from constants import RR_DEFAULT, SMA200_PERIOD, SIDEWAYS_BAND

Adicione novas constantes AQUI, NÃO em arquivos individuais.
Arquivos que ainda têm constantes locais devem migrar — ver
docs/CONSTANTS.md seção "DRIFT".

Categorização (espelhada da MD):
- WORLD_FACT: imutáveis matemáticas/históricas
- BUSINESS_RULE: regras calibradas de negócio
- REGIME: classifier params
- BACKTEST: walk-forward/gate
- GO_CRITERION: critérios de aprovação

State vivo (capital/fees/prices) NÃO está aqui — pull live via lib_coinex.
"""

# ─────────────────────────────────────────────────────────────────────────────
# WORLD_FACT — imutáveis
# ─────────────────────────────────────────────────────────────────────────────
EULER_MASCHERONI    = 0.5772156649    # constante matemática
LUNAR_CYCLE_DAYS    = 29.530588853    # constante astronômica
HALVING_DATE_2024   = "2024-04-19"    # último halving BTC
SECONDS_PER_HOUR    = 3600


# ─────────────────────────────────────────────────────────────────────────────
# BUSINESS_RULE — risk & sizing (espelha config.ps1)
# ─────────────────────────────────────────────────────────────────────────────
RR_DEFAULT          = 5.0     # risco/retorno mínimo (1:5) — alinhado $RR_MINIMO config.ps1
SCORE_THRESHOLD     = 65.0    # score mínimo — alinhado $SCORE_MINIMO config.ps1
RISK_PCT_PER_TRADE  = 0.01    # 1% do capital — inviolável
MAX_OPEN_RISK_PCT   = 0.03    # 3% capital em risco simultâneo


# ─────────────────────────────────────────────────────────────────────────────
# REGIME classifier
# ─────────────────────────────────────────────────────────────────────────────
SMA200_PERIOD          = 200       # window para SMA200 (consolidado de SMA200_WINDOW)
WMA200_BARS_DAILY      = 1400      # 200 days × 7 (weekly aproximação)
TRANSITION_WINDOW      = 10        # transition_classifier
TRANSITION_BARS        = 20        # regime_8state
RETURN_60D_LOOKBACK    = 60        # janela de retorno 60d
SIDEWAYS_BAND          = 0.02      # ±2% em torno de SMA200 (consolidado DIST_SIDEWAYS)
DIST_STRONG            = 0.15      # ±15% para BULL_STRONG/BEAR_STRONG
RETURN_60D_STRONG      = 0.15      # retorno 60d para classificar strong
RETURN_60D_SIDEWAYS    = 0.10      # retorno 60d sideways
ADX_PERIOD             = 14        # ADX classic
ADX_STRONG_THRESHOLD   = 25.0      # ADX >= 25 = trending
CAPITULATION_THRESHOLD = 0.25      # drawdown ≥25% = capitulation
DEFAULT_BULL_THRESHOLD = 10.0      # >10% retorno 60d = bull (unificado)


# ─────────────────────────────────────────────────────────────────────────────
# BACKTEST core
# ─────────────────────────────────────────────────────────────────────────────
MAX_BARS_FORWARD       = 50
REGIME_LOOKBACK        = 200
MIN_CANDLES            = 35
ATR_STOP_MULT          = 2.0
FEE_PCT_BACKTEST       = 0.08      # CoinEx VIP 0 round-trip aprox (live via GetFeeContext)
RESAMPLE_DAYS          = 14

# ─────────────────────────────────────────────────────────────────────────────
# TRIPLE BARRIER SIMULATION (López de Prado AFML cap 3)
# Path-dependent: walk candles futuros, marca primeira barreira tocada
# ─────────────────────────────────────────────────────────────────────────────
TB_ATR_PERIOD          = 14        # ATR window para sizing stop/target
TB_STOP_ATR_MULT       = 1.0       # stop = entry - 1*ATR (R=1)
TB_TARGET_ATR_MULT     = 5.0       # target = entry + 5*ATR (R=5)
TB_MAX_BARS            = 168       # timeout 7 dias (168h) — evita trade infinito
TB_FEE_TAKER_PCT       = 0.0005    # CoinEx taker 0.05% (entry + exit aplicados)
TB_SLIPPAGE_PCT        = 0.0005    # 0.05% slippage típico em micro-caps


# ─────────────────────────────────────────────────────────────────────────────
# GO_CRITERION (diferentes critérios — nomes explícitos pós DRIFT-2)
# ─────────────────────────────────────────────────────────────────────────────
GO_CRITERION_POSITIVE_YEARS_PCT   = 70.0   # long_14y: 70% anos positivos
GO_CRITERION_POSITIVE_WINDOWS_PCT = 60.0   # walkforward_14y: 60% windows
GO_CRITERION_TOTAL_PF             = 1.5    # profit factor mínimo
GO_CRITERION_MAX_STREAK           = 4      # streak negativo curto
GO_CRITERION_ERGODICITY           = 0.40   # consistência mínima
GO_LIVE_DD_THRESHOLD_R            = 20.0   # max drawdown em R
GO_LIVE_DISCOUNT_FACTOR           = 0.5    # Sharpe descontado por incerteza
GO_LIVE_THRESHOLD                 = 1.5    # Sharpe descontado mínimo


# ─────────────────────────────────────────────────────────────────────────────
# SIMONS GATE (López de Prado)
# ─────────────────────────────────────────────────────────────────────────────
DSR_THRESHOLD          = 0.95      # Deflated Sharpe Ratio
PSR_THRESHOLD          = 0.95      # Probabilistic Sharpe Ratio
SIMONS_N_TRIALS_DEFAULT = 50       # número de variações testadas
SIMONS_SAMPLE_VAR       = 0.5      # variância amostral de Sharpes


# ─────────────────────────────────────────────────────────────────────────────
# STRATA / EDGES
# ─────────────────────────────────────────────────────────────────────────────
EDGE_STRONG_MIN        = 0.50
EDGE_MEDIUM_MIN        = 0.30
EDGE_WEAK_MIN          = 0.10
DIRECTION_MIN_EDGE     = 0.30


# ─────────────────────────────────────────────────────────────────────────────
# FUNDING PEAK
# ─────────────────────────────────────────────────────────────────────────────
FUNDING_HOT_THRESHOLD    = 0.05    # rolling 5d mean funding
FUNDING_EXTREME_THRESHOLD = 0.08
FUNDING_DROP_PCT         = 0.30    # 30% drop do peak = signal
FUNDING_LOOKBACK_DAYS    = 14
FUNDING_PEAK_MIN_DAYS    = 5


# Backward-compat aliases (DEPRECATE em refactor futuro)
SMA200_WINDOW = SMA200_PERIOD
DIST_SIDEWAYS = SIDEWAYS_BAND
SCORE_THRESHOLD_V2 = SCORE_THRESHOLD


# ─────────────────────────────────────────────────────────────────────────────
# TEST FIXTURES — mock values para testes (evita magic numbers nos tests)
# ─────────────────────────────────────────────────────────────────────────────
TEST_BTC_PRICE              = 60000.0
TEST_ALT_PRICE_SUB_DOLLAR   = 0.5
TEST_CAPITAL_USDT           = 1000.0
TEST_RR_SCENARIO            = 5.0
TEST_ATR_PCT                = 2.5
TEST_CHANGE_24H_BULLISH     = 5.0
TEST_CHANGE_24H_BEARISH     = -5.0

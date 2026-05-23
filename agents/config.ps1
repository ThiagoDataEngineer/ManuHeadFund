# config.ps1 — Configuracao central do sistema de agentes
# Para chaves reais: preencha agents/config.local.ps1 (no .gitignore)

# Carrega segredos locais se existirem (config.local.ps1 tem prioridade)
$_localConfig = Join-Path $PSScriptRoot "config.local.ps1"
if (Test-Path $_localConfig) { . $_localConfig }

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
$RR_MINIMO         = 5.0      # risco/retorno minimo (1:5) — alta exigencia, menos setups, mais upside
$RR_PREFERIDO      = 5.0      # risco/retorno preferido (1:5)
$SCORE_MINIMO      = 65.0     # score ponderado minimo — 55 era bar baixo para capital real
$MAX_TRADES_DIA    = 5        # maximo de trades por dia
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

$CLAUDE_MODEL       = "claude-sonnet-4-6"          # Tech + Mentor: analise complexa
$CLAUDE_MODEL_CHEAP = "claude-haiku-4-5-20251001"  # Fund + Sent + Chain: ~10x mais barato
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

# ── Diretorio de Journal ──────────────────────────────────────────────────────

$JOURNAL_DIR  = "$PSScriptRoot\..\journal"
$JOURNAL_FILE = "$JOURNAL_DIR\trades.csv"
$LOG_DIR      = "$PSScriptRoot\..\logs"

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
$GEM_SCORE_MIN_DISC   = 70     # DISCOVERY: exige score alto (risco maior)
$GEM_SCORE_MIN_MOM    = 60     # MOMENTUM: bar ligeiramente menor

# Acumulacao organica — thresholds (Gate 6)
$GEM_CV_ORGANIC_MIN   = 0.5    # coef. variacao de volume: heterogeneidade minima
$GEM_WASH_MAX_PCT     = 0.40   # max 40% de candles suspeitos de wash
$GEM_GREEN_RATIO_MIN  = 0.65   # min 65% de candles de alta (compradores dominantes)
$GEM_WICK_RATIO_MAX   = 2.5    # max ratio sombra/corpo (pressao vendedora)

# Range minimo para pre-filtro (Gate 1 complementar)
$GEM_RANGE_MIN_PCT    = 0.15   # variacao minima de 15% no dia

# ── Criar diretorios se nao existirem ────────────────────────────────────────

@($JOURNAL_DIR, $LOG_DIR) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

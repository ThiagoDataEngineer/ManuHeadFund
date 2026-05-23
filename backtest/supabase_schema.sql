-- ============================================================
-- CoinEx AI Agent — Backtesting Schema
-- Rodar no Supabase Dashboard:
-- https://supabase.com/dashboard/project/urcqtpklpfyvizcgcsia/sql/new
-- Não afeta tabelas existentes: payments, shares, trials, etc.
-- ============================================================

-- ── 1. CANDLES (dados históricos OHLCV) ──────────────────────────────────────
create table if not exists candles (
  id          bigserial   primary key,
  market      text        not null,
  period      text        not null,
  ts          timestamptz not null,
  open        numeric     not null,
  high        numeric     not null,
  low         numeric     not null,
  close       numeric     not null,
  volume      numeric     not null,
  inserted_at timestamptz default now()
);

create unique index if not exists candles_market_period_ts
  on candles (market, period, ts);

create index if not exists candles_lookup
  on candles (market, period, ts desc);

-- ── 2. SIGNALS (sinais gerados pelo TechAgent sobre histórico) ────────────────
create table if not exists backtest_signals (
  id          bigserial   primary key,
  market      text        not null,
  period      text        not null,
  bar_ts      timestamptz not null,
  signal      text        not null,   -- COMPRA | VENDA | NEUTRO
  score       numeric,                -- 0-100
  entry_price numeric,
  stop_loss   numeric,
  take_profit numeric,
  atr         numeric,
  indicators  jsonb,                  -- ex: {"ema_cross": true, "rsi_os": true}
  created_at  timestamptz default now()
);

create index if not exists signals_market_period
  on backtest_signals (market, period, bar_ts desc);

-- ── 3. TRADES (trades simulados a partir dos sinais) ─────────────────────────
create table if not exists backtest_trades (
  id           bigserial   primary key,
  signal_id    bigint      references backtest_signals(id),
  market       text        not null,
  direction    text        not null,  -- LONG | SHORT
  entry_ts     timestamptz not null,
  exit_ts      timestamptz,
  entry_price  numeric     not null,
  exit_price   numeric,
  stop_loss    numeric     not null,
  take_profit  numeric     not null,
  exit_reason  text,                  -- STOP | TARGET | TIMEOUT
  result_r     numeric,               -- ex: +2.4 ou -1.0
  pnl_pct      numeric,
  fee_pct      numeric     default 0.10,
  capital_used numeric,
  regime       text,                  -- bull | bear | sideways (classify_regime via SMA200)
  created_at   timestamptz default now()
);

-- ── 4. BACKTEST_RUNS (resultado de cada execução completa) ────────────────────
create table if not exists backtest_runs (
  id              bigserial   primary key,
  market          text        not null,
  period          text        not null,
  date_from       timestamptz not null,
  date_to         timestamptz not null,
  capital_initial numeric     not null,
  total_trades    int,
  winning_trades  int,
  win_rate        numeric,
  expectancy_r    numeric,
  profit_factor   numeric,
  max_drawdown    numeric,
  sharpe_ratio    numeric,
  calmar_ratio    numeric,
  final_capital   numeric,
  return_pct      numeric,
  notes            text,
  regime_breakdown jsonb,              -- {"bull": {...}, "bear": {...}, "sideways": {...}, "counts": {...}}
  created_at       timestamptz default now()
);

-- ALTER para adicionar colunas em tabelas existentes (rodar se já criadas):
-- alter table backtest_trades add column if not exists regime text;
-- alter table backtest_runs  add column if not exists regime_breakdown jsonb;

-- ── 5. PUMP_FINGERPRINTS (biblioteca de padrões de pump orgânico) ─────────────
create table if not exists pump_fingerprints (
  id              bigserial   primary key,
  market          text        not null unique,   -- ex: PEPEUSDT
  cv_volume       numeric     not null,          -- coeficiente de variação do volume (>0.5 = orgânico)
  green_ratio     numeric     not null,          -- fração de candles de alta (0-1)
  body_ratio      numeric     not null,          -- razão média corpo/range (0-1)
  max_retraction  numeric     not null,          -- retração máxima do pico durante janela (0-1)
  vol_accel       numeric     not null,          -- aceleração: avg_2a_metade / avg_1a_metade
  outcome_pct     numeric     not null default 0, -- resultado real do pump (ex: 441.0 = +441%)
  notes           text,
  computed_at     timestamptz default now()
);

create index if not exists fingerprints_outcome
  on pump_fingerprints (outcome_pct desc);

-- Euclidean similarity query (uso no gem_agent.ps1 via Supabase RPC ou REST):
-- select market, outcome_pct,
--        sqrt(power(cv_volume - $1, 2) + power(green_ratio - $2, 2)) as distance
-- from pump_fingerprints
-- order by distance asc
-- limit 10;

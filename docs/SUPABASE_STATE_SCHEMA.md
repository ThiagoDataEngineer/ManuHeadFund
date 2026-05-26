# Supabase State Store — Schema (prefixo `mhf_` para isolar)

**Status:** Ready to apply (Fase 1 TDD complete, 14/14 PASS).

## ⚠️ Por que prefixo `mhf_`

O projeto Supabase compartilha tabelas com outros apps:
- ✅ Suas (ManuHeadFund): `backtest_*`, `candles`, `agent_events`
- ❌ De outros apps: `payments`, `shares`, `pro_access`, `lnurl_*`, `pro_codes`, etc.

Para evitar qualquer chance de conflito ou colisão de nomes futura, **TODAS** as tabelas
novas usam prefixo `mhf_` (ManuHeadFund).

---

## Como aplicar

1. Abra https://urcqtpklpfyvizcgcsia.supabase.co/project/_/sql
2. Cole **TODO** o bloco SQL abaixo
3. Run (vai criar 6 tabelas com prefixo `mhf_` + RLS policies)
4. Volte aqui e roda smoke: `powershell.exe -File scripts/smoke_supabase_state.ps1`
5. Se passar tudo: ativar flag `journal/USE_SUPABASE_STATE.flag`

## SQL (copiar inteiro)

```sql
-- ============================================================================
-- ManuHeadFund State Store — 6 tabelas com prefixo mhf_ (isolamento)
-- Apply once via Supabase SQL Editor
-- ============================================================================

-- 1. Tabela smoke (apaga depois se quiser)
CREATE TABLE IF NOT EXISTS mhf_state_smoke (
    market   TEXT PRIMARY KEY,
    side     TEXT,
    entry    NUMERIC,
    stop     NUMERIC,
    target   NUMERIC,
    snapshot TEXT
);

-- 2. mhf_trailing_positions: estado das posições trailing/Moon Bag
-- pk_id permite múltiplas legs por market (Moon Bag tem harvest+moon)
CREATE TABLE IF NOT EXISTS mhf_trailing_positions (
    pk_id            TEXT PRIMARY KEY,        -- "{market}" ou "{market}:{moonBagKind}"
    market           TEXT NOT NULL,
    side             TEXT NOT NULL,
    entry            NUMERIC NOT NULL,
    stop             NUMERIC NOT NULL,
    target           NUMERIC NOT NULL,
    size             NUMERIC,
    "orderId"        TEXT,
    source           TEXT,
    mode             TEXT,
    max_days         INTEGER DEFAULT 0,
    dd_threshold_pct NUMERIC DEFAULT 30,
    phase            INTEGER DEFAULT 0,
    peak             NUMERIC,
    "stopCurrent"    NUMERIC,
    active           BOOLEAN DEFAULT TRUE,
    "openedAt"       TEXT,
    "updatedAt"      TEXT,
    "currentPrice"   NUMERIC,
    "moonBagPairId"  TEXT,
    "moonBagKind"    TEXT,                    -- 'harvest' | 'moon' | NULL (legacy)
    "layer4Advisory" TEXT,
    "layer4AdvisoryReason" TEXT,
    "lastLayer4Review"     TEXT,
    "moonBagAdvisory"      TEXT,
    "moonBagAdvisoryReason" TEXT,
    "lastMoonBagReview"    TEXT,
    "lastMentorReview"     TEXT,
    "entryRegime"          TEXT
);
CREATE INDEX IF NOT EXISTS idx_mhf_trailing_market ON mhf_trailing_positions (market);
CREATE INDEX IF NOT EXISTS idx_mhf_trailing_active ON mhf_trailing_positions (active) WHERE active = TRUE;

-- 3. mhf_capital_context: snapshot atual do capital (1 row)
CREATE TABLE IF NOT EXISTS mhf_capital_context (
    id          INTEGER PRIMARY KEY DEFAULT 1,
    spot        NUMERIC NOT NULL,
    futures     NUMERIC NOT NULL,
    total       NUMERIC NOT NULL,
    snapshot_ts TEXT NOT NULL,
    source      TEXT NOT NULL
);

-- 4. mhf_validation_snapshots: append-only log de cada ciclo
CREATE TABLE IF NOT EXISTS mhf_validation_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    snapshot_ts  TEXT NOT NULL,
    cycle        INTEGER,
    positions_n  INTEGER,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_mhf_validation_ts ON mhf_validation_snapshots (snapshot_ts DESC);

-- 5. mhf_mentor_reviews: log de Layer 2 6h checkpoint reviews
CREATE TABLE IF NOT EXISTS mhf_mentor_reviews (
    id           BIGSERIAL PRIMARY KEY,
    market       TEXT NOT NULL,
    review_ts    TEXT NOT NULL,
    decision     TEXT,
    reason       TEXT,
    confidence   NUMERIC,
    new_stop     NUMERIC,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_mhf_mentor_market_ts ON mhf_mentor_reviews (market, review_ts DESC);

-- 6. mhf_trade_outcomes: trades fechados (necessário pra Kelly Layer 3)
CREATE TABLE IF NOT EXISTS mhf_trade_outcomes (
    id            BIGSERIAL PRIMARY KEY,
    market        TEXT NOT NULL,
    side          TEXT NOT NULL,
    entry         NUMERIC NOT NULL,
    exit_price    NUMERIC,
    stop          NUMERIC,
    target        NUMERIC,
    r_multiple    NUMERIC,
    pnl_pct       NUMERIC,
    closed_at     TEXT NOT NULL,
    close_reason  TEXT,
    source        TEXT,
    mode          TEXT,
    payload       JSONB
);
CREATE INDEX IF NOT EXISTS idx_mhf_outcomes_closed ON mhf_trade_outcomes (closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_mhf_outcomes_market ON mhf_trade_outcomes (market);

-- ============================================================================
-- Row Level Security (RLS): tudo permitido para anon + service_role
-- (mesmo padrão das outras tabelas suas; ajustar depois se quiser restringir)
-- ============================================================================

ALTER TABLE mhf_state_smoke           ENABLE ROW LEVEL SECURITY;
ALTER TABLE mhf_trailing_positions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE mhf_capital_context       ENABLE ROW LEVEL SECURITY;
ALTER TABLE mhf_validation_snapshots  ENABLE ROW LEVEL SECURITY;
ALTER TABLE mhf_mentor_reviews        ENABLE ROW LEVEL SECURITY;
ALTER TABLE mhf_trade_outcomes        ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (idempotente: posso rodar SQL de novo sem erro)
DROP POLICY IF EXISTS anon_all       ON mhf_state_smoke;
DROP POLICY IF EXISTS anon_all       ON mhf_trailing_positions;
DROP POLICY IF EXISTS anon_all       ON mhf_capital_context;
DROP POLICY IF EXISTS anon_all       ON mhf_validation_snapshots;
DROP POLICY IF EXISTS anon_all       ON mhf_mentor_reviews;
DROP POLICY IF EXISTS anon_all       ON mhf_trade_outcomes;
DROP POLICY IF EXISTS service_all    ON mhf_state_smoke;
DROP POLICY IF EXISTS service_all    ON mhf_trailing_positions;
DROP POLICY IF EXISTS service_all    ON mhf_capital_context;
DROP POLICY IF EXISTS service_all    ON mhf_validation_snapshots;
DROP POLICY IF EXISTS service_all    ON mhf_mentor_reviews;
DROP POLICY IF EXISTS service_all    ON mhf_trade_outcomes;

CREATE POLICY anon_all ON mhf_state_smoke           FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON mhf_trailing_positions    FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON mhf_capital_context       FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON mhf_validation_snapshots  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON mhf_mentor_reviews        FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON mhf_trade_outcomes        FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY service_all ON mhf_state_smoke           FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON mhf_trailing_positions    FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON mhf_capital_context       FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON mhf_validation_snapshots  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON mhf_mentor_reviews        FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON mhf_trade_outcomes        FOR ALL TO service_role USING (true) WITH CHECK (true);
```

---

## Convenção de nomes (importante)

| Tabela criada | Conteúdo |
|---|---|
| `mhf_trailing_positions` | Estado das posições trailing + Moon Bag |
| `mhf_capital_context` | Snapshot atual de capital (spot + futures + total) |
| `mhf_validation_snapshots` | Log append-only de cada ciclo do scan_master |
| `mhf_mentor_reviews` | Layer 2: 6h checkpoint reviews |
| `mhf_trade_outcomes` | Trades fechados (Kelly Layer 3) |
| `mhf_state_smoke` | Tabela de teste (pode dropar depois) |

## Tabelas existentes que NÃO vamos tocar

**Suas (ManuHeadFund original):**
- `backtest_runs`, `backtest_signals`, `backtest_trades`, `candles`, `agent_events`, `api_registry`, `events`, `idem_store`, `trials`

**De outros apps (não tocar):**
- `payments`, `shares`, `pending_splits`, `lnurl_challenges`, `preimage_claims`
- `pro_access`, `promo_codes`, `waitlist`

---

## O que vem depois

Quando o smoke passar:

1. **Migrar dados existentes**: `migrate_state_to_supabase.ps1` lê `journal/*.json` atual e escreve em `mhf_*`. Mantém JSON local intocado.
2. **Refactor libs** (`lib_trailing.ps1`, `lib_moon_bag.ps1`, `lib_capital_context.ps1`).
3. **Ativar flag**: `New-Item journal/USE_SUPABASE_STATE.flag`
4. **Adicionar 4 jobs no GitHub Actions** (Layers 1, 2, 4, 5)
5. **24h paper validation**

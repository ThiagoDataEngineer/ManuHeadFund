# Supabase State Store — Schema

**Status:** Ready to apply (Fase 1 TDD complete, 14/14 PASS).

Para ativar Layers 1-5 24/7 na nuvem, precisamos migrar `journal/*.json` para Postgres
no Supabase. Este doc tem o SQL completo + ordem de execução.

---

## Como aplicar

1. Abra https://urcqtpklpfyvizcgcsia.supabase.co/project/_/sql
2. Cole **TODO** o bloco SQL abaixo
3. Run (vai criar 5 tabelas + 1 de teste + RLS policies)
4. Volte aqui e roda smoke: `powershell.exe -File scripts/smoke_supabase_state.ps1`
5. Se passar tudo: ativar flag `journal/USE_SUPABASE_STATE.flag`

## SQL (copiar inteiro)

```sql
-- ============================================================================
-- ManuHeadFund State Store — 5 tabelas core + 1 smoke test
-- Apply once via Supabase SQL Editor
-- ============================================================================

-- 1. Tabela smoke (apaga depois se quiser)
CREATE TABLE IF NOT EXISTS state_smoke_test (
    market   TEXT PRIMARY KEY,
    side     TEXT,
    entry    NUMERIC,
    stop     NUMERIC,
    target   NUMERIC,
    snapshot TEXT
);

-- 2. trailing_positions: estado das posições trailing/Moon Bag
-- PK composto market+pairId pois Moon Bag tem 2 legs por market
CREATE TABLE IF NOT EXISTS trailing_positions (
    pk_id            TEXT PRIMARY KEY,        -- "{market}:{moonBagKind|main}" para unicidade
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
CREATE INDEX IF NOT EXISTS idx_trailing_market ON trailing_positions (market);
CREATE INDEX IF NOT EXISTS idx_trailing_active ON trailing_positions (active) WHERE active = TRUE;

-- 3. capital_context: snapshot atual do capital (1 row apenas)
CREATE TABLE IF NOT EXISTS capital_context (
    id          INTEGER PRIMARY KEY DEFAULT 1,
    spot        NUMERIC NOT NULL,
    futures     NUMERIC NOT NULL,
    total       NUMERIC NOT NULL,
    snapshot_ts TEXT NOT NULL,
    source      TEXT NOT NULL
);

-- 4. validation_snapshots: append-only log de cada ciclo do scan_master
CREATE TABLE IF NOT EXISTS validation_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    snapshot_ts  TEXT NOT NULL,
    cycle        INTEGER,
    positions_n  INTEGER,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_validation_ts ON validation_snapshots (snapshot_ts DESC);

-- 5. mentor_reviews: log de Layer 2 6h checkpoint reviews
CREATE TABLE IF NOT EXISTS mentor_reviews (
    id           BIGSERIAL PRIMARY KEY,
    market       TEXT NOT NULL,
    review_ts    TEXT NOT NULL,
    decision     TEXT,
    reason       TEXT,
    confidence   NUMERIC,
    new_stop     NUMERIC,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_mentor_market_ts ON mentor_reviews (market, review_ts DESC);

-- 6. trade_outcomes: trades fechados (necessário pra Kelly Layer 3)
CREATE TABLE IF NOT EXISTS trade_outcomes (
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
CREATE INDEX IF NOT EXISTS idx_outcomes_closed ON trade_outcomes (closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_outcomes_market ON trade_outcomes (market);

-- ============================================================================
-- Row Level Security (RLS)
-- Política simples: anon role pode tudo (dev). Em prod produção, restrinja.
-- ============================================================================

ALTER TABLE state_smoke_test     ENABLE ROW LEVEL SECURITY;
ALTER TABLE trailing_positions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE capital_context      ENABLE ROW LEVEL SECURITY;
ALTER TABLE validation_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentor_reviews       ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_outcomes       ENABLE ROW LEVEL SECURITY;

-- Drop existing policies se já houver (idempotente)
DROP POLICY IF EXISTS anon_all ON state_smoke_test;
DROP POLICY IF EXISTS anon_all ON trailing_positions;
DROP POLICY IF EXISTS anon_all ON capital_context;
DROP POLICY IF EXISTS anon_all ON validation_snapshots;
DROP POLICY IF EXISTS anon_all ON mentor_reviews;
DROP POLICY IF EXISTS anon_all ON trade_outcomes;

CREATE POLICY anon_all ON state_smoke_test     FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON trailing_positions   FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON capital_context      FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON validation_snapshots FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON mentor_reviews       FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON trade_outcomes       FOR ALL TO anon USING (true) WITH CHECK (true);

-- Idem para service_role (caso aplique pelos secrets do GitHub)
CREATE POLICY service_all ON state_smoke_test     FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON trailing_positions   FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON capital_context      FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON validation_snapshots FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON mentor_reviews       FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON trade_outcomes       FOR ALL TO service_role USING (true) WITH CHECK (true);
```

---

## O que vem depois

Quando o smoke passar:

1. **Migrar dados existentes**: script `scripts/migrate_state_to_supabase.ps1` lê `journal/*.json` atual e escreve no Supabase. Mantém JSON local intocado (rollback fácil).
2. **Refactor libs** (`lib_trailing.ps1`, `lib_moon_bag.ps1`, `lib_capital_context.ps1`) para chamar `Get-StateRecords` / `Save-StateRecords`. Backwards-compat preservada.
3. **Ativar flag**: `New-Item journal/USE_SUPABASE_STATE.flag`
4. **Adicionar 4 jobs no GitHub Actions**:
   - `layer1-trailing-adaptive` (5min)
   - `layer2-mentor-review` (30min)
   - `layer4-tori-timestop` (5min)
   - `layer5-moonbag-review` (5min)
5. **24h paper validation** com Layers 1-5 ativos 24/7

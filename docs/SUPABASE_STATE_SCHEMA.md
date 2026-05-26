# Supabase State Store — Schema `manuheadfund` (isolamento total)

**Status:** Ready to apply (Etapa 1 TDD complete: 23/23 PASS).

## Estratégia de isolamento

Todas as tabelas do ManuHeadFund vivem dentro do schema dedicado `manuheadfund`,
**fora** do schema `public` onde estão as tabelas dos seus outros apps.

| Schema | Conteúdo | Quem mexe |
|---|---|---|
| `public` | `payments`, `shares`, `pro_access`, `lnurl_*`, `events`, `api_registry`, etc. | **Outros apps** |
| `manuheadfund` | Tudo do ManuHeadFund (existentes migradas + novas) | **Apenas este projeto** |

Isso significa que mesmo com `service_role` key, é impossível um bug no nosso código
tocar acidentalmente em `payments` (schema diferente, queries direcionadas).

---

## Aplicação em 2 passos

**Passo 1**: Rodar SQL abaixo no SQL Editor (cria schema + 6 tabelas novas + RLS).

**Passo 2** (manual — não tem API): Habilitar o schema na API REST do Supabase:
1. Acesse: https://urcqtpklpfyvizcgcsia.supabase.co/project/_/settings/api
2. Procure **"Exposed schemas"**
3. Adicione `manuheadfund` na lista (provavelmente já tem `public` lá)
4. Clique **Save**

> Sem o Passo 2, o PostgREST **não expõe** o schema novo via REST e nosso código falha
> com erro `42P01: relation "manuheadfund.trailing_positions" does not exist`.

---

## Etapa 1 — Schema + 6 tabelas novas (NÃO mexe nas existentes)

```sql
-- ============================================================================
-- ManuHeadFund Etapa 1: schema dedicado + 6 tabelas novas
-- Apply once via Supabase SQL Editor
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS manuheadfund;
GRANT USAGE ON SCHEMA manuheadfund TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA manuheadfund GRANT ALL ON TABLES TO anon, authenticated, service_role;

-- 1. Tabela smoke (apaga depois se quiser)
CREATE TABLE IF NOT EXISTS manuheadfund.state_smoke (
    market   TEXT PRIMARY KEY,
    side     TEXT,
    entry    NUMERIC,
    stop     NUMERIC,
    target   NUMERIC,
    snapshot TEXT
);

-- 2. trailing_positions: estado das posições trailing/Moon Bag
CREATE TABLE IF NOT EXISTS manuheadfund.trailing_positions (
    pk_id            TEXT PRIMARY KEY,
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
    "moonBagKind"    TEXT,
    "layer4Advisory" TEXT,
    "layer4AdvisoryReason" TEXT,
    "lastLayer4Review"     TEXT,
    "moonBagAdvisory"      TEXT,
    "moonBagAdvisoryReason" TEXT,
    "lastMoonBagReview"    TEXT,
    "lastMentorReview"     TEXT,
    "entryRegime"          TEXT
);
CREATE INDEX IF NOT EXISTS idx_trailing_market ON manuheadfund.trailing_positions (market);
CREATE INDEX IF NOT EXISTS idx_trailing_active ON manuheadfund.trailing_positions (active) WHERE active = TRUE;

-- 3. capital_context: snapshot atual do capital (1 row)
CREATE TABLE IF NOT EXISTS manuheadfund.capital_context (
    id          INTEGER PRIMARY KEY DEFAULT 1,
    spot        NUMERIC NOT NULL,
    futures     NUMERIC NOT NULL,
    total       NUMERIC NOT NULL,
    snapshot_ts TEXT NOT NULL,
    source      TEXT NOT NULL
);

-- 4. validation_snapshots: append-only log de cada ciclo do scan_master
CREATE TABLE IF NOT EXISTS manuheadfund.validation_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    snapshot_ts  TEXT NOT NULL,
    cycle        INTEGER,
    positions_n  INTEGER,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_validation_ts ON manuheadfund.validation_snapshots (snapshot_ts DESC);

-- 5. mentor_reviews: log de Layer 2 6h checkpoint reviews
CREATE TABLE IF NOT EXISTS manuheadfund.mentor_reviews (
    id           BIGSERIAL PRIMARY KEY,
    market       TEXT NOT NULL,
    review_ts    TEXT NOT NULL,
    decision     TEXT,
    reason       TEXT,
    confidence   NUMERIC,
    new_stop     NUMERIC,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_mentor_market_ts ON manuheadfund.mentor_reviews (market, review_ts DESC);

-- 6. trade_outcomes: trades fechados (Kelly Layer 3)
CREATE TABLE IF NOT EXISTS manuheadfund.trade_outcomes (
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
CREATE INDEX IF NOT EXISTS idx_outcomes_closed ON manuheadfund.trade_outcomes (closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_outcomes_market ON manuheadfund.trade_outcomes (market);

-- ============================================================================
-- RLS: tudo permitido para anon + service_role
-- ============================================================================

ALTER TABLE manuheadfund.state_smoke           ENABLE ROW LEVEL SECURITY;
ALTER TABLE manuheadfund.trailing_positions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE manuheadfund.capital_context       ENABLE ROW LEVEL SECURITY;
ALTER TABLE manuheadfund.validation_snapshots  ENABLE ROW LEVEL SECURITY;
ALTER TABLE manuheadfund.mentor_reviews        ENABLE ROW LEVEL SECURITY;
ALTER TABLE manuheadfund.trade_outcomes        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS anon_all    ON manuheadfund.state_smoke;
DROP POLICY IF EXISTS anon_all    ON manuheadfund.trailing_positions;
DROP POLICY IF EXISTS anon_all    ON manuheadfund.capital_context;
DROP POLICY IF EXISTS anon_all    ON manuheadfund.validation_snapshots;
DROP POLICY IF EXISTS anon_all    ON manuheadfund.mentor_reviews;
DROP POLICY IF EXISTS anon_all    ON manuheadfund.trade_outcomes;
DROP POLICY IF EXISTS service_all ON manuheadfund.state_smoke;
DROP POLICY IF EXISTS service_all ON manuheadfund.trailing_positions;
DROP POLICY IF EXISTS service_all ON manuheadfund.capital_context;
DROP POLICY IF EXISTS service_all ON manuheadfund.validation_snapshots;
DROP POLICY IF EXISTS service_all ON manuheadfund.mentor_reviews;
DROP POLICY IF EXISTS service_all ON manuheadfund.trade_outcomes;

CREATE POLICY anon_all ON manuheadfund.state_smoke           FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON manuheadfund.trailing_positions    FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON manuheadfund.capital_context       FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON manuheadfund.validation_snapshots  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON manuheadfund.mentor_reviews        FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all ON manuheadfund.trade_outcomes        FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY service_all ON manuheadfund.state_smoke           FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON manuheadfund.trailing_positions    FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON manuheadfund.capital_context       FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON manuheadfund.validation_snapshots  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON manuheadfund.mentor_reviews        FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all ON manuheadfund.trade_outcomes        FOR ALL TO service_role USING (true) WITH CHECK (true);
```

---

## Etapa 2 — Migrar 4 tabelas existentes (DEPOIS da Etapa 1 validada)

**⚠️ NÃO RODAR AGORA.** Só rodar quando Etapa 1 estiver 100% funcional.

Mover tabelas grandes (`candles` tem 282k rows, `backtest_signals`/`backtest_trades`
têm 26k cada) para o schema `manuheadfund`. `ALTER TABLE SET SCHEMA` é atomic e
instantâneo (não copia dados, só renomeia metadado).

```sql
-- ============================================================================
-- Etapa 2: migrar tabelas existentes ManuHeadFund para schema dedicado
-- ROLLBACK: ALTER TABLE manuheadfund.candles SET SCHEMA public;
-- ============================================================================

ALTER TABLE public.candles           SET SCHEMA manuheadfund;
ALTER TABLE public.backtest_runs     SET SCHEMA manuheadfund;
ALTER TABLE public.backtest_signals  SET SCHEMA manuheadfund;
ALTER TABLE public.backtest_trades   SET SCHEMA manuheadfund;
```

**Após esta operação**:
- `backtest/db.py` precisa receber update para passar `Accept-Profile: manuheadfund`
- Mesma coisa para qualquer caller de `agent_events` se você descobrir que é nosso

---

## Plano completo (4 etapas)

```
Etapa 1 — SQL atual + Settings UI   →  Schema criado + tabelas novas + REST exposto
Etapa 2 — Smoke validation real      →  Roda smoke_supabase_state.ps1
Etapa 3 — Migrate JSON → Supabase    →  Posicoes atuais migradas
Etapa 4 — Refactor 3 libs + 4 jobs   →  Layers 1-5 24/7 GitHub Actions
Etapa 5 — Migrar candles/backtest    →  ALTER TABLE SET SCHEMA + db.py update
```

---

## Tabelas que continuam fora (outros apps)

`payments`, `shares`, `pending_splits`, `lnurl_challenges`, `preimage_claims`,
`pro_access`, `promo_codes`, `waitlist`, `events`, `api_registry`, `agent_events`,
`idem_store`, `trials`.

Estas pertencem aos seus outros apps (sistema de trials/pagamentos/Lightning) —
ficam intocadas no schema `public`.

# scripts/apply_supabase_schema.ps1
# Cria schema 'manuheadfund' + 6 tabelas + RLS + expose schema na REST API.
#
# Uso:
#   $env:SUPABASE_PAT = "sbp_..."
#   .\scripts\apply_supabase_schema.ps1
#
# Idempotente: pode rodar varias vezes sem efeito colateral.

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/lib_supabase_management.ps1")
. (Join-Path $root "agents/config.local.ps1")

# Validate PAT in env
$pat = $env:SUPABASE_PAT
if (-not $pat) {
    Write-Host "ERR: env var SUPABASE_PAT nao definido. Setar antes de rodar:" -ForegroundColor Red
    Write-Host '  $env:SUPABASE_PAT = "sbp_..."' -ForegroundColor Yellow
    exit 1
}

# Project ref derived from SUPABASE_URL
$projectRef = ($env:SUPABASE_URL -replace "https?://", "" -replace "\..*", "")
Write-Host "ProjectRef: $projectRef" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== Step 1: Validate PAT ===" -ForegroundColor Cyan
$projects = Test-SupabasePat -Pat $pat
$ourProj = $projects | Where-Object { $_.id -eq $projectRef }
if (-not $ourProj) {
    Write-Host "ERR: PAT nao tem acesso ao projeto $projectRef" -ForegroundColor Red
    exit 1
}
Write-Host "OK: PAT valido, projeto '$($ourProj.name)' acessivel ($($ourProj.status))" -ForegroundColor Green

# ============================================================================
# Step 2: SQL DDL — schema + tables + RLS
# ============================================================================

$sql = @'
-- Idempotente: pode rodar varias vezes
CREATE SCHEMA IF NOT EXISTS manuheadfund;
GRANT USAGE ON SCHEMA manuheadfund TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA manuheadfund GRANT ALL ON TABLES TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS manuheadfund.state_smoke (
    market   TEXT PRIMARY KEY,
    side     TEXT,
    entry    NUMERIC,
    stop     NUMERIC,
    target   NUMERIC,
    snapshot TEXT
);

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
CREATE INDEX IF NOT EXISTS idx_mhf_trailing_market ON manuheadfund.trailing_positions (market);
CREATE INDEX IF NOT EXISTS idx_mhf_trailing_active ON manuheadfund.trailing_positions (active) WHERE active = TRUE;

CREATE TABLE IF NOT EXISTS manuheadfund.capital_context (
    id          INTEGER PRIMARY KEY DEFAULT 1,
    spot        NUMERIC NOT NULL,
    futures     NUMERIC NOT NULL,
    total       NUMERIC NOT NULL,
    snapshot_ts TEXT NOT NULL,
    source      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS manuheadfund.validation_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    snapshot_ts  TEXT NOT NULL,
    cycle        INTEGER,
    positions_n  INTEGER,
    payload      JSONB
);
CREATE INDEX IF NOT EXISTS idx_mhf_validation_ts ON manuheadfund.validation_snapshots (snapshot_ts DESC);

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
CREATE INDEX IF NOT EXISTS idx_mhf_mentor_market_ts ON manuheadfund.mentor_reviews (market, review_ts DESC);

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
CREATE INDEX IF NOT EXISTS idx_mhf_outcomes_closed ON manuheadfund.trade_outcomes (closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_mhf_outcomes_market ON manuheadfund.trade_outcomes (market);

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

-- Verifica resultado: lista tabelas no schema novo
SELECT table_name FROM information_schema.tables WHERE table_schema = 'manuheadfund' ORDER BY table_name;
'@

Write-Host ""
Write-Host "=== Step 2: Apply SQL (schema + 6 tables + RLS) ===" -ForegroundColor Cyan
$result = Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $sql
Write-Host "OK: SQL aplicado. Tabelas criadas:" -ForegroundColor Green
$result | ForEach-Object { Write-Host "  - manuheadfund.$($_.table_name)" -ForegroundColor DarkGray }

# ============================================================================
# Step 3: Add 'manuheadfund' to exposed schemas list
# ============================================================================

Write-Host ""
Write-Host "=== Step 3: Expose schema in REST API ===" -ForegroundColor Cyan
$exposeResult = Add-SupabaseExposedSchema -Pat $pat -ProjectRef $projectRef -Schema "manuheadfund"
Write-Host "  $($exposeResult.message)" -ForegroundColor $(if ($exposeResult.changed) { "Green" } else { "DarkGray" })
Write-Host "  Exposed schemas now: $($exposeResult.schemas -join ', ')" -ForegroundColor DarkGray

Write-Host ""
Write-Host "=== ALL DONE ===" -ForegroundColor Green
Write-Host "Proximo passo: smoke test" -ForegroundColor Yellow
Write-Host "  powershell.exe -File scripts/smoke_supabase_state.ps1" -ForegroundColor DarkGray

-- Setup trailing_positions table for state store sync (2026-06-11)
-- Fix: warning PGRST205 "Could not find the table 'public.trailing_positions'"
-- em todo ciclo do scan_master (lib_trailing.ps1 Get/Save-TrailingPositions).
--
-- Execute isso no Supabase Dashboard (SQL Editor)
-- URL: https://app.supabase.com/project/[seu-project]/sql/new
--
-- Colunas camelCase entre aspas: lib_state_store.ps1 envia as keys do JSON
-- direto como colunas (orderId, stopCurrent, openedAt, updatedAt, moonBagKind).

CREATE TABLE public.trailing_positions (
    pk_id TEXT PRIMARY KEY,            -- market ou "market:moonBagKind" (_Get-TrailingPkId)
    market TEXT NOT NULL,
    side TEXT,
    entry NUMERIC,
    stop NUMERIC,
    target NUMERIC,
    "orderId" TEXT,
    source TEXT,
    mode TEXT,                         -- GEM | STANDARD | TIER_A | ORPHAN_AUTO
    max_days INTEGER,
    dd_threshold_pct NUMERIC,
    phase INTEGER,
    peak NUMERIC,
    "stopCurrent" NUMERIC,
    active BOOLEAN DEFAULT TRUE,
    "openedAt" TEXT,                   -- "yyyy-MM-dd HH:mm:ss" (formato da lib, sem TZ)
    "updatedAt" TEXT,
    "moonBagKind" TEXT,                -- runner | bag (Moon Bag: 2 legs por market)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Indexes pra performance
CREATE INDEX idx_trailing_positions_market ON public.trailing_positions(market);
CREATE INDEX idx_trailing_positions_active ON public.trailing_positions(active);

-- Row-level security (consistente com trade_rejections)
ALTER TABLE public.trailing_positions ENABLE ROW LEVEL SECURITY;

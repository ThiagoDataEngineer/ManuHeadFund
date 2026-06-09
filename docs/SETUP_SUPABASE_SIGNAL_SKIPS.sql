-- Setup signal_skips table for counterfactual learning (2026-06-09)
-- Execute isso no Supabase Dashboard (SQL Editor)
-- URL: https://app.supabase.com/project/[seu-project]/sql/new

CREATE TABLE public.signal_skips (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL,
    market TEXT NOT NULL,
    direction TEXT NOT NULL,
    gate TEXT NOT NULL,
    entry_price NUMERIC NOT NULL,
    regime TEXT,
    source TEXT DEFAULT 'regime',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Indexes pra performance
CREATE INDEX idx_signal_skips_ts ON public.signal_skips(ts DESC);
CREATE INDEX idx_signal_skips_market ON public.signal_skips(market);
CREATE INDEX idx_signal_skips_regime ON public.signal_skips(regime);

-- Row-level security (opcional)
ALTER TABLE public.signal_skips ENABLE ROW LEVEL SECURITY;

-- Setup trade_rejections table for counterfactual learning (2026-06-09)
-- Execute isso no Supabase Dashboard (SQL Editor)
-- URL: https://app.supabase.com/project/[seu-project]/sql/new

CREATE TABLE public.trade_rejections (
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
CREATE INDEX idx_trade_rejections_ts ON public.trade_rejections(ts DESC);
CREATE INDEX idx_trade_rejections_market ON public.trade_rejections(market);
CREATE INDEX idx_trade_rejections_regime ON public.trade_rejections(regime);

-- Row-level security (opcional)
ALTER TABLE public.trade_rejections ENABLE ROW LEVEL SECURITY;

-- SETUP_SUPABASE_COIN_REGISTRY_DYNAMIC_2026_08_19.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Achado real (2026-08-19): Invoke-FqsLazyEnrich (gem_executor.ps1) ja
-- chama automaticamente backtest/coingecko_enrichment.py -- so que
-- journal/coin_registry.json e curadoria manual estatica (commitada, 68
-- moedas). 19+ dos top ~100 mercados FUTURES mais liquidos da CoinEx
-- (LINK/ADA/AVAX/BNB/UNI/etc) ficavam presos em FQS=AVOID por AUSENCIA de
-- cadastro, nao por qualidade real -- travando qualquer sinal LONG forte
-- nelas em SPOT pequeno pra sempre, nunca FUTURES alavancado.
--
-- Owner pediu escala real ("lista de 100 moedas atualizadas") -- fix
-- pontual (cadastrar manualmente) nao escala. Esta tabela e o destino do
-- job periodico (coingecko_enrichment.py --all-from-registry, cron 6h)
-- que mantem dado FRESCO (preco atual, ATH, supply) sem depender de
-- pesquisa manual a cada expansao futura.
--
-- market como PRIMARY KEY: upsert, 1 linha por mercado, sempre a versao
-- mais recente. Get-FundamentalScore passa a consultar esta tabela
-- PRIMEIRO (dado dinamico fresco), com fallback pro coin_registry.json
-- estatico se a tabela estiver vazia/indisponivel (fail-safe -- curadoria
-- manual sempre disponivel mesmo se Supabase cair).
--
-- Campos derivados automaticamente via CoinGecko (age_years, supply_capped,
-- recovered_2021_ath, current_price_usd, ath_all_time_usd) -- burn_active/
-- utility_score/concentration_top10 continuam SO no registro estatico
-- (julgamento curado manual, CoinGecko nao tem esse dado) -- Get-
-- FundamentalScore precisa mesclar os dois, nao substituir um pelo outro.

CREATE TABLE IF NOT EXISTS manuheadfund.coin_registry_dynamic (
    market              TEXT PRIMARY KEY,
    age_years           NUMERIC,
    supply_capped       BOOLEAN,
    recovered_2021_ath  BOOLEAN,
    current_price_usd   NUMERIC,
    ath_all_time_usd    NUMERIC,
    max_supply          NUMERIC,
    circulating_supply  NUMERIC,
    coingecko_id        TEXT,
    source              TEXT DEFAULT 'coingecko_enrichment_auto',
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coin_registry_dynamic_updated ON manuheadfund.coin_registry_dynamic(updated_at DESC);

ALTER TABLE manuheadfund.coin_registry_dynamic ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON manuheadfund.coin_registry_dynamic TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "coin_registry_dynamic_all" ON manuheadfund.coin_registry_dynamic;
CREATE POLICY "coin_registry_dynamic_all" ON manuheadfund.coin_registry_dynamic
    FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';

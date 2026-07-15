-- docs/SETUP_SUPABASE_GEMS_CANDIDATES.sql
-- 2026-07-15: Schema da tabela gems_candidates (discovery pipeline gem-scanner -> gem-executor)
-- Copy-paste este script INTEIRO no Supabase SQL Editor e Run.
--
-- Auditoria 2026-07-15 (achado P2): esta tabela nunca teve schema versionado
-- no repo -- foi criada manualmente (ou nunca foi criada) direto no Supabase
-- Dashboard. gem_scanner_live.ps1/gem_executor_live.ps1 usavam SUPABASE_ANON_KEY
-- pra INSERT/SELECT/PATCH, o que so funciona se existir RLS policy publica pra
-- role anon -- impossivel confirmar sem o schema. Scripts corrigidos (2026-07-15)
-- pra usar SUPABASE_SERVICE_KEY (bypassa RLS), mas a tabela ainda precisa existir
-- com as colunas certas.

CREATE TABLE IF NOT EXISTS public.gems_candidates (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL,
    direction TEXT NOT NULL,
    tori_score FLOAT8 DEFAULT 65,
    change_24h FLOAT8 DEFAULT 0,
    volume_24h FLOAT8 DEFAULT 0,
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gems_candidates_status ON public.gems_candidates(status);
CREATE INDEX IF NOT EXISTS idx_gems_candidates_discovered ON public.gems_candidates(discovered_at DESC);

-- RLS: habilitado, mas sem policy pra 'anon' -- exige SERVICE_KEY (usado pelos
-- scripts atuais). Se algum dia precisar de acesso via ANON_KEY (ex: dashboard
-- publico read-only), criar policy explicita de SELECT aqui.
ALTER TABLE public.gems_candidates ENABLE ROW LEVEL SECURITY;

-- VERIFY:
-- SELECT count(*) FROM public.gems_candidates;
-- SELECT market, direction, status, discovered_at FROM public.gems_candidates ORDER BY discovered_at DESC LIMIT 10;

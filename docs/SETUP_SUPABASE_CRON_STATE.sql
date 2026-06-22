-- cron_state: last-run de cada job agendado (dedup robusto a throttle do GH Actions).
-- Rode no SQL Editor do Supabase. Idempotente.
create table if not exists manuheadfund.cron_state (
    job_id       text primary key,
    last_run_utc timestamptz not null,
    updated_at   timestamptz not null default now()
);

-- grants (mesmo padrao das outras tabelas manuheadfund)
grant all on manuheadfund.cron_state to anon, authenticated, service_role;

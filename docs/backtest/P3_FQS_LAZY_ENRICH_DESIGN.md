# P3 — FQS Lazy On-Demand Enrichment (2026-05-23)

> User analysis identificou funil: 1761 pairs -> 12 whitelist (0.7%). Test-TierGuard
> hard-coded check + GEM auto-approve veta por FQS missing. Solution P3: synchronous
> CoinGecko enrichment quando GEM detected mas market missing no registry.

## Sumário executivo

P3 selecionado entre alternativas (P1 whitelist auto-expand / P2 GEM bypass tier guard / P3 lazy FQS):
- **Mais seguro**: preserva defesas Tier guard + auto-approve 6 sub-gates
- **Mais cirúrgico**: só elimina gap "GEM detected → FQS missing → veto cego"
- **Latência aceitável**: ~7-10s per GEM novo
- **Rollback fast**: opt-in via env FQS_LAZY_ENRICH_ENABLED=1

## Arquitetura

```
GEM detected (score≥80) 
  → Test-GemAutoApprove sub-gate #3 (FQS category)
    → IF FQS = N/A_no_registry AND env=1:
      → Invoke-FqsLazyEnrich (synchronous)
        ├── Test-FqsLazyEnrichEligible (MARKET_TO_CG mapping)
        ├── Rate limit check (6s global / 24h per market)
        └── Exec python coingecko_enrichment.py --markets X
      → Get-FundamentalScore (re-lookup)
      → If QUALITY+: GEM passes
      → Else: veta normal
```

## Implementação

### lib_fqs_lazy_enrich.ps1 (180 linhas)
- `Test-FqsLazyEnrichEligible`: parse MARKET_TO_CG from python source
- `Invoke-FqsLazyEnrich`: synchronous python exec, 20s default timeout
- `Get-FqsLazyCacheStatus`: rate-limit + per-market TTL check
- `_Log-LazyAttempt`: append-only journal/fqs_lazy_enrich_attempts.jsonl

### Wire em Test-GemAutoApprove
Insertion após sub-gate #3 (FQS category check):
```powershell
if ($fqsCategory -eq "N/A_no_registry" -and $env:FQS_LAZY_ENRICH_ENABLED -eq "1") {
    if (Get-Command Invoke-FqsLazyEnrich -ErrorAction SilentlyContinue) {
        $lazyResult = Invoke-FqsLazyEnrich -Market $Gem.market -TimeoutSec 20
        if ($lazyResult.success -and $lazyResult.new_fqs_category) {
            $fqsCategory = $lazyResult.new_fqs_category
        }
    }
}
```

## Rate limiting (preserva CoinGecko free tier 10 calls/min)

| Constraint | Default | Why |
|---|---|---|
| `LAZY_ENRICH_MIN_INTERVAL_SEC` | 6s | 10 calls/min upper bound |
| `LAZY_ENRICH_PER_MARKET_TTL_HOURS` | 24h | Evita re-attempt repetido |
| `TimeoutSec` (default) | 20s | CoinGecko + Python startup + multi-HTTP |

## Smoke real (validated)

| Market | Eligible | Duration | New Category |
|---|---|---|---|
| NEARUSDT | ✓ cg=near | 8s (timeout originally) | success after timeout fix |
| WLDUSDT | ✓ cg=worldcoin-wld | 9.6s | SPECULATIVE |
| FAKEXXXUSDT | ✗ not in MARKET_TO_CG | 0s | n/a |

WLD enrichment confirmou: SPECULATIVE retornado, registry persisted, future calls hit cache.

## Expected impact (forward)

| Métrica | Antes P3 | Após P3 |
|---|---|---|
| GEMs com FQS=N/A_no_registry | ~3-5/dia veto cego | Tentativa enrichment ~7s |
| Registry growth rate | 4/cycle (queue weekly) | +1/GEM detection (real-time) |
| CoinGecko free tier usage | ~30 calls/day (queue) | +0-10 calls/day (lazy) |
| GEMs auto-approved fora dos 12 whitelist | 0 | TBD (depende FQS QUALITY+) |

## Riscos identificados

1. **CoinGecko rate limit hit**: 10 calls/min strict — burst de GEMs em 1 cycle pode rejeitar. Mitigado pelo 6s interval check.
2. **Latência 7-10s no GEM detection**: aceitável (era rejected anyway sem enrichment).
3. **Python startup overhead**: ~2s cold start. Acumula com CoinGecko HTTPS.
4. **MARKET_TO_CG manual mapping**: ainda required pre-condition. Mercados não mapped → eligibility=false.

## Recomendação forward

Em 30d:
- Audit `journal/fqs_lazy_enrich_attempts.jsonl` para rate-limit hits
- Track quantos GEMs passaram pelo lazy enrich e foram auto-approved
- Se rate < 5/day: keep enabled
- Se rate > 30/day: considerar cron weekly de pre-enrichment

## Skill insight novo

> **"Synchronous on-demand é viável quando latência tolerable AND custos delimitados"**.
> Pre-enrichment batch (weekly) força queue depth. Lazy synchronous descobre na hora.
> Trade-off correto: aceitar 7-10s latência pra unlock GEMs que ficariam veto cego.

## Activation

Env var `FQS_LAZY_ENRICH_ENABLED=1` ativada para User scope. Próxima sessão daemon
herda automaticamente.

Rollback: `[System.Environment]::SetEnvironmentVariable('FQS_LAZY_ENRICH_ENABLED', '', 'User')`
+ daemon restart.

## Artefatos

- `agents/lib_fqs_lazy_enrich.ps1` (180 linhas)
- `agents/lib_gem_auto_approve.ps1:60+` (wire)
- `tests/lib_fqs_lazy_enrich.Tests.ps1` (10 PASS)
- `journal/fqs_lazy_enrich_attempts.jsonl` (audit trail)
- Doc: este arquivo

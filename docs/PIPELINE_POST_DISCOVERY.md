# Pipeline post-discovery (source-aware downstream)

Documenta o que acontece DEPOIS de um market ser descoberto/promovido, e
ESPECIFICAMENTE o que cada estagio downstream deve validar de forma diferente
por fonte (GEM vs TIER_A_LIVE vs STANDARD).

> Criado 2026-05-19 PM após gap identificado: "o que vier depois do GEM deve
> estar ciente do tipo de fonte e validar a mais ou diferente que outros".

## Fluxos source-aware (4 fontes distintas)

```
┌────────────────────────────────────────────────────────────────────────┐
│  FONTE                  │  CARACTERISTICAS                              │
├─────────────────────────┼───────────────────────────────────────────────┤
│  GEM                    │  Micro-cap, vol baixo, momentum-driven        │
│                         │  Risco alto, R:R 1:200 alvo, max_days budget  │
│                         │                                               │
│  TIER_A_LIVE            │  Validado Bailey-LdP, capital real            │
│                         │  Sharpe60>=1.5, DSR>=0.6, conservative DD     │
│                         │                                               │
│  ORCHESTRATOR (legacy)  │  Watchlist tradicional + Mentor APROVAR       │
│                         │  R:R 1:5, paper-first                         │
│                         │                                               │
│  NARRATIVE_SEED         │  Discovery weekly, ainda paper-track          │
│                         │  Aguarda Sharpe60 maturar                     │
└─────────────────────────┴───────────────────────────────────────────────┘
```

## Estagios downstream e suas validacoes ESPECIFICAS

### 1. Position Entry (executor)

| Stage | GEM | TIER_A_LIVE | STANDARD |
|---|---|---|---|
| Market type routing | spot OR futures | spot OR futures | futures only |
| Sizing % capital | DISCOVERY 0.3% / MOM 0.5% | 1% × tier multiplier | 1% |
| Min vol threshold | $10K | $200K | $200K |
| Pre-trade gates | gem_safety + Tori | promotion_gates + MCE | whitelist + Mesa |

### 2. Trailing Stop Manager

| Stage | GEM | TIER_A_LIVE | STANDARD |
|---|---|---|---|
| Mode | "GEM" | "TIER_A" | "STANDARD" |
| Phase 3 trail width | 20% peak | ATR × 2.0 | ATR × 2.0 |
| Moon bag partial 50% | sim, no target | nao | nao |
| max_days enforce | sim (14d default) | nao (sem limite) | nao |

### 3. Drawdown Monitor (daily cron)

| Source | FLAG threshold | CRITICAL threshold | Action |
|---|---|---|---|
| `gem` | -30% | -45% | TG alert + dont auto-close (gem tolera vol) |
| `tier_a` / `orchestrator` | -15% | -25% | TG + re-validate matrix (CRITICAL) |
| `default` | -15% | -25% | Mesmo Tier A |

### 4. Auto-demote ladder

| Stage | GEM | TIER_A_LIVE | STANDARD |
|---|---|---|---|
| Streak FLAG -> propose demote | N/A (not in ladder) | 3+ dias = TG /demote | N/A |
| Cooldown post-demote | N/A | 30 dias | N/A |
| Sharpe streak negative | N/A | 4 sem = forced demote | N/A |

### 5. Beta concentration gate

| Source | Conta beta? |
|---|---|
| TIER_A_LIVE | sim, AVG <= 1.0 |
| GEM | nao (separate budget de risco) |
| STANDARD | sim |

### 6. Funding rate gate

| Source | Threshold long | Threshold short |
|---|---|---|
| Todos | z >= 2.0 BLOCK | z <= -2.0 BLOCK |

(Funding e exchange-wide, nao depende de source da posicao)

## Persistencia (lib_trailing.ps1 Add-TrailingPosition)

Campos NEW 2026-05-19 PM:
- `mode`: "GEM" | "TIER_A" | "STANDARD" (auto-derive de Source se vazio)
- `max_days`: 0 = sem limite. GEM default 14.
- `dd_threshold_pct`: 0 = global default. GEM=40%, TIER_A=25%.

## Que cron checa o que (e quando)

| Cron | Frequencia | Source-aware? | Que estagio aplica |
|---|---|---|---|
| `scan_master` | 15-120min adaptive | sim via mode | entry triagem + mesa |
| `gem_loop` | 1h | implicito (so opera gem) | gem_agent + executor |
| `Update-TrailingStops` | Por ciclo de scan_master | **sim 2026-05-19** | max_days enforce + GEM trail |
| `tier_a_drawdown_monitor` | Domingo + diario | **sim 2026-05-19** | FLAG/CRITICAL por source |
| `promotion_cron` | Domingo 03h | nao (so Tier B promote) | ladder progression |
| `auto_demote_proposal` | Domingo (via cron) | sim (so Tier A LIVE) | TG /demote propose |
| `weekly_discovery` | Domingo (via cron) | nao (sempre paper-first) | Bailey-LdP tier ABC |
| `weekly_data_refresh` | Sabado 22h | nao | funding + correlation cache |

## TDD Coverage

- `tests/lib_trailing_source_aware.Tests.ps1` — 9 tests: mode/max_days/dd_threshold persist + Test-MaxDaysExceeded
- `backtest/tests/test_drawdown_source_aware.py` — 7 tests: SOURCE_THRESHOLDS validation

## Quando reavaliar / retroalimentar

- Se GEM positions ficarem expostas > max_days frequentemente -> investigar pq sistema nao fechou organicamente (target atingido? stop atingido?)
- Se Tier A LIVE bater CRITICAL toda semana -> reduzir threshold de promote inicial (Sharpe60 1.5 -> 1.8?)
- Se 0 GEM trades em 30 dias -> gem_agent gates demasiado restritivos
- Se XMR/HYPE/TON nao graduam em 60d apesar de Sharpe alto -> investigar promotion_gates blockers

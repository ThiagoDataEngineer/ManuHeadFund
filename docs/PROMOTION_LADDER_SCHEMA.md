# Promotion Ladder Schema

> Append-only event log em `journal/promotion_pipeline.jsonl`.
> Cada linha = 1 evento JSON. State atual de um market = última linha onde `market` aparece.

## Eventos possiveis (campo `event`)

| event | quando ocorre | tier_state efeito |
|---|---|---|
| `discovered` | candidato entra DESCOBERTA | set para 0 |
| `evaluated` | gate roda (nao muda tier) | mantem |
| `promoted` | passa pra proximo tier | +1 |
| `demoted` | regride 1 tier | -1 |
| `user_decision` | user responde Telegram | mantem (metadata) |

## tier_state mapping

| state | label | size_pct | trade real? |
|---|---|---|---|
| 0 | DESCOBERTA | 0 | nao |
| 1 | OBSERVATION | 0 | nao (apenas log) |
| 2 | PAPER_C | 25 | paper simulado |
| 3 | PAPER_B | 50 | paper-real CoinEx |
| 4 | TIER_A_LIVE | 100 | real |

## Schema de cada linha

```json
{
  "ts": "2026-05-18T15:00:00Z",
  "event": "discovered|evaluated|promoted|demoted|user_decision",
  "market": "PENDLEUSDT",
  "tier_state": 0,
  "tier_label": "DESCOBERTA",
  "source": "user_manual|snapshot_auto|news_feed|system",
  "metrics": {
    "n_trades": 0,
    "sharpe_30d": null,
    "max_dd": null,
    "mom_20d": null,
    "regime_asset": null,
    "regime_btc": null,
    "psr": null,
    "days_in_tier": 0
  },
  "gate_eval": {
    "gate_name": "obs_to_c|c_to_b|b_to_a|demote",
    "passed": true,
    "reasons": ["sharpe_30d_ok", "regime_ok", ...],
    "failures": []
  },
  "user_decision": "approve|reject|wait",
  "notes": "optional human readable"
}
```

## Funcoes principais (lib_promotion_ladder.ps1)

| Funcao | Retorno |
|---|---|
| `Add-PromotionEvent -Market X -Event Y` | append linha |
| `Get-PromotionState -Market X` | object {state, label, since, days_in_tier} ou null |
| `Get-PromotionCandidatesByState -State N` | array de markets |
| `Test-GateObservationToC -Metrics` | bool + reasons |
| `Test-GateCToB -Metrics` | bool + reasons |
| `Test-GateBToLive -Metrics` | bool + reasons |
| `Test-DemoteTrigger -Market X` | bool + reason |
| `Invoke-PromotionPropose -Market X` | suggestion: "promote"\|"demote"\|"hold" |
| `Invoke-PromotionPropose -EnforceGates -CurrentTierAMarkets ...` | aplica `Invoke-AllGates` (15+ gates incl FQS, beta, funding) antes do gate de tier — adicionado 2026-05-19 |

## Asymmetric demote (NOVO 2026-05-19)

Demote rapido para crash protection. Ver `agents/lib_asymmetric_demote.ps1`:

| Funcao | Retorno |
|---|---|
| `Test-AsymmetricDemoteCondition -Market X -StreakThreshold 3` | `{should_demote, streak, reason}` |
| `Invoke-AutoDemoteIfNeeded -Market X` | demote automatico se 3+ dias FLAG OU 1 CRITICAL |

**Regra**: 3 dias FLAG consecutivos = auto-demote (sem 30d cooldown padrao). Protege contra Luna-style -99% em 72h.

## Fundamental Quality gate (NOVO 2026-05-19, ONDA 3.1)

FQS V1.5 wired em `Invoke-AllGates` (opt-in `-TargetTier`) e `weekly_discovery` (auto). Ver `agents/lib_fundamental_quality.ps1`:

| Categoria | FQS | Tier elegivel |
|---|---|---|
| BLUE_CHIP | 6-7 | TIER_A + TIER_B + GEM |
| QUALITY | 4-5 | TIER_A + TIER_B + GEM |
| SPECULATIVE | 2-3 | GEM only |
| AVOID | 0-1 | bloqueado |

Refinos V1.5:
1. `young_NA_cycle` bonus pra tokens < 2y (cycle_resilience nao penaliza)
2. `burn_net_deflation` reconhece supply discipline mesmo em uncapped (ex: ETH EIP-1559)
3. `concentration_insider_pct` override quando exchange wallets distorcem `concentration_top10`

## Params opcionais (2026-05-20 PM)

`Invoke-PromotionPropose` e `Invoke-PromotionCycle` aceitam params extras para ativar gates antes dormentes:

| Param | Tipo | Default | Gate ativado |
|---|---|---|---|
| `-CurrentPrice` | `[Nullable[double]]` | `$null` | `pump_buy` (se Peak7d tambem fornecido) |
| `-Peak7d` | `[Nullable[double]]` | `$null` | `pump_buy` |
| `-DateBrt` | `[Nullable[datetime]]` | `$null` | `time_of_week` |
| `-Direction` | `string` | `"long"` | usado por funding + time_of_week |
| `-PositionSizeUsd` | `[Nullable[double]]` | `$null` | `slippage` (se VolumeUsd > 0) |
| `-CurrentLongMarkets` | `string[]` | `@()` | `cross_corr` |

**Backward compat**: sem param novo, gate respectivo eh SKIP (opt-in). Comportamento existente preservado.

### `Invoke-PromotionCycle -EnforceGates` (2026-05-20 PM)

Aplica `Invoke-AllGates` ANTES de cada `propose_promote`. Antes era so Test-Gate*ToB (DSR/Sharpe), agora cobre concentration/beta/FQS/sector/cooldown/funding/min_volume/phase_boundary em todos promotes.

Resolve gap descoberto 2026-05-20: `Invoke-AllGates` era so chamada por `Invoke-PromotionPropose` (orfa em prod). `Invoke-PromotionCycle` (produca0o real via cron) nao chamava -> todos 13 gates eram **dormentes em prod**.

**Como ativar**: passar `-EnforceGates` na chamada de `promotion_weekly_cron.ps1` (caller pode ser editado quando paper validation passar).

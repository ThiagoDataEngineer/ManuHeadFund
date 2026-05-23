# V6_LIVE_ENABLED.flag — Activation Criteria

**Criado 2026-05-20 PM4**. Define critério **temporal + comportamental** explícito pra promover V6 cascade de paper-only para live execution.

## Decisão registrada

Após fix Mentor hallucination (PM1) + fix runspace dot-source (PM3), V6 está pronto **estruturalmente**. Mas precisa validação prod **comportamental** antes de tocar capital real.

## Métrica honesta — VETARs de mérito vs ruído estrutural

**IMPORTANTE PM6 2026-05-20**: a métrica "VETAR sem causa acionável" deve EXCLUIR:

| Tipo | Razão de exclusão | Patterns no `reason` |
|---|---|---|
| **Hallucination (pré-PM1)** | Bug de prompt já corrigido | `mesa pulou`, `fqs indisponivel`, `caixa preta`, `[ALERTA]` |
| **Conflito modo (pré-PM6)** | Bug arquitetural já corrigido | `conflito.*modo`, `mutuamente exclusivos` |
| **Fail-safe (Mentor down)** | Infra issue, não decisão | `mentor indisponivel` |

Apenas **VETARs de mérito** (33/55 = 60% no histórico atual) contam pra calibração.

## Gate de ativação — 4 condições simultâneas

| # | Condição | Como medir | Status atual |
|---|---|---|---|
| 1 | **5 ciclos consecutivos pós-fix com 0 hallucination + 0 conflito modo** | grep `decisions.csv` excluindo patterns acima | ⏳ 1/5 (pós-PM6) |
| 2 | **≥1 APROVAR coerente OU veto-de-mérito por ciclo** (não fail-safe/conflito) | filtrar `mentor_decision` pós-exclusão dos 3 tipos ruído | ⏳ valida cron 09:00 BRT |
| 3 | **Pester regression ≥1620 PASS** estável (sem drift) | `validate_pre_deploy.ps1` exit 0 antes de criar flag | ✅ atual 1620 |
| 4 | **Watch_status sem alertas vermelhos** 72h | runspace_audit + drawdown + workers OK | ✅ atual all green |

## Data alvo

**Sábado 2026-05-23** (3 dias úteis paper validation):
- Cron 09:00 BRT amanhã (21/05): ciclo 1 pós-fix L3 (runspace)
- 22/05 09:00: ciclo 2
- 23/05 09:00: ciclo 3 — se passou todos 4 critérios → criar flag

Se algum critério falhar → adiar +3 dias, re-validar.

## Como ativar

```powershell
# Após confirmar 4 critérios:
"ativado_em: $((Get-Date).ToString('o'))" | Out-File journal/V6_LIVE_ENABLED.flag -Encoding utf8

# Validate:
pwsh scripts/validate_pre_deploy.ps1   # exit 0

# Telegram alert manual:
pwsh scripts/watch_status.ps1 -Telegram

# Primeiro ciclo live: monitorar Wait-TelegramApproval 5min response
```

## Como reverter

```powershell
Remove-Item journal/V6_LIVE_ENABLED.flag -Force
# Próximo ciclo já volta paper-only
```

## Sinais de alarme pra rollback

| Sinal | Ação |
|---|---|
| Mentor APROVA mais de 80% em 24h | Pode estar sub-vetando — investigar prompt |
| 1+ ordem real sem `/ok` response (race condition) | Rollback imediato + audit `Wait-TelegramApproval` |
| Capital DD intraday > -3% | Rollback automático via Daily Loss Circuit |
| Slippage > 0.5% em 1+ ordem | Rollback + audit slippage gate |
| Provider trace mostra >50% Haiku rescue | Anthropic instabilidade — pausar até retomar |

## Decisão paralela: GEM sizing

Math do GEM 0.2% × $2762 = $5.52/trade EV ~$14/mês = não muda vida.

**Aumentado pra 0.5% DISCOVERY / 0.8% MOMENTUM** ([config.ps1:135](agents/config.ps1#L135)). EV $34/mês mantendo RISK_MAXIMO_PCT 1% golden rule (drawdown 10 stops = 2.5% capital).

**Próximo ajuste**: quando capital >$5K, revisar pra 1% / 1.5% (mantendo golden rule sob escala maior).

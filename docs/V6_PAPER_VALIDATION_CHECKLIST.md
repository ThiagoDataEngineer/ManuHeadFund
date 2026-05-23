# V6 Paper Validation Checklist

> **Criado 2026-05-20**. Critérios para promover V6 cascade de paper-only (B default)
> para LIVE execution (A opt-in via `journal/V6_LIVE_ENABLED.flag`).

## Por que validar antes de ligar

V6 cascade teve correções estruturais hoje (Mesa.confluencias missing,
Mentor FullContext, 4 gates wired). Cascade nunca executou em LIVE.
Antes de criar `V6_LIVE_ENABLED.flag`, validar paper full cycle.

## Critérios mínimos (TODOS devem passar)

### 1. Volume de decisões
- [ ] ≥ **50 decisões V6** em paper observadas em ~7 dias
- [ ] **Mix realista**: pelo menos 5 APROVAR + 5 VETAR + 5 ABORTAR (não 100% de qualquer um)
- [ ] Comando: `grep "EXECUTAR\|ABORTAR" journal/decisions.csv | tail -50`

### 2. Mentor decisões coerentes
- [ ] **Taxa VETAR sem causa actionable < 30%** (antes era 100% por confluências missing)
- [ ] Mentor cita knowledge_cited em ≥ 50% das decisões
- [ ] Razões de VETAR são específicas (não "Mesa pulou debate")
- [ ] **Zero "FQS não declarado" hallucinations** quando market está no `coin_registry.json`
- [ ] Provider distribution majoritariamente `anthropic_sonnet` (>80%) — Haiku rescue só em outage
- [ ] Comando: `python -c "import csv; rows = list(csv.DictReader(open('journal/decisions.csv'))); v = [r for r in rows[-50:] if r['mentor_decision']=='VETAR']; print(len(v), 'VETOs')"`
- [ ] Hallucination check: `grep -ic 'Mesa pulou' journal/decisions.csv` deve crescer < 1/dia
- [ ] Hallucination FQS: `grep -ic 'FQS não declarado' journal/decisions.csv` deve crescer < 1/dia

### 3. Gates funcionais
- [ ] **13+ gates loggados** em pelo menos 1 ciclo (concentration/daily_loss/sector/cooldown/min_volume/phase/funding/beta/FQS + pump_buy/time_of_week/slippage/cross_corr)
- [ ] Nenhum gate retorna erro em runtime (audit logs/master_*.log)
- [ ] FQS V1.6 partial path dispara pelo menos 1x (após batch enrichment)
- [ ] **`ENFORCE_GATES_ENABLED.flag` ativado** — `Invoke-PromotionCycle` aplica `Invoke-AllGates` antes de cada propose_promote (era órfã antes de PM2)
- [ ] FQS coverage: ≥ 90% dos markets do top candidates ciclo têm entry em `coin_registry.json` (queue auto-enrich roda Sábado)

### 4. Sem regressões
- [ ] **Pester full suite ≥ 1594 PASS** consistente (baseline 2026-05-20)
- [ ] **Python pytest ≥ 997 PASS** consistente
- [ ] Comando: `Invoke-Pester -Path tests/ -PassThru -Quiet`

### 5. Watchdog estável
- [ ] **Zero false respawns** em 24h consecutivas (era 3699/dia antes do fix OR→AND)
- [ ] gem_loop alive consistente (PID estável)
- [ ] Comando: `grep "false respawn\|GemLoop precisa respawn" journal/watchdog.log | tail -100 | wc -l` deve ser 0

### 6. Capital safety
- [ ] `LIVE_MODE_ENABLED.flag` ativo + capital ≥ $2500
- [ ] Beta avg portfolio ≤ 1.2 (cap atual)
- [ ] Asymmetric demote streak < 3 em todos Tier A LIVE
- [ ] Drawdown vs peak (source-aware): nenhum Tier A em CRITICAL

### 7. Wait-TelegramApproval funcional
- [ ] Teste manual: `Send-TelegramAlert -Message "test"` chega
- [ ] /ok responde no tg_listener (offset tracking ok)
- [ ] Timeout 5min validado em pelo menos 1 teste manual

## Como ativar A após validação

```powershell
# 1. Confirmar todos os criterios acima passam
# 2. Criar flag opt-in:
"ativado_em: $((Get-Date).ToString('o'))" | Out-File journal/V6_LIVE_ENABLED.flag -Encoding utf8

# 3. Restart watchdog + scan_master para pegar flag:
Stop-Process -Name powershell -Force  # ATENCAO: vai matar tudo PS, use idempotent restart
# Ou apenas aguardar proximo cron PromotionCron (~02:00 BRT)

# 4. Monitorar primeira ordem real com /ok response
```

## Rollback rápido

```powershell
Remove-Item journal/V6_LIVE_ENABLED.flag -Force
# V6 imediatamente volta a paper-only no proximo ciclo
```

## Sinais de alarme — desativar imediatamente

- Mentor APROVAR > 80% das decisões (sistema pode estar inflando confiança)
- Mais de 2 ordens reais em 1 dia sem aprovação Telegram (race condition)
- Slippage > 0.5% em qualquer ordem (lib slippage gate fez algo errado)
- Capital drawdown intraday > -3% (DLC capital-scaled deveria ter parado antes)

## Cron monitor sugerido (futuro)

Criar `scripts/v6_validation_daily.ps1` que roda às 23:55 BRT e:
1. Lê últimas 50 decisões V6 do dia
2. Conta APROVAR/VETAR/ABORTAR distribution
3. Verifica os 7 critérios acima
4. Envia summary Telegram com checklist passes/fails

Implementação deferred até houver paper data suficiente (~7 dias).

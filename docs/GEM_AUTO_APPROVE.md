# GEM Auto-Approve — Strict Criteria

**Criado 2026-05-20 PM4. ✅ ATIVADO 14:28 BRT** — flag `journal/GEM_AUTO_APPROVE.flag` presente.

Captura GEMs quando user dorme/desconectado SEM perder a defensividade.

## Motivação

Audit 24h em 2026-05-20: **6 GEMs detectados, 0 executados**. Razão: `Wait-TgCallbackApproval` aguarda 5min, user offline → timeout → reject.

User pode estar dormindo, em reunião, ou simplesmente sem celular. **6 trades × $13.81 EV × 30% win = $24/dia perdidos por inatividade**.

## Como ativar

```powershell
"ativado_em: $((Get-Date).ToString('o'))" | Out-File journal/GEM_AUTO_APPROVE.flag -Encoding utf8
```

Para desativar:
```powershell
Remove-Item journal/GEM_AUTO_APPROVE.flag -Force
```

## Critérios STRICT (TODOS necessários)

| # | Critério | Default | Por quê |
|---|---|---|---|
| 1 | `journal/GEM_AUTO_APPROVE.flag` presente | opt-in | Decisão consciente do user |
| 2 | Gem.score >= 90 | top-tier | Reduz falsos positivos do scanner |
| 3 | FQS category in (BLUE_CHIP, QUALITY) | validated | Tokenomics + history filtrados |
| 4 | Market tem entry no `coin_registry.json` | NOT N/A_no_registry | Sem dados = sem confiança |
| 5 | Sizing <= 1% do capital | $27.62 max em $2762 | Golden rule risk_max 1% |
| 6 | Daily cap | 3 trades/dia | Anti-runaway exposure |

## Audit trail

Cada auto-approve loga em `journal/gem_auto_approve_log.jsonl`:
```json
{"timestamp":"2026-05-20T13:56:58Z","date":"2026-05-20","market":"DASHUSDT","score":92,"fqs":"QUALITY","order_id":"ORD123","reasons":["opt_in_flag_present","score_ok(92)","fqs_QUALITY","sizing_ok(0.5%)","daily_cap_ok(0/3)"]}
```

Daily cap counter usa este log (count rows where `date == today`).

## Telegram pós-auto-approve

User sempre recebe alert **mesmo em auto-approve**:
```
*GEM AUTO-APPROVED* -- DASHUSDT score=92
FQS:QUALITY daily=1/3
```

Pode revisar e cancelar manualmente se necessário (não bloqueia ordem mas alerta).

## Decision tree no scan_master

```
GEM detectado
   ↓
Test-GemAutoApprove
   ├─ approved=true  → auto-execute (sem espera)
   └─ approved=false → Wait-TgCallbackApproval 5min
                        ├─ approve → execute
                        └─ timeout/reject → log "GEM rejeitada"
```

## Risk math

| Cenário | Trades/dia | $/trade | Daily exposure | Drawdown 3 stops |
|---|---|---|---|---|
| Manual (atual) | 0-6 | $13.81 | $0-83 | $0-21 (worst) |
| **Auto strict** | 0-3 | $13.81 | $0-41 | $0-21 (worst, cap 3) |

Auto é **mais conservador em exposure diária** porque cap em 3 vs manual ilimitado.

## Quando NÃO ativar

- Markets em zona macro hostil (phase_3_bear final): MCE já protegerá, mas redundância manual ajuda
- Capital < $2K: $0.5% × $2K = $10/trade × 3 = $30/dia exposure ainda pequeno
- Após 3+ stops consecutivos: pausar manual por 24h (sentimento)

## Como desativar emergência

```powershell
# Remove flag (próximo gem volta pra manual)
Remove-Item journal/GEM_AUTO_APPROVE.flag -Force

# Ou via Telegram (futuro: comando /gem_auto_off)
```

## Telegram alerts esperados

| Evento | Mensagem |
|---|---|
| GEM detectado, NÃO auto-approved (manual path) | `*GEM ALERT* DASHUSDT score=85 [...]` (botão approve) |
| GEM AUTO-APPROVED | `*GEM AUTO-APPROVED* -- DASHUSDT score=92 FQS:QUALITY daily=1/3` |
| GEM EXECUTADA (auto path) | `*GEM EXECUTADA* DASHUSDT ordem=ORD123 [...]` |
| GEM rejeitada por timeout (manual path) | `*GEM REJEITADA* DASHUSDT -- timeout ou usuario cancelou` |
| Auto-approve daily cap atingido | (silencioso — fica pra manual) |

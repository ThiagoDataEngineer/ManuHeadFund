# ☁️ CLOUD-ONLY MODE — Status Operacional (2026-06-18)

## 📊 Status: ✅ LIVE

Sistema ManuHeadFund agora roda **100% na nuvem (GitHub Actions)**.  
PC local pode estar **desligado — sistema continua tradando**.

---

## 🔄 Arquitetura Nuvem

### GitHub Actions Workflow (`.github/workflows/trading-pipeline.yml`)

**Schedule**: Executa a cada 5 minutos

```
┌─────────────────────────────────────────────────────────────┐
│              GitHub Actions (ubuntu-latest)                 │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  JOB 1: trailing-stop-monitor (5 min)                       │
│  ├─ Update-TrailingPeakLive (peaks, locks, phases)          │
│  ├─ Sync-TrailingToExchange (empurra SL real)               │
│  └─ Log: journal/trailing_stop_monitor.log                  │
│                                                               │
│  JOB 23: cloud-trading (gem_loop -Once, 15 min)            │
│  ├─ scan_master full stack (gems, gates, conviction)        │
│  ├─ Executor de ordens (com capital safety 1% max)          │
│  └─ Log: journal/gem_loop.log                               │
│                                                               │
│  JOB 24: telegram-cloud (listener -Once, 5 min)            │
│  ├─ Poll Telegram updates                                   │
│  ├─ Responde: /halt /resume /balance /stops /scan           │
│  └─ Offset persistido em Supabase                           │
│                                                               │
│  Dashboard (JOB 4, 5 min)                                   │
│  ├─ Coleta dados em tempo real                              │
│  └─ Publica em gh-pages                                     │
│                                                               │
└─────────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────┐
│              Supabase Backend (Single Source of Truth)       │
├─────────────────────────────────────────────────────────────┤
│ manuheadfund schema:                                         │
│  ├─ trailing_positions (posições abertas + peaks)           │
│  ├─ trade_outcomes (histórico de trades)                    │
│  ├─ fqs_registry (fila de candidatos)                       │
│  ├─ conviction_observations (ensemble votes)                │
│  └─ telegram_state (offset de mensagens)                    │
└─────────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────┐
│              CoinEx Exchange API                             │
├─────────────────────────────────────────────────────────────┤
│  ├─ Posições abertas (FUTURES + SPOT)                       │
│  ├─ Ordens pendentes (vigilância)                           │
│  ├─ Preços em tempo real                                    │
│  └─ Trailing stop management                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚨 Flags de Controle (journal/)

| Flag | Status | Significado |
|------|--------|-------------|
| `LOCAL_TRADING_DISABLED.flag` | ✅ ATIVO | Loop gem_loop/scan_master local parado |
| `POSITION_WATCHER_DISABLED.flag` | ✅ ATIVO | position_watcher local aposentado |
| `CLOUD_ONLY_MODE.flag` | ✅ ATIVO | Modo nuvem ativo |
| `LIVE_MODE_ENABLED.flag` | ✅ ATIVO | Trading real (sem CLOUD_DRY_RUN) |
| `LAYER4_AUTO_EXECUTE.flag` | ✅ ATIVO | Execução automática de ordens |
| `V6_LIVE_ENABLED.flag` | ✅ ATIVO | Orchestrator V6 ativo |

### Reativar Local (se necessário)
```bash
# Remover flag de desativação
rm journal/LOCAL_TRADING_DISABLED.flag

# gem_loop LOOP local volta a rodar
# (ainda respeitando -Once da nuvem em paralelo)
```

---

## 📡 Credenciais (GitHub Secrets)

**Todos em GitHub Secrets (privado, você controla):**

| Secret | Tipo | Origem |
|--------|------|--------|
| `COINEX_ACCESS_ID` | CoinEx API | Você cria em CoinEx |
| `COINEX_SECRET_KEY` | CoinEx API | Você cria em CoinEx |
| `SUPABASE_URL` | Supabase | Seu projeto Supabase |
| `SUPABASE_SERVICE_KEY` | Supabase | role=service_role |
| `TELEGRAM_BOT_TOKEN` | Telegram | @BotFather |
| `TELEGRAM_CHAT_ID` | Telegram | Seu chat ID |
| `ANTHROPIC_API_KEY` | Claude API | Seu token |
| `GROQ_API_KEY` | Groq | Seu token (fallback) |
| `MISTRAL_API_KEY` | Mistral | Seu token (fallback) |

**Segurança:**
- ✅ GitHub Secrets = privado (você controla 100%)
- ✅ Actions injeta em env vars (memory-only)
- ✅ Logs redacted com `***`
- ✅ Zero credenciais em disco ou commits

### Revogar Credenciais
1. Regenere chaves em **CoinEx** + **Supabase** + **APIs**
2. Update **GitHub Secrets** (Settings > Secrets and variables)
3. Próximo job Actions usa novas credenciais automaticamente

---

## 📊 Monitoring

### GitHub Actions Dashboard
👉 **https://github.com/ThiagoDataEngineer/ManuHeadFund/actions**

- ✅ Job history (últimas execuções)
- ✅ Logs de cada job
- ✅ Failure alerts
- ✅ Workflow trigger

### Local Logs (Supabase-backed)
```powershell
# Ver eventos de Telegram
tail journal/telegram_listener.log

# Ver trailing stops
tail journal/trailing_stop_monitor.log

# Ver gem_loop
tail journal/gem_loop.log

# Ver scan_master
tail journal/scan_master.log
```

### Dashboard Live
👉 **GitHub Pages** (quando ativado): https://ThiagoDataEngineer.github.io/ManuHeadFund

---

## ⚡ Operação 24/7

### Cenário 1: PC ON + Nuvem ON
```
PC local (gem_loop PARADO por flag) + Nuvem (ativa)
→ Nuvem trada, PC é espectador (opcional)
→ Logs em journal/ + Supabase
```

### Cenário 2: PC OFF + Nuvem ON
```
PC desligado + Nuvem (ativa)
→ Nuvem trada autonomamente 24/7
→ PC pode ligar depois, captura estado do Supabase
→ Posições protegidas por trailing stops
```

### Cenário 3: PC ON + Nuvem OFF (rare)
```
PC local (remove LOCAL_TRADING_DISABLED.flag) + Nuvem parada
→ Local roda sozinho (fallback mode)
→ Use apenas temporariamente
```

---

## 🔧 Troubleshooting

### Nuvem não executou
1. Verifique GitHub Actions: https://github.com/.../actions
2. Procure por `failed` jobs
3. Leia logs do job que falhou
4. Common causes:
   - Credenciais expiradas (update GitHub Secrets)
   - Supabase down (check status.supabase.com)
   - CoinEx API error (check CoinEx status)

### Trailing stops não atualizaram
1. Verifique: `tail journal/trailing_stop_monitor.log`
2. Verifique Supabase: `trailing_positions` table
3. Trigger manual: 
   ```yaml
   # No GitHub Actions: "Run workflow" > select cloud-trading
   ```

### Telegram não responde
1. Verifique `TELEGRAM_BOT_TOKEN` em GitHub Secrets
2. Check telegram listener logs: `tail journal/telegram_listener.log`
3. Envie msg via Telegram: `/status` (deve responder)

### Posição presa sem SL
1. Verifique: `tail journal/trailing_stop_monitor.log`
2. Procure por erro de "Sync-TrailingToExchange"
3. Manual override:
   ```powershell
   # Local: rodar trailing_stop_monitor.ps1 direct
   pwsh -File scripts/trailing_stop_monitor.ps1
   ```

---

## 📈 Performance

**Nuvem vs Local:**

| Métrica | Nuvem | Local |
|---------|-------|-------|
| Uptime | 99.9% (SLA GitHub) | Depende PC |
| Latência | ~5-10s | <1s |
| Custo | Free tier + Actions | PC energia |
| Escalabilidade | ∞ | CPU/RAM limitado |
| Auditabilidade | Completa | Parcial |

---

## 🔄 Roadmap Pós-Cloud-Only

1. **Trailing Executor Phase 2** (2026-06-25)
   - Smart SL move based on order flow
   - Multiple stop levels per position

2. **Live Dashboard Phase 2** (2026-06-25)
   - WebSocket updates (real-time)
   - Trade control buttons (directly trigger /halt, etc)

3. **Learning Engine** (2026-06-30)
   - Capture mistakes in cloud logs
   - Auto-improve conviction thresholds

4. **Cost Optimization** (2026-07-01)
   - Migrate Mentors to Groq (cheaper)
   - Batch API calls to CoinEx

---

## 📚 Referências

- [CREDENTIALS_PROTECTION.md](./CREDENTIALS_PROTECTION.md) — Como as credenciais são protegidas
- [.github/workflows/trading-pipeline.yml](../.github/workflows/trading-pipeline.yml) — Workflow definition
- [docs/ARCHITECTURE_TATICA.md](./ARCHITECTURE_TATICA.md) — Arquitetura do sistema
- [CLAUDE.md](../CLAUDE.md) — Project guidelines

---

**Status em tempo real**: Check GitHub Actions dashboard  
**Última atualização**: 2026-06-18 15:00 BRT  
**Commit**: 9e894f2

# 🚀 Supabase Integration — Quick Start (7 dias)

**Objetivo:** Levar TUDO online, eliminar quebras local-only, manter GitHub Actions 24/7 operacional.

---

## 📋 Pré-requisitos

- ✅ `lib_state_store.ps1` já presente (backend abstração)
- ✅ Supabase account + `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` em env vars
- ✅ Schema `manuheadfund` já existe (isolado, não toca outras apps)
- ✅ 5 tabelas de aprendizado já existem (commit c67f25e)

---

## 🎯 Dia 1-2: Setup Tables

### 1. Execute DDL em Supabase
```sql
-- Abra Supabase dashboard → SQL Editor → colar docs/SETUP_SUPABASE_COMPLETE.sql
-- Run. Esperado: 5 tabelas criadas (trade_outcomes, open_positions, exchange_sync_log, daily_reconciliation, agent_decisions)

-- Verify:
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'manuheadfund'
ORDER BY table_name;
```

### 2. Valide conexão
```powershell
# No terminal (PS 5.1+)
$env:SUPABASE_URL = "https://xxxx.supabase.co"
$env:SUPABASE_SERVICE_KEY = "eyJxxx..."

# Test lib_state_store
. agents/lib_state_store.ps1
Test-StateBackend  # Deve retornar "supabase"

# Test Save-StateRecords
Save-StateRecords -Table "trade_outcomes" -Records @(@{
    id = "test_001"
    entry_ts = (Get-Date).ToUniversalTime()
    symbol = "BTCUSDT"
    direction = "LONG"
    source = "test"
    entry_price = 100
    quantity = 1
    status = "pending"
    created_at = (Get-Date).ToUniversalTime()
}) -PrimaryKey "id"

# Verify em Supabase dashboard
# SELECT * FROM manuheadfund.trade_outcomes WHERE id = 'test_001';
```

---

## 🎯 Dia 3-4: Integrar Libs

### 1. Copie novos arquivos
```powershell
# Já estão em place:
agents/lib_trade_journal_supabase.ps1      # Save-TradeOutcome, Get-RecentTrades, Get-TradeStats
agents/lib_position_sync_live.ps1          # Sync-ExchangePositionsLive, Reconcile-AppToJournal
```

### 2. Wire em gem_loop (após discovery)
**Arquivo:** `agents/gem_loop.ps1` (linha ~XX)
```powershell
# APÓS candidatos descobertos, ANTES de entrar em Invoke-GemExecute
$candidates | ForEach-Object {
    # ... lógica existente ...
}

# ADD: Sync positions do app ANTES de nova rodada
Sync-ExchangePositionsLive -IsFutures $true  | Out-Null
Sync-ExchangePositionsLive -IsFutures $false | Out-Null
```

### 3. Wire em position_watcher (qdo app fecha trade)
**Arquivo:** `agents/trailing_stop_monitor.ps1` (linha ~XX, após close detection)
```powershell
# Qdo detecta uma posição fechada pela app
if ($shouldClose -eq $true) {
    # ... close logic ...
    
    # ADD: Reconcile com app
    Reconcile-AppToJournal -Limit 5 | Out-Null
}
```

---

## 🎯 Dia 5: Testes Unitários

```powershell
# Rodar testes localmente (backend=local)
Invoke-Pester tests/lib_trade_journal_supabase.Tests.ps1 -Verbose
Invoke-Pester tests/lib_position_sync_live.Tests.ps1 -Verbose

# Expected: All pass (18+16 testes)
```

---

## 🎯 Dia 6: Teste E2E (Supabase Real)

### 1. Abra trade via app CoinEx (manual, 1x)
```powershell
# Abre uma posição Futures real na conta
# Anote: symbol, qty, entry price
```

### 2. Rode sync
```powershell
. agents/lib_state_store.ps1
. agents/lib_position_sync_live.ps1

$synced = Sync-ExchangePositionsLive -IsFutures $true
$synced | Format-Table symbol, direction, entry_price, stop_loss
```

### 3. Valide em Supabase
```sql
SELECT id, symbol, direction, entry_price, stop_loss, status
FROM manuheadfund.open_positions
WHERE symbol = 'BTCUSDT'  -- seu trade
ORDER BY created_at DESC
LIMIT 1;
```

**Esperado:** Posição aparece em <2min

### 4. Fecha trade via app
```powershell
# App fecha o trade (manual)
# Aguarde 30s
```

### 5. Reconcile
```powershell
$outcomes = Reconcile-AppToJournal -Limit 5
$outcomes | Format-Table symbol, direction, pnl_realized, status
```

### 6. Valide journal
```sql
SELECT entry_ts, symbol, direction, pnl_realized, status
FROM manuheadfund.trade_outcomes
WHERE symbol = 'BTCUSDT' AND status = 'closed'
ORDER BY entry_ts DESC
LIMIT 1;
```

**Esperado:** Trade registrado com PnL correto

---

## 🎯 Dia 7: Deploy Production

### 1. Ativa backend Supabase
```powershell
# Em c:\Users\thiag\Coinex_AI_USER_API\journal\
New-Item -ItemType File -Path "USE_SUPABASE_STATE.flag" -Force
# Arquivo vazio = flag ativado
```

### 2. Set env vars em GitHub Actions
```bash
# Via GitHub Settings → Secrets and variables → Actions
SUPABASE_URL = https://xxxx.supabase.co
SUPABASE_SERVICE_KEY = eyJ...
STATE_STORE_BACKEND = supabase
```

### 3. Rodar uma vez manualmente (validar nuvem)
```bash
# GitHub UI → Actions → (seu workflow) → Run workflow
# Monitore: job logs devem mostrar Supabase saves OK
```

### 4. Telegram alert
Adicione ao seu heartbeat/startup:
```powershell
$msg = @"
✅ Supabase backend ATIVO
Trades hoje: $(Get-TradeStats -DaysBack 1).total
Posições ativas: $(Get-StateRecords -Table "open_positions" -Filter @{status="active"}).Count
"@
Send-TelegramMessage -Text $msg
```

---

## 🛡️ Fallbacks (Graceful)

| Cenário | Ação |
|---------|------|
| Supabase down | Save local JSON automaticamente, re-sync qdo voltar |
| PGRST205 (tabela missing) | Circuit breaker ativa, fallback local (já em lib_state_store:274) |
| Network timeout | Retry 3x, log warning, continua local |
| GitHub Actions fail | Job retry automático, notifica Telegram |

---

## ✅ Validação Final

```powershell
# Rode tudo local ANTES de ativar produção
$global:STATE_STORE_BACKEND = "supabase"

# Test 1: Save trade
Save-TradeOutcome @{entry_ts=(Get-Date); symbol="TEST"; direction="LONG"; source="test"; entry_price=100; quantity=1}

# Test 2: Read back
Get-RecentTrades -DaysBack 1 -Limit 10

# Test 3: Stats
Get-TradeStats -DaysBack 7

# Test 4: Sync positions
Sync-ExchangePositionsLive -IsFutures $true

# Test 5: Reconcile
Reconcile-AppToJournal -Limit 1

# ALL = Success ✅
```

---

## 📊 Métricas de Sucesso

✅ `trade_outcomes.jsonl` atualizado realtime (vs 25 dias stale)
✅ `open_positions.jsonl` tem posições do app (vs 0 bytes)
✅ GitHub Actions lê Supabase sem acesso local
✅ Trailing monitor adota orphans (SHORT WLDUSDT tem stop!)
✅ Zero human intervention (automático 24/7)

---

## 📚 Referências

- `docs/SETUP_SUPABASE_COMPLETE.sql` — DDL completo
- `docs/SUPABASE_INTEGRATION_MASTER_PLAN.md` — estratégia detalhada
- `agents/lib_state_store.ps1` — backend abstração (já setup)
- `agents/lib_trade_journal_supabase.ps1` — trade helpers
- `agents/lib_position_sync_live.ps1` — position sync

---

## 🆘 Troubleshooting

**Q: Recebo PGRST205?**
A: Tabela não existe. Execute DDL novamente em Supabase SQL Editor.

**Q: Trades não aparecem em Supabase?**
A: Verifique `SUPABASE_URL` / `SUPABASE_SERVICE_KEY`. Test: `Invoke-RestMethod -Uri "$env:SUPABASE_URL/rest/v1/manuheadfund.trade_outcomes?select=*&limit=1" -Headers @{apikey=$env:SUPABASE_SERVICE_KEY}`

**Q: Nuvem (GitHub Actions) falha?**
A: Set env vars em GitHub Secrets. Restart action.

**Q: Performance lenta?**
A: Supabase limite default é 1MB/seg. Se >1000 trades/dia, considere batch writes.

---

**Status:** 2026-07-07 | Ready to implement

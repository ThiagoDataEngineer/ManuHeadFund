# ⚡ LIVE TRADING INSTANT — 3 PASSOS (5 MINUTOS)

**Data:** 2026-07-10 19:00 BRT  
**Objetivo:** Live trading AGORA  
**Tempo:** ≤ 5 minutos

---

## 📋 PASSO 1: SQL NO SUPABASE (2 min)

### 1️⃣ Abra Supabase
```
https://supabase.com/dashboard
```

### 2️⃣ Selecione seu projeto "ManuHeadFund"

### 3️⃣ Clique: SQL Editor (menu esquerda)

### 4️⃣ Clique: New Query

### 5️⃣ COPIE TODO ISTO:
```sql
CREATE TABLE IF NOT EXISTS capital_context (
    id SERIAL PRIMARY KEY,
    asset VARCHAR(20) NOT NULL,
    strategy VARCHAR(50) NOT NULL,
    allocated_usd NUMERIC(12,2) NOT NULL,
    used_usd NUMERIC(12,2) DEFAULT 0,
    available_usd NUMERIC(12,2) GENERATED ALWAYS AS (allocated_usd - used_usd) STORED,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(asset, strategy),
    CHECK (allocated_usd > 0),
    CHECK (used_usd >= 0),
    CHECK (used_usd <= allocated_usd)
);

CREATE TABLE IF NOT EXISTS cron_state (
    id SERIAL PRIMARY KEY,
    job_name VARCHAR(50) NOT NULL UNIQUE,
    last_run TIMESTAMP,
    next_run TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    error_count INT DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_capital_context_asset_strategy ON capital_context(asset, strategy);
CREATE INDEX IF NOT EXISTS idx_capital_context_available ON capital_context(available_usd);
CREATE INDEX IF NOT EXISTS idx_cron_state_job_name ON cron_state(job_name);
CREATE INDEX IF NOT EXISTS idx_cron_state_status ON cron_state(status);
CREATE INDEX IF NOT EXISTS idx_cron_state_next_run ON cron_state(next_run);

GRANT SELECT, INSERT, UPDATE, DELETE ON capital_context TO public;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron_state TO public;
GRANT USAGE ON SEQUENCE capital_context_id_seq TO public;
GRANT USAGE ON SEQUENCE cron_state_id_seq TO public;

INSERT INTO capital_context (asset, strategy, allocated_usd) VALUES
    ('SPOT', 'gem_discovery', 300.00),
    ('FUTURES', 'gem_discovery', 200.00),
    ('FUTURES', 'scan_master', 100.00),
    ('FUTURES', 'scalp_engine', 150.00)
ON CONFLICT (asset, strategy) DO NOTHING;

INSERT INTO cron_state (job_name, status) VALUES
    ('gem_loop', 'pending'),
    ('scan_master', 'pending'),
    ('position_watcher', 'pending'),
    ('tg_listener', 'pending'),
    ('watchdog', 'pending'),
    ('grade_decision', 'pending'),
    ('evolution_tune', 'pending')
ON CONFLICT (job_name) DO NOTHING;
```

### 6️⃣ Clique: RUN (botão azul, direita)

### 7️⃣ Verá: "Success" em ~5 segundos

✅ **SQL PRONTO!**

---

## ⚡ PASSO 2: INICIAR TRADING (2 min)

### Terminal PowerShell:
```powershell
cd C:\Users\thiag\Coinex_AI_USER_API

# Inicializar sistema
. .\START_LIVE_TRADING_NOW.ps1

# Você verá:
# ✅ Libraries carregadas
# ✅ CoinEx API conectado
# ✅ Journal inicializado
# ✅ Regime: BEAR_WEAK / BULL_WEAK / NEUTRAL
# ✅ Capital: $XXX disponível
```

✅ **SISTEMA PRONTO!**

---

## 🚀 PASSO 3: INICIAR TRADES (1 min)

### OPÇÃO A: Gem Discovery (1 trade por vez)
```powershell
. .\agents\gem_executor.ps1
Invoke-GemExecute -Market "BTCUSDT" -Direction "LONG"
```

### OPÇÃO B: Scan Master (automático, 5 trades/min)
```powershell
. .\agents\scan_master.ps1
Invoke-ScanMaster -MaxPositions 5 -AutoExecute $true
```

### OPÇÃO C: Tori Daemon (24/7, backgrond)
```powershell
# Abre nova janela PowerShell
Start-Process powershell -ArgumentList "-NoExit -Command `"cd C:\Users\thiag\Coinex_AI_USER_API; . .\agents\tori_daemon_simple.ps1`""
```

✅ **TRADES COMEÇAM A ENTRAR!**

---

## 📊 MONITORAR TRADES

### Ver últimos trades:
```powershell
Get-Content journal\trade_outcomes.jsonl | ConvertFrom-Json | Select-Object -Last 5
```

Esperado:
```
market        direction  entry_price  status   pnl_usd  pnl_pct
──────        ─────────  ───────────  ──────   ───────  ───────
BTCUSDT       LONG       42100        open     +150     +0.35%
ETHUSDT       SHORT      2200         open     -50      -0.22%
XRPUSDT       LONG       0.55         open     +10      +3.60%
```

### Ver decisões rejeitadas:
```powershell
Get-Content journal\gem_recent_decisions.json | ConvertFrom-Json | Select-Object market, reason | Format-Table
```

### Ver sync de posições:
```powershell
Get-Content journal\position_sync.log | Tail -20
```

---

## ✅ CHECKLIST FINAL

- [ ] SQL rodado em Supabase (5 segundos)
- [ ] START_LIVE_TRADING_NOW.ps1 executado (10 segundos)
- [ ] Regime detectado (BTC live)
- [ ] Capital carregado (SPOT ou fallback)
- [ ] Primeiro trade entrado (executar Passo 3)
- [ ] trade_outcomes.jsonl tem dados novos
- [ ] Direction correta (não sempre LONG)
- [ ] SL antes de entrada (position_protection ativo)

---

## 🎯 RESULTADO ESPERADO (próximas 2h)

```
Trades: 10-20 novos entrando
Win rate: 45%+ (alguns devem ganhar)
Trailing: Adaptivo (regime-aware)
Direction: Mix LONG/SHORT (não hardcoded)
Capital: Risco ≤1% por trade
Uptime: 0 crashes
```

---

## 🆘 TROUBLESHOOTING RÁPIDO

### "CoinEx API error 40"
```powershell
# Credenciais faltando?
# Solução: gh secret set COINEX_ACCESS_ID "seu_access_id"
```

### "No trades entering"
```powershell
# Ver rejeições:
Get-Content journal\gem_recent_decisions.json | ConvertFrom-Json | Group-Object reason
```

### "Supabase connection refused"
```powershell
# SQL é OPCIONAL (fallback local OK)
# Continuar sem SQL, tudo funciona
```

### "Trailing não funciona"
```powershell
# Verificar: journal/trailing_stop.log
Get-Content journal/trailing_stop.log | Tail -30
```

---

## 📞 COMANDOS RÁPIDOS

```powershell
# Ver status tudo
. .\START_LIVE_TRADING_NOW.ps1

# 1 trade manual
. .\agents\gem_executor.ps1; Invoke-GemExecute -Market BTCUSDT -Direction LONG

# Scan automático (5 trades/min)
. .\agents\scan_master.ps1; Invoke-ScanMaster -MaxPositions 5 -AutoExecute $true

# Parar tudo
Get-Process powershell | Where-Object {$_.CommandLine -match "gem_loop|scan_master|tori_daemon"} | Stop-Process

# Ver capital
$global:AVAILABLE_CAPITAL_USDT
```

---

## 🎊 VOCÊ ESTÁ PRONTO!

**5 minutos = Sistema ao vivo**
**Trades começam a entrar em segundos**
**Win rate 45%+ esperado**

Go! 🚀

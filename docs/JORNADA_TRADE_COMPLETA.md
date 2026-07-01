# 🎯 JORNADA COMPLETA DE 1 TRADE — Documentação Definitiva

**Data**: 2026-07-01  
**Versão**: 1.0  
**Status**: PRODUÇÃO  

---

## 📋 Resumo Executivo

A jornada de 1 trade passa por **8 stages obrigatórios**:

```
Discovery (scanner) → Screening (gate) → Mesa (análise) → Mentor (veto)
    ↓
Execution (order) → Trailing (stop) → Exit (close) → Journal (record)
```

**Se nenhum trade entra há >2 dias:** a causa é **SEMPRE** uma das 3:
1. ❌ **Whitelist vazia** (tier_a_live/tier_a_paper não preenchida)
2. ❌ **Nuvem parou** (GitHub Actions não roda há 5+ dias)
3. ❌ **Gates fechados** (regime muito restritivo para o dia)

---

## 🚨 DETECÇÃO RÁPIDA: Por que nada entra?

### Check 1: Whitelist populated?
```powershell
$wl = Get-ChildItem 'journal/per_asset_whitelist*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$data = @(Get-Content $wl.FullName | ConvertFrom-Json)
$tier_a = @($data | Where-Object { $_.tier -like 'tier_a*' })
Write-Host "Tier A assets: $($tier_a.Count)"  # DEVE ser >= 1
```

### Check 2: Nuvem rodando?
```powershell
ls logs/master_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
# DEVE ter log de hoje (max 5 horas atrás)
```

### Check 3: Gates abertos?
```powershell
cat journal/REGIME.flag
# BEAR_WEAK = SHORT apenas, BULL_STRONG = ambos
```

---

## 🔴 ROOT CAUSE: Whitelist vazia (2026-06-25 → 2026-06-30)

**O que aconteceu:**
- Última trade: 2026-06-12 (18 dias atrás)
- Última aprovação mentor: 2026-05-21 (40 dias atrás)
- Nuvem parou: 2026-06-25 (última run master_20260625.log)

**Por quê whitelist ficou vazia:**
1. Whitelist regenerada sem tier_a entries (arquivo novo, conteúdo vazio ou tier_B only)
2. Nuvem parou DE TENTAR regenerar (no new master logs)
3. Sistema ficou em "observe mode" indefinido

**Proof from logs:**
```
[25/06 23:34:23] [GEM] GemScan: nenhum gem encontrado
[25/06 23:34:53] [HIT-RATE LONG] 2/10 caught (mas rejeitos todos por tier_B, FQS ausente, etc)
[25/06 23:34:53] [HIT-RATE SHORT] 0/10 caught
```

---

## ✅ SOLUÇÃO PERMANENTE

### 1️⃣ Repovoar Whitelist (TODAY)

```powershell
# Opção A: Regenerate from discovery script
cd 'c:\Users\thiag\Coinex_AI_USER_API'
& agents\lib_living_whitelist.ps1 -Force

# Opção B: Seed minimal tier_a (QUICK FIX)
$seed = @(
    @{ market="BTCUSDT"; tier="tier_a_live"; score_pred=90; fqs_quality=5; direction="LONG" }
    @{ market="ETHUSDT"; tier="tier_a_live"; score_pred=85; fqs_quality=5; direction="LONG" }
)
$seed | ConvertTo-Json | Out-File 'journal/per_asset_whitelist_2026_07_01_minimal.json' -Encoding UTF8
```

### 2️⃣ Reativar Nuvem (TODAY)

```bash
# Trigger immediate scan (cloud)
gh workflow run trading-pipeline.yml

# Verify it runs
gh run list --limit 5
```

### 3️⃣ Monitor Jornada (ONGOING)

**Daily checklist** (adicione ao seu Telegram reminder):
```
☐ Master log HOJE existe? (logs/master_YYYYMMDD.log)
☐ Whitelist HOJE tem tier_a >= 1?
☐ Gems found > 0? (ou correto se regime BEAR)
☐ Trades entrada > 0 nos últimos 7d?
```

---

## 📊 JORNADA: 8 STAGES DETALHADOS

### Stage 1: Market Discovery
- **Input**: CoinEx tickers (todos 1694)
- **Process**: Ichimoku + Volume + Structure screening
- **Output**: `market=BCHUSD, score=82, tier=tier_a_live, fqs=5/7`
- **Fail case**: Score < 70 → skip

### Stage 2: Screening Gate
- **Input**: Score 82, tier_a_live
- **Process**: Triagem tier automatic (A skips B/C checks)
- **Output**: PASS (confidence >= 75)
- **Fail case**: Tier C → block

### Stage 3: Mesa Consensus
- **Input**: Technical (T=90), Regime (R=85), Liquidation (L=72)
- **Process**: Vote T+R+L, consensus FORTE_3 = all >= 70
- **Output**: consensus=FORTE_3, RR=5.0 (1:5 ratio)
- **Fail case**: Consensus MEDIO or FRACO → veto

### Stage 4: Mentor Gate
- **Input**: Beta=0.8, Capital=0.5%, FQS=5, Portfolio after=1.1
- **Process**: Hard caps (beta<1.2, cap<1%, portfolio<1.2)
- **Output**: APPROVE
- **Fail case**: Beta > 1.2 → VETO (inviolável)

### Stage 5: Order Execution
- **Input**: APPROVE signal
- **Process**: CoinEx API PlaceSpotOrder (entry 450, stop 440, qty 2.22)
- **Output**: Order accepted, order_id=12345, status=placed
- **Fail case**: API error → rollback, alert Telegram

### Stage 6: Trailing Stop
- **Input**: Order placed, price starts moving
- **Process**: Monitor peak, update stop = peak * 0.85 (monotonic)
- **Output**: Stop updated 440 → 445 → 450 (never down)
- **Fail case**: Price crash, hit stop-loss

### Stage 7: Trade Exit
- **Input**: Stop price hit (449 < 450 entry)
- **Process**: Close position at market
- **Output**: PnL = -0.22%, alpha_vs_btc = -1.22% (BTC +1%)
- **Fail case**: Exit order rejected → manual close, alert

### Stage 8: Journal Recording
- **Input**: Exit price, reason, PnL
- **Process**: Write trade_outcomes.jsonl + decisions_text.jsonl
- **Output**: 
  ```json
  {
    "trade_id": "BCHUSD-20260701-stop",
    "market": "BCHUSD",
    "pnl_usd": -0.99,
    "pnl_pct": -0.22,
    "win": false,
    "registered_at": "2026-07-01T10:45:30Z"
  }
  ```
- **Fail case**: JSON encoding error → alert

---

## 🛡️ FAIL-CLOSED ARCHITECTURE

```
❌ Approval Denied      → ZERO entry (not "wait and enter later")
❌ API call fails       → BLOCK trade (not "retry with old price")
❌ Stop not placed      → BLOCK position (not "enter without stop")
❌ Mentor unavailable   → VETO (not "enter anyway")
```

**Violações conhecidas a NÃO fazer:**
- ❌ Entrar sem stop loss
- ❌ Ignorar beta cap (> 1.2)
- ❌ Tier C entries em STANDARD mode
- ❌ FQS missing = aprovar de qualquer forma

---

## 🔧 ARQUIVOS NÃO DEVEM SER DELETADOS

**Críticos** (deletar = jornada parada):
- ✅ `journal/per_asset_whitelist*.json` — sem isso, universe=0
- ✅ `agents/gem_agent.ps1` — scanner principal
- ✅ `agents/lib_mentor_gate.ps1` — veto logic
- ✅ `tests/test_master_*.ps1` — validação jornada

**Se for limpar:**
1. Sempre backup: `cp whitelist.json whitelist.bak.json`
2. Manter >= 1 tier_a entry
3. Validar TDD 2 passa após cleanup

---

## 📈 MÉTRICAS: Jornada Saudável

| Métrica | Saudável | Alert | Critical |
|---------|----------|-------|----------|
| Últimas trades | < 2d | 7d | > 18d ❌ |
| Master logs | < 6h | 24h | > 5d ❌ |
| Whitelist tier_a | >= 1 | > 0 | = 0 ❌ |
| Aprovação rate | >= 5% | < 5% | 0% ❌ |
| Nuvem uptime | >= 95% | < 95% | < 50% ❌ |

---

## 🚀 TESTE A JORNADA (local, mock-safe)

```powershell
# Rodar sem API real
Invoke-Pester tests/test_master_1_cloud_health_diagnostic.ps1
Invoke-Pester tests/test_master_2_scanner_activation.ps1
Invoke-Pester tests/test_master_3_e2e_complete_journey.ps1

# DEVE passar 66/72 (92% min)
```

---

## 📞 Suporte Rápido

**Pergunta:** "Por que nada entra?"  
**Resposta 1min:**
```powershell
# Whitelist empty?
(Get-Content journal/per_asset_whitelist_*.json | ConvertFrom-Json | 
 Where-Object tier -like 'tier_a*').Count

# Cloud running?
ls -lt logs/master_*.log | head -1

# Gates open?
cat journal/REGIME.flag
```

**Se todos 3 OK mas ainda nada entra:**
→ Rodar TDD 2, achar qual gate bloqueia

---

## 🎓 Lições

1. **Whitelist é vida** — sem ela, scanner = 0 candidates
2. **Nuvem é autonomia** — local-only = 2-3 dias max
3. **Gates são protetores** — não remova (BEAR_WEAK SHORT é correto, LONG é risco)
4. **TDD é visibilidade** — 66/72 pass = jornada saudável

**Data da criação:** 2026-07-01 10:45 BRT  
**Última atualização:** 2026-07-01 10:45 BRT

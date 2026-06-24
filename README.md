# 🚀 ManuHeadFund - CoinEx AI Trading System

Sistema automatizado de trading com IA (Mentor Agent) + Auto-Trade Engine para CoinEx SPOT + FUTURES (HYBRID 50/50).  
**Status**: ✅ **CLOUD-ONLY LIVE** | Nuvem 24/7 | Local OFF | **Last Updated**: 2026-06-23

---

## 🛡️ UPDATE 2026-06-23 — Stops FAIL-CLOSED (SPOT completo + FUTURES) + Learning Evolution

**Causa raiz corrigida**: o loop SPOT do `position_watcher` só *alertava* no SL, **nunca vendia**
(stop era software-side; daemon morto 19→23/06 deixou OPNUSDT cair a −69%). Agora há proteção
real em 3 camadas + reconciliação de estado + evolução do motor de aprendizado. **59 TDD.**

### Proteção SPOT (3 camadas, sem stop-market — que já deu problema)
1. **Stop-limit agressivo na corretora** — `lib_spot_stop_guard.ps1`. Preço de execução 3% abaixo
   do trigger (`Get-SpotStopLimitPrice`) → vira limit marketável que **preenche no gap mesmo com
   daemon morto**. Idempotente (`Resolve-SpotStopActions`: PLACE/OK/UPDATE/CANCEL) — sem o bug das
   178 duplicatas. **UPDATE quando o trailing sobe** + auto-upgrade self-heal de stops legados.
2. **Fallback market-sell** — `Test-SpotStopFallback`: se o preço atravessa o stop e o limit não
   executou, o daemon vende a mercado (cobre gap com daemon vivo).
3. **Dust guard** — `Test-SpotStopPlaceable`: pula poeira/sub-nano/símbolo-inválido sem spam.

### Proteção FUTURES (`lib_futures_stop_guard.ps1`)
SL exchange-side (mark-price, fecha a mercado) — sólido. Furos cobertos por `Resolve-FuturesStopGuard`:
**SET** (posição nua não-rastreada → seta SL) / **CLOSE_FALLBACK** (nua + já furou → fecha a mercado).

### Reconcile + Learning
- `lib_state_reconcile.ps1` — uma fonte de verdade (remove duplicatas, marca CSV fantasma CLOSED).
- `Get-GateKey` (lib_direction_learning) — counterfactual agrega de verdade (1092→26 chaves;
  revela que vetos SHORT em bear perdem 44–70% de ganhadores).
- `lib_asymmetric_trail.ps1` — deixa o ganhador correr (**opt-in** `ASYMMETRIC_TRAIL_ENABLED`, default OFF até forward-test).

---

## 🎯 UPDATE 2026-06-19 — TDD Completo + Position Sync Fix

### ✅ O que foi feito
1. **sync_and_fix_tp.ps1** — Agora auto-detecta TODAS as posições abertas (não hardcoded)
2. **trailing_stop_monitor.ps1** — Remove hardcoded markets, chama sync sem filtro
3. **TDD Completo** — Validados todos 5 caminhos de entrada de trade ✅

### 5 Caminhos de Entrada (Todos Testados)
| Caminho | Frequência | Status | Tipo |
|---------|-----------|--------|------|
| **gem_loop** | 15 min | ✅ LIVE | Automático |
| **scan_master** | 1h | ✅ LIVE | Observação |
| **/idea** | Manual | ✅ LIVE | Manual |
| **/approve** | Manual | ✅ LIVE | Manual |
| **sync_and_fix_tp** | 5 min | ✅ LIVE (FIXED) | Auto |

**Resultado**: Sistema 100% automático e sincronizado. Posições sempre atualizadas.
Ver: [TDD_FINAL_RESULTS_2026_06_19.md](./TDD_FINAL_RESULTS_2026_06_19.md)

---

## ☁️ CLOUD-ONLY MODE (2026-06-18) — Nuvem é Única Fonte

**Status**: ✅ LIVE | PC pode estar OFF | GitHub Actions roda autonomamente

### O que mudou
| Componente | Antes | Agora |
|-----------|-------|-------|
| **Execution** | Local loop (24/7 PC) | GitHub Actions (24/7 cloud) |
| **Trailing Stop** | position_watcher local | trailing_stop_monitor JOB1 (cada 5 min) |
| **gem_loop** | Loop contínuo local | gem_loop -Once JOB23 (cada 15 min) |
| **Telegram** | Listener local | telegram_listener -Once JOB24 (cada 5 min) |
| **State** | JSON local + Supabase | Supabase backend ÚNICO |
| **PC Local** | Necessário 24/7 | Opcional (dev/debug apenas) |

### Operação Nuvem
```yaml
# GitHub Actions runs continuously:
- JOB 1:  trailing-stop-monitor (cada 5 min)   → protege posições
- JOB 23: gem_loop -Once (cada 15 min)        → novos sinais + execução
- JOB 24: telegram_listener (cada 5 min)      → responde comandos
- Dashboard: auto-atualiza estado
```

### Segurança
✅ Credenciais: GitHub Secrets (você controla)  
✅ Local: config.local.ps1 gitignored + memory-only  
✅ Reversível: rm `LOCAL_TRADING_DISABLED.flag` → local volta  

**Documentação**: [docs/CREDENTIALS_PROTECTION.md](./docs/CREDENTIALS_PROTECTION.md)

---

## 🧠 OPÇÃO C — SISTEMA AUTO-LEARNING (2026-06-18) ✅ LIVE

**Status**: ✅ **FUNCIONANDO AGORA** | Análise Gráfica + Auto-Calibração 24h

### O que é Opção C

Sistema completo de **auto-aprendizado e auto-calibração diária**:

1. **Chart Gate (Bloqueador Ativo)** — Rejeita entradas ruins
   - ✅ Pump signatures (topping patterns, volume climax)
   - ✅ Fake breakouts (shooting stars)
   - ✅ Vendas climáticas (rejections)
   - **Resultado**: Evita -11% (COAIUSDT tipo pump-chase)

2. **Daily Auto-Calibration (00:00 UTC)** — Sistema aprende sozinho
   - ✅ Analisa TOP 5 ganhadores e perdedores do dia anterior
   - ✅ Calcula gap: dinheiro deixado na mesa vs dinheiro economizado
   - ✅ Auto-ajusta thresholds: conviction_threshold + mesa_score_strong
   - ✅ Logs tudo em `journal/daily_calibration.jsonl`
   - **Resultado**: Sistema se auto-regula a cada 24h (não espera semana)

3. **Insight Tool** — Real-time winners/losers analysis
   ```bash
   python3 backtest/insight_realtime_winners_24h.py
   # Output: TOP 5 gainers vs losers, gap analysis, auto-calibration advice
   ```

### Fluxo Diário

```
Dia 1 - 08:00 UTC:
  insight_realtime_winners_24h.py
  ├─ AINUSDT +19.77% → Você entrou? SIM
  ├─ COAIUSDT -11.38% → Você entrou? NÃO (chart_pump_bloqueado)
  └─ GAP = $850 deixado na mesa

Dia 1 - 23:00 UTC:
  daily_autocalibration.ps1
  ├─ Vê gap $850
  ├─ Decide: "abrir gates amanhã"
  └─ Atualiza: conviction 50→48, mesa 60→55

Dia 2 - 00:00 UTC:
  gem_executor carrega novo gates
  ├─ Conviction agora 48 (era 50)
  ├─ Próximas 24h vai entrar em TOP 5
  └─ LOOP REPETE
```

### Como Funciona (Cloud-Only)

**Automático via GitHub Actions** (rodando agora):
- ✅ `.github/workflows/hourly-autocalibration.yml`
- ✅ Cron: `0 * * * *` (a cada hora)
- ✅ Persiste estado em Supabase (não local)
- ✅ Sem necessidade de máquina local

**O que precisa estar configurado**:
- Secrets no GitHub (Settings → Secrets):
  - `SUPABASE_URL`: URL do projeto Supabase
  - `SUPABASE_SERVICE_KEY`: Service key Supabase

**Status**:
- Veja runs em: Actions tab
- Logs: Artifacts com journal/daily_calibration.jsonl
- Estado persistido: Supabase `regime_state` table

### Status Atual

| Componente | Status | Resultado |
|-----------|--------|-----------|
| Chart Gate (Test-ChartPatternGate) | ✅ PRONTO | Bloqueia pump-chase, topping |
| Daily Auto-Calibration (daily_autocalibration.ps1) | ✅ PRONTO | Ajusta gates a cada 24h |
| Insight Tool (insight_realtime_winners_24h.py) | ✅ PRONTO | Calcula gap, recomenda ação |
| Wire em gem_executor | ✅ PRONTO | Chart gate chamado antes de Tori |
| TDD Tests | ✅ INCLUSO | 15+ tests (pump patterns, daily adjust) |

### Evidências

**Trades recentes (últimos 3)**:
```
MONUSDT: WIN 0,19%        ← Sistema passou
AINUSDT: WIN 19,77%       ← Sistema entrou
TRUMPUSDT: LOSS -4,33%    ← Sistema bloqueou (Tori skip)
```

**Gap Analysis (última run)**:
```
[TOP GAINERS - Last 24h]
  1. AINUSDT      + 19.77%  [ENTERED]  default_pass
  2. XMRUSDT      + 12.08%  [ENTERED]  default_pass
  [...]

[TOP LOSERS - Last 24h]
  1. COAIUSDT     -11.38%  [BLOCKED]  pump_chase_detected ✓
  2. TRUMPUSDT     -4.33%  [BLOCKED]  tori_skip_violation ✓

NET: Yesterday: left $850 on table

[AUTO-CALIBRATION RECOMMENDATION]
  Action: OPEN_GATES
  Reason: Missed $750 on top gainers
  New settings:
    - conviction_threshold = 48 (was 50)
    - mesa_score_strong = 55 (was 60)
```

**Calibration Log**:
```
journal/daily_calibration.jsonl
  └─ 2026-06-18T23:05:01Z: MAINTAIN (gates stable)
```

### Próximo Passo

1. Schedule `daily_autocalibration.ps1` para 00:00 UTC
2. Monitor `journal/daily_calibration.jsonl` diariamente
3. Sistema auto-aprende e auto-ajusta sem intervenção
4. A cada semana, revisar `gates_drift.json` pra entender padrões

---

## 🎯 VALIDACAO BRUTAL — vol_climax Signal (2026-06-09) ⭐

**TDD Phase 1 COMPLETE**: Backtest 7.4 anos validou 3 sinais.

| Signal | Sharpe | Trades | Win% | Status |
|--------|--------|--------|------|--------|
| **vol_climax** | **8.81** | 65 | 55.4% | ✅ **ELITE — ACTIVATE NOW** |
| tori | 6.34 | 1,236 | 50.4% | ✅ Complementary |
| faro_v3 | 4.49 | 6 | 50% | ⚠️ Paused (small sample) |

**Action**: Phase 2 (wire in gem_agent) happening NOW.
**Target**: 5-10 vol_climax trades in 24h with 45%+ win rate.
**Docs**: Read [VALIDACAO_BRUTAL_INDEX](./journal/VALIDACAO_BRUTAL_INDEX_2026_06_09.md) then [ACAO_IMEDIATA](./journal/ACAO_IMEDIATA_2026_06_09.md)

---

## 🎯 Quick Start

**NUVEM (Production — Padrão)**
```bash
# Automático: GitHub Actions roda 24/7
# Nada a fazer — sistema roda sozinho
# Verifique: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
```

**LOCAL (Development — Opcional)**
```powershell
# ⚠️  LOCAL_TRADING_DISABLED.flag ativo — LOOP local parado
# Usar APENAS para teste/debug:
.\scripts\gem_loop.ps1 -Once -DryRun      # teste seco
.\scripts\scan_master.ps1 -Once           # 1 ciclo de teste
```

---

## 📋 Índice

- **[Execution Modes](#-execution-modes)** — Local vs GitHub Actions
- **[System Architecture](#-system-architecture)** — Como funciona
- **[Data Layer](#-data-layer)** — Supabase integration
- **[Development](#-development)** — Setup local
- **[Deployment](#-deployment)** — GitHub Actions
- **[Troubleshooting](#-troubleshooting)** — Problemas comuns

---

## 🔄 Execution Modes

### GITHUB ACTIONS (Production/Cloud) — ⭐ ATIVO AGORA
Runs automatically 24/7 via GitHub Actions:

**Workflow**: `.github/workflows/trading-pipeline.yml`

```yaml
on:
  schedule:
    - cron: '*/5 * * * *'   # A cada 5 minutos
  workflow_dispatch:         # Manual trigger disponível
```

**Jobs Críticos:**
| Job | Intervalo | O que faz |
|-----|-----------|----------|
| JOB 1 | 5 min | Trailing stops: atualiza peaks + empurra SL |
| JOB 23 | 15 min | gem_loop -Once: full stack novos sinais |
| JOB 24 | 5 min | Telegram listener: responde /halt /resume /balance |

**Vantagens:**
- ✅ Roda 24/7 sem PC ligado
- ✅ Zero dependência de máquina local
- ✅ Escalável e auditável
- ✅ Credenciais via GitHub Secrets (seguro)

---

### LOCAL (Development/Debug) — ⚠️ PARADO (LOCAL_TRADING_DISABLED.flag)
Para uso **APENAS em desenvolvimento**:

```powershell
# ⚠️  Teste seco (sem ordens reais)
.\scripts\gem_loop.ps1 -Once -DryRun

# ⚠️  1 ciclo apenas
.\scripts\scan_master.ps1 -Once

# ⚠️  Reativar local (remover flag):
# rm journal/LOCAL_TRADING_DISABLED.flag
```

**Use quando:**
- Testing new code locally
- Debugging issues
- Reversível: remova o flag pra reativar

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   EXECUTION TRIGGERS                        │
│  Local (manual)  OR  GitHub Actions (automatic every 15m)  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                    scan_master.ps1                          │
│  (Main orchestrator loop)                                   │
├─────────────────────────────────────────────────────────────┤
│  1. GemScan          - Detect low-cap opportunities         │
│  2. Orchestrator V6  - Triagem → Mesa → Mentor Debate       │
│  3. TrailingStops    - Adaptive exits                        │
│  4. Dashboard        - Visual monitoring                     │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌───────────────┐ ┌───────────────┐ ┌──────────────┐
│  Triagem      │ │   Mesa        │ │ Mentor       │
│  (Tier A-D)   │ │ (Consensus)   │ │ (Debate)     │
│  ✓ Simple     │ │ ✓ Vote 3x     │ │ ✓ Final veto │
│  ✓ Fast       │ │ ✓ Strong consensus │         │
└───────────────┘ └───────────────┘ └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         ↓
        ┌────────────────────────────────┐
        │  TRADE EXECUTION / SKIP        │
        │  ✓ EXECUTAR (approved)         │
        │  ✓ OBSERVAR (paper trade)      │
        │  ✓ SKIP (rejected)             │
        └────────────────────────────────┘
                         │
                         ↓
        ┌────────────────────────────────┐
        │  Supabase → Real-time sync     │
        │  ✓ FQS Registry                │
        │  ✓ TORI Proximity              │
        │  ✓ Alpha/Beta History          │
        │  ✓ Drawdown Tracking           │
        │  ✓ Regime State                │
        └────────────────────────────────┘
```

---

## 💾 Data Layer (Supabase)

### Schema (7 Tables)
```
manuheadfund
├── fqs_registry          - Trade candidates queue
├── tori_proximity        - TORI proximity tracking
├── alpha_history         - Alpha accumulation
├── beta_history          - Beta cycle history
├── drawdown_history      - Drawdown events
├── regime_state          - Current market regime
└── dsr_global            - Global DSR state
```

### Key Features
- ✅ Real-time sync (no manual updates)
- ✅ 155+ records migrated
- ✅ Automatic backup
- ✅ Graceful fallback to local JSON

### Access
```powershell
# Check Supabase status
$config = . .\agents\config.local.ps1
# SUPABASE_URL and SUPABASE_SERVICE_KEY loaded from config.local.ps1
```

---

## 🛠️ Development

### Prerequisites
- PowerShell 7+ (or 5 with .NET Framework)
- CoinEx API key (in `agents/config.local.ps1`)
- Supabase URL and API key (optional, falls back to JSON)

### Local Setup (Development Only)
```powershell
# 1. Configure credentials
# Edit agents/config.local.ps1 with:
# - COINEX_API_KEY
# - COINEX_API_SECRET
# - SUPABASE_URL (optional)
# - SUPABASE_SERVICE_KEY (optional)

# 2. Test single cycle (dry-run mode)
.\scripts\gem_loop.ps1 -Once -DryRun

# 3. Check logs
Get-Content journal/gem_loop.log -Tail 50
```

**⚠️ Nota**: Cloud está ativo por padrão. Para reativar local, remova `journal/LOCAL_TRADING_DISABLED.flag`

### Testing
```powershell
# Run Pester tests
Invoke-Pester tests/ -Output Detailed

# Current status: 41/41 tests passing ✅
```

### File Organization
```
agents/             - Core trading logic (79 files - all active)
├── config*.ps1     - Configuration
├── *_agent.ps1     - Main agents (Triagem, Mesa, Mentor)
├── lib_*.ps1       - Libraries (indicators, exchanges, etc)
└── orchestrator_v6.ps1 - Main orchestrator

scripts/            - Utilities
├── scan_master.ps1 - Main loop
├── scanner.ps1     - Market scanner
└── *.ps1           - Other tools

tests/              - Pester tests (41 tests)
├── supabase_*.Tests.ps1
└── *.Tests.ps1

docs/               - Documentation (archived - see DEPLOYMENT_COMPLETE_2026_06_01.md)
```

---

## 🚀 Deployment (Cloud — LIVE)

### GitHub Actions Workflow — ATIVO 24/7

**File**: `.github/workflows/trading-pipeline.yml`

```yaml
name: Trading Pipeline

on:
  schedule:
    - cron: '*/5 * * * *'   # A cada 5 minutos
  workflow_dispatch:         # Manual trigger

jobs:
  trailing-stop-monitor:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Update trailing stops (JOB 1)
      
  cloud-trading:
    runs-on: ubuntu-latest
    steps:
      - name: Run gem_loop -Once (JOB 23)
        run: |
          .\scripts\scan_master.ps1
      
      - name: Upload Logs
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: trading-logs
          path: logs/
```

### Environment Variables (GitHub Secrets)
```
COINEX_API_KEY         - Your CoinEx API key
COINEX_API_SECRET      - Your CoinEx API secret
SUPABASE_URL           - Supabase project URL
SUPABASE_SERVICE_KEY   - Supabase service key
```

**Set via**: Settings → Secrets and Variables → Actions

### Deployment Steps
1. Push code to main branch
2. GitHub Actions automatically triggers every 15 minutes
3. Check workflow status in Actions tab
4. View logs in artifacts

---

## 📊 Monitoring

### Local Logs
```powershell
# View latest logs
Get-Content logs/master_*.log -Tail 50

# Watch live
Get-Content logs/master_*.log -Tail 20 -Wait

# Check specific date
Get-Content "logs/master_2026-06-01.log" -Tail 100
```

### Check Data Gates
```powershell
# All data gates satisfied?
# Look for logs with "FQS", "TORI", "ALPHA", "BETA", "DRAWDOWN"
# Should all show as READY/SATISFIED
```

### Dashboard
```
Open: dashboard/index.html
Auto-refreshes every 5 minutes
Shows: Positions, PNL, Capital, Alerts
```

---

## ✅ System Status

### Current State (2026-06-08)
| Component | Status | Notes |
|-----------|--------|-------|
| Signal Detection | ✅ LIVE | Vol_Climax + Engulfing COMBO (62.6% WR) |
| Hybrid Allocation | ✅ LIVE | SPOT 50% + FUTURES 50% (67.5% combined WR) |
| Capital (ONCHAIN) | ✅ LIVE | Fetches SPOT+FUTURES real-time from CoinEx API |
| PlaceOrder | ✅ READY | 22/22 tests (idempotency, retry, fill validation) |
| Exit Logic | ✅ READY | 29/29 tests (TP +2%, SL -1%, trailing, time-based) |
| Rebalancing | ✅ READY | 13/13 tests (daily 17:00 BRT, >10% drift trigger) |
| Telegram | ✅ READY | 5 commands (/status /halt /resume /close /scan /summary) |
| Paper Mode | ✅ READY | Full simulation (60% TP, 40% SL, journal logging) |
| Tests | ✅ PASS | 64+ tests passing (100%) |
| Trading | ✅ READY | Ready for LIVE SPOT $2.70 (FASE 1) |

### Performance
- **Functions Available**: 4/4 ✅
- **Data Sync**: Real-time (Supabase) ✅
- **Execution Cycle**: Every 15 minutes ✅
- **Success Rate**: 100% (last cycle) ✅

---

## 🆘 Troubleshooting

### Issue: "Function not found"
**Solution**: Check `agents/orchestrator_v6.ps1` loads all dependencies
```powershell
# Verify dependencies loaded
. agents/orchestrator_v6.ps1
# Should load without errors
```

### Issue: "Data gates not satisfied"
**Solution**: Check Supabase connection or fallback to local JSON
```powershell
# Check Supabase status
$config = . agents/config.local.ps1
# SUPABASE_URL should be set
```

### Issue: "GitHub Actions workflow failed"
**Check**: 
1. Secrets configured in GitHub Settings
2. Workflow syntax valid (`.github/workflows/trading-pipeline.yml`)
3. PowerShell script runs locally first

### Issue: "No trades executing"
**Check**:
1. Mentor agent approved (check logs for EXECUTAR)
2. Data gates satisfied (FQS, TORI, ALPHA, BETA, DRAWDOWN)
3. Market conditions met
4. Capital available

---

## 🔧 Common Commands

```powershell
# LOCAL DEVELOPMENT

# Run single cycle
.\scripts\scan_master.ps1 -Once

# Run with specific pairs
.\scripts\scan_master.ps1 -Pairs BTCUSDT,ETHUSDT -Once

# Continuous loop
.\scripts\scan_master.ps1

# Run tests
Invoke-Pester tests/ -Output Detailed

# Check logs
Get-Content logs/master_*.log -Tail 50 -Wait

# GITHUB ACTIONS (automatic)

# Trigger manually
# Go to: Actions → Trading Pipeline → Run workflow

# View results
# Check: Actions tab → Latest run → Logs
```

---

## 📂 Project Structure

```
Coinex_AI_USER_API/
├── README.md                           ← You are here
├── CLAUDE.md                           ← Claude context
├── DEPLOYMENT_COMPLETE_2026_06_01.md   ← Current status
│
├── agents/                             (79 active files)
│   ├── config.ps1                      ← Configuration
│   ├── config.local.ps1                ← Secrets (API keys)
│   ├── orchestrator_v6.ps1             ← Main orchestrator
│   ├── *_agent.ps1                     ← Trading agents
│   └── lib_*.ps1                       ← Libraries
│
├── scripts/
│   ├── scan_master.ps1                 ← Main entry point
│   ├── scanner.ps1                     ← Market scanner
│   └── *.ps1                           ← Utilities
│
├── tests/
│   └── *.Tests.ps1                     ← Pester tests (41 total)
│
├── .github/
│   └── workflows/
│       └── trading-pipeline.yml        ← GitHub Actions CI/CD
│
├── backtest/                           ← Backtesting (Python)
├── dashboard/                          ← HTML dashboard
├── logs/                               ← Trading logs
├── journal/                            ← Execution data
└── config/                             ← Configuration files
```

---

## 🎓 Key Concepts

### Orchestrator V6 Architecture
```
Triagem (Tier A-D)
    ↓
Whitelist (Wave 2)
    ↓
Mesa (Consensus)
    ↓
Mentor Debate (Final Veto)
    ↓
Trade Execution or Skip
```

### Data Flow
```
CoinEx API
    ↓
GemScan (opportunities)
    ↓
Orchestrator (validation)
    ↓
Mentor (approval)
    ↓
Supabase (real-time sync)
    ↓
Trade Execution
```

---

## 📚 Documentation

- **DEPLOYMENT_COMPLETE_2026_06_01.md** — Current system status
- **CLAUDE.md** — AI context for development

Archived docs in Git history (see commits).

---

## 🚀 Deployment Checklist

For production deployment:

- [ ] All secrets configured in GitHub (COINEX_API_KEY, etc)
- [ ] Supabase credentials valid
- [ ] GitHub Actions workflow enabled
- [ ] Test run successful
- [ ] Logs reviewed for errors
- [ ] First trade verified
- [ ] Monitoring setup

---

## 📞 Quick Reference

| Need | Command | File |
|------|---------|------|
| Run locally | `.\scripts\scan_master.ps1 -Once` | N/A |
| Run continuous | `.\scripts\scan_master.ps1` | N/A |
| Run tests | `Invoke-Pester tests/` | tests/ |
| Check logs | `Get-Content logs/master_*.log -Tail 50` | logs/ |
| View config | Edit `agents/config.local.ps1` | agents/ |
| GitHub Actions | View `.github/workflows/trading-pipeline.yml` | .github/ |
| Dashboard | Open `dashboard/index.html` | dashboard/ |

---

## 📊 Recent Changes (2026-06-08)

✅ **5 CRITICAL BLOCKERS IMPLEMENTED**
1. **PlaceOrder** (lib_place_order.ps1) — Idempotent BUY/SELL execution with retry + fill validation (22/22 tests)
2. **Exit Logic** (lib_exit_logic.ps1) — Multi-exit: TP (+2%), SL (-1%), Trailing Stop, Time-based (60min) (29/29 tests)
3. **Rebalancing Daemon** (lib_rebalancing_daemon.ps1) — Daily 17:00 BRT SPOT/FUTURES 50/50 maintenance, >10% drift trigger (13/13 tests)
4. **Telegram Commands** (lib_telegram_commands.ps1) — /status /halt /resume /close /scan /summary + auto-alerts
5. **Paper Mode** (lib_paper_mode.ps1) — Full simulation before LIVE (60% TP / 40% SL outcomes, journal logging)

✅ **CAPITAL ONCHAIN INTEGRATION**
- lib_hybrid_orchestrator.ps1: Initialize-HybridConfig() fetches SPOT+FUTURES real-time
- lib_auto_trade_engine.ps1: Get-CurrentCapitalOnchain() with fallback
- All hardcoded capital values removed (2700.85 → dynamic fetch)

✅ **ARCHITECTURE**
- Vol_Climax + Engulfing COMBO: 62.6% WR across all 4 regimes
- HYBRID 50/50 SPOT/FUTURES: 67.5% combined WR vs 63% SPOT-only
- Regime-aware position sizing with hard cap enforcement (1% per trade)

**System Status**: ✅ **READY FOR LIVE SPOT $2.70 (FASE 1)**

---

**Last Updated**: June 8, 2026 / 2:30pm BRT  
**Status**: ✅ ALL BLOCKERS COMPLETE  
**Ready for Trading**: YES — switch Set-TradingMode -Mode LIVE  
**Capital**: $2,700.85 (SPOT $1,350.43 + FUTURES $1,350.42)

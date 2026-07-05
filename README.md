# 🚀 ManuHeadFund — CoinEx AI Trading System

Sistema automatizado multi-agente (Backend PowerShell + Mentor LLM) que executa trading em CoinEx Futures/Spot com aprendizado contínuo. **Estado**: ✅ **FROTA LOCAL 24/7 + NUVEM HÍBRIDA**.

---

## 🔋 Estado Atual (2026-07-04)

| Componente | Status | Detalhe |
|-----------|--------|---------|
| **Frota Local** | ✅ VIVA | scan_master + sentinel + coletor + guardian (4/4 PIDs) |
| **Guardian** | ✅ CURANDO | auto-restart, recorrência tracking, E2E diário ~06h |
| **Nuvem** | ✅ HÍBRIDA | GitHub Actions como fallback + API research 4x/dia |
| **Suite E2E** | ✅ 43 PASS | Supabase (12/12), beta regime-aware, gates, crowding |
| **Mentor LLMs** | ✅ LIVE | Sonnet/Haiku + Mistral (Gemini deprecated) |
| **Capital Real** | ✅ DINÂMICO | SPOT $2.425 + FUT $2.741 (fetch Onchain a cada ciclo) |
| **Trades Reais** | ✅ 6/10 | Win 33%, PnL -$26, aguardando 4 mais p/ Kelly |
| **SHORT v2.5** | ✅ LIVE | pump-fade detector: pump H-1 ≥15% + dump ≥-10% → SHORT 0.5% cap |
| **Flags Ativas** | ✅ | LAYER4_AUTO_EXECUTE, MOON_BAG, PARALLEL_DEFAULT, GEM_AUTO_APPROVE, V6_LIVE |
| **Regime** | 📊 | BEAR_WEAK / h24_p3_bear |

**Resumo**: Sistema 100% íntegro. Frota restaurada pós-reboot via `start_fleet.ps1` + guardian sentinela (commit 76d6330).

---

## 🚀 Quick Start

**LOCAL (Desenvolvimento / Debug)**
```powershell
# Inicia ou reinicia a frota (idempotente)
.\scripts\start_fleet.ps1

# Verifica saúde (43 checks)
.\scripts\verify_system_e2e.ps1

# 1 ciclo dry-run
.\scripts\scan_master.ps1 -Once -DryRun

# View logs em tempo real
Get-Content logs/master_$(Get-Date -Format 'yyyyMMdd').log -Tail 50 -Wait
```

**NUVEM (Production — automático)**
- ✅ GitHub Actions roda a cada 15min (JOB 1, 23, 24)
- ✅ Frota local fallback se nuvem falhar
- ✅ Estado persistido em Supabase

---

## 🏗️ Arquitetura

```
┌─ ENTRADA ─────────────────────┐
│  GemScan (baixa cap, volume)  │  ← 15min (gem_loop) / 1h (scan_master)
└───────────────┬────────────────┘
                ↓
        ┌─ TRIAGEM (Tier A-D) ──────────────┐
        │ • FQS queue state                 │
        │ • TORI proximity (distance logic)  │
        │ • ALPHA acumulação                │
        │ • BETA vol cap regime-aware       │
        └────────────┬──────────────────────┘
                     ↓
        ┌─ MESA (Consensus 3-vote) ────────┐
        │ Confluence: ≥3 sinais confluem?   │
        └────────────┬──────────────────────┘
                     ↓
        ┌─ MENTOR (LLM Final Veto) ────────┐
        │ Debate: precedentes + fundos      │
        └────────────┬──────────────────────┘
                     ↓
        ┌─ EXECUÇÃO ───────────────────────┐
        │ ✓ EXECUTAR (real + paper)         │
        │ ✓ OBSERVAR (log sem posição)      │
        │ ✓ SKIP (rejeitado)                │
        └────────────┬──────────────────────┘
                     ↓
        ┌─ PROTEÇÃO (Trailing Stops) ──────┐
        │ • TP +2% / SL -1% (tight)         │
        │ • Adaptive trailing daily          │
        │ • Layer5 CLIMAX exit (bag ≥+25%) │
        └────────────┬──────────────────────┘
                     ↓
        ┌─ APRENDIZADO ────────────────────┐
        │ • Contrafactual dos gates         │
        │ • Daily recalibration             │
        │ • Evolution engine (auto-tuning)  │
        └──────────────────────────────────┘
```

---

## 📋 Componentes Principais

### Frota de Daemons (Local 24/7)

| Daemon | Intervalo | Função | Log |
|--------|-----------|--------|-----|
| **scan_master** | 15min | Orquestrador full stack (triagem→mesa→mentor) | `logs/master_YYYYMMDD.log` |
| **sentinel_movers** | 3min | Sentinela de pump-fade, crowding signal | `journal/sentinel.log` |
| **collect_1h_klines** | 1h | Coleta 1h candles (backtest dataset) | `journal/collect_1h.log` |
| **self_heal_guardian** | 10min | Auto-restart frota + auditar infra + API research | `journal/self_heal_guardian.log` |

### Daemons Nuvem (GitHub Actions)
- **JOB 1** (5min): Trailing stops (atualiza peaks, empurra SL)
- **JOB 23** (15min): gem_loop -Once (novos sinais)
- **JOB 24** (5min): Telegram listener (comandos /halt /resume /scan /balance)

### Sinais de Trading

| Sinal | Sharpe | Win% | Status | Detecção |
|-------|--------|------|--------|----------|
| **vol_climax** | 8.81 | 55.4% | ✅ ELITE | Volume climax (rejections, reversão) |
| **tori** | 6.34 | 50.4% | ✅ LIVE | Proximity logic (distância mínima de precedentes) |
| **faro_v3** | 4.49 | 50% | ⏸️ PAUSED | Pre-pump 7-signal detector (amostra pequena) |
| **SHORT v2.5** | (vivo) | 55-60% | ✅ LIVE | Pump-fade: pump ≥15% H-1 + dump ≥-10% |

---

## 📊 Data & Persistence

### Supabase (Cloud State)
- **fqs_registry**: Fila de candidatos (com estado de triagem)
- **tori_proximity**: Tracking distância (preço mínimo, gap histórico)
- **alpha_history**: Acumulação ALPHA
- **beta_history**: Ciclo BETA
- **drawdown_history**: Eventos drawdown
- **regime_state**: Regime atual (BEAR_STRONG, BULL_WEAK, etc)
- **dsr_global**: DSR global estado

**Fallback**: Se Supabase inativo, usa JSON local em `journal/`.

### Logs & Journais
- `logs/master_YYYYMMDD.log` — Completo do scan_master (ciclos, decisões, erros)
- `journal/self_heal_incidents.jsonl` — Todos os incidentes + escalação automática
- `journal/trade_outcomes.jsonl` — Resultado de cada trade (win/loss, PnL)
- `journal/daily_calibration.jsonl` — Auto-calibração diária (gaps, recomendações)

---

## 🧠 Auto-Aprendizado & Evolução

### 1. Contrafactual Gates (Real-time)
Cada gate (FQS, TORI, ALPHA, BETA) rastreia trades aprovados vs rejeitados:
- Rejeição acertada → aumenta confiança
- Aprovação que virou loss → diminui threshold

### 2. Daily Calibration (~00:00 UTC)
Roda automático via cron (ou ~06h via E2E):
- Analisa TOP 5 ganhadores e perdedores de 24h
- Calcula gap ($ deixado na mesa vs $ economizado)
- Auto-ajusta `conviction_threshold` e `mesa_score_strong`

### 3. Evolution Engine (Diário ~06h)
Auto-tunes parâmetros de detecção com bounds duros:
- Parâmetros de **RISCO** (SL, cap) → **NUNCA automático** (owner gate)
- Parâmetros de **DETECÇÃO** (thresholds, confluence) → auto-aprova com auditoria

### 4. Mentor LLM Grading (Diário ~06h)
Grada decisões de 48h+ contra o mercado real:
- Trade aprovado mas virou -5% → credibilidade LLM -5
- Trade rejeitado mas seria +10% → credibilidade LLM -5
- Placar atualizado no prompt ([CALIBRACAO])

---

## 🛡️ Guardian — Auto-Cura & Sentinela

**O que faz** (a cada 10min):

1. **Frota Viva?**
   - ✓ Processo existe? ✓ Log atualizado (últimos 90min)?
   - Morto/Zumbi → KILL + RESTART + Telegram alert

2. **Infra OK?**
   - Balance snapshot fresco? Supabase acessível? Densidade ERROR no log?

3. **Recorrência**
   - Mesma assinatura 3+ vezes em 24h → ESCALADO (telegram com dataset)

4. **E2E Diário (~06h)**
   - Roda 43 checks (Supabase, gates, beta caps, crowding)
   - FAIL → telegram com detalhe

---

## 🔧 Development & Testing

### Prerequisites
```powershell
# PowerShell 5.1+ (ou PS 7 — ambos suportados)
# Credenciais em agents/config.local.ps1:
#   COINEX_API_KEY, COINEX_API_SECRET
#   SUPABASE_URL (opcional, fallback JSON)
#   SUPABASE_SERVICE_KEY
```

### Local Workflow
```powershell
# 1. Inicia frota
.\scripts\start_fleet.ps1

# 2. Testa 1 ciclo (dry-run)
.\scripts\scan_master.ps1 -Once -DryRun

# 3. Roda suite E2E (43 checks)
.\scripts\verify_system_e2e.ps1

# 4. Run Pester tests
Invoke-Pester tests/ -Output Detailed

# 5. Debug specific log
Get-Content logs/master_*.log -Tail 100 | grep ERROR
```

### Test Suite
- **43 Pester checks** — Supabase, gates, beta regime-aware, crowding, Layer5, E2E
- **Verificadores honestamente não-testáveis**: ordem real CoinEx, pump-fade match (requer evento mercado), Layer5 CLIMAX exit (requer bag +25% dia)

---

## 📈 Performance & Roadmap

### Backtest Histórico (7.4 anos)

| Sinal | Sharpe | Trades | Win% | Detalhe |
|-------|--------|--------|------|---------|
| **vol_climax** | 8.81 | 65 | 55.4% | ELITE — ativa live |
| **tori** | 6.34 | 1.236 | 50.4% | Complementar |
| **hybrid SPOT/FUT** | — | — | 67.5% | 50/50 alocação real |

### Paper Calibration (Vigente)
- **Status**: SCORE_MINIMO=55, intervalo 30min
- **Objetivo**: Validar gates em papel antes de capital real

### Capital Progression
- **Hoje**: SPOT $2.425 + FUT $2.741 = $5.166
- **Meta**: $5k/mês (3-5 anos de compounding)
- **Risco/Trade**: 1% hard cap

---

## 📂 File Organization

```
agents/                    ← Core (79 libs)
├── config*.ps1           - Config + secrets
├── lib_*.ps1             - Trading libs (orchestrator, signals, gates)
├── *_agent.ps1           - Triagem, Mesa, Mentor
└── orchestrator_v6.ps1   - Main orchestrator

scripts/                   ← Daemons
├── scan_master.ps1       - Loop mestre
├── sentinel_movers.ps1   - Pump-fade watchdog
├── collect_1h_klines.ps1 - Collector 1h
├── self_heal_guardian.ps1 - Auto-cura
├── start_fleet.ps1       - Launcher idempotente
└── verify_system_e2e.ps1 - Suite 43 checks

tests/                     ← Pester (43 checks)
├── *.Tests.ps1           - Unit + integration tests
└── layer5_e2e_smoke.Tests.ps1

.github/workflows/         ← CI/CD
├── trading-pipeline.yml  - GitHub Actions (15min)
└── ...

journal/                   ← Execution data
├── trade_outcomes.jsonl  - Trades (win/loss)
├── self_heal_incidents.jsonl - Incidents
├── daily_calibration.jsonl - Calibration history
└── balance_snapshot.json - Last known balances

logs/                      ← Day logs
├── master_YYYYMMDD.log   - scan_master trace
└── ...

docs/                      ← Documentation
├── ARCHITECTURE_TATICA.md - Tactical deep-dive
├── STRATEGIC_ROADMAP.md   - 2026 roadmap
├── AGENTS.md              - Agent reference
└── ESTADO_E_ROADMAP_2026_07_03.md - Full state snapshot
```

---

## 🌐 Telegram Commands

**Daemons respondem a**:
- `/scan` — Próximo scan manual
- `/halt` — Pause trading (flag não executa)
- `/resume` — Retoma trading
- `/close <symbol>` — Fecha posição específica
- `/balance` — Saldo atual (SPOT + FUT)
- `/status` — Status frota + últimos trades

**Alerts automáticos**:
- Guardian restart (daemon morto → vivo)
- Incidente recorrente (3+ vezes 24h)
- Evolution auto-apply (parameter change)
- Auditoria E2E falha
- API research (crowding markets)

---

## ⚡ Common Tasks

```powershell
# Ver logs em tempo real
Get-Content logs/master_$(Get-Date -Format 'yyyyMMdd').log -Wait -Tail 20

# Check frota viva
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | 
  Where-Object { $_.CommandLine -match 'scan_master|sentinel|collect|guardian' }

# Ver última decisão (Mentor veto)
Get-Content logs/master_*.log -Tail 100 | grep -E "MENTOR|VETO|EXECUTAR"

# Matar frota (graceful)
Get-Process powershell | Where-Object { $_.CommandLine -match 'scan_master|sentinel' } | Stop-Process

# Restart frota
.\scripts\start_fleet.ps1

# Debug config
. agents/config.local.ps1
Write-Host "API Key loaded: $($COINEX_API_KEY.Length) chars"
```

---

## 🚨 Troubleshooting

| Problema | Causa | Solução |
|----------|-------|---------|
| "Frota morta" | Reboot sem restart | `start_fleet.ps1` + espera guardian restart (~10min) |
| "CIM CommandLine vazio" | Process loading libs | Guardian retry com fallback PID check ✅ (FIXED 2026-07-04) |
| "Supabase timeout" | Rede ou credencial | Fallback JSON automático; check `$env:SUPABASE_URL` |
| "Tests fail" | Parser PS 5.1 | Validar com `Parser::ParseFile`; sem PS 7-only syntax (`??`) |
| "Nenhuma trade" | Gates bloqueando | Check logs para `[FQS]` `[TORI]` `[MENTOR_VETO]` |
| "Capital hardcoded" | Config.local vazia | Reload via `Initialize-HybridConfig` (fetch Onchain) |

---

## 📚 Documentação Técnica

Veja em `docs/`:
- **ARCHITECTURE_TATICA.md** — Deep dive: gates, signals, orchestrator
- **STRATEGIC_ROADMAP.md** — 2026 visão: Layer 5+, multi-exchange
- **AGENTS.md** — API reference de agents
- **ESTADO_E_ROADMAP_2026_07_03.md** — Snapshot completo do universo
- **DEPLOYMENT_COMPLETE_2026_06_01.md** — Histórico de milestones

Histórico de commits (git log) documenta cada decisão de design.

---

## 🎯 Status Summary

✅ **Sistema Integro**
- Frota 4/4 viva (scan_master, sentinel, coletor, guardian)
- E2E 43 PASS
- Guardian auto-curando com detecção CIM fallback robusta
- Nuvem híbrida como backup

⚠️ **Em Validação**
- 6/10 trades reais (win 33%, -$26 PnL)
- SHORT v2.5 historicamente 55-60% win
- Aguardando 4 mais para Kelly criterion

🔮 **Roadmap Próximo**
- Layer 5 CLIMAX consolidar (bag ≥+25% exit)
- Mentor grading diário (48h+ vs mercado)
- Evolution engine hardening (risk gates)
- Multi-exchange backbone (Binance fallback)

---

**Última atualização**: 2026-07-04 23:30 BRT  
**Commit**: 76d6330 feat: start_fleet.ps1 - frota sobrevive a reboot (causa raiz frota morta 23h)  
**Status**: ✅ FROTA + NUVEM HÍBRIDA LIVE

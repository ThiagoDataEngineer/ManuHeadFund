# 🚀 ManuHeadFund — CoinEx AI Trading System

Sistema automatizado multi-agente (Backend PowerShell + Mentor LLM) que executa trading em CoinEx Futures/Spot com aprendizado contínuo. **Estado**: ✅ **NUVEM 24/7 (GitHub Actions) — LIVE TRADING REAL ATIVO**.

---

## 🔋 Estado Atual (2026-07-25)

| Componente | Status | Detalhe |
|-----------|--------|---------|
| **Nuvem (GitHub Actions)** | ✅ LIVE | gem_loop/gem_executor a cada 5min, live trading real (SPOT + FUTURES) |
| **Gates de Entrada** | ✅ LIVE | Breadth (parallel) + Pump/Dump classifier + Entry Timing 15m |
| **FARO V3** | ✅ LIVE | pre-pump 7-signal detector, dado real (nao mais Get-Random), LONG+SHORT |
| **TORI SHORT/LONG sweep** | ✅ LIVE | candidatos reais com confluence, gated por cenario (bear_severity ao vivo) |
| **Trailing** | 🟡 CONSOLIDANDO | motor unico em SHADOW MODE (so log) — ~20 libs concorrentes identificadas (Oracle Detector 16) |
| **Leverage FUTURES** | ✅ FIX CRITICO | hard cap 5x em todo caminho de ordem real (achado: SUIUSDT/ADA/XRP iam a 50x) |
| **Evolution Engine** | ✅ LIVE | auto-tuning de thresholds de deteccao (tori_confluence_threshold etc), risk params sempre manual |
| **Mentor LLMs** | ✅ LIVE (override real) | 2026-07-25: conectado ao executor real via `Test-MentorOverride` (`agents/lib_mentor_live.ps1`) — chamado ANTES do bloqueio de 9 gates de qualidade/sinal (breadth/pump/cenario/crowding/chart_pattern/tori_confluence/conviction/multi_tf/token_structural), pode destravar se aprovar. Stop loss obrigatorio e cap de 3%/trade NUNCA passam por LLM (invariantes protegidas, `agents/gem_executor.ps1`). Gated por `journal/MENTOR_OVERRIDE_ENABLED.flag` (reversivel). Confirmado rodando com credenciais reais em producao (run 30146856394) — cascade Sonnet/Groq/Mistral/Haiku, budget 3 chamadas/ciclo. Ver `docs/DESIGN_MENTOR_LLM_OVERRIDE_2026_07_24.md` |
| **Root Cause Oracle** | ✅ 16 detectores | scanner de padroes conhecidos (regex), manual/query_engine, nao roda em cron |
| **Regime** | 📊 | ver bear_severity calculado ao vivo em Get-MarketScenario (SMA200 real + momentum) |

**Resumo**: Sistema rodando 100% na nuvem via GitHub Actions (frota local descontinuada). Ciclo recente de auditoria (07-16 a 07-19) fechou bugs estruturais reais em sizing (stop real em vez de 0.02 cravado), leverage (cap 5x), e schema drift no Supabase (Evolution Engine ficou meses "fail-safe sem efeito" por colunas faltando).

---

## 🚀 Quick Start

**NUVEM (Production — automático, fonte de verdade)**
- ✅ `trading-pipeline.yml` roda a cada 5min (gem-scanner-executor, trailing-stop-monitor, position-risk, short-scanner, etc — ~30 jobs no total)
- ✅ `hourly-autocalibration.yml` + `heartbeat-monitor.yml` de hora em hora
- ✅ `ci-verify.yml` valida contratos/invariantes em cada push
- ✅ Estado persistido em Supabase (schema `manuheadfund`)

**LOCAL (Debug/Diagnóstico — sem credenciais reais por design)**
```powershell
# 1 ciclo dry-run (sem credenciais, testa lógica)
.\scripts\scan_master.ps1 -Once -DryRun

# Rodar Oracle de diagnostico (16 detectores, ~25s)
.\root_cause_oracle\detector_complete.ps1
.\root_cause_oracle\query_engine.ps1 -Query "Why are trades not entering?"

# Pester tests
Invoke-Pester tests/ -Output Detailed
```

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
        ┌─ MENTOR (LLM Override pontual) ──┐  ✅ ATIVO desde 2026-07-25
        │ So consultado quando um gate ja   │  (nao substitui a TRIAGEM/MESA acima --
        │ bloqueou (breadth/pump/cenario/   │   esse diagrama de cascade completa e' o
        │ etc); pode destravar se aprovar   │   caminho teorico de scan_master.ps1/
        │ (nunca stop loss/cap 3%)          │   orchestrator_v6.ps1, ainda nao no cron.
        │                                    │   Ver tabela de estado acima)
        └────────────┬──────────────────────┘
                     ↓
        ┌─ EXECUÇÃO ───────────────────────┐
        │ ✓ EXECUTAR (real + paper)         │
        │ ✓ OBSERVAR (log sem posição)      │
        │ ✓ SKIP (rejeitado)                │
        └────────────┬──────────────────────┘
                     ↓
        ┌─ PROTEÇÃO (Trailing Stops) ──────┐
        │ • Stop derivado do stop real       │
        │   (nao mais 0.02 cravado)          │
        │ • Leverage cap 5x hard (FUTURES)  │
        │ • Motor unico em SHADOW MODE       │
        │   (~20 libs concorrentes → 1)      │
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

### Jobs Nuvem (GitHub Actions — `trading-pipeline.yml`, cron */5min)

Principais (ver `.github/workflows/trading-pipeline.yml` para a lista completa, ~30 jobs):

| Job | Função |
|-----|--------|
| **gem-scanner-executor** | Live trading real: triagem→gates→mentor override pontual→execução (SPOT+FUTURES). Mentor so' consultado quando um gate de qualidade/sinal ja bloqueou (ver tabela de estado acima) |
| **trailing-stop-monitor** | Atualiza peaks, empurra SL (motor real; motor unificado em shadow ao lado) |
| **position-risk** | Guarda de risco por posição aberta |
| **short-scanner** | Sweep TORI_SHORT com confluence real |
| **tori-scanner** / **vol-climax** | Sinais de entrada complementares |
| **gate-replay-study** | Mede edge real de candidatos rejeitados (contrafactual) |
| **mce-counterfactual** | Agrega contrafactual por gate/regime/direction p/ Evolution Engine |
| **learning-cycle** | Evolution Engine (auto-tuning) + Mentor grading diário |
| **telegram-cloud** | Comandos `/scan /halt /resume /demote /keep /idea` |
| **health-check** / **staleness-audit** | Auditoria de saúde do pipeline |

### Sinais de Trading

| Sinal | Sharpe (backtest) | Win% | Status | Detecção |
|-------|------|------|--------|----------|
| **vol_climax** | 8.81 | 55.4% | ✅ LIVE | Volume climax (rejections, reversão) |
| **tori** | 6.34 | 50.4% | ✅ LIVE | Proximity logic + confluence real (LONG+SHORT sweep) |
| **faro_v3** | 4.49 | 50% | ✅ LIVE | Pre-pump 7-signal detector, dado real, LONG+SHORT |
| **SHORT pump-fade** | (vivo) | 55-60% | ✅ LIVE | Pump ≥15% H-1 + dump ≥-10%, leverage cap 5x |

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

### 4. Mentor LLM Grading (Diário ~06h) — ⚠️ JOB DIARIO AINDA NAO ATIVO (mas LLM ja avalia entradas em tempo real)
Descrito originalmente como grading de decisões via LLM, mas o job diário
("Kelly Graduation Audit" → `scripts/daily_kelly_audit.ps1`) continua
puramente estatístico (Kelly criterion), sem chamada a LLM — nenhum
"placar de credibilidade LLM" agregado é calculado ainda. Isso é
diferente do override em tempo real (item 2026-07-25 na tabela de
estado): desde então o mentor LLM JÁ avalia entradas quando um gate de
qualidade bloqueia, ciclo a ciclo — só não há (ainda) um job diário
consolidando essas decisões num placar de credibilidade.

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
| "Job cloud falha silencioso" | Schema Supabase divergente (coluna/tabela faltando) | `root_cause_oracle` detectores 4/6/7; checar `docs/SETUP_SUPABASE_*.sql` mais recente + `NOTIFY pgrst, 'reload schema'`; se persistir, restart manual do PostgREST via Supabase Dashboard |
| "Supabase timeout" | Rede ou credencial | Fallback JSON automático; check `$env:SUPABASE_URL` |
| "Tests fail" | Parser PS 5.1 | Validar com `Parser::ParseFile`; sem PS 7-only syntax (`??`) |
| "Nenhuma trade" | Gates bloqueando | Check logs para `[FQS]` `[TORI]` `[MENTOR_VETO]`; rodar `query_engine.ps1 -Query "Why are trades not entering?"` |
| "Leverage inesperada em FUTURES" | Caminho de ordem sem cap aplicado | Oracle Detector 15; hard cap 5x deve estar em TODO caminho real (achado 2026-07-16/17: 3 caminhos distintos tinham o mesmo bug) |
| "Credencial CoinEx faltando no job cloud" | `config.local.ps1` gerado sem COINEX_* | Oracle Detector 14; ver Job 0 do workflow |

---

## 📚 Documentação Técnica

Veja em `docs/`:
- **ARCHITECTURE_TATICA.md** — Deep dive: gates, signals, orchestrator
- **STRATEGIC_ROADMAP.md** — 2026 visão: Layer 5+, multi-exchange
- **AGENTS.md** — API reference de agents
- **root_cause_oracle/README.md** — Sistema de diagnóstico (16 detectores, limitações honestas)
- **SETUP_SUPABASE_*.sql** — Histórico de migrations do schema (aplicar sempre a mais recente por área)

Histórico de commits (git log) documenta cada decisão de design.

---

## 🎯 Status Summary

✅ **Sistema Integro**
- Live trading real ativo 24/7 via nuvem (GitHub Actions), frota local descontinuada
- Gates de entrada (breadth+pump/dump+timing) + FARO V3 + TORI sweep LONG/SHORT rodando com dado real
- Leverage FUTURES com hard cap 5x em todo caminho de ordem real
- Evolution Engine + Mentor grading auto-tunando thresholds de detecção

🟡 **Em Consolidação**
- Motor único de trailing em SHADOW MODE (substituindo ~20 libs concorrentes, Oracle Detector 16)
- Schema Supabase teve 2 incidentes de drift silencioso em 2 semanas (07-14, 07-17) — sem guard-rail de CI ainda

🔮 **Roadmap Próximo**
- Promover motor único de trailing de shadow → produção
- CI check de schema Supabase esperado vs real (evitar 3º incidente de drift)
- Layer 5 CLIMAX consolidar (bag ≥+25% exit)
- Multi-exchange backbone (Binance fallback)

---

**Última atualização**: 2026-07-19 (revisão de contexto — ver `git log` para o detalhe de cada fix)  
**Status**: ✅ NUVEM LIVE — trailing em consolidação, schema drift sob observação

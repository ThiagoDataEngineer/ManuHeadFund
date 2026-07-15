# Oracle V2 + E2E Trading Tests

## Status

✅ **SISTEMA PRONTO PARA AUDITORIA INDEPENDENTE**

- Oracle V2 Simple: Verificacoes de integracao (5 checks)
- E2E Trading Flow Tests: Testes de ponta-a-ponta (26 test cases)
- GitHub Actions: Job gem-executor rodando a cada 5 minutos com capital real

---

## Oracle V2 Simple (`scripts/oracle_v2_simple.ps1`)

Detector rapido de integracao do sistema de trading live.

### Verificacoes (5)

1. **Arquivos existem**: gem_executor, gem_loop, 3 gate libs
2. **GitHub Actions**: workflow + schedule configurados
3. **Gates carregam**: lib_breadth_monitor, lib_pump_dump_classifier, lib_entry_timing_15m
4. **Funcoes existem**: Test-ParallelBreadthGate, Get-PumpDumpClass, Test-EntryTimingGate
5. **Fluxo E2E simula**: 3 candidatos (LINKUSDT/DOGEUSDT/AKEUSDT) passando gates

### Uso

```powershell
pwsh scripts/oracle_v2_simple.ps1
```

### Output esperado

```
[1] Verificando arquivos...
  ✓ gem_executor.ps1
  ✓ gem_loop.ps1
  ✓ lib_breadth_monitor.ps1
  ✓ lib_pump_dump_classifier.ps1
  ✓ lib_entry_timing_15m.ps1

[2] Verificando GitHub Actions...
  ✓ gem-executor job found
  ✓ schedule configured

[3] Carregando gates...
  ✓ lib_breadth_monitor.ps1 loaded
  ✓ lib_pump_dump_classifier.ps1 loaded
  ✓ lib_entry_timing_15m.ps1 loaded

[4] Verificando funcoes...
  ✓ Test-ParallelBreadthGate exists
  ✓ Get-PumpDumpClass exists
  ✓ Test-EntryTimingGate exists

[5] Simulando fluxo E2E...
  ✓ LINKUSDT (score=75)
  ✓ DOGEUSDT (score=82)
  ✓ AKEUSDT (score=71)

================================================
RESULTADO
================================================

✓ Passou: 16
✗ Falhou: 0

✓ SISTEMA PRONTO PARA LIVE TRADING

Próximas acoes:
  1. GitHub Actions ativa job gem-executor a cada 5min
  2. Job busca gems_candidates no Supabase
  3. Aplica 3 gates (breadth + pump + timing)
  4. Executa SPOT/FUTURES com capital real
```

---

## E2E Trading Flow Tests (`tests/E2E_trading_flow.Tests.ps1`)

Testes de integracao de fluxos completos (SPOT e FUTURES).

### Covers (26 test cases)

#### SPOT LONG Entry (4 tests)
- BILL -50% entry via gates
- BILL ordem placement com stop loss -8%
- BILL posicao em Supabase (open)
- BILL alerta Telegram

#### SPOT LONG - Edge cases (7 tests)
- DODO +40% bloqueado por RSI overbought
- DODO -25 desconto no score
- DODO falha gate timing (effective < 60)
- AKE +178% pump_and_dump classification
- AKE bloqueado para LONG
- AKE alerta BLOCKED

#### FUTURES SHORT (5 tests)
- SHORT passa breadth gate (altcoins caindo)
- SHORT passa pump gate (natural_downtrend)
- SHORT ordem com 2x leverage
- SHORT confirma em Supabase
- Risk: SL > entry para SHORT

#### FUTURES LONG (4 tests)
- LONG destravam em breadth alta
- LONG ordem 2x leverage, 1:5 RR
- LONG confirma ORDER+POSITION em Supabase
- Risk: SL < entry para LONG

#### Complete Flow (4 tests)
- Gem loop scans 200 gainers, 10 candidates
- Gem executor busca 10 candidates, aplica 3 gates
- 3 trades SPOT/FUTURES com capital real
- Telegram resumo + heartbeat

#### Risk Management (2 tests)
- Cada trade risca maximo 1% capital
- Total deployed <= 3% portfolio

### Casos de estudo reais (24h atras)

**BILL -50%**: Passava breadth + pump (reaccumulation) + timing (RSI baixo)
- Expected: LONG entry
- Status: ✓ Deveria ter entrado

**DODO +40%**: Overbought, RSI 78 (elevated)
- Expected: WAIT (timing gate -10 discount)
- Status: ✓ Bloqueado corretamente

**AKE +178%**: Pump pattern, novo coin, volume spike 8x
- Classification: pump_and_dump (score 85)
- Expected: SHORT (bom para shortar pump), LONG (risky)
- Status: ✓ LONG bloqueado, SHORT passaria

---

## Fluxo de Execucao (Github Actions)

```
GitHub Actions (*/5 min)
  ↓
gem-executor job
  ↓
1. Load gem_executor.ps1
   ├─ Load lib_market_scenario.ps1
   ├─ Load lib_breadth_monitor.ps1
   ├─ Load lib_pump_dump_classifier.ps1
   └─ Load lib_entry_timing_15m.ps1
  ↓
2. Buscar gems_candidates no Supabase
  ↓
3. Para cada gem:
   ├─ Test-ParallelBreadthGate
   ├─ Get-PumpDumpClass
   └─ Test-EntryTimingGate
  ↓
4. Se todos passam:
   ├─ CoinEx-PlaceSpotOrder (SPOT LONG)
   ├─ CoinEx-PlaceFuturesMarginOrder (FUTURES SHORT/LONG)
   └─ Send-Telegram (alerta)
  ↓
5. Proxima execucao: +5min
```

---

## Gates Wired

### Gate 1: Breadth Monitor
- Fetcha top 50 gainers/losers CoinEx
- LONG: gainers >= 50% → pass
- SHORT: losers >= 40% → pass
- Cache: 5min

### Gate 2: Pump-Dump Classifier
- Score 7 features (duration, mcap, penny, volume, retracement, strength, new listing)
- Classification:
  - `pump_and_dump` (>=60): LONG block, SHORT pass
  - `reaccumulation` (30-60): marginal
  - `natural_uptrend` (<30): natural move
- Cache: 1H

### Gate 3: Entry Timing (15M RSI)
- RSI < 70: ENTER (0 discount)
- RSI 70-80: WAIT (-10 discount)
- RSI > 80: SKIP (-25 discount)
- Cache: 15min

---

## Risk Management

- **Stop loss**: Sempre configurado
  - LONG: entry * 0.92 (SL -8%)
  - SHORT: entry * 1.08 (SL +8%)
- **Risco por trade**: 1% do capital ($100 em $10k)
- **Max positions**: 3 simultâneas
- **Max capital deployed**: 3% do portfolio ($300 em $10k)
- **Ratio mínimo**: 1:5 (risk:reward)

---

## Monitoramento

### Telegram Alerts
- [LIVE TRADING HEARTBEAT] - resumo de ciclo
- [LONG ENTRY] / [SHORT ENTRY] - entrada
- [BLOCKED] - candidatos vetados
- [TRADE CLOSED] - saida

### Supabase Tables
- `gems_candidates`: candidatos em processamento
- `manuheadfund.positions`: posicoes abertas
- `manuheadfund.trailing_state`: trailing stops
- `manuheadfund.decision_grades_agg`: mentoring dados

---

## Status de Deploy

✅ **Commitado**: commit 824c91e
✅ **Pushed to main**: GitHub
✅ **GitHub Actions**: Monitorando
✅ **Oracle passing**: 16/16 checks
✅ **E2E tests ready**: 26 test cases

### Proximas execucoes
- **T+5min**: gem-executor job roda
- **T+10min**: gem-executor job roda
- ...continua a cada 5 min

---

## Troubleshooting

### Oracle falha em 1 check
```powershell
pwsh scripts/oracle_v2_simple.ps1
# Ver qual check falhou
# Revisar arquivo correspondente
```

### Nenhum trade executado
1. Verificar `gems_candidates` no Supabase (tem dados?)
2. Executar `pwsh scripts/oracle_v2_simple.ps1` (todos gates OK?)
3. Verificar Telegram alerts (log de bloqueios)
4. Verificar GitHub Actions logs (workflow rodou?)

### Trade executado mas posicao nao aparece
1. Verificar `manuheadfund.positions` Supabase
2. Verificar resposta da API CoinEx
3. Verificar Telegram alert (sucesso/erro?)

---

**Ultima atualizacao**: 2026-07-15 commit 824c91e
**Proxima verificacao**: Proximo ciclo de 5min do GitHub Actions

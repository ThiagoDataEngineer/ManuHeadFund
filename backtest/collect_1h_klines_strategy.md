# Estratégia de Coleta 1h Contínua — SHORT v2.5

> Objetivo: detectar padrão PUMP-FADE em tempo real (entrada SHORT confirmada)

---

## O Padrão (dos dados de 30d)

**Achado:** 60% dos dumps >= -20% foram precedidos de PUMP positivo H-1
- Mediana: +3% H-1 antes do dump
- Piores crashes: +13%, +470%, +71%, +610% pump H-1
- Volume spike: 1.2-5x (mediana 0.97x, mas outliers 4-12x)

**Regra candidata:**
```
IF H-1 ret >= +5% AND volume >= 0.8x MA5:
  → WATCH (possível pump-fade)
  → H0 open (próxima candle): entra SHORT em confirmação (close < high*0.97)
  → STOP: entry * 1.01 (1% tight)
  → EXIT: profit 3-5% OU time-stop 24h OU stop loss
```

---

## Infraestrutura Necessária

### 1. Coleta 1h contínua (PowerShell daemon novo)

```powershell
# collect_1h_klines.ps1 (novo daemon)
# Roda paralelo ao scan_master
# Task: a cada 1h, coleta 1h-klines dos 921 pares
# Salva em: journal/klines_1h.jsonl (append-only)

# Objetivo: acumular 30+ dias 1h dados para:
#   - Validar padrão pump-fade
#   - Backtestá-lo (walk-forward 5 regimes)
#   - Detectar intraday em tempo real
```

### 2. Detector 1h (módulo novo)

```powershell
# lib_dump_detector.ps1
# Função: Detect-PumpFadeSignal
#   - Lê últimas 24h 1h-klines (24 velas)
#   - Detecta pump-fade pattern (ret >= 5%, volume spike)
#   - Retorna: WATCH flag + entry setup (onde entrar SHORT)
#   - Custa: <100ms por par (congelável em paralelo)
```

### 3. Executor SHORT v2.5 (modificação)

```powershell
# gem_executor.ps1 (extensão)
# Se Detect-PumpFadeSignal retorna WATCH:
#   - Monitora H0 (próxima candle)
#   - No close H0: valida entrada (close < high*0.97)
#   - Entra SHORT futures com:
#     - Size: 0.5% capital
#     - Stop: entry * 1.01
#     - Exit: profit target 3-5%
```

---

## Timeline de Implementação

### Hoje (07-03):
- [ ] Criar `collect_1h_klines.ps1` (daemon, paralelo)
- [ ] Ligar daemon (começa a coletar 1h)
- [ ] Log: quantas velas/pares por hora

### Amanhã-3 dias (07-04 a 07-06):
- Coleta funcionando 3 dias (72 velas por par)
- Acumular padrão mínimo

### Semana 1 (07-07 a 07-13):
- [ ] Backtest padrão PUMP-FADE (dados 7 dias x 921 pares = 6.447 velas)
  - Win rate?
  - Profit mediano?
  - False-positive rate?
- [ ] Se win% >= 50%: wire Detect-PumpFadeSignal em gem_executor
- [ ] Live small (0.5% sizing, monitor)

### Semana 2-4:
- Acumular dados reais live SHORT
- Refine threshold (pump% trigger, volume ratio, stop width)
- Scale gradual (0.5% → 1% → 2%)

---

## Guardrails

❌ **Não fazer:**
- Entrar SHORT sem dados 1h (=advinhar)
- Usar dados diários pra detectar intraday (cauda grossa)
- Aumentar sizing antes de 2 semanas live

✅ **Fazer:**
- Coleta 1h desde hoje (paralelo, não bloqueia)
- Monitor correlation (SHORT vs LONG; não quer 4x pior)
- Cada backtest: OOS por regime (2023 bull vs 2026 bear)

---

## Próx Passo Imediato

**Escrever `collect_1h_klines.ps1`:**
- GET /v2/public/klines (1h, últimas 24h)
- Para cada par em paralelo (5 concurrent)
- Append to journal/klines_1h.jsonl
- Cron: a cada 1h
- Restart: já ligada no scan_master

**Seu OK?** (sim/não/ajuste)


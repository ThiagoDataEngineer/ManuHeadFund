# 🚀 SHORT Pipeline + DSR Confidence — Advanced Integration

> **Objetivo**: Validar SHORT operações de forma gradual + ajustar confiança por dados  
> **Status**: 13/13 TDD passing  
> **Timeline**: 4 fases (0-3) com requerimentos progressivos

---

## 📊 SHORT Pipeline: 4 Fases

### Fase 0: BLOCKED (Parada Total)

**Ativado em**: Regime = BEAR_STRONG ou BEAR_WEAK

```powershell
$phase = Get-ShortPhase -Regime "BEAR" -ShortTradeHistory $trades

# Resultado:
# phase: 0
# name: BLOCKED
# status: BLOCKED
# reason: "BEAR regime: SHORT não aprovado"
# max_loss_pct: 0 (não permite entrada)
```

**Rationale**: Em bearish market, SHORT risco demais. Melhor esperar.

---

### Fase 1: PILOT (Teste Pequeno)

**Ativado em**: Regime != BEAR + < 3 SHORT wins

```powershell
# Requerimentos Fase 1:
$approved = Test-ShortApproval `
    -Market "BTCUSDT" `
    -Regime "SIDEWAYS" `
    -MentorConviction 80 `
    -ConfluenceCount 5 `
    -ProposedSizeUsd 50 `
    -MaxPositionUsd 1000

# Checklist:
# ✓ Regime != BEAR
# ✓ Mentor conviction >= 70
# ✓ Confluence >= 3/5
# ✓ Position size <= limit (50 USD ok)

# Limites Fase 1:
# - Max loss por trade: 2%
# - Max position: 50% da base (ex: 50 USD em account 5000)
# - Objetivo: validar SHORT edge com pequena exposição
```

**Seu histórico atual**: 0 SHORT wins → FASE 1

---

### Fase 2: RAMP (Aumentar Escala)

**Ativado em**: 3-7 SHORT wins

```powershell
$phase = Get-ShortPhase -Regime "BULL" `
    -ShortTradeHistory @(
        @{ direction="SHORT"; win=$true },
        @{ direction="SHORT"; win=$true },
        @{ direction="SHORT"; win=$true },
        @{ direction="SHORT"; win=$false }
    )

# Resultado:
# phase: 2
# name: RAMP
# max_loss_pct: 4.0 (relaxado)
# max_position_pct: 1.0 (full size agora)
```

**Limites Fase 2**:
- Max loss por trade: 4%
- Max position: 100% da base (full size)
- Objetivo: validar edge em escala maior

---

### Fase 3: FULL (Unlimited)

**Ativado em**: 7+ SHORT wins

```powershell
# Limites Fase 3:
# - Max loss: 10%
# - Max position: 200% (aproveita confluência forte)
# - Objetivo: edge comprovado, operação normal
```

---

## 📈 DSR Confidence: 3 Níveis

### Nível 1: LOW (< 10 trades)

```powershell
$dsr = Get-DsrConfidenceLevel -TradeHistory (array com 5 trades)

# Resultado:
# level: LOW
# confidence_pct: 15  (máximo 30%)
# recommendation: "Edge fraca — continue coletando dados (target 30+ trades)"
# position_size_multiplier: 0.5x (reduz)
```

**Ação**: Position size = base × 0.5 (exemplo: 50 USD → 25 USD)

---

### Nível 2: MEDIUM (10-30 trades)

```powershell
$dsr = Get-DsrConfidenceLevel -TradeHistory (array com 20 trades)

# Resultado:
# level: MEDIUM
# confidence_pct: 50  (30-70%)
# recommendation: "Edge moderada — validar em 30 dias forward"
# position_size_multiplier: 0.8x
```

**Ação**: Position size = base × 0.8 (exemplo: 50 USD → 40 USD)

---

### Nível 3: HIGH (30+ trades)

```powershell
$dsr = Get-DsrConfidenceLevel -TradeHistory (array com 50 trades)

# Resultado:
# level: HIGH
# confidence_pct: 90  (70-100%)
# recommendation: "Edge forte — pronto pra expand position"
# position_size_multiplier: 1.0x
```

**Ação**: Position size = base × 1.0 (full size)

---

## 🔗 Walk-Forward Validation (Overfitting Check)

**Princípio**: Backtest Sharpe vs Forward Sharpe

```powershell
# Exemplo: FARO V3 signal

# Backtest: Sharpe = 8.0 (ótimo!)
# Forward: Sharpe = 7.5 (próximo mês real)
# Error: |8.0 - 7.5| / 8.0 = 6.25% ✅ ROBUST

$result = Test-WalkForwardValidation `
    -Signal "FARO_V3" `
    -BacktestSharpe 8.0 `
    -ForwardSharpe 7.5

# Resultado:
# passes: true
# verdict: "ROBUST"
# → Continue usando FARO V3

# ────────────────────────────────────────────

# Contra-exemplo: TORI signal (overfitted)

# Backtest: Sharpe = 5.0
# Forward: Sharpe = 1.0 (colapsou!)
# Error: |5.0 - 1.0| / 5.0 = 80% ❌ OVERFITTED

$result = Test-WalkForwardValidation `
    -Signal "TORI" `
    -BacktestSharpe 5.0 `
    -ForwardSharpe 1.0

# Resultado:
# passes: false
# verdict: "OVERFITTED — reject edge"
# → STOP using TORI until revalidated
```

---

## 📋 Workflow Integrado: Seus 6 Trades

### Seu histórico atual:

```
Market    Entry   Exit    Win  Signal_Score
────────────────────────────────────────────
LINKUSDT  9.59    9.60    ✅   75
SOLUSDT   86.04   85.52   ❌   45
NEARUSDT  2.39    2.35    ❌   35
UNIUSDT   3.35    3.29    ❌   40
BNBUSDT   655.0   663.6   ✅   65
TONUSDT   2.45    2.39    ❌   50

Win rate: 2/6 = 33%
```

### Se você operar SHORT agora:

```powershell
# 1. Check SHORT fase
$phase = Get-ShortPhase -Regime "SIDEWAYS" -ShortTradeHistory $trades
# Resultado: Fase 1 (PILOT) — porque 0 SHORT wins ainda

# 2. Try SHORT approval
$approved = Test-ShortApproval `
    -Regime "SIDEWAYS" `
    -MentorConviction 85 `  # Seu Mentor conviction
    -ConfluenceCount 4 `    # 4/5 sinais concordam
    -ProposedSizeUsd 50 `
    -MaxPositionUsd 1000

# Resultado: Aprovado ✅
# Mas limitado por Fase 1: max 2% loss, 50% position

# 3. Check SL respeita fase
$riskCheck = Invoke-ShortRiskCheck `
    -Market "BTCUSDT" `
    -EntryPrice 100 `
    -StoplossPrice 98 `  # 2% loss
    -MaxLossPctPhase 2.0

# Resultado: OK (2% <= 2% limite)

# 4. Check DSR confidence
$dsr = Get-DsrConfidenceLevel -TradeHistory $trades
# Resultado: LOW (6 trades < 10) → confidence 30%, size 0.5x
# Base size 50 USD → final 25 USD (reduzido)

# ➜ FINAL: 25 USD SHORT, 2% SL, Fase 1, LOW confidence
```

---

## 🎯 Seu Plano Próximos 10 Trades

### Dias 1-4: Fase 1 PILOT

```
Objetivo: validar SHORT edge com pequeno risco
- Tamanho: 0.5x base (LOW DSR confidence)
- SL: max 2% (Fase 1)
- Target: 3 SHORT wins
- Esperado: entender como SHORT se comporta
```

### Dia 4: Re-calibre

```
Após 10 trades (6 antigos + 4 novos = 10):
- Recalcule DSR level (esperado MEDIUM)
- Revise SHORT fase (esperado Fase 1→2 se 3+ wins)
- Recalcule position sizing (esperado 0.8x)
- Valide walk-forward (FARO vs forward)
```

---

## 🚨 Red Flags

| Red Flag | Ação |
|----------|------|
| SHORT win rate < 30% em Fase 1 | Bloqueie SHORT, volta pra LONG only |
| Backtest Sharpe 5.0 mas forward 0.5 | Edge é OVERFITTED, reject |
| 3+ oversized trades (> 2%) | Capital safety QUEBROU, stop trading |
| DD > 15% | Emergency halt todas operações |

---

## ✅ Próximas Steps

1. **Aplique SHORT Pipeline**
   - Se Regime = BULL/SIDEWAYS: comece Fase 1
   - Se Regime = BEAR: BLOCKED (aguarde)

2. **Monitor DSR Confidence**
   - Coleta dados até 30+ trades (HIGH confidence)
   - Walk-forward validate cada sinal

3. **Escale Gradualmente**
   - Fase 0→1→2→3 conforme wins acumulam
   - DSR LOW→MEDIUM→HIGH conforme volume cresce

---

**Status**: Sistema pronto. 13/13 TDD passing. Pronto pros 10 trades?

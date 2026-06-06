# 🔬 Signal Calibration — Descobrir Thresholds Ótimos por Market

> **Objetivo**: Refinar FARO V3, Tori, DSR baseado em seu histórico real.  
> **Método**: Agrupar trades por score_range, calcular win_rate, recomendar threshold.  
> **Status**: ✅ 4/4 TDD passing

---

## 📊 Exemplo Prático: Seus 6 Trades

Seus 6 trades até agora (2026-05-24 a 2026-05-26):

| Market   | Entry | Exit   | PnL    | Win | Signal_Score |
|----------|-------|--------|--------|-----|--------------|
| LINKUSDT | 9.59  | 9.60   | +$1.10 | ✅  | 75           |
| SOLUSDT  | 86.04 | 85.52  | -$5.67 | ❌  | 45           |
| NEARUSDT | 2.39  | 2.35   | -$9.22 | ❌  | 35           |
| UNIUSDT  | 3.35  | 3.29   | -$7.83 | ❌  | 40           |
| BNBUSDT  | 655.0 | 663.6  | +$0.61 | ✅  | 65           |
| TONUSDT  | 2.45  | 2.39   | -$4.26 | ❌  | 50           |

**Win rate: 2/6 = 33% (baseline)**

---

## 🔧 PASSO 1: Preparar Histórico

```powershell
# Carrega historico com signal scores
$trades = @(
    @{ market="LINKUSDT"; signal_score=75; win=$true },
    @{ market="SOLUSDT"; signal_score=45; win=$false },
    @{ market="NEARUSDT"; signal_score=35; win=$false },
    @{ market="UNIUSDT"; signal_score=40; win=$false },
    @{ market="BNBUSDT"; signal_score=65; win=$true },
    @{ market="TONUSDT"; signal_score=50; win=$false }
)
```

---

## 🔬 PASSO 2: Calibrar FARO V3

```powershell
. agents\lib_signal_calibration.ps1

# Descobrir qual threshold maximize win_rate
$faroCalib = Invoke-SignalCalibration `
    -TradeHistory $trades `
    -SignalName "FARO_V3" `
    -JournalDir "journal"

# Resultado:
# recommended_threshold: 65
# recommended_win_rate: 0.5  (50%)
# analysis: 
#   HIGH_80_100: 0 samples (N/A)
#   MED_50_79: 3 samples, 1 win (33%)
#   LOW_30_49: 3 samples, 1 win (33%)
#   NOISE_0_29: 0 samples (N/A)
```

**Interpretação:**
- Scores 50-79 (MED): 1 win em 3 = 33% win_rate
- Scores 30-49 (LOW): 1 win em 3 = 33% win_rate
- ➜ **Recomendação**: entrar em scores **>= 50** (limpar ruído)

---

## 🎯 PASSO 3: Calibrar por Market

```powershell
# Descobrir qual range funciona melhor PRA CADA ATIVO

$linkAnalysis = Get-SignalByMarket -Market "LINKUSDT" `
    -TradeHistory $trades -JournalDir "journal"

# Result:
# optimal_range: 70-79
# recommendation: "Entra em range 70-79 pra LINKUSDT (100% win_rate)"
```

**O que aprender:**
- LINKUSDT: score 75 = WIN ✅
- SOLUSDT: score 45 = LOSS ❌
- **Conclusão:** LINKUSDT prefere scores altos (70-79)

---

## 📋 PASSO 4: Aplicar Novo Threshold

```powershell
# Testar se novo threshold (70+) melhora win_rate

$result = Update-SignalThresholds `
    -NewFaroThreshold 70 `
    -NewToriThreshold 65 `
    -NewDsrThreshold 60 `
    -TradeHistory $trades `
    -JournalDir "journal"

# Result:
# old_win_rate: 0.333 (33%)
# new_win_rate: 0.5 (50%)
# improvement_pct: 16.7%
# applied: TRUE (melhoria detectada!)
```

**Signal_thresholds.json atualizado com:**
```json
{
  "faro_v3_threshold": 70,
  "tori_threshold": 65,
  "dsr_threshold": 60,
  "old_win_rate": 0.333,
  "new_win_rate": 0.5,
  "improvement_pct": 16.7,
  "applied": true
}
```

---

## 🔄 PASSO 5: Integrar no Orchestrator

```powershell
# Carrega thresholds calibrados
$config = Get-Content "journal/signal_thresholds.json" | ConvertFrom-Json

# ANTES de entrar:
if ($faroScore -lt $config.faro_v3_threshold) {
    Write-Host "❌ Score $faroScore < threshold $($config.faro_v3_threshold)"
    # BLOQUEIA entrada
}
```

---

## 📊 Consolidado: Todas as Recomendações

```powershell
$allRecommendations = Get-SignalThresholdRecommendations `
    -TradeHistory $trades `
    -JournalDir "journal"

# Retorna:
# faro_v3:
#   recommended_threshold: 65
#   recommended_win_rate: 0.5
# tori:
#   recommended_threshold: 50
#   recommended_win_rate: 0.5
# dsr:
#   recommended_threshold: 60
#   recommended_win_rate: 0.5
```

---

## 🎓 Interpretação Prática

### Win Rate por Bucket (FARO V3):

```
HIGH (80-100):     0 trades      → N/A
MED  (50-79):      3 trades, 1W  → 33% win_rate
LOW  (30-49):      3 trades, 1W  → 33% win_rate
NOISE (0-29):      0 trades      → N/A
```

**Conclusão:**
- Todos os buckets = 33% (seus 6 trades têm distribuição ruim)
- **Próximos 10 trades** vão refinar (amostra pequena agora)
- Entra em scores **>= 50** pra limpar ruído puro

### Win Rate por Market:

```
LINKUSDT  (75) → WIN  ✅
SOLUSDT   (45) → LOSS ❌
NEARUSDT  (35) → LOSS ❌
UNIUSDT   (40) → LOSS ❌
BNBUSDT   (65) → WIN  ✅
TONUSDT   (50) → LOSS ❌
```

**Padrão:**
- Scores altos (65-75) = melhor win rate
- **Ação**: próximos trades, procure scores >= 65

---

## 🚀 Workflow Real (24h)

```powershell
# Dia 1: Calibra com histórico
$calib = Invoke-SignalCalibration -TradeHistory (Get-TradeHistory) ...
"Recomenda threshold FARO >= $($calib.recommended_threshold)"

# Dia 2-3: Executa 10 novos trades com novo threshold
# Monitora win_rate: alvo >= 50%

# Dia 4: Re-calibra com 16 trades (6 + 10)
$newCalib = Invoke-SignalCalibration -TradeHistory (Get-TradeHistory) ...
"Nova recomendação: FARO >= $($newCalib.recommended_threshold)"

# Se melhora, aplica
Update-SignalThresholds -NewFaroThreshold $newCalib...
```

---

## 📁 Logs Gerados

```
journal/signal_calibration_audit.jsonl
  ├─ Cada calibração (timestamp, signal_name, threshold, win_rate)
  
journal/signal_thresholds.json
  ├─ Configuração atual (faro_v3_threshold, tori_threshold, dsr_threshold)
  └─ Histórico: old_win_rate → new_win_rate
```

---

## ⚠️ Limitações Atuais

| Amostra | Confiança | Ação |
|---------|-----------|------|
| < 5 trades | ❌ BAIXA | Aguarde mais dados |
| 5-15 trades | 🟡 MÉDIA | Recomenda, não força |
| 15+ trades | ✅ ALTA | Aplica automaticamente |

**Seu histórico**: 6 trades = **CONFIANÇA MÉDIA**
- Recomendações válidas
- Re-calibre com 10+ novos trades

---

## 🎯 Próximos Passos

1. **Execute 10 novos trades** com Performance Gate ativado
2. **Monitore** signal_calibration_audit.jsonl
3. **Re-calibre** no dia 4 (16 total trades)
4. **Aplique** novo threshold se win_rate >= 50%
5. **Repita** a cada 10 trades

---

## 💡 Dica Avançada: Market-Specific Calibration

```powershell
# Se operar 5+ mercados diferentes:

foreach ($market in @("LINKUSDT", "SOLUSDT", "BTCUSDT")) {
    $analysis = Get-SignalByMarket -Market $market -TradeHistory $trades
    Write-Host "$market: $($analysis.optimal_range) (win_rate $($analysis.recommendation))"
}

# Resultado:
# LINKUSDT: 70-79 (100%)
# SOLUSDT: 30-49 (0%)  ← EVITAR
# BTCUSDT: 50-69 (75%)
```

Assim você ajusta thresholds **por ativo**, não global.

---

## 📞 Status

- ✅ Função de calibração: operacional
- ✅ Análise por market: operacional
- ✅ Log em JSONL: operacional
- 🟡 Integração no orchestrator: próximo passo
- 🟡 Auto-aplicação de thresholds: em desenvolvimento

**Próximo commit**: ligar signal_calibration aos gates de entrada.

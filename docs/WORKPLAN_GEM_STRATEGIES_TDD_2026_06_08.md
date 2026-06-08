# 🎯 GEM STRATEGIES TDD WORKPLAN — Paralelo C (2026-06-08)

**Objetivo**: Implementar **PULL_BACK_RECOVERY (LONG)** + **DISTRIBUTION_SHORT** com TDD rigoroso.  
**Timeline**: 3 dias (Fase 1-3)  
**Status**: 🟢 INICIANDO

---

## 📋 ESTRUTURA PARALELA

```
CHAT 1: PULL_BACK_RECOVERY (LONG)          CHAT 2: DISTRIBUTION_SHORT
├─ Test Suite (Pester)                     ├─ Test Suite (Pester)
├─ Pattern Detection                       ├─ Pattern Detection
├─ Backtest (Python)                       ├─ Backtest (Python)
├─ Executor (PS1)                          ├─ Executor (PS1)
└─ LIVE Router                             └─ LIVE Router
```

---

## 🔴 FASE 1 — TEST SUITES (HOJE 2h)

### **CHAT 1: test_pullback_recovery.Tests.ps1**

**Tests to write (TDD first)**:
- [ ] Test-PullbackDetected: primeiro pump 5x em 1-5 dias
- [ ] Test-SupportTested: preço toca suporte ±2%
- [ ] Test-VolumeRecovery: volume cresce após pullback
- [ ] Test-EntryZoneValid: entry acima prior high
- [ ] Test-RiskCalculation: SL no suporte, 2% loss
- [ ] Test-TargetCalculation: TP 30x entry (gem math)
- [ ] Test-LiquidityCheck: $500 entry em $50K volume
- [ ] Test-ConfidenceScore: 55-65% win rate threshold
- [ ] Test-RealDataPEPE: padrão em PEPE histórico
- [ ] Test-RealDataBONK: padrão em BONK histórico

**Expected**: 10 tests, 100% pass

---

### **CHAT 2: test_distribution_short.Tests.ps1**

**Tests to write (TDD first)**:
- [ ] Test-ATHRetesting: preço testa ATH 2-3x
- [ ] Test-RedVsGreen: red candles ≥ green tamanho
- [ ] Test-HighVolume: vol ≥ avg_20 nos últimos 3 bars
- [ ] Test-SupportIdentified: clear support level existe
- [ ] Test-EntryOnBreak: entry quando support quebra
- [ ] Test-StopCalculation: SL acima ATH +3%
- [ ] Test-TargetCalculation: TP -50% do ATH
- [ ] Test-TimingCritical: entry window 1-2 barras máx
- [ ] Test-RealDataBONK: padrão em BONK dump histórico
- [ ] Test-RealDataSKYAI: padrão em SKYAI reversal

**Expected**: 10 tests, 80% pass (timing é difícil)

---

## 🟠 FASE 2 — BACKTEST VALIDATION (AMANHÃ 4h)

### **CHAT 1: backtest/test_pullback_recovery_real.py**

```python
def test_pullback_recovery_pepe_2023_2025():
    """
    Input: PEPE histórico 2023-2025
    Hypothesis: Quando pullback testa support, profit em 7 dias?
    
    Metrics:
    - Win rate: expect 55-65%
    - Avg R: expect 7.5R
    - Max DD: expect 5%
    - Sharpe: expect >2.0
    - PBO: expect <0.50 (not overfit)
    """
    pass

def test_pullback_recovery_bonk_2024_2025():
    """Mesmo test em BONK"""
    pass

def test_pullback_recovery_skyai_2024_2025():
    """Mesmo test em SKYAI"""
    pass
```

**Expected output**: `journal/pullback_recovery_backtest_2026_06_09.json`
```json
{
  "pepe": {
    "total_samples": 127,
    "win_rate": 0.58,
    "avg_r_multiple": 7.8,
    "max_dd_pct": 4.2,
    "sharpe": 2.14,
    "pbo": 0.38,
    "verdict": "PASS ✅"
  }
}
```

---

### **CHAT 2: backtest/test_distribution_short_real.py**

```python
def test_distribution_short_bonk_2024_2025():
    """
    Input: BONK FASE 4-5 histórico
    Hypothesis: Quando red=green + support testa, short funciona?
    
    Metrics:
    - Win rate: expect 45-50%
    - Avg R: expect 2.0R
    - Max DD: expect 8%
    - Timing accuracy: expect >70% entry hit
    """
    pass

def test_distribution_short_pepe_2023_2025():
    """Mesmo test em PEPE dumps"""
    pass

def test_distribution_short_skyai_2024():
    """Mesmo test em SKYAI reversal"""
    pass
```

**Expected output**: `journal/distribution_short_backtest_2026_06_09.json`

---

## 🟢 FASE 3 — IMPLEMENTATION + LIVE (PRÓXIMOS 3 DIAS 8h)

### **CHAT 1: lib_pullback_recovery.ps1**

```powershell
function Detect-PullbackRecoveryPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][array] $Candles  # 1h timeframe, últimas 100
    )
    
    # TDD: testes validam cada step
    # 1. Detecta pump_1 (5x em 1-5 dias)
    # 2. Detecta pullback (testa suporte)
    # 3. Detecta volume recovery
    # 4. Calcula confidence
    
    return @{
        detected = $true
        phase = "PULLBACK"
        confidence = 0.72
        entry_price = 0.000013
        stop_loss = 0.000011
        target = 0.000025
        r_multiple = 30
        position_size_pct = 0.003  # 0.3%
    }
}
```

---

### **CHAT 2: lib_distribution_short.ps1**

```powershell
function Detect-DistributionShortPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][array] $Candles  # 1h timeframe, últimas 50
    )
    
    # TDD: testes validam cada step
    # 1. Valida ATH retest pattern
    # 2. Valida red=green volume
    # 3. Identifica support level
    # 4. Calcula entry/stop/target
    
    return @{
        detected = $true
        phase = "DISTRIBUTION"
        confidence = 0.65
        entry_type = "SUPPORT_BREAK"
        entry_price = 0.000012
        stop_loss = 0.000015
        target = 0.0000060
        r_multiple = 10
        position_size_pct = 0.002  # 0.2%
        timing_critical = $true  # 1-2 barras window
    }
}
```

---

## ✅ DEFINIÇÃO DE DONE

### **Por estratégia**:

**PULL_BACK_RECOVERY**:
- [ ] 10 Pester tests, 100% pass
- [ ] Backtest 3 coins (PEPE/BONK/SKYAI), win_rate ≥55%
- [ ] Executor function com TDD
- [ ] LIVE router integrado
- [ ] Primeiro trade real com Telegram alert

**DISTRIBUTION_SHORT**:
- [ ] 10 Pester tests, 80%+ pass
- [ ] Backtest 3 coins, win_rate ≥45%
- [ ] Executor function com TDD
- [ ] LIVE router integrado (cautela, 30% capital)
- [ ] Primeiro trade real com Telegram alert + timeout 5 dias

---

## 📊 MÉTRICAS DE SUCESSO

| Métrica | PULL_BACK | DISTRIBUTION_SHORT |
|---------|-----------|-------------------|
| Test Pass Rate | 100% | 80%+ |
| Backtest Win Rate | ≥55% | ≥45% |
| Backtest Expectancy | ≥7.5R | ≥2.0R |
| Backtest Sharpe | ≥2.0 | ≥1.0 |
| PBO (not overfit) | ≤0.50 | ≤0.50 |
| Real Trades/Month | 5-8 | 3-5 |
| Expected Monthly Gain | +15-20% | +3-5% |

---

## 🛠️ FERRAMENTAS USADAS

```
PowerShell 5.1 ← Tests + Executor
Pester 3.4 ← Test framework (TDD)
Python 3.9 ← Backtest, análise histórica
CoinEx API ← Dados real-time
JSON ← Journal/output
GitHub Actions ← Automation
```

---

## 📁 ARQUIVOS A CRIAR

```
tests/
├── test_pullback_recovery.Tests.ps1        (10 Pester tests)
├── test_distribution_short.Tests.ps1       (10 Pester tests)

backtest/
├── test_pullback_recovery_real.py          (3 coin backtest)
├── test_distribution_short_real.py         (3 coin backtest)

agents/
├── lib_gem_discovery.ps1                   (scanner)
├── lib_pullback_recovery.ps1               (pattern detection)
├── lib_distribution_short.ps1              (pattern detection)
├── lib_gem_router.ps1                      (execution router)

journal/
├── pullback_recovery_backtest_2026_06_09.json
├── distribution_short_backtest_2026_06_09.json
├── gem_discovery_live.jsonl                (real-time signals)
```

---

## ⏱️ TIMELINE

| Quando | O Quê | Quem |
|--------|-------|------|
| **Hoje (2h)** | Escrever 20 Pester tests | CHAT 1 + CHAT 2 |
| **Amanhã (4h)** | Rodar backtest PEPE/BONK/SKYAI | CHAT 1 + CHAT 2 |
| **Dia 3 (3h)** | Implementar executors | CHAT 1 + CHAT 2 |
| **Dia 3 (1h)** | Merge routers + ativar LIVE | CHAT 1 + CHAT 2 |
| **Dia 4 (monitor)** | Primeiros trades reais | Manual |

---

**Status**: 🟢 READY TO START  
**Approver**: User  
**Risk Level**: CONTROLLED (TDD + backtest first, LIVE second)


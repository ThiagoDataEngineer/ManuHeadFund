# Pilar 1 — Trailing Adaptativo: Layers 2-5 Roadmap

**Status:** Layer 1 ✅ COMPLETA (37/37 testes)  
**Próximas:** Layer 2-5 (TDD workflow, ~3-4 semanas total)  
**Validação:** Paper trades 48h + live capital $2.76K

---

## 🎯 Visão Geral (5 Camadas)

| Layer | Nome | Impacto | Timeline | Dependência |
|-------|------|--------|----------|------------|
| **1** | ATR-Dinâmico + Regime-Aware | ✅ DONE (22/22) | ✅ 2026-05-25 | Nenhuma |
| **2** | Mentor Reflection (6h checkpoint) | +5-8pp win% | 2-3 dias | Layer 1 |
| **3** | Kelly Fractional Sizing | +10-20% ROI | 2-3 dias | Layer 1 |
| **4** | Tori Proximity (anticipatory) | +2-5pp | 3-5 dias | Layer 1 |
| **5** | Moon Bag (50/50 harvest+upside) | +3-7% Sharpe | 2-3 dias | Layer 1 |

**Total Impact (all layers):** +12-25% win rate, +15-30% Sharpe ratio

---

## 📋 Layer 2: Mentor Reflection (6h Checkpoint)

### Objetivo
Mentor agent revisa posições **mid-life (6h após entry)** para detectar:
- Early warning signs (breakeven atingido antes de 6h?)
- Regime shift (mercado mudou de BULL → BEAR?)
- Tight stop opportunity (preço proxímo ao stop?)

### Design

```
Loop:
  a) Nova posição aberta → registra timestamp
  b) A cada 6h: chama Mentor-Review
  c) Mentor analisa:
     - Tempo em posição vs histórico
     - Regime mudou?
     - Price vs entry/stop/target
  d) Decisão: HOLD | CLOSE_NOW | TIGHTEN_STOP
  e) Se TIGHTEN_STOP: move stop mais perto (esperando reversal)
```

### TDD Test Cases

```powershell
Describe "Mentor-Review @ 6h checkpoint" {
    Context "Early warning detection" {
        It "should flag if BE reached before 6h (panic sell)" {
            # Posição: entry 100, stop 95, target 130
            # A 3h: preço 100 (breakeven)
            # Mentor: "potencial false breakout, consider close"
        }
        
        It "should flag if regime shifted BULL→BEAR" {
            # Entry em BULL_STRONG, 6h depois BEAR_STRONG
            # Mentor: "regime shift, tighten stop to 98"
        }
        
        It "should recommend HOLD if on-track" {
            # Entry 100, 6h depois preço 110 (10% gain)
            # Mentor: "on track, hold"
        }
    }
    
    Context "Stop tightening logic" {
        It "should calculate tight stop 50% closer to entry" {
            # Original: entry 100, stop 95 (5% floor)
            # Tight: stop 97.5 (2.5% floor, 50% closer)
        }
    }
}
```

### Implementação Sketch

```powershell
# agents/mentor_review.ps1

function Get-MentorReview {
    param(
        [PSCustomObject]$Position,
        [string]$Regime
    )
    
    $timeSinceEntry = (Get-Date) - [DateTime]$Position.enteredAt
    $priceProgress = ($CurrentPrice - $Position.entry) / ($Position.target - $Position.entry)
    
    # Early warning: Breakeven atingido muito cedo?
    if ($timeSinceEntry.TotalHours -lt 3 -and $priceProgress -ge 0) {
        return @{
            action = "CLOSE_NOW"
            reason = "false_breakout_too_early"
            confidence = 0.7
        }
    }
    
    # Regime shift?
    if ($Position.regime -ne $Regime -and $Regime -match "BEAR|CAPITULATION") {
        return @{
            action = "TIGHTEN_STOP"
            newStop = $Position.stop + ($Position.stop - $Position.entry) * 0.5
            reason = "regime_shift_bearish"
            confidence = 0.8
        }
    }
    
    return @{
        action = "HOLD"
        reason = "on_track"
        confidence = 0.9
    }
}
```

### Métricas Esperadas
- ✅ +5-8pp win rate (evita false breakouts)
- ✅ -3pp drawdown (tightening stops)
- ✅ ~0.5 Mentor reviews por trade (48h média)

### Timeline
- **Sprint 1:** TDD + design (1 dia)
- **Sprint 2:** Implementation (1 dia)
- **Sprint 3:** Integration + paper (1 dia)

---

## 💰 Layer 3: Kelly Fractional Sizing

### Objetivo
Ajustar tamanho de posição dinamicamente baseado em:
- **Win rate histórico** (último 30 trades)
- **RR ratio** (risco/retorno)
- **Kelly formula:** `kelly% = (b*p - q) / b` onde b=RR, p=win%, q=loss%

### Design

```
Exemplo:
  - Last 30 trades: 20 wins, 10 losses (67% win rate)
  - RR = 3 (risco $100 para ganhar $300)
  - Kelly: (3 * 0.67 - 0.33) / 3 = 0.61 = 61% bankroll
  - Fractional (conservative): 0.61 * 0.25 = 15% bankroll
  
  Capital: $2760
  Position size: $2760 * 0.15 = $414
```

### TDD Test Cases

```powershell
Describe "Kelly Fractional Sizing" {
    Context "Win rate calculation" {
        It "should calculate win% from last 30 closed trades" {
            # 20 wins, 10 losses → 66.67%
        }
        
        It "should handle <30 trades gracefully (use bootstrap)" {
            # Only 10 closed trades: assume 50% (conservative)
        }
    }
    
    Context "Kelly formula" {
        It "should apply Kelly with 67% WR and RR=3" {
            # kelly = (3*0.67-0.33)/3 = 0.61
            # fractional(0.61, 0.25) = 0.1525 = 15.25%
        }
        
        It "should cap maximum to 25% (max fractional)" {
            # Even with 90% WR, never exceed 25%
        }
        
        It "should floor minimum to 1% (min fractional)" {
            # Even with 20% WR, never below 1%
        }
    }
    
    Context "Impact on profitability" {
        It "should increase position size in winning streaks" {
            # After +5 trades in a row: size increases
        }
        
        It "should decrease after losing streak" {
            # After -3 trades: size decreases
        }
    }
}
```

### Implementação Sketch

```powershell
# agents/lib_kelly_sizing.ps1

function Get-KellySizing {
    param([double]$Capital, [double]$RRRatio, [double]$FractionalFactor = 0.25)
    
    $closedTrades = @(Get-ClosedTrades -Last 30)
    
    if ($closedTrades.Count -eq 0) {
        # Bootstrap: assume 50% WR
        $winRate = 0.5
    } else {
        $wins = @($closedTrades | Where-Object { $_.pnl -gt 0 }).Count
        $winRate = $wins / $closedTrades.Count
    }
    
    # Kelly formula
    $kelly = ($RRRatio * $winRate - (1 - $winRate)) / $RRRatio
    
    # Fractional (conservative)
    $fractional = [Math]::Max(0.01, [Math]::Min(0.25, $kelly * $FractionalFactor))
    
    return [PSCustomObject]@{
        winRate = [Math]::Round($winRate * 100, 2)
        kelly = [Math]::Round($kelly * 100, 2)
        fractional = [Math]::Round($fractional * 100, 2)
        positionSize = [Math]::Round($Capital * $fractional, 2)
    }
}
```

### Métricas Esperadas
- ✅ +10-20% ROI (vs fixed sizing)
- ✅ -20-30% Sharpe drawdown (mais consistente)
- ✅ 2-3x menos blowups (capital preservation)

### Timeline
- **Sprint 1:** TDD + formula (0.5 dia)
- **Sprint 2:** Integration (1 dia)
- **Sprint 3:** Paper validation (1 dia)

---

## 🎯 Layer 4: Tori Proximity (Anticipatory)

### Objetivo
Integrar **Tori bounce strategy** com trailing adaptativo:
- Detecta **proximity a trendline** (-3% a +5%)
- **Anticipatory stops:** move stop antes de Tori touch (não depois)
- Reward: +5% target vs 2% legacy

### Design

```
Tori Phase:
  1. Scan: encontra trendline com 3+ touches
  2. Proximity: preço -3% a +5% da linha
  3. Anticipatory: quando < -1% distância:
     - Tighten stop 50% (prepare for bounce)
     - Raise target +2% (bounce reward)
     - Aumentar weight no Orchestrator
  4. Execute: se toca + sinal de bounce, aciona
```

### TDD Test Cases

```powershell
Describe "Tori Proximity Anticipatory" {
    Context "Trendline detection" {
        It "should identify valid trendline (3+ touches, slope 5-35°)" {
            # BNB: 3 touches em 20 dias, slope 8°
        }
    }
    
    Context "Proximity calculation" {
        It "should calculate distance to trendline (-3% to +5%)" {
            # Trendline: 50000
            # Price: 49500 → distance -1%
        }
        
        It "should trigger anticipatory when < -1% distance" {
            # Distance -1.5% → tighten stop, raise target
        }
    }
    
    Context "Stop tightening logic" {
        It "should move stop 50% closer on anticipatory trigger" {
            # Original stop: entry - 2%
            # Anticipatory: entry - 1% (50% tighter)
        }
    }
    
    Context "Target adjustment" {
        It "should raise target +2% on Tori entry" {
            # Original target: entry + 5%
            # Tori target: entry + 7%
        }
    }
}
```

### Implementação Sketch

```powershell
# agents/lib_tori_anticipatory.ps1

function Get-ToriAnticipatory {
    param([PSCustomObject]$Position, [double]$ToriTrendlinePrice)
    
    $distance = ($Position.current - $ToriTrendlinePrice) / $ToriTrendlinePrice * 100
    
    if ($distance -gt 5 -or $distance -lt -3) {
        return $null  # Out of proximity
    }
    
    if ($distance -lt -1) {
        # Anticipatory trigger
        return @{
            action = "ANTICIPATORY"
            newStop = $Position.stop + ($Position.stop - $Position.entry) * 0.5
            newTarget = $Position.target * 1.02
            confidence = 0.75
        }
    }
    
    return @{ action = "MONITOR" }
}
```

### Métricas Esperadas
- ✅ +2-5pp win rate (anticipatory capture)
- ✅ +4-8% avg profit (higher target)
- ✅ ~0.3 Tori trades/day (selective)

### Timeline
- **Sprint 1:** TDD + proximity calc (1 dia)
- **Sprint 2:** Integration (1-2 dias)
- **Sprint 3:** Paper validation (2 dias)

---

## 🌙 Layer 5: Moon Bag (50/50 Harvest + Upside)

### Objetivo
Capturar **moon moves** enquanto colhe lucros:
- Divide posição: 50% harvest (close at +5%), 50% moon bag (unlimited)
- Moon bag: zero stop até 30% target OR 20 dias
- Reward: +3-7% Sharpe (consistency + upside)

### Design

```
Split Strategy:
  1. Entry: $1000 posição
  2. Harvest (50%): $500 → fecha em +5% (take profits)
  3. Moon Bag (50%): $500 → trailing stop extremamente solto:
     - Stop: entry - 10% (MUITO fundo)
     - Target: entry + 30% (capturar moonshot)
     - Duration: até 30% target OU 20 dias
  4. Reward: capturou +5% de certeza + potencial +30% upside
```

### TDD Test Cases

```powershell
Describe "Moon Bag Split Strategy" {
    Context "Position splitting" {
        It "should split 50/50 at entry" {
            # Entry: $1000 → $500 harvest + $500 moon
        }
    }
    
    Context "Harvest leg" {
        It "should close harvest leg at +5% automatically" {
            # Entry 100, close at 105
        }
        
        It "should lock +5% profit regardless of market" {
            # Even if market tanks, harvest secured
        }
    }
    
    Context "Moon bag leg" {
        It "should set ultra-loose stop at entry -10%" {
            # Entry 100, stop 90 (vs typical 98-99)
        }
        
        It "should set moon target at entry +30%" {
            # Entry 100, target 130
        }
        
        It "should trail normally until 20 days" {
            # After 20 days: force close moon bag
        }
    }
    
    Context "Moon move capture" {
        It "should capture +30% moon move" {
            # Entry 100, peak 130 → closed at 130
            # Total: +5% (harvest) + +30% (moon) = profit!
        }
        
        It "should preserve harvest if moon hits stop" {
            # Entry 100, harvest closed at 105 (+5%)
            # Moon crashes to 90 (stop hit)
            # Total: +5% (harvest saved) - 5% (moon loss) = breakeven
        }
    }
}
```

### Implementação Sketch

```powershell
# agents/lib_moon_bag.ps1

function Split-MoonBag {
    param([PSCustomObject]$Position, [double]$Capital)
    
    $harvestSize = $Capital * 0.5
    $moonSize = $Capital * 0.5
    
    return @{
        harvest = @{
            size = $harvestSize
            entry = $Position.entry
            target = $Position.entry * 1.05  # +5%
            stop = $Position.entry * 0.98
            duration = "until_target"
        }
        moon = @{
            size = $moonSize
            entry = $Position.entry
            target = $Position.entry * 1.30  # +30%
            stop = $Position.entry * 0.90  # -10%
            duration = "until_target_or_20days"
            trailingStopEnabled = $true
        }
    }
}
```

### Métricas Esperadas
- ✅ +3-7% Sharpe ratio (consistency + upside)
- ✅ +2-4% win rate (harvest garante wins)
- ✅ 100% harvest win rate (sempre +5%)
- ✅ ~30% moon win rate (quando captura moonshot)
- ✅ Blowup reduzido em 50% (harvest protege)

### Timeline
- **Sprint 1:** TDD + split logic (1 dia)
- **Sprint 2:** Integration (1 dia)
- **Sprint 3:** Paper validation (1-2 dias)

---

## 📅 Master Timeline (4 semanas)

```
Week 1:
  Mon-Tue: Layer 2 (Mentor) — TDD + impl
  Wed:     Layer 2 paper validation (24h)
  
Week 2:
  Mon-Tue: Layer 3 (Kelly) — TDD + impl
  Wed:     Layer 3 paper validation (24h)
  
Week 3:
  Mon-Wed: Layer 4 (Tori) — TDD + impl
  Thu-Fri: Layer 4 paper validation (48h)
  
Week 4:
  Mon-Tue: Layer 5 (Moon) — TDD + impl
  Wed:     Layer 5 paper validation (24h)
  Thu-Fri: Integration testing (all 5 layers together)
```

---

## 🧪 Paper Trade Validation (Each Layer)

### Layer 2 (Mentor)
```bash
./scripts/scan_master.ps1 -SkipGem -SkipOrchestrator -Layers 1,2
# Expect: +3-5pp win rate vs Layer 1 alone
# Duration: 24h (enough for 5-10 mentor reviews)
```

### Layer 3 (Kelly)
```bash
./scripts/scan_master.ps1 -SkipGem -SkipOrchestrator -Layers 1,2,3
# Expect: +5-10% ROI vs fixed sizing
# Duration: 24h (3-5 sized trades for statistical power)
```

### Layer 4 (Tori)
```bash
./scripts/scan_master.ps1 -Layers 1,2,3,4 -ToriEnabled
# Expect: +2-5pp win rate on Tori signals
# Duration: 48h (need enough Tori setups to validate)
```

### Layer 5 (Moon)
```bash
./scripts/scan_master.ps1 -Layers 1,2,3,4,5 -MoonBagEnabled
# Expect: +3-7% Sharpe, 100% harvest win rate
# Duration: 48h (need moon bag to survive for duration test)
```

### Integration (All 5)
```bash
./scripts/scan_master.ps1 -Layers 1,2,3,4,5 -MoonBagEnabled -ToriEnabled
# Expect: Combined +12-25% win rate improvement
# Duration: 7 days (full cycle for all features)
```

---

## 📊 Metrics Collection (Each Layer)

```powershell
# Use collect_paper_metrics.ps1

.\scripts\collect_paper_metrics.ps1 `
  -StartTime "2026-05-25 00:00" `
  -EndTime "2026-05-27 00:00" `
  -OutputDir ".\metrics\layer_2_mentor" `
  -Verbose

# Output: metrics/layer_2_mentor/paper_metrics_20260525_HHMM.json
# Contains: 
#   - trailing stats (stops updated by regime)
#   - performance stats (win rate, PnL, stops/targets)
#   - phase distribution
#   - per-market breakdown
```

---

## 🎯 Success Criteria

### Layer 2 (Mentor): ✅ SUCCESS if
- [ ] Win rate +3-5pp vs Layer 1 alone
- [ ] Mentor reviews 0.3-0.5 per trade (not too noisy)
- [ ] 0 regressions on Layer 1

### Layer 3 (Kelly): ✅ SUCCESS if
- [ ] ROI +5-10% vs fixed sizing
- [ ] Position sizing 10-25% of capital (reasonable)
- [ ] No overnight blowups

### Layer 4 (Tori): ✅ SUCCESS if
- [ ] Win rate +2-5pp on Tori signals
- [ ] Anticipatory stops avoid 20%+ false breaks
- [ ] ~0.3 Tori trades/day (not spammy)

### Layer 5 (Moon): ✅ SUCCESS if
- [ ] Harvest: 100% win rate on +5% target
- [ ] Moon bag: 25-35% win rate on moon moves
- [ ] Sharpe +3-7% vs Layer 1

### Integration (All 5): ✅ SUCCESS if
- [ ] Combined +12-25% win rate
- [ ] Combined +15-30% Sharpe
- [ ] <5% drawdown increase
- [ ] All tests passing (37/37 + new tests)

---

## 🚀 Starting Point

**Today (2026-05-25):**
- ✅ Layer 1 complete, 37/37 tests GREEN
- ✅ Integration in scan_master.ps1
- ✅ Paper trades 48h running (validating Layer 1 metrics)

**In 5 days (2026-05-30):**
- Should have Layer 1 validated (metrics collected, analysis complete)
- Ready to start Layer 2 TDD

**In 30 days (2026-06-24):**
- All 5 layers implemented, tested, validated in paper
- Ready for LIVE trades on real capital ($2.76K)

---

## 📝 Notes

- **TDD-first approach:** Each layer gets tests BEFORE implementation
- **Paper validates:** 24-48h paper trades between layers (catch issues early)
- **No live until:** All 5 layers + integrated test (7 days paper minimum)
- **Metrics logged:** Every trade decision + outcome → layer effectiveness audit trail
- **Fallback:** If any layer degrades performance, can disable via flags

---

**Next Step:** Start Layer 2 (Mentor) after Layer 1 paper validation completes (2026-05-27).


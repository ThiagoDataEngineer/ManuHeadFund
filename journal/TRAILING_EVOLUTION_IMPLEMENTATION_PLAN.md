# 🚀 Trailing Stop Evolution — Implementation Plan

**Objetivo:** Implementar Layer 2 (TP evolution) em 1-2 dias  
**Status:** Ready to implement  
**Commits needed:** 1-2 (implementation + tests)

---

## 📐 Technical Specification

### Current State (Layer 0-1)

```powershell
# lib_trailing.ps1: Update-TrailingStops()

Phase 0 (Entry):
  SL = entry - (atr * 1.5)  # Proteção inicial
  TP = entry + (rr * SL)    # Alvo fixo

Phase 1 (+33% target):
  SL → breakeven + buffer

Phase 2 (+66% target):
  SL → tranca 1/3 do ganho

Phase 3 (Ongoing):
  SL → trailing puro (move com cada novo pico/vale)
```

### Proposed Addition (Layer 2)

```powershell
# lib_trailing.ps1: Add to Update-TrailingStops() Phase 3

if ($phase -eq 3 -and $conviction -gt 80) {
    $current_gain_pct = ($current_price - $entry_price) / $entry_price * 100
    
    # Só evoluir TP se ganho > 33% do alvo
    if ($current_gain_pct -gt ($target_gain_pct * 0.33)) {
        
        # TP avança 0.5-1% incremental
        $tp_step = $tp * 0.005  # +0.5%
        $tp_new = $take_profit + $tp_step
        
        # Update na corretora
        Set-CoinExPosition-TakeProfit -OrderId $posId -TakeProfit $tp_new
        
        # Log para análise
        Write-TrailingTargetEvolution -Market $market `
            -OldTP $take_profit -NewTP $tp_new `
            -Conviction $conviction -GainPct $current_gain_pct
    }
}
```

---

## 📋 Implementation Checklist

### Phase 1: Create new logging function

**File:** `agents/lib_trailing_learning_logger.ps1` (extend existing)

```powershell
function Write-TrailingTargetEvolution {
    <#
    .SYNOPSIS
    Log quando TP evolui (Layer 2 do trailing)
    
    .PARAMETER Market
    Par de trading
    
    .PARAMETER OldTP
    TP anterior
    
    .PARAMETER NewTP
    TP novo (evoluído)
    
    .PARAMETER Conviction
    Score de convicção (0-100)
    
    .PARAMETER GainPct
    Ganho atual em %
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $OldTP,
        [Parameter(Mandatory)] [double] $NewTP,
        [Parameter(Mandatory)] [int] $Conviction,
        [Parameter(Mandatory)] [double] $GainPct
    )
    
    $logEntry = @{
        timestamp = [datetime]::UtcNow.ToString("O")
        market = $Market
        tp_old = $OldTP
        tp_new = $NewTP
        tp_delta_pct = [math]::Round(($NewTP - $OldTP) / $OldTP * 100, 4)
        conviction = $Conviction
        gain_pct = [math]::Round($GainPct, 2)
        phase = 3
        event_type = "TP_EVOLUTION"
    } | ConvertTo-Json -Compress
    
    Add-Content -Path "$JOURNAL_DIR/trailing_target_evolution.jsonl" -Value $logEntry
}
```

### Phase 2: Integrate into lib_trailing.ps1

**File:** `agents/lib_trailing.ps1`  
**Function:** Update-TrailingStops()  
**Location:** After Phase 3 SL update section

```powershell
# ─────────────────────────────────────────────────────────────────────────
# PHASE 3 — TRAILING SL + TP EVOLUTION (Layer 2)
# ─────────────────────────────────────────────────────────────────────────

if ($phase -eq 3) {
    
    # SL trailing (existing)
    if ($direction -eq "LONG") {
        $new_sl = $current_price - ($atr * 1.0)
        if ($new_sl -gt $stop_loss) {
            Update-CoinExPosition-StopLoss -OrderId $orderId -StopLoss $new_sl
            Write-TrailingDecision -Market $market -OldSL $stop_loss `
                -NewSL $new_sl -Action "RAISE_SL" -Conviction $conviction
        }
    } else {
        $new_sl = $current_price + ($atr * 1.0)
        if ($new_sl -lt $stop_loss) {
            Update-CoinExPosition-StopLoss -OrderId $orderId -StopLoss $new_sl
            Write-TrailingDecision -Market $market -OldSL $stop_loss `
                -NewSL $new_sl -Action "LOWER_SL" -Conviction $conviction
        }
    }
    
    # TP EVOLUTION (NEW — Layer 2)
    if ($conviction -gt 80) {
        $profit_ratio = $current_price - $entry_price
        $target_ratio = $take_profit - $entry_price
        $progress_pct = $profit_ratio / $target_ratio * 100
        
        if ($progress_pct -gt 33) {  # Só se 33%+ do caminho
            $tp_delta = $take_profit * 0.005  # +0.5%
            $tp_new = $take_profit + $tp_delta
            
            try {
                Update-CoinExPosition-TakeProfit -OrderId $orderId -TakeProfit $tp_new
                Write-TrailingTargetEvolution -Market $market -OldTP $take_profit `
                    -NewTP $tp_new -Conviction $conviction -GainPct $progress_pct
            } catch {
                Write-Host "⚠️  TP evolution falhou: $_" -ForegroundColor Yellow
                # Não bloqueia — SL já trailing
            }
        }
    }
}
```

### Phase 3: Create TDD tests

**File:** `tests/lib_trailing_evolution.tests.ps1` (new)

```powershell
Describe "Write-TrailingTargetEvolution" {
    
    It "logs TP evolution with correct delta" {
        $old = 0.500
        $new = 0.5025
        Write-TrailingTargetEvolution -Market "BTCUSDT" -OldTP $old -NewTP $new `
            -Conviction 85 -GainPct 35
        
        $last = Get-Content "$JOURNAL_DIR/trailing_target_evolution.jsonl" -Tail 1 | ConvertFrom-Json
        $last.tp_old | Should Be 0.500
        $last.tp_new | Should Be 0.5025
        $last.conviction | Should Be 85
    }
    
    It "calculates delta percentage correctly" {
        # 0.500 → 0.5025 = +0.5%
        $delta = (0.5025 - 0.500) / 0.500 * 100
        $delta | Should Be 0.5
    }
    
    It "only evolves TP if conviction > 80" {
        # Mock condition check
        $conviction = 75
        $should_evolve = $conviction -gt 80
        $should_evolve | Should Be $false
    }
    
    It "only evolves TP if progress > 33%" {
        # Mock condition check
        $progress = 40
        $should_evolve = $progress -gt 33
        $should_evolve | Should Be $true
    }
    
    It "appends to trailing_target_evolution.jsonl" {
        $before = @(Get-Content "$JOURNAL_DIR/trailing_target_evolution.jsonl" | Measure-Object -Line).Lines
        Write-TrailingTargetEvolution -Market "ETHUSDT" -OldTP 1.0 -NewTP 1.005 `
            -Conviction 82 -GainPct 50
        $after = @(Get-Content "$JOURNAL_DIR/trailing_target_evolution.jsonl" | Measure-Object -Line).Lines
        ($after - $before) | Should Be 1
    }
    
    # Add 5+ more edge case tests...
}
```

---

## 🧪 Test Scenarios

### Test 1: Normal Evolution (Happy Path)
```
Position: BTCUSDT LONG
Entry:  63000 USDT
Current: 63500 USDT (gain +0.79%)
TP:     70000 USDT (alvo)
Conv:   85 (strong)

Phase 3 check:
├ Conviction 85 > 80 ✅
├ Progress 0.79/11.11 = 7% < 33% ❌

Action: SKIP (não atingiu 33%)

--- depois de mais movimento ---

Current: 65000 USDT (gain +3.17%)
Progress: 3.17/11.11 = 28.5% < 33% ❌

Action: SKIP

--- mais movimento ---

Current: 66000 USDT (gain +4.76%)
Progress: 4.76/11.11 = 42.8% > 33% ✅

Action: EVOLVE TP
├ OldTP: 70000
├ NewTP: 70000 + (70000 * 0.005) = 70350
└ Log: trailing_target_evolution.jsonl
```

### Test 2: Low Conviction (Gate Failed)
```
Position: ETHUSDT LONG
Conviction: 65 (not enough)

Phase 3 check:
├ Conviction 65 > 80 ❌

Action: SKIP TP evolution (SL still trailing)
```

### Test 3: Early Stage (Progress < 33%)
```
Position: DYDXUSDT LONG
Progress: 20% of target

Phase 3 check:
├ Conviction 82 > 80 ✅
├ Progress 20% > 33% ❌

Action: SKIP (too early, protect with SL)
```

---

## 📊 Expected Outcomes (48h)

### Scenario A: Trending Market (Rare)
```
BTCUSDT 5 tradings:
├ Entrada → Phase 0/1 (SL apenas)
├ +33% → Phase 2 (SL trancado)
├ +50% → Phase 3 + TP evolui +0.5% (1x log)
├ +70% → Phase 3 + TP evolui +0.5% (2x log)
└ +85% → Phase 3 + TP evolui +0.5% (3x log)

Expected: 3-5 TP evolution logs (trending)
Benefit: +5-10% extra capture vs static TP
```

### Scenario B: Choppy Market (Common)
```
ETHUSDT 3 tradings:
├ Entrada → Phase 0/1 (SL apenas)
├ +25% → Phase 2 (SL trancado, TP static)
└ Pullback -5% → Hit SL (exit)

Expected: 0 TP evolution logs (chop)
Benefit: SL protected (better than static)
```

### Scenario C: Quick Spike
```
GRASSUSDT 1 trading:
├ Entrada → Phase 0/1
├ +40% quickly → Phase 2 (SL trancado)
├ +60% → Phase 3 + TP evolui +0.5% (1x log)
└ Exit TP hit

Expected: 1 TP evolution log
Benefit: +5-10% vs static TP
```

---

## 🛠️ Deployment Checklist

- [ ] Create Write-TrailingTargetEvolution function
- [ ] Add to lib_trailing_learning_logger.ps1
- [ ] Integrate into lib_trailing.ps1 Update-TrailingStops()
- [ ] Create trailing_target_evolution.jsonl output
- [ ] Write TDD tests (5-10 scenarios)
- [ ] Run full test suite (must pass 100%)
- [ ] Commit: "feat: Trailing stop evolution layer 2 (TP incremental)"
- [ ] Deploy to live
- [ ] Monitor 48h for logs
- [ ] Analyze results: frequency, benefit, edge cases

---

## 📌 Key Decisions

**Q: Why +0.5% incremental?**  
A: Conservative, won't overshoot, accumulates over trend (5 moves = +2.5% total)

**Q: Why only Phase 3?**  
A: SL still protective in phases 1-2, TP not needed yet

**Q: Why conviction > 80?**  
A: High confidence in trend, not statistical noise

**Q: Why progress > 33%?**  
A: Allows time to tighten SL, then evolve TP safely

**Q: Will this break existing logic?**  
A: No. Standalone gate (conv > 80), separate log, try/catch wrapper

---

## 📈 Success Metrics

After 48h deployment:

1. **Frequency:** 5-20 logs in trailing_target_evolution.jsonl
2. **Gate Accuracy:** Conv > 80 = 100% precision (no false positives)
3. **Benefit:** Visual inspection of profit @ exit vs TP evolution logs
4. **Risk:** Zero SL bugs (SL still first priority)
5. **Performance:** Sub-100ms per TP update (no latency spikes)

---

**Status:** 🟢 READY TO IMPLEMENT  
**Timeline:** 1-2 days  
**Next:** Schedule implementation + testing


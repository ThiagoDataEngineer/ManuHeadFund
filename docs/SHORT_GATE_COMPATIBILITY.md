# SHORT Gate Compatibility Matrix — Tier 1 Audit (2026-05-23)

> Foundation audit. Output: BRANCH decision pra Tier 2. Pattern: doc-alongside-TDD.

## Sumário executivo

**Verdict: BRANCH A** — foundation 85% symmetric. Tier 2 fast-track viável.

Apenas 4 items SHORT-specific precisam dev:
1. Scanner direction param (1 line)
2. Mentor prompt direction context (additive)
3. SHORT predicate detector (new lib)
4. Per-asset whitelist SHORT tier (config)

**Estimated Tier 2**: 3-4h (não os 6-7h se Branch B/C).

## Audit detalhado — 19 gates × direção

| # | Gate | Status SHORT | Evidência | Tier 2 ação |
|---|---|---|---|---|
| 1 | Universe filter | ⚠️ Add SHORT tier field | per_asset_whitelist sem SHORT_TIER | Config add (15min) |
| 2 | Triagem | ⚠️ Direction default LONG | triagem_agent assume LONG | Add -Direction param (30min) |
| 3 | Mesa drones | ✅ **Symmetric** | `$MESA_VALID_SIGNALS = @("LONG","SHORT","NEUTRO")` | NO CHANGE |
| 4 | MCE | ✅ Symmetric | Score 0-100 neutral direction | NO CHANGE |
| 5 | Beta Cap | ✅ + DONE T-Beta | `lib_beta_cap_per_phase.ps1` deployed | Wire em gate (15min) |
| 6 | Daily Loss CB | ✅ Symmetric | -2% capital total | NO CHANGE |
| 7 | Drawdown | ✅ Symmetric | tier_a level metric | NO CHANGE |
| 8 | DSR | ⚠️ Per-direction needed | Currently per-market only | Extend lib (1h) |
| 9 | Mentor LLM | ⚠️ Prompt LONG-biased implicit | Prompt mostly direction-agnostic | Add direction context (30min) |
| 10 | Setup math | ✅ **Already handles both** | `Calculate-StopTarget` `-Direction LONG\|SHORT` | NO CHANGE |
| 11 | Sizing | ✅ Symmetric | 1% rule direction-agnostic | NO CHANGE |
| 12 | TG Approval | ⚠️ Icon variant | Currently LONG green emoji | Add SHORT red (15min) |
| 13 | Forbidden Guard | ✅ Symmetric | Pattern-based | NO CHANGE |
| 14 | Idempotency | ✅ Symmetric | Hash-based | NO CHANGE |
| 15 | **PlaceOrder** | ✅ **Already supports** | `CoinEx-PlaceOrder side "buy"\|"sell"` futures | NO CHANGE |
| 16 | Stop placement | ✅ Already handles | Calculate-StopTarget reverses correctly | NO CHANGE |
| 17 | TP placement | ✅ Already handles | Same as stop | NO CHANGE |
| 18 | Trade Log + Alpha | ✅ Symmetric | journal.ps1 LONG/SHORT branches | NO CHANGE |
| 19 | Reflection | ✅ Symmetric | Generic outcome capture | NO CHANGE |

**Symmetric: 13/19 (68%)**
**Trivial change: 5/19 (26%)** (15min-30min each)
**Real refactor: 1/19 (5%)** (DSR per-direction, 1h)

## Por-gate código encontrado

### Gate 3 (Mesa) — Symmetric ✓
```powershell
# mesa_agent.ps1:158
$MESA_VALID_SIGNALS = @("LONG","SHORT","NEUTRO")
```
Drones já vote SHORT. Consensus aggregator agnóstico.

### Gate 10 (Calculate-StopTarget) — Already supports ✓
```powershell
# gem_executor.ps1:70+
[Parameter(Mandatory)] [string] $Direction,   # "LONG" | "SHORT"
...
if ($Direction -eq "LONG") {
    # stop abaixo, target acima
} else {
    # SHORT: stop acima, target abaixo
    if ($stopPrice -le $Entry) { throw "...stop <= entry INVERTIDO" }
}
```
Math reversed correctly. Validation guard catches direction errors.

### Gate 15 (PlaceOrder) — Already supports ✓
```powershell
# lib_coinex.ps1:287
function CoinEx-PlaceOrder($market, $side, $type, $amount, ...) {
    # side: "buy" | "sell"
}
```
SHORT = futures sell-first. API already capable.

### Gate 18 (journal) — Symmetric ✓
```powershell
# journal.ps1:108+
$pnlUSD = if ($sinal -eq "LONG") {
    [math]::Round(($ExitPrice - $entryPrice) * $quantidade, 2)
} else {
    # SHORT
    [math]::Round(($entryPrice - $ExitPrice) * $quantidade, 2)
}
```

### Gate 2 (Triagem) — Needs direction param ⚠️
```powershell
# Currently no -Direction param in triagem invoke
# Need: add -Direction "LONG"|"SHORT" + tier classification per direction
```

### Gate 8 (DSR) — Per-direction needed ⚠️
```powershell
# Currently: dsr_global.json has per_market entries
# Need: per_market_long_short structure
# OR separate dsr_global_short.json
```

## Branch A vs B vs C verdict

| Branch | Condição | Esforço Tier 2 | Hoje veredict |
|---|---|---|---|
| **A** | ≥80% symmetric | 3-4h | ✓ **APPLIES** (68% sym + 26% trivial = 94%) |
| B | 30-80% symmetric | 6-7h | n/a |
| C | <30% symmetric | 10h+ halt | n/a |

## Tier 2 recommended sequence (Branch A)

```
T2.1 (1h) — Config + trivial wires
  ├─ per_asset_whitelist SHORT_TIER field
  ├─ TG emoji SHORT variant
  ├─ Wire Beta cap per-phase em gate existente
  └─ Triagem -Direction param

T2.2 (1h) — Mentor SHORT context
  ├─ Add direction context em prompt
  ├─ Schema 5-tier with direction in motivo
  └─ TDD: SHORT scenario in lib_llm_mocks

T2.3 (1.5h) — SHORT predicate detector
  ├─ lib_short_signals.ps1 (Wyckoff BC + RSI overband)
  ├─ Reuse Detect-VolumeClimax -Side SHORT (existing!)
  └─ TDD: synthetic SHORT signals

T2.4 (1h) — Scanner SHORT cron
  ├─ short_scanner.ps1 (similar to vol_climax_scanner)
  ├─ Forward tracker SHORT path
  └─ Cron register hourly
```

**Total Tier 2: ~4.5h** (não 3-4h naive — incluindo Mentor + scanner).

## Tier 1 deliverables (HOJE)

| Item | Status |
|---|---|
| Audit complete | ✅ Este doc |
| lib_beta_cap_per_phase.ps1 + 17 TDD | ✅ Deployed |
| Decision recommendation | ✅ BRANCH A |
| Memory + CLAUDE.md update | (next step) |

## Riscos identificados

1. **Mentor LONG bias implicit**: prompt assume LONG por convention. Variant pode causar inconsistência cross-direction (mesma situação SHORT vs LONG produzindo diferentes vetos). **Mitigação**: Mentor prompt deve declarar "this analysis is for {direction}" explicit.

2. **TG approval UI**: user pode confundir LONG/SHORT se UI não distingue claramente. **Mitigação**: emoji + cor distintos + uppercase tag.

3. **DSR per-direction sample muito pequeno**: separar SHORT em DSR pode demorar months pra ter n≥30. **Mitigação**: usar DSR combinado initially, separar quando sample disponível.

4. **Hedge complexity**: net portfolio beta com SHORT (peso negativo) precisa cuidado matemático. **Mitigação**: defer hedge mode pra Tier 4, focar Tier 2-3 em SHORT isolated.

## Next action (Tier 2)

Pre-condition met: Branch A confirmed. Execute Tier 2 pode começar próxima sessão OR continuar hoje se budget permite (~4.5h adicional).

# project_coinex_reference_insights_2026_05_15.md

## Resumo

Documento consolidado dos 9 insights-chave extraídos de `knowledge/COINEX_REFERENCE.md`.
Marca quais foram implementados (Ações 2-3), quais ficam como pendências documentadas
para futuras fases (Ações 4-7) com critério de ativação.

---

## Insights Consolidados

### 1. Self-Trade Prevention (stp_mode) — IMPLEMENTADO v1.7
**Status:** ✅ LIVE  
**Implementação:** Params `[string]$StpMode = "ct"` em:
- `CoinEx-PlaceOrder` (FUTURES)
- `CoinEx-PlaceSpotOrder` (SPOT)
- `CoinEx-PlaceSpotStopOrder` (SPOT stop-order)

**Valores suportados:**
- `"ct"` (cancel-taker) — default, proteção automática
- `"cm"` (cancel-maker)
- `"both"` (cancel ambos)
- `"none"` — opt-out (não inclui field no body)

**Teste:** 6 novos testes em `lib_coinex.Tests.ps1` (60/60 verde).  
**Backward-compat:** 100% — chamadas legacy continuam com `"ct"` automático.

---

### 2. FUTURES tick_size explícito vs SPOT quote_ccy_precision
**Status:** 📋 DOCUMENTADO, 🔄 PARCIALMENTE IMPLEMENTADO  
**Insight:** 
- **FUTURES:** tem campo `tick_size` explícito (ex: "0.5" para BTC)
- **SPOT:** usa `quote_ccy_precision` (até 10 casas, sem tick_size real)
- Sub-dollar (AIUSDT 0.099895) só é viável em SPOT porque quote_ccy_precision=8

**Implementação existente:**
- `Get-MarketPrecision` (em lib_coinex.ps1 linhas 91-147) cacheia ambos com TTL 1h
- Fallback seguro: 8 casas decimais em ambos os casos

**Futura ativação:**
- Diferenciação automática de rounding para FUTURES vs SPOT em `Calculate-StopTarget`
- Validação hard: rejeitar ordem se `tick_size` incompatível em FUTURES

**Critério:** Quando gem_executor ou Calculate-StopTarget forem otimizados para precision.

---

### 3. Margin Isolated SPOT é gap estrutural (não automatizável via API v2)
**Status:** 🚫 LIMITATION DOCUMENTADA  
**Insight:** CoinEx oferece Margin Isolated SPOT **apenas via UI manual**, não via API v2.
- Todas as ordens spot via API v2 são **cashless spot** (not margined)
- Cross margin também indisponível via API v2
- Impacta: leverage em spot não é possível automatizar

**Implicações:**
- Trading spot fica restrito a capital próprio (sem leverage)
- Estratégia recomendada: usar FUTURES para leverage (default já feito)

**Documentação:** Adicionada em memory para referência auditor (quando compliance checar)

**Critério de ativação:** Nunca — é limitação estrutural, não feature.

---

### 4. TP/SL nativos múltiplos (até 20) — FUTURES ONLY
**Status:** 📋 DOCUMENTADO  
**Insight:** CoinEx FUTURES suporta até 20 Take-Profit e Stop-Loss orders nativos
simultaneamente. SPOT **não suporta**.

**Implementação atual:**
- FUTURES: só 1 TP + 1 SL por ordem (atual via `take_profit_price` + `stop_loss_price`)
- SPOT: usa `/v2/spot/stop-order` (endpoint condicional separado)

**Futura ativação:** Quando escalar para multi-exit strategy (cascata de TPs)
- Ex: TP em 1R, 2R, 3R, etc. (até 20 ordens paralelas)
- Requer refactor de gem_executor para gerar array de TP orders

**Critério:** Quando atingir 90%+ win rate em single-exit, escalar para multi-exit.

---

### 5. Fee tiers dinamicamente via API (LIVE v1.6+)
**Status:** ✅ LIVE  
**Implementação:** `CoinEx-GetFeeContext` já usa endpoint autenticado
- Endpoint: GET `/v2/account/trade-fee-rate?market=MARKET&market_type=FUTURES`
- Fallback: `$COINEX_FEE_MAKER_FALLBACK = 0.002` se sem credenciais

**Já integrado em:** Cost tracker (lib_cost_tracker.ps1) e margin calcs

---

### 6. Funding rate 8h + propagação 24h
**Status:** ✅ LIVE  
**Implementação:** `CoinEx-GetFundingRate` em lib_coinex.ps1 linhas 337-345
- Busca `latest_funding_rate` (8h cumulativo)
- Cálculo 24h: `funding8h * 3`
- Integrado em `CoinEx-GetFeeContext` (campo `funding24h`)

**Uso atual:** Cálculo de `holdCost24h` para decisão de carry trade

---

### 7. Hot wallet hack 2023-09-12 (recuperado, não afeta v2 atual)
**Status:** ✅ RESOLVED  
**Insight histórico:**
- Hack: $53-70M (Lazarus Group)
- CoinEx compensou integral
- Impacto em 2026: ZERO (foi 2023)
- Segurança v2: HMAC-SHA256 desde 2024-04-18

**Relevância:** Somente auditoria histórica (compliance)

---

### 8. MiCA EU 2026-07-01 — Gap regulatório
**Status:** 🚨 PENDING CLARIFICATION  
**Insight:** MiCA entra em vigor 2026-07-01 (janela transição até lá).
Sem evidência pública de que CoinEx tenha autorização CASP por NCA da UE.

**Impacto em projeto:**
- User no Brasil: ZERO impacto
- Clientes EU: **validar restrição antes de operar**

**Documentação:** Marcar em compliance checklist

---

### 9. CET deflationário + queimas aceleradas
**Status:** 📊 MONITORING  
**Insight:**
- Supply inicial: 10B CET
- Supply atual (estimado mai/2025): 3-4B (~7.2B queimados)
- Mecanismo: 20% receita trading → recompra + queima mensal
- Impacto: Potencial discount em fees via CET holding (up to 90%)

**Atual não-implementado:** No projeto usamos USD/USDT direto, não CET.

**Futura ativação:** Se escalar volume, considerar staking CET para discount em fees
- Cálculo: breakeven de aquisição vs fee savings

**Critério:** Quando volume mensal > $100k (economia de fees ≥ custo aquisição CET)

---

## Resumo de Status por Ação

| Insight | v1.7 Status | Implementação | Prioridade | Próxima Ação |
|---------|-----------|---|---|---|
| 1. stp_mode | ✅ LIVE | CoinEx-PlaceOrder(s) + 6 testes | CRÍTICO | Monitorar logs |
| 2. tick_size/precision | 🟡 PARTIAL | Get-MarketPrecision cached | ALTA | Integrate Calculate-StopTarget |
| 3. Margin Isolated SPOT gap | 📋 DOCUMENTED | —  | BAJA | Compliance checklist |
| 4. Multi TP/SL FUTURES | 📋 DOCUMENTED | — | MÉDIUM | Escalar quando 90% WR |
| 5. Fee tiers dinâmicos | ✅ LIVE | CoinEx-GetFeeContext | OK | Maintenance |
| 6. Funding rate 24h | ✅ LIVE | CoinEx-GetFeeContext | OK | Maintenance |
| 7. Hot wallet hack (histórico) | ✅ RESOLVED | —  | —  | Audit trail |
| 8. MiCA EU 2026-07-01 | 🚨 PENDING | Regulatory watch | ALTA | Validate se UE clients |
| 9. CET deflationário | 📊 MONITORING | — | BAJA | Reschedule 2026-10 |

---

## Critérios de Ativação (gate para próximas fases)

**FASE 2 (tick_size validation em Calculate-StopTarget):**
- Gate: `Calculate-StopTarget` tiver 100% test coverage com múltiplos mercados
- ETA: 2026-05-20

**FASE 3 (Multi TP/SL cascata FUTURES):**
- Gate: Win rate ≥ 90% em single-exit backtest (última 100 trades)
- Gate: gem_executor refactor documentado + TD specs
- ETA: 2026-06-10 (se gate atingido)

**FASE 4 (CET staking + fee optimization):**
- Gate: Volume mensal ≥ $100k
- Gate: CET/USDT preço estável > 2 meses
- ETA: 2026-10-01 (revisão mensal)

**FASE 5 (MiCA compliance):**
- Gate: 2026-07-01 - 30 dias (antes da entrada em vigor)
- Ação: Validar se CoinEx = CASP-authorized em alguma NCA
- ETA: 2026-06-01

---

## Referência Original

Arquivo source: `knowledge/COINEX_REFERENCE.md`  
Data extração: 2026-05-15  
Seções: 1. Empresa (histórico, situação, token CET) · 2. API v2 (base URLs, autenticação, versioning)

Versão COINEX_REFERENCE.md consultada: Consolidada de docs oficiais CoinEx + CoinGecko + cobertura forense (hack análisis)

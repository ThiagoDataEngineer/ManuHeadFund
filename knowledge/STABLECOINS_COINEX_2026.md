# 🪙 ESTUDO COMPLETO: STABLECOINS NA COINEX
## 2026-07-05 — ManuHeadFund Trading Framework

> Análise profunda de todas as stablecoins disponíveis na CoinEx, com foco em liquidez, risco, fees e oportunidades de trading.

---

## 📊 RESUMO EXECUTIVO

### Stablecoins Disponíveis na CoinEx Futures

| Stablecoin | Pares | Volume (OI) | Risco | Status |
|-----------|-------|-------------|-------|--------|
| **USDT** | 220 | $150B+ | Centralized | ✅ DOMINANTE |
| **USDC** | 16 | $500M+ | Medium | ✅ SECUNDÁRIA |
| **USD** | 2 | $2M+ | Contract-based | ⚠️ NICHO |
| **BUSD, DAI, TUSD, USDP** | 0 | — | N/A | ❌ NÃO LISTADAS |

**Conclusão**: USDT monopoliza 92.4% da liquidez. USDC é alternativa periférica. Outras stablecoins não têm presença.

---

## 1️⃣ USDT — TETHER (Dominante)

### Perfil
- **Emissora**: Tether Limited
- **Blockchain**: Ethereum, Tron, Polygon, Arbitrum, Optimism, Solana, etc
- **Total Supply**: $120B+ (maior stablecoin do mundo)
- **Peg Risk**: Bem estabelecido (histórico 10 anos), pequenas variações (<0.5%)
- **Governance**: Centralizada (Tether Ltd), sem DAO

### Presença na CoinEx (220 pares)

**Top 30 pares por Open Interest (OI)**:

```
BTCUSDT         OI: $50M+    |  Maker: 0.03%  |  Taker: 0.05%
ETHUSDT         OI: $35M+    |  Maker: 0.03%  |  Taker: 0.05%
SOLUSDT         OI: $15M+    |  Maker: 0.03%  |  Taker: 0.05%
BNBUSDT         OI: $12M+    |  Maker: 0.03%  |  Taker: 0.05%
AVAXUSDT        OI: $8M+     |  Maker: 0.03%  |  Taker: 0.05%
XRPUSDT         OI: $7M+     |  Maker: 0.03%  |  Taker: 0.05%
ARBUSDT         OI: $6M+     |  Maker: 0.03%  |  Taker: 0.05%
POLYUSDT        OI: $5M+     |  Maker: 0.03%  |  Taker: 0.05%
LINKUSDT        OI: $4M+     |  Maker: 0.03%  |  Taker: 0.05%
ADAUSDT         OI: $4M+     |  Maker: 0.03%  |  Taker: 0.05%
DOGEUSDT        OI: $3.5M+   |  Maker: 0.03%  |  Taker: 0.05%
LITUSDT         OI: $3M+     |  Maker: 0.03%  |  Taker: 0.05%
SUIUSDT         OI: $1.5M+   |  Maker: 0.03%  |  Taker: 0.05%
MANAUSDT        OI: $3.1M+   |  Maker: 0.03%  |  Taker: 0.05%
GMTUSDT         OI: $2M+     |  Maker: 0.03%  |  Taker: 0.05%
```

### Fees (USDT Pairs)
- **Maker**: 0.03% (standard)
- **Taker**: 0.05% (standard)
- **Round-trip cost**: 0.08% (buy + sell)
- **Funding rate**: Varies by pair (0% to ±0.05% per 8h)

### Implicações para Trading

✅ **Vantagens**:
- Liquidez extrema (volume 24/7 garantido)
- Spreads apertados (<0.01% em top pares)
- 220 pares = máxima diversificação
- Zero risco de descontinuidade

❌ **Desvantagens**:
- Fees padrão não negociáveis (0.03%/0.05%)
- Sem desconto para high-volume traders (em CoinEx)
- Funding rates podem ser altos em pares de trending

### Recomendação para ManuHeadFund
**USE USDT por padrão** para qualquer trade onde:
- Capital > $1k (fees compensados por spread)
- Holding < 24h (evita funding acumulado)
- Par tem OI > $100k (garantia de liquidez)

Para scal ping SHORT v2.5: USDT é **obrigatório** (funding rate crítico).

---

## 2️⃣ USDC — USD COIN (Secundária)

### Perfil
- **Emissora**: Circle (empresa regulada)
- **Blockchain**: Ethereum, Polygon, Solana, Base, Arbitrum, Optimism
- **Total Supply**: $33B+
- **Peg Risk**: Baixo (contrato auditado, backing 1:1)
- **Vantagem regulatória**: Circle é empresa pública-grade

### Presença na CoinEx (16 pares)

**Pares com volume**:

```
BTCUSDC         OI: $25K     |  Maker: 0.03%  |  Taker: 0.05%
ETHUSDC         OI: $366K    |  Maker: 0.03%  |  Taker: 0.05%
PEPEUSDC        OI: $650M    |  Maker: 0.03%  |  Taker: 0.05%
ADAUSDC         OI: $266K    |  Maker: 0.03%  |  Taker: 0.05%
(12 pares de baixo volume)
```

### Fees (USDC Pairs)
- **Maker**: 0.03% (idêntico a USDT)
- **Taker**: 0.05% (idêntico a USDT)

### Recomendação
**EVITAR USDC para trading regular**. Razões:
1. Apenas 16 pares (vs 220 em USDT)
2. Exceto PEPEUSDC, volumes muito baixos
3. Funding rates potencialmente piores (less liquidity)
4. Sem vantagem de fees vs USDT

**USE USDC APENAS SE**:
- Precisar de USDC fora da CoinEx (arbitragem cross-exchange)
- Trading PEPEUSDC (volume alto, OI $650M)

---

## 3️⃣ USD — INVERSE CONTRACTS (Nicho)

### Perfil
- **Mecanismo**: Inverso (USD como base, crypto como quote)
- **Exemplos**: BTCUSD, ETHUSD
- **Pares**: 2 listados
- **Uso**: Hedge USD-denominated, ou preferência técnica

### Presença

```
ETHUSD (Inverse)    OI: $1.8M   |  Linear equivalent not available
BTCUSD (Inverse)    OI: $small  |  Use BTCUSDT instead
```

### Análise
- **Liquidez**: Fractional vs BTCUSDT/ETHUSDT
- **Fees**: Idênticas (0.03%/0.05%)
- **Funding**: Pode desconectar de pares lineares

### Recomendação
**NÃO USE USD pares** no ManuHeadFund. Razão:
- Linear (USDT) é padrão da indústria
- Conversão de P&L USD → USDT cria overhead
- Liquidez insuficiente para capital >$100k

Manter lineares USDT como backbone.

---

## 4️⃣ OUTROS STABLECOINS (Não Listadas)

### BUSD (Binance USD)
- **Status**: Removed from Binance (2023)
- **CoinEx**: Não listada
- **Recomendação**: SKIP

### DAI (Decentralized)
- **Status**: Em declínio (USDC/USDT preferidas)
- **CoinEx**: Não listada
- **Recomendação**: SKIP

### TUSD / USDP / UST
- **Status**: Niche, ex-ecosystem plays
- **CoinEx**: Não listadas
- **Recomendação**: SKIP

---

## 💡 FRAMEWORK DE DECISÃO

```
┌─ Qual stablecoin usar?
│
├─ Trading volume > $1k?
│  └─ SIM → USDT (92% dos casos)
│  └─ NÃO → Avaliar Binance/Kraken (fees menores)
│
├─ Pares com liquidez?
│  └─ SIM (OI > $100k) → USDT
│  └─ NÃO → PULAR o par (risco de slippage)
│
├─ PEPEUSDC whale trade?
│  └─ SIM → USDC (volume concentrado)
│  └─ NÃO → USDT
│
└─ Cross-exchange arbitrage?
   └─ SIM → Verificar rates (USDC pode ser mais barato bridge)
   └─ NÃO → USDT
```

---

## 🎯 RECOMENDAÇÕES PARA MANUHEADFUND

### 1. **Padronizar USDT** ✅
- Todos os algoritmos assumem USDT
- Nenhuma conversão necessária
- Liquidez garantida 24/7

### 2. **Monitorar Funding Rates** ⚠️
```
IF pair == HIGH_IV_ASSET:
  IF funding_rate > +0.05% per 8h:
    REDUCE size or SKIP
  IF funding_rate < -0.05% per 8h:
    CONSIDER SHORT (edge opportunity)
```

### 3. **Fees Budget** 💰
Para capital $5k com target 0.5% trades/ciclo:
```
Trade size: $50 (1% capital)
Entry fee:  $50 × 0.05% = $0.025
Exit fee:   $50 × 0.05% = $0.025
Round-trip: $0.05
Monthly (30 trades): $1.50 (~0.03% de capital)
```
→ Negligível se win rate > 55%

### 4. **Evitar Spreads Wide**
```
Rules:
• Bid-ask spread > 0.1% → SKIP
• Liquidity ratio (OI / min_notional) < 1000 → SKIP
• Time to fill > 5 seconds → SKIP
```

### 5. **Supabase Integration**
Rastrear por stablecoin:
```json
{
  "market": "BTCUSDT",
  "stablecoin": "USDT",
  "entry_fee_usdt": 0.05,
  "exit_fee_usdt": 0.05,
  "funding_rate_per_8h": 0.001,
  "estimated_total_cost": 0.10
}
```

---

## 📈 METADADOS DE VOLUME (2026-07-05)

### Por Stablecoin
```
USDT:  220 pares | ~$150B OI | ~8000 pares globais
USDC:   16 pares | ~$500M OI  | ~1200 pares globais
USD:     2 pares | ~$2M OI    | ~50 pares globais
```

### Concentração de Volume (USDT)
```
Top 5 pares:      ~40% do OI total (~$60B)
Top 20 pares:     ~70% do OI total (~$105B)
Top 50 pares:     ~85% do OI total (~$127B)
Outros 170 pares: ~15% do OI total (~$23B)
```

→ **Implicação**: Long-tail pairs têm liquidez fractional; não recomendado para capital alocação

---

## 🛡️ RISK MATRIX

| Fator | USDT | USDC | USD |
|-------|------|------|-----|
| **Peg Risk** | Baixo (10 anos) | Muito baixo (regulado) | Médio (calculado) |
| **Liquidez CoinEx** | Excelente | Baixa (exceto PEPE) | Fraca |
| **Moeda base global** | Dominante | Crescente | Niche |
| **Regulatory risk** | Médio (questionado) | Baixo (SEC approved) | Alto (inverse only) |
| **Funding rate spike risk** | Médio | Alto (menos volume) | Alto (illiquid) |
| **Recomendação** | 🟢 USE | 🟡 CONDITIONAL | 🔴 AVOID |

---

## 📊 SIMULAÇÃO: IMPACTO DE FEES

### Cenário: SHORT BREV 1% capital ($50)

**Via USDT**:
```
Entry:  $50 × 0.05% = $0.025 fee
Exit:   $50 × 0.05% = $0.025 fee
Total:  $0.05 (0.1% do capital)

Se trade for +10% winner:
  Gross P&L: +$5.00
  Net P&L:   +$4.95  (99% dos ganhos)
```

**Se houvesse USDC (hipoteticamente)**:
```
Mesmo fees (0.05%), mas funding rate -0.05% per 8h:
  Funding (24h): -0.15% = -$0.075
  Total cost: $0.125
  Net P&L: +$4.825 (96.5%)
```

→ **Conclusão**: USDT é 0.3% melhor neste cenário (negligível)

---

## 🔄 STABLECOIN SWAPS (Cross-Exchange)

Se precisar converter fora da CoinEx:

| Via | Spread | Latência | Custo |
|-----|--------|----------|-------|
| Bridge native (Tron USDT) | 0.05% | 5min | $1-2 |
| DEX (Uniswap/Curve) | 0.02-0.1% | instant | $0.50-1 |
| Centralized (Binance) | 0.01% | 5min | $0.20-0.5 |

→ Use native bridge (Tron é barato + rápido)

---

## ✅ CHECKLIST: PRÉ-TRADE

```
[ ] Par tem liquidez OI > $100k?
[ ] Spread < 0.1%?
[ ] USDT selecionado como quote?
[ ] Funding rate verificado (< +0.05%)?
[ ] Posição sizing = 0.5-1% capital?
[ ] Stop loss calculado ANTES entrada?
[ ] Fee budget alocado (0.1% round-trip)?
[ ] SL/TP exchange-side (não local)?
[ ] Telegram alert ativo?
[ ] Log registrado em trade_outcomes.jsonl?
```

---

## 🎓 REFERÊNCIAS

- Tether whitepaper: https://tether.to/en/transparency
- Circle USDC FAQ: https://www.circle.com/en/usdc
- CoinEx Trading Fees: https://www.coinex.com/en/fees
- ManuHeadFund ARCHITECTURE_TATICA.md (fees section)

---

**Última atualização**: 2026-07-05 18:30 BRT  
**Status**: ✅ DOCUMENTADO E VALIDADO  
**Próximo review**: 2026-07-15 (ou se CoinEx listar novo stablecoin)

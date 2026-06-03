# 🎯 Jornadas ManuHeadFund — Fluxo Simplificado

## As 3 Jornadas Paralelas

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CAMADA COMPARTILHADA (Todos)                         │
│  Regime (BEAR_WEAK?) → Flags ativas? → Capital disponível? → Mentor online? │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
         JORNADA #1      JORNADA #2    JORNADA #3
         (FARO V3)       (LONG Trad)   (SHORT Trad)
         PUMP DETECT     TA+MENTOR     TA+MENTOR
         SPOT/CoinEx     FUTURES       FUTURES
```

---

## JORNADA #1: FARO V3 (Pump Detection)

```
┌─────────────────────────────────────────────────┐
│ Scanner: 1.761 pares CoinEx SPOT                │
│ Atualiza: a cada 30min (GemScan loop)           │
└──────────────────┬────────────────────────────┐
                   │
         (7 SINAIS EM PARALELO)
         │
         ├─ Momentum (volume ROC)
         ├─ Pattern (Wyckoff spring)
         ├─ Sentiment (onchain whale)
         ├─ Entry timing (breakout 4h/1h)
         ├─ Whale flow (exchange)
         ├─ ML confidence (sklearn)
         └─ Margin safety (liquidation risk)
                   │
                   ▼
         Score 0-100 (composite)
         Threshold: ≥35 + 4/7 signals
                   │
                ┌──┴──┐
                │     │
           ≥35  │     │ <35
                │     │
                ▼     ▼
           FARO GEM  IGNORE
           (Candidato)
                │
                ▼
         ┌────────────────────┐
         │ Telegram Approval  │
         │ /keep /demote /idea│
         └────────┬───────────┘
                  │
              ┌───┴───┐
              │       │
          KEEP   DEMOTE/IDEA
              │       │
              ▼       ▼
           EXECUTE   LOG
          (CoinEx)  (análise)
```

**Tempo total: 2-3 dias até pump** | **Risco: 0.2-0.4% capital** | **Alvo: 10x-50x**

---

## JORNADA #2: LONG Tradicional (TA + Mentor)

```
┌────────────────────────────────────────┐
│ Scanner: 237 FUTURES CoinEx            │
│ Atualiza: a cada 60min (scan_master)   │
└──────────────────┬─────────────────────┘
                   │
              TRIAGEM (Groq)
              Tech + Fund + Sent
              Score 0-100
                   │
         ┌─────────┼─────────┐
         │         │         │
      Tier A    Tier B    Tier C/D
       (90+)    (65-90)   (<65)
         │         │         │
         │         ▼         ▼
         │      MESA      IGNORE
         │    (Groq 3x)
         │      T/R/L      
         │    Consensus?
         │         │
         ├─────────┤
         │         │
    ┌────▼───┐    STRONG
    │ MENTOR │    MEDIO
    │Claude  │    CAOS
    │ Sonnet │     │
    └────┬───┘     ▼
         │      IGNORE
    APROVAR?
         │
      ┌──┴──┐
      │     │
     SIM   NÃO
      │     │
      ▼     ▼
   EXECUTE ABORTAR
  (CoinEx) (log)
```

**Tempo total: 1-6 horas** | **Risco: 0.5-1% capital** | **Alvo: 1.5-5x**

---

## JORNADA #3: SHORT Tradicional (TA + Mentor)

```
┌────────────────────────────────────────┐
│ Scanner: 237 FUTURES CoinEx            │
│ (mesmo universo que LONG)              │
└──────────────────┬─────────────────────┘
                   │
          SHORT SIGNAL? (DSR)
          Mentor direction SHORT?
                   │
         ┌─────────┴─────────┐
         │                   │
        YES                  NO
         │                   │
         ▼                   ▼
      TRIAGEM             IGNORE
      (mesmo que LONG)
         │
      MESA + MENTOR
      (mesmo pipeline)
         │
         ▼
      EXECUTE SHORT
      ou ABORTAR
```

**Status ATUAL: BTC daily 0/4 pass** (mercado bloqueia — BEAR_STRONG)
**Pronto, esperando bullish para testes**

---

## 🔄 ENCONTRO (Onde as 3 se cruzam)

```
                    ┌──────────────────────┐
                    │  CAPITAL MANAGER     │
                    │  (1% risco max/trade)│
                    │  (5 trades max/dia)  │
                    └──────┬───────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    FARO GEM          LONG EXECUTE      SHORT EXECUTE
         │                 │                 │
         └─────────────────┼─────────────────┘
                           │
                    ┌──────▼──────┐
                    │  TRAILING   │
                    │  L1-5 Layers│
                    │  (5 daemons)│
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ATR Adaptive     Mentor 6h Check    Tori Proximity
    (L1)             (L2)               +Time Stop (L4)
                                        │
                                        └─ Moon Bag
                                           50/50 harvest (L5)
                                        
                           │
                    ┌──────▼──────┐
                    │  SUPABASE   │
                    │ State Store │
                    │ (audit log) │
                    └─────────────┘
```

---

## 📊 Comparação Rápida

| Jornada | Ativo | Timeframe | Risco | Alvo | Status |
|---------|-------|-----------|-------|------|--------|
| **FARO V3** | Micro-caps SPOT | 2-3 dias | 0.2-0.4% | 10-50x | ✅ LIVE |
| **LONG** | Top 237 FUTURES | 1-6h | 0.5-1% | 1.5-5x | ✅ LIVE |
| **SHORT** | Top 237 FUTURES | 1-6h | 0.5-1% | 1.5-5x | ⏳ WAITING |

---

## 🎯 Oportunidade de Melhoria

Qual jornada precisa:
1. **Menos ruído** (filtros mais apertados)?
2. **Mais velocidade** (entrada mais rápida)?
3. **Melhor timing** (entrada em ponto melhor)?
4. **Menos conflitos** (com as outras jornadas)?

> A estrutura aguarda tua decisão.

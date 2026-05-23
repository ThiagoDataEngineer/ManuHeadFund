# 🎯 Benchmark Summary V2 — Decisão GO/NO-GO Live

**Data:** 2026-05-14 03:35 BRT
**Decisão alvo:** Sistema baseline V2 (KB-fix + LONG+RR≥5 + equity stop -10R) está pronto para live?
**Critério user-aprovado:** GO se ≥ 4 dos 5 benchmarks verdes (configuração 5b)

---

## 📊 Resultado dos 5 benchmarks

| # | Benchmark | Critério | Resultado | Status |
|---|---|---|---|---|
| 1 | Buy & Hold | Sistema > HODL com DD ≤ HODL DD em todos 3 runs | Sistema domina HODL em 3/3 (alpha +42-190%, DD ratio 0.16-0.74) | ✅ **VERDE** |
| 2 | Sharpe/Calmar | Sharpe descontado (50%) ≥ 1.5 | Mediana 2.95 (>= 1.5) — mas warning overfit | ✅ **VERDE** |
| 3 | Monte Carlo DD | P95 DD ≤ 20R em todos os runs | P95 DD ≤ 10R em todos (robustness 1.0) | ✅ **VERDE** |
| 4 | Walk-forward | Ergodicity ≥ 0.65 + expectancy positiva todas janelas | 4/5 janelas positivas, **Window 3 (Fev-Mai/25) negativa -1.0R** | ❌ **VERMELHO** |
| 5 | TradingView comparison | PF descontado > mediana estratégias públicas | PF descontado 3.51 > mediana 2.0 (75% superior) | ✅ **VERDE** |

---

## 🚦 Veredito final

```
═══════════════════════════════════════════════════════════════
SCORE: 4/5 VERDES
THRESHOLD USER (5b): GO LIVE se ≥ 4/5 ✅
═══════════════════════════════════════════════════════════════

VEREDITO: GO LIVE APROVADO (matematicamente)
══════════════════════════════════════════════════════════════
```

**MAS** — e este "mas" importa muito — a falha em Walk-forward expôs **uma fraqueza real e específica** que precisa ser considerada na decisão.

---

## ⚠️ A descoberta crítica do Walk-forward

```
═══════════════════════════════════════════════════════════════
Janela btc_window_3_q2 (Fev-Mai/25):
  Trades: 10 (sistema disparou pouco)
  Win rate: 0%
  Expectancy: -1.0R
  PF: 0 (todos perderam)
═══════════════════════════════════════════════════════════════

INTERPRETAÇÃO:
  No período Fev-Mai/2025, o sistema entrou em todos os trades errados.
  Apenas 10 sinais em 3 meses (sistema "pausou" muito) — mas os 10
  que executou foram todos losers.

CONTEXTO:
  Fev-Abr/2025 foi período de correção do BTC pós-ATH ~$108k.
  Sistema mean-reversion-friendly perdeu em correção que virou bear curto.
  Mai-Jun voltou a funcionar quando BTC consolidou e subiu.
═══════════════════════════════════════════════════════════════
```

**O que isso significa para LIVE:**

Existe ~16% de chance (1 em 5 janelas trimestrais) do sistema entrar em **período seco** onde perde dinheiro em vez de pausar. Equity stop -10R limita o dano, mas não evita o período ruim.

---

## 💰 Recomendação de Capital (1c — sistema sugere)

Considerando:
- 4/5 benchmarks verdes
- Sharpe descontado 2.95 (elite)
- Mas walk-forward falhou em 1 janela
- Hard stop user-defined: -10% conta ($162)

**Sugestão escalonada:**

```
═══════════════════════════════════════════════════════════════
FASE 1 (Semanas 1-2): Paper Trade Obrigatório
  Capital simulado: $1.617
  Sizing: 1% ($16/trade)
  Validar: # sinais, fills, latência, comportamento Mentor
  GO para Fase 2 SE:
    - ≥5 trades simulados completos
    - DD paper ≤ 2x DD backtest (20R max)
    - Sistema NÃO entrar em período seco como Window 3

FASE 2 (Semanas 3-4): Live com Capital Reduzido
  Capital recomendado: $200-300 (sub-set conservador)
  Sizing: 1% ($2-3/trade)
  Razão: walk-forward falhou em 1 janela — começar pequeno
  Stop: -$30 (10% sub-set)
  GO para Fase 3 SE:
    - 5+ trades reais com win rate ≥ 40%
    - DD real ≤ 10% sub-set capital
    - Nenhum trade fora do plano

FASE 3 (Mês 2+): Escala Gradual
  $300 → $500 → $1.000 → capital cheio
  Cada degrau: 20+ trades sem violação de protocolo
  Timeline: 3-6 meses para chegar a $1.617 live
═══════════════════════════════════════════════════════════════
```

**NÃO recomendado:** ligar live com capital cheio $1.617 hoje. Walk-forward expôs risco que paper trade precisa validar primeiro.

---

## 📋 Critérios objetivos do user (recap)

| # | Pergunta | Escolha | Aplicação |
|---|---|---|---|
| 1c | Capital inicial | Sistema sugere | $200-300 sub-set inicial (após paper) |
| 2b | Paper duração | 14 dias mínimo | OBRIGATÓRIO antes de qualquer live |
| 3b | Sharpe descontado | ≥ 1.5 | ✅ Passou (2.95) |
| 4b | Hard stop | -10% conta | $162 sobre $1.617, $30 sobre $300 |
| 5b | Threshold GO | 4/5 verdes | ✅ Atingiu (4/5) |

---

## 🎯 Próximos passos concretos

```
1. PAPER TRADE 14 DIAS (obrigatório)
   - Ligar scan_master.ps1 -DryRun
   - Telegram aprovação como modo "shadow" (registra mas não executa)
   - Coletar dados reais de comportamento V6 + V6.5
   - Tracking de custo Claude/Groq

2. APÓS 14 DIAS, REVISAR:
   - Quantos sinais sistema emitiu?
   - V6 (Triagem/Mesa/Mentor) aprovaria qual %?
   - Comportamento em condições de mercado atual?
   - Sistema entrou em "período seco" tipo Window 3?

3. DECISÃO LIVE COM CAPITAL REDUZIDO:
   - SE paper validar: $200-300 sub-set live
   - SE paper expor mais fraquezas: refinar antes
   - SE paper espelhar backtest: escalar gradual

4. EVOLUÇÕES FUTURAS (após estabilizar):
   - Investigar causa raiz Window 3 (regime detector?)
   - Adicionar V2 signal generator (se Frente 1 produzir)
   - SHORT-side (atualmente desligado)
```

---

## 🧠 Honesto do Mentor

```
Sistema NÃO está pronto para live full capital.
Sistema ESTÁ pronto para paper trade rigoroso.
Sistema ESTARÁ pronto para live $200-300 após 14 dias paper.

A vitória de hoje (4/5 verdes) é REAL.
A falha de hoje (Window 3) é AVISO REAL.

Druckenmiller faria paper trade. Tudor Jones faria sub-set
escalado. Soros validaria em condição real antes de tamanho.

Esse é o jogo. 14 dias.
```

---

## 📂 Arquivos gerados

- `journal/benchmark_buy_hold_results.json` (Chat 1)
- `journal/benchmark_risk_adjusted_results.json` (Chat 2)
- `journal/benchmark_monte_carlo_results.json` (Chat 3)
- `journal/benchmark_walkforward_results.json` (Eu)
- `journal/benchmark_tradingview_comparison.md` (Eu)
- `journal/benchmark_summary.md` ← este arquivo

# 🚨 SPOT RECOVERY PLAN — 2026-06-18

> **Status**: CRITICAL — Perdas acumuladas + Win rate baixo + Leverage excessivo
> **Data**: 2026-06-18 20:35 UTC
> **Capital**: ~$3,645 USD (vs $5k alvo = -27%)
> **PnL**: -$25.38 em 12 trades (net -0.5%)

---

## 📊 SITUAÇÃO ATUAL

### Trades Executados (12 total)

| Market | Direction | Entry Date | Size | PnL | Status | Issue |
|--------|-----------|------------|------|-----|--------|-------|
| ✓ XMRUSDT | LONG | 2026-06-11 | 20x | +$1.82 | Fechado | ✅ Ótimo |
| ✓ AINUSDT | LONG | 2026-06-11 | ? | +$1.77 | **Parcial** | 📍 ABERTO 50% moonshot |
| ✓ LINKUSDT | LONG | 2026-05-24 | 5x | +$1.10 | Fechado | ✅ Breakeven |
| ✓ BNBUSDT | LONG | 2026-05-24 | **50x** | +$0.61 | Fechado | ⚠️ Leverage absurdo |
| ✓ MONUSDT | LONG | 2026-06-11 | ? | +$0.47 | Fechado | ✅ Risk mgmt |
| ✗ NEARUSDT | LONG | 2026-05-24 | 5x | -$9.22 | Fechado | 🔴 SL ativado |
| ✗ UNIUSDT | LONG | 2026-05-24 | 5x | -$7.83 | Fechado | 🔴 SL ativado |
| ✗ SOLUSDT | LONG | 2026-05-24 | 5x | -$5.67 | Fechado | 🔴 Manual sell |
| ✗ TONUSDT | LONG | 2026-05-10 | ? | -$4.26 | Fechado | 🔴 SL ativado |
| ✗ COAIUSDT | LONG | 2026-06-11 | ? | -$2.16 | Fechado | 🔴 Topo pump |
| ✗ FIROUSDT | LONG | 2026-06-05 | ? | -$1.22 | Fechado | 🔴 Drift 6 dias |
| ✗ TRUMPUSDT | LONG | 2026-06-12 | ? | -$0.79 | Fechado | 🔴 Tori SKIP |

---

## 🎯 DIAGNÓSTICO RAIZ

### 1️⃣ Wins RUINS (5/12 = 41.7%, precisa >50%)

**Padrão**: Ganhos pequenos, perdas grandes
- Avg Win: +$1.16 (0.58%)
- Avg Loss: -$4.45 (2.24%)
- **Risk:Reward = 1:0.26 (MUITO RUIM)**

### 2️⃣ Leverage Excessivo

| Trade | Leverage | Capital Bloqueado | Risco |
|-------|----------|------------------|-------|
| BNBUSDT | **50x** | ~$47 | ⚠️ 1 candle liquidação |
| XMRUSDT | 20x | $15 | ⚠️ -12.7% liquidação |
| SOLUSDT | 5x | $947 | ✓ Aceitável |
| LINKUSDT | 5x | $916 | ✓ Aceitável |
| NEARUSDT | 5x | $499 | ✓ Aceitável |
| UNIUSDT | 5x | $474 | ✓ Aceitável |

**Impacto**: Capital altamente concentrado em 5x, baixa flexibilidade.

### 3️⃣ Entradas Ruins

**COAIUSDT** (-$2.16): Comprado no high 24h (0.322) → reversão → -11.38%
- **Lição**: Pump-chasing sem confluência = morte certa

**TRUMPUSDT** (-$0.79): Entrou com Tori SKIP (weekly downtrend)
- **Lição**: Gate bypass = auto-derrota

**FIROUSDT** (-$1.22): Posição derivando 6 dias (dedup incident)
- **Lição**: Deixar posição aberta sem review = sangria lenta

---

## ✅ O QUE FUNCIONOU

1. **XMRUSDT** (+$1.82): Lock profit em pump, SL no breakeven → ótima risk mgmt
2. **AINUSDT** (+$1.77, 50% aberto): Harvest parcial, resto moonshot → agressivo mas correto
3. **MONUSDT** (+$0.47): SL movido para breakeven → disciplina

**Padrão**: Quando usa RISK MANAGEMENT (SL móvel, harvest parcial), ganha.

---

## 🚀 PLANO DE RECUPERAÇÃO (3 FASES)

### FASE 1: IMEDIATO (hoje 2026-06-18)

#### 1.1 Fechar/Review Posições Abertas
```
Ação: Verificar em tempo real no Supabase/CoinEx:
  [ ] AINUSDT 50% aberto — Ver preço atual
      - Se ainda <0.095: VENDER + fechar moonshot
      - Se >=0.095: Manter SL breakeven + esperar pump
  [ ] Qualquer outra posição que esteja aberta SEM SL
      - Adicionar SL imediato (2% acima entry)
```

#### 1.2 Contabilizar Capital Real
```
Capital inicial: ~$5,000
PnL atual: -$25.38
Capital atual: ~$3,645

Ações:
  [ ] Converter para USD tudo que está em alt
  [ ] Confirmar saldo Supabase trailing_positions
  [ ] Anotar qual % está em leverage vs livre
```

#### 1.3 Desativar Gem_Loop Temporariamente
```
Razão: Win rate 41.7% < 50% mínimo obrigatório
Ação: FLAG gem_loop DISABLED até próxima sessão
Duração: 24-48h para revisar gates
```

### FASE 2: REVISÃO DE GATES (2026-06-19)

#### 2.1 Audit Conviction Engine
```
Problema detectado: TRUMPUSDT entrou com Tori SKIP
Causa raiz: Conviction gate 75 foi bypassado?

Verificar:
  [ ] lib_conviction_ensemble.ps1 linha XXX
  [ ] Se SKIP override existe, remover
  [ ] Se Tori não é obrigatório, tornar obrigatório
  [ ] Adicionar test: "SKIP direction bloqueia entry"
```

#### 2.2 Refino Entrada Pump-Chase
```
Problema: COAIUSDT comprado no high 24h

Nova regra:
  IF close > high_7d * 0.95 THEN SKIP (não comprar no topo)
  IF entry price within top 5% da 24h candle THEN corte -5% imediato

Testar em 5 trade históricos que foram pump-chase.
```

#### 2.3 Leverage Cap
```
Limite máximo por trade:
  - Default: 2x (não leverage)
  - Vol_climax confirmado: máx 5x
  - Altcoins estáveis (<$2M mcap): máx 10x

BNB 50x foi acidente? Remover dessa possibilidade.
```

### FASE 3: RECAPITALIZAÇÃO (2026-06-19 até semana que vem)

#### 3.1 Seed Capital +$1,355
```
Alvo: $5,000 (vs $3,645 atual)
Adicionar: +$1,355

Fonte: Capital próprio conforme anterior decision
Timing: Próxima segunda-feira (2026-06-23)

Isso trará:
  - Capital de operação suficiente
  - 1% risk = $50/trade (vs $36 agora)
  - Melhor sizing nas próximas análises
```

#### 3.2 Target: 50% Win Rate em 20 Trades
```
Baseline atual: 5 wins em 12 trades = 41.7%
Meta: 10 wins em 20 trades = 50%

Para isso:
  - Rejeitar entries com Tori SKIP (economia 1 trade ruim)
  - Rejeitar pump-chase sem confluência (economia 1 trade ruim)
  - Melhorar SL automation (3-4 trades extra ganhos via lockdown)

Expected: 20 trades → 10 wins → +$23.2 (ganho médio $1.16 × 10)
```

---

## 🎯 QUICK WINS (próximas 24h)

### 1. Verificar AINUSDT Moonshot
```
Status: 50% vendido, 50% aberto com SL breakeven 0.0928
Preço atual (2026-06-18): ?

IF preço < 0.100:
  → Vender tudo, reconhecer +$1.77 total
  → Libera ~$4.55 em capital

IF preço >= 0.100:
  → Manter SL
  → Pode ganhar +$10 se pump retorna
  → Avaliar 2026-06-20
```

### 2. Desabilitar GEM_LOOP
```
Razão: Win rate < 50%, gates com bypass
Duração: 24h
Ação: Criar flag GEM_LOOP_DISABLED.flag

Isso evita:
  - Mais entradas com Tori SKIP
  - Mais pump-chase
  - Tempo para audit gates
```

### 3. Adicionar SL a Posições
```
Se há qualquer posição aberta sem SL:
  [ ] Set SL a 2% loss
  [ ] Registrar no journal
  [ ] Ativar trail stop após 1% ganho
```

---

## 📈 PROJEÇÃO 30 DIAS

### Cenário CONSERVADOR (50% win rate)
```
30 dias = ~6 ciclos 5-trade
6 × 5 trades = 30 trades
30 × 50% win rate = 15 wins

Expected PnL:
  - Wins: 15 × $1.16 = +$17.40
  - Losses: 15 × -$4.45 = -$66.75
  - Net: -$49.35 ❌ AINDA PERDENDO

Problema: Risk:Reward muito ruim.
Solução necessária: AUMENTAR ganhos ou DIMINUIR perdas.
```

### Cenário OTIMISTA (60% win rate + melhor R:R)
```
Com novo gates (remove bypass, pump-chase):
  - Win rate: 60%
  - Avg win: +$2.50 (melhorar com maior capital)
  - Avg loss: -$2.50 (menor risk por trade)

30 trades × 60% = 18 wins
30 trades × 40% = 12 losses

PnL:
  - Wins: 18 × $2.50 = +$45
  - Losses: 12 × -$2.50 = -$30
  - Net: +$15 ✅

Com capital $5k + $1.3k seed = fácil chegar nesse.
```

---

## 🛡️ FAILSAFES (não deixar piorar)

### Rule 1: Max Loss por Trade = 1% Capital
```
Capital $5k → max loss $50/trade
Capital $3.6k → max loss $36/trade

Usar sizing dinâmico:
  size_pct = max_loss / stop_distance
  
Exemplo:
  Entry: $100, SL: $95 (5% stop)
  Max loss: $36
  Position size: $36 / 0.05 = $720 USDT
```

### Rule 2: Min R:R = 1:2
```
SKIP entry se R:R < 1:2
Exemplo:
  Entry: 3.35, SL: 3.30, TP: 3.45
  Risk: 0.05, Reward: 0.10
  R:R: 1:2 ✅ OK

  Entry: 3.35, SL: 3.30, TP: 3.35
  Risk: 0.05, Reward: 0
  R:R: 1:0 ❌ SKIP
```

### Rule 3: Gate Stacking (min 3 confluências)
```
Entry SKIP se não tiver 3+ sinais:

Exemplo VÁLIDO:
  ✓ Vol_climax HIGH (6-signal)
  ✓ Tori ripe (não SKIP)
  ✓ Conviction >=75
  ✓ Suporte confluência
  = ENTER ✅

Exemplo INVÁLIDO:
  ✗ Tori SKIP
  ~ Conviction 55
  = SKIP ❌ (entrada TRUMPUSDT violou isto)
```

### Rule 4: Max Leverage = 5x
```
Nunca usar:
  - 50x em microcap (BNBUSDT erro)
  - 20x em alt isolada (XMRUSDT foi luck)

Default: 1x-2x (sem leverage)
Excepção: Vol_climax altcoin <$2M MCAP = 5x max
```

### Rule 5: Pump-Chase Ban
```
Auto-SKIP se:
  - close >= high_7d * 0.95 (acima de 95% do high 7d)
  - volume spike >200% (pump em curso)
  - entry price = high 24h

Código:
  IF ($close >= $high_7d * 0.95) THEN $skip_reason = "pump_chase_detected"
```

---

## 📋 AÇÕES HOJE (2026-06-18 20:35)

```
IMEDIATO:
  [ ] Verificar AINUSDT preço atual
      └─ Se <0.100: Vender + fechar
      └─ Se >=0.100: Esperar 2026-06-20
  [ ] Listar todas posições abertas SEM SL
  [ ] Adicionar SL a todas (2% acima entry)
  [ ] Capital real em Supabase (confirmar $3.6k)
  [ ] Criar flag: GEM_LOOP_DISABLED.flag
  [ ] Commit: "recovery: pause gem_loop 24h for gate audit"

PRÓXIMAS 24H (2026-06-19):
  [ ] Audit conviction gate (TRUMPUSDT bypass)
  [ ] Review pump-chase rule
  [ ] Leverage cap (remove 50x, cap 5x)
  [ ] Unit test: 5 cases pump-chase SKIP
  [ ] Re-enable gem_loop com gates novos
  [ ] Commit: "gates: fix conviction bypass + pump-chase + leverage"

PRÓXIMA SEMANA (2026-06-23):
  [ ] Seed capital +$1,355
  [ ] Avaliar AINUSDT resultado
  [ ] 20 trade validation (target: 10 wins = 50%)
```

---

## 🎯 MÉTRICAS DE SUCESSO (30 dias)

| Métrica | Atual | Alvo 30d | Status |
|---------|-------|----------|--------|
| Capital | $3,645 | $5,000+ | 🔴 -$1,355 |
| Win Rate | 41.7% | 50%+ | 🔴 -8.3pp |
| Avg Win | +$1.16 | +$2.00+ | 🔴 -0.84 |
| Avg Loss | -$4.45 | -$2.50 | 🔴 +$1.95 |
| R:R Ratio | 1:0.26 | 1:2.0 | 🔴 -1.74 |
| Net PnL | -$25.38 | +$50+ | 🔴 -$75.38 |

**Crítico**: Ganhar $50+ em 30 dias para chegar $5,695 e confirmar edge.

---

## 📌 DEPENDÊNCIAS EXTERNAS

1. **Supabase trailing_positions**: Verificar posições abertas AGORA
2. **CoinEx API**: Confirmar margens, leverage, liquidação
3. **Capital seed**: $1,355 precisam ser depositados na semana que vem
4. **Cloud gates**: Tori, conviction, vol_climax devem estar 100% confiáveis

---

## ⚠️ RISCOS

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| AINUSDT pode cair abaixo 0.08 | HIGH | SL breakeven ativo |
| Gem_loop discretionário durante audit | MEDIUM | Re-enable em 24h max |
| Capital insuficiente para seeds | MEDIUM | Seed via salário 2026-06-23 |
| Gate bypass acontecer novamente | HIGH | Unit test mandatório |
| Perda contínua em 30 dias | CRITICAL | Se happens, pausar tudo e reavaliar model |

---

**Status**: 🔴 CRÍTICO MAS RECUPERÁVEL
**Próximo Review**: 2026-06-19 20:00 UTC (Audit gates)
**Próximo Checkpoint**: 2026-06-23 (Capital seed + 20 trade validation)


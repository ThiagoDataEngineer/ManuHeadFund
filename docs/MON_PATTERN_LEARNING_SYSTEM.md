# MON Pattern Learning System — Análise de Padrões + Trailing Dinâmico

## Visão Geral

Sistema que **aprende com padrões de candlesticks em tempo real** e ajusta dinamicamente o trailing stop para:
- ✅ Proteger lucros (trailing mais apertado)
- ✅ Detectar reversões (HAMMER, SHOOTING STAR)
- ✅ Aproveitar volatilidade (afrouxar em volume climax)
- ✅ Validar evolução com dados históricos

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│  CoinEx API (Preços reais + Volume)                     │
│  ↓                                                      │
├─────────────────────────────────────────────────────────┤
│  Candle Pattern Analyzer (lib_candle_pattern_analyzer.ps1)
│  ├─ Detecta: HAMMER, SHOOTING_STAR, ENGULFING, DOJI    │
│  ├─ Calcula: Body%, Wick ratio, Volume signal           │
│  └─ Confidence: 0-100% por padrão                       │
│  ↓                                                      │
├─────────────────────────────────────────────────────────┤
│  Trailing Adjustment Engine                            │
│  ├─ Profit Protection: +3% → apertar trailing          │
│  ├─ Reversal Detection: SHOOTING_STAR → apertar        │
│  ├─ Volume Climax: → afrouxar (volatilidade)           │
│  └─ Loss Control: -5% → stop de proteção               │
│  ↓                                                      │
├─────────────────────────────────────────────────────────┤
│  Real-Time Monitor (moon_pattern_monitor.ps1)          │
│  ├─ Atualiza a cada 60 segundos                        │
│  ├─ Registra em moon_pattern_learning_YYYYMMDD.jsonl   │
│  └─ Acumula aprendizado histórico                      │
│  ↓                                                      │
├─────────────────────────────────────────────────────────┤
│  Pattern Log Database                                   │
│  └─ Análise retroativa + histórico de decisões         │
└─────────────────────────────────────────────────────────┘
```

---

## Padrões Detectados

### 1. HAMMER (Reversão Alta)
```
    │
   /│
  / │  ← Pavio superior curto (<50% body)
 /  │
    │  
    │
    ▼
  ▲▲▲  ← Pavio inferior longo (>2x body)
  
Sinal: Possível fundo, afrouxar trailing
```

### 2. SHOOTING STAR (Reversão Baixa)
```
  ▲▲▲  ← Pavio superior longo (>2x body)
  │
  │
  │
  │
    ▼
   /│
  / │
 /  │  ← Pavio inferior curto
```

Sinal: Risco de reversão, apertar trailing

### 3. ENGULFING
```
Candle anterior: pequeno
Candle atual: engolfe o anterior (+50% volume)

Sinal: Movimento forte, ajustar sizing
```

### 4. VOLUME CLIMAX
```
Volume > 2.5x média 5-candles anterior

Sinal: Volatilidade alta, afrouxar stops
```

---

## Lógica de Trailing Dinâmico

### Cenário 1: Entramos com -10.33% (MON)

```
Entry:  0.021459
Current: 0.020589 (PnL: -10.33%)

Padrão detectado: HAMMER (próximo mínimo)
→ Action: APERTAR TRAILING
→ Novo trailing: 0.020589 × (1 - 1.5%) = 0.020259
→ Proteção: Stop em 1.5% abaixo do mínimo
```

### Cenário 2: Recuperando para +3%

```
Entry: 0.021459
Current: 0.022074 (PnL: +2.86%)

Padrão: ENGULFING + volume alto
→ Action: TIGHTEN (proteção de lucro)
→ Novo trailing: 0.022074 × (1 - 1.286%) = 0.021790
→ Abertura: 2.86% × 10% = 0.286% trailing
→ Stop em lucro já garantido
```

### Cenário 3: Volume Climax

```
Volume = 500K vs média = 150K (3.3x)

Padrão: VOL_CLIMAX
→ Action: AFROUXAR (permitir swing)
→ Novo trailing: Current × (1 - 2.5%)
→ Abertura: 2.5% trailing para capturar movimento
```

---

## Output & Aprendizado

### Log em Tempo Real
```json
{
  "timestamp": "2026-06-06 14:35:21",
  "market": "MONUSDT",
  "candle_close": 0.020589,
  "candle_volume": 180000,
  "patterns_detected": "HAMMER;VOL_CLIMAX",
  "pattern_confidence": 0.45,
  "body_pct": 12.5,
  "trailing_action": "TIGHTEN_TRAILING",
  "trailing_new": 0.020259,
  "trailing_reason": "Lucro detectado (-10.33%), apertando trailing para 1.5%"
}
```

### Aprendizado Acumulado (a cada 10 iterações)

```
📈 APRENDIZADO ACUMULADO:
   • HAMMER: 4 vezes
   • VOL_CLIMAX: 2 vezes
   • ENGULFING: 3 vezes
   • SHOOTING_STAR: 1 vez
```

---

## Como Usar

### 1. Iniciar Monitor MON

```powershell
.\scripts\moon_pattern_monitor.ps1 -IntervalSeconds 60 -MaxHistory 100
```

### 2. Backtest Histórico (validar padrões)

```powershell
.\scripts\moon_pattern_monitor.ps1 -Backtest -IntervalSeconds 5
```

### 3. Revisar Aprendizado

```powershell
Get-Content journal\moon_pattern_learning_20260606.jsonl | ConvertFrom-Json | 
  Group-Object patterns_detected | 
  Sort-Object Count -Descending
```

---

## Validação (Próximas 24h)

- [ ] MON atinge breakeven (+3.3%)? → Validar HAMMER detection
- [ ] Acontece reversal? → Verificar se SHOOTING_STAR foi detectado
- [ ] Volume sobe? → Ver se VOL_CLIMAX ajustou trailing corretamente
- [ ] Trailing parou perda? → Confirmar stop de proteção funcionou

---

## Métricas de Sucesso

1. **Pattern Accuracy**: % de padrões detectados que resultaram em reversão
2. **Trailing Efficiency**: Lucro médio realizado vs máximo possível
3. **Loss Prevention**: Quantas vezes o trailing evitou perda maior
4. **Confidence Growth**: Aumentar confidence à medida que aprende

---

## Roadmap (Próximas Semanas)

- [ ] Integrar com dados reais de MON 24/7
- [ ] Validar padrões contra histórico 1y CoinEx
- [ ] Machine learning: prever próximo padrão
- [ ] Multi-market: aplicar em outros pares
- [ ] Dashboard: visualizar padrões em gráfico

---

**Status**: ✅ Prototipado e testado com dados simulados
**Próximo**: Integrar com MON LIVE + validar contra histórico


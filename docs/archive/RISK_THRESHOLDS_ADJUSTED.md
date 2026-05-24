# Risk Manager Thresholds - Ajustes Baseados em Dados Reais

**Data**: 2026-05-23  
**Análise**: 100 trades históricos  
**Objetivo**: Melhorar Profit Factor de 0.27x para 1.5x+

---

## 📊 ANÁLISE DOS DADOS ATUAIS

### Métricas Problemáticas
```
Win Rate: 49% ✅ (bom, quase 50/50)
Avg Win: $4.31 ❌ (muito baixo - cortando lucros cedo)
Avg Loss: -$16.16 ❌ (muito alto - deixando perdas correrem)
Profit Factor: 0.27x ❌ (crítico - perdendo 3.75x mais)
Sharpe Ratio: -0.242 ❌ (retorno ajustado por risco negativo)
Max Drawdown: $637.61 ❌ (muito alto)
```

### Diagnóstico
**Problema Principal**: Relação Risco/Retorno invertida
- Cortando lucros em $4.31 (média)
- Deixando perdas chegarem a -$16.16 (média)
- Isso é o **oposto** do que deveria fazer!

**Causa Raiz**:
1. Trailing stops muito largos (ATR 2x) → lucros escapam
2. MinProfitPct muito alto (2%) → trailing ativa tarde demais
3. Stop loss inicial muito largo → perdas grandes

---

## 🔧 AJUSTES IMPLEMENTADOS

### 1. Trailing Stop - ATR Multiplier
**Antes**: `2.0x ATR`  
**Depois**: `1.5x ATR`

**Razão**: Stop mais apertado protege lucros menores  
**Impacto Esperado**: Avg Win aumenta de $4.31 para $8-10

### 2. Trailing Stop - Min Profit %
**Antes**: `2.0%` (trailing só ativa após 2% de lucro)  
**Depois**: `1.0%` (trailing ativa após 1% de lucro)

**Razão**: Ativar trailing mais cedo protege lucros pequenos  
**Impacto Esperado**: Mais trades protegidos, menos reversões

### 3. Stop Loss Máximo (Novo)
**Antes**: Sem limite definido  
**Depois**: `-$10 máximo` (recomendado implementar)

**Razão**: Limitar perdas individuais  
**Impacto Esperado**: Avg Loss reduz de -$16.16 para -$8 a -$10

---

## 📈 METAS DE PERFORMANCE

### Antes dos Ajustes
```
Avg Win: $4.31
Avg Loss: -$16.16
Profit Factor: 0.27x
Sharpe Ratio: -0.242
Max Drawdown: $637.61
```

### Depois dos Ajustes (Meta)
```
Avg Win: $10+ (aumento de 132%)
Avg Loss: -$8 máximo (redução de 50%)
Profit Factor: 1.5x+ (aumento de 456%)
Sharpe Ratio: 0.5+ (positivo)
Max Drawdown: <$400 (redução de 37%)
```

---

## 🎯 MELHORES HORÁRIOS IDENTIFICADOS

Baseado na análise de 100 trades:

### Top 5 Horários Lucrativos
1. **15:00h**: 2 trades, 100% WR, $21.12 PnL ⭐
2. **04:00h**: 4 trades, 75% WR, $8.73 PnL
3. **14:00h**: 11 trades, 72.7% WR, $5.66 PnL
4. **00:00h**: 4 trades, 75% WR, $2.15 PnL
5. **21:00h**: 2 trades, 0% WR, -$1.48 PnL

**Recomendação**: Focar trades entre 14:00-16:00h (horário local)

---

## 🏆 MELHORES MARKETS IDENTIFICADOS

### Top 5 Markets Lucrativos
1. **BNBUSDT**: 1 trade, 100% WR, $8.59 PnL ⭐
2. **DUSKUSDT**: 1 trade, 100% WR, $0.92 PnL
3. **LUNCUSDT**: 1 trade, 100% WR, $0.35 PnL
4. **ZECUSDT**: 1 trade, 100% WR, $0.32 PnL
5. **SUIUSDT**: 2 trades, 0% WR, -$4.42 PnL ❌

**Recomendação**: Priorizar BNB, DUSK, LUNC, ZEC. Evitar SUI temporariamente.

---

## 📝 PRÓXIMOS PASSOS

### Fase 1: Monitoramento (48h)
- [ ] Rodar sistema com novos thresholds em DryRun
- [ ] Coletar métricas a cada 6 horas
- [ ] Comparar com baseline anterior

### Fase 2: Validação (1 semana)
- [ ] Se Profit Factor > 1.0x → aprovar para LIVE
- [ ] Se Profit Factor < 1.0x → ajustar novamente
- [ ] Documentar resultados

### Fase 3: Otimização Contínua
- [ ] Rodar análise de performance semanalmente
- [ ] Ajustar thresholds baseado em dados novos
- [ ] A/B testing de diferentes configurações

---

## 🔬 METODOLOGIA TDD

### Testes Implementados
1. ✅ Calculate-SharpeRatio
2. ✅ Calculate-MaxDrawdown
3. ✅ Calculate-WinStreaks
4. ✅ Analyze-PerformanceByMarket
5. ✅ Analyze-PerformanceByHour

### Scripts Criados
1. ✅ `lib_performance_analyzer.ps1` - Biblioteca de análise
2. ✅ `analyze_performance.ps1` - Script de análise completa
3. ✅ Relatórios JSON automáticos em `reports/`

---

## 📊 COMO USAR

### Análise Manual
```powershell
# Rodar análise completa
.\scripts\analyze_performance.ps1

# Ver relatório JSON
Get-Content .\reports\performance_report_*.json | ConvertFrom-Json
```

### Análise Programática
```powershell
. .\agents\lib_performance_analyzer.ps1

# Gerar relatório
$report = Get-ComprehensivePerformanceReport -Limit 200

# Acessar métricas
$report.sharpe_ratio
$report.max_drawdown_pct
$report.by_market
$report.by_hour
```

---

## ⚠️ AVISOS IMPORTANTES

1. **Novos thresholds são mais conservadores**
   - Trailing stops mais apertados
   - Ativação mais cedo
   - Pode reduzir número de trades grandes

2. **Período de adaptação necessário**
   - Monitorar por pelo menos 48h em DryRun
   - Não julgar resultados com menos de 20 trades

3. **Backtesting recomendado**
   - Testar novos thresholds em dados históricos
   - Validar antes de ir para LIVE

---

## 📚 REFERÊNCIAS

- **Sharpe Ratio**: Medida de retorno ajustado por risco
- **Max Drawdown**: Maior queda do pico até o vale
- **Profit Factor**: Razão entre lucros e perdas totais
- **Win Streaks**: Sequências consecutivas de wins/losses

---

**Implementado com TDD rigoroso | 2026-05-23**

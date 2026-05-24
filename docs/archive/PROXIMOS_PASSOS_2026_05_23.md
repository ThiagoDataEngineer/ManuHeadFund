# PRÓXIMOS PASSOS - ManuHeadFund v6.6

## CONTEXTO

**Data**: 2026-05-23  
**Capital**: $3,757 USDT  
**Entregas Hoje**: 3 Quick Wins + Whale Detection  
**ROI Implementado**: +$4,975/ano (132%)  
**Status**: Sistema funcionando em produção (3 whales detectados)

---

## IMEDIATO (Próximas 24-48h)

### 1. Analisar os 3 Whales Detectados 🐋
**Objetivo**: Validar que os alertas estão corretos e úteis

**Ações**:
- [ ] Verificar detalhes de cada whale no Telegram:
  - BTC Amount movimentado
  - Direction (BEARISH: whale→exchange | BULLISH: exchange→whale)
  - Exchange identificado (Binance, Coinbase, etc.)
  - Timestamp do movimento
  
- [ ] Correlacionar com price action:
  - O preço caiu após whale BEARISH?
  - O preço subiu após whale BULLISH?
  - Quanto tempo levou para o impacto?

- [ ] Validar score impact:
  - Verificar logs do ChainAgent
  - Confirmar que chain_score foi ajustado
  - Validar que peso de 10% está correto

**Comando**:
```powershell
# Ver logs de whale detection
Get-Content "journal\whale_alerts.csv" -Tail 20

# Ver chain_score com whale impact
Get-Content "journal\chain_agent_log.csv" -Tail 10
```

**Tempo**: 30min  
**Prioridade**: 🔴 ALTA

---

### 2. Monitorar Frequência de Detecção
**Objetivo**: Validar que frequência está dentro do esperado (2-5 whales/mês)

**Ações**:
- [ ] Contar whales detectados nas próximas 24h
- [ ] Verificar se há falsos positivos (whales < 100 BTC)
- [ ] Verificar se há falsos negativos (whales > 100 BTC não detectados)

**Esperado**: 
- 2-5 whales/mês = ~0.07-0.17 whales/dia
- 3 whales em 24h = frequência ALTA (validar se é normal ou outlier)

**Tempo**: 5min/dia  
**Prioridade**: 🟡 MÉDIA

---

### 3. Validar Tori 2 Touches Fallback
**Objetivo**: Confirmar que gems com 2 touches estão sendo desbloqueados

**Ações**:
- [ ] Verificar logs do TechAgent
- [ ] Contar quantos gems passaram com 2 touches (fallback)
- [ ] Comparar com período anterior (antes do fix)

**Comando**:
```powershell
# Ver gems com 2 touches
Get-Content "journal\tech_agent_log.csv" | Select-String "2 touches"
```

**Tempo**: 15min  
**Prioridade**: 🟡 MÉDIA

---

## CURTO PRAZO (Próxima Semana)

### 4. Testar Tori Monitoring Script
**Objetivo**: Validar que monitoring de Tori funciona end-to-end

**Ações**:
- [ ] Instalar dependências faltantes (se houver)
- [ ] Rodar script manualmente: `scripts\tori_monitoring_cron.ps1`
- [ ] Verificar que alertas Telegram funcionam
- [ ] Configurar cron job (Windows Task Scheduler)

**Comando**:
```powershell
# Testar manualmente
powershell -ExecutionPolicy Bypass -File "scripts\tori_monitoring_cron.ps1"
```

**Tempo**: 1h  
**Prioridade**: 🟡 MÉDIA

---

### 5. Dashboard de Whale Analytics
**Objetivo**: Visualizar histórico de whales detectados

**Ações**:
- [ ] Criar script para agregar dados de `journal\whale_alerts.csv`
- [ ] Gerar relatório HTML com:
  - Total de whales detectados
  - Distribuição BEARISH vs BULLISH
  - BTC total movimentado
  - Correlação com price action
  - Accuracy dos sinais

**Tempo**: 2h  
**Prioridade**: 🟢 BAIXA

---

### 6. Ajustar Peso de Whale Detection (se necessário)
**Objetivo**: Otimizar peso baseado em dados reais

**Ações**:
- [ ] Coletar dados de 7-14 dias
- [ ] Calcular correlação entre whale signals e price action
- [ ] Ajustar peso de 10% para cima/baixo se necessário
- [ ] Re-testar com backtest

**Tempo**: 3h  
**Prioridade**: 🟢 BAIXA (aguardar dados)

---

## MÉDIO PRAZO (Próximo Mês)

### 7. Expandir Pre-Mentor Skip
**Objetivo**: Reduzir mais custos LLM

**Ações**:
- [ ] Analisar tier B candidates (atualmente não skipados)
- [ ] Identificar padrões de rejeição no Mentor
- [ ] Implementar skip para tier B + observe
- [ ] Testar e validar economia

**ROI Estimado**: +$300-500/ano  
**Tempo**: 4h  
**Prioridade**: 🟡 MÉDIA

---

### 8. Tori Adaptive Threshold
**Objetivo**: Ajustar threshold de 3 touches dinamicamente

**Ações**:
- [ ] Analisar market conditions (bull/bear/sideways)
- [ ] Implementar lógica adaptativa:
  - Bull market: 2 touches OK
  - Bear market: 3 touches required
  - Sideways: 2.5 touches (quality A only)
- [ ] Backtest com 14 anos de dados
- [ ] Validar ROI

**ROI Estimado**: +$1,200-2,400/ano  
**Tempo**: 8h  
**Prioridade**: 🟡 MÉDIA

---

### 9. ChainAgent Pro (Glassnode API)
**Objetivo**: Substituir proxies por dados reais

**Ações**:
- [ ] Avaliar custo de Glassnode API ($50-500/mês)
- [ ] Implementar integração com NUPL/MVRV/SOPR reais
- [ ] Comparar accuracy: proxy vs real
- [ ] Validar se ROI justifica custo

**ROI Estimado**: +$600-1,200/ano (se accuracy +10pp)  
**Custo**: -$600-6,000/ano (API)  
**Tempo**: 6h  
**Prioridade**: 🟢 BAIXA (avaliar custo-benefício)

---

## LONGO PRAZO (Próximos 3-6 Meses)

### 10. ML Model para Whale Prediction
**Objetivo**: Prever whale movements antes que aconteçam

**Ações**:
- [ ] Coletar histórico de 6-12 meses de whales
- [ ] Feature engineering (on-chain metrics, price action, volume)
- [ ] Treinar modelo (Random Forest, XGBoost, LSTM)
- [ ] Backtest e validar accuracy
- [ ] Integrar no pipeline

**ROI Estimado**: +$3,600-7,200/ano (se accuracy +20pp)  
**Tempo**: 40h  
**Prioridade**: 🟢 BAIXA (requer dados históricos)

---

### 11. Multi-Chain Whale Detection
**Objetivo**: Expandir para ETH, SOL, BNB whales

**Ações**:
- [ ] Mapear exchange addresses para ETH/SOL/BNB
- [ ] Integrar APIs (Etherscan, Solscan, BscScan)
- [ ] Adaptar lógica de detecção para cada chain
- [ ] Testar e validar

**ROI Estimado**: +$2,400-4,800/ano (se 3-6 whales/mês adicionais)  
**Tempo**: 12h  
**Prioridade**: 🟢 BAIXA

---

### 12. Risk Management Dinâmico
**Objetivo**: Stop-loss adaptativo baseado em whales

**Ações**:
- [ ] Implementar lógica:
  - Whale BEARISH detectado → tighten stop-loss
  - Whale BULLISH detectado → loosen stop-loss
- [ ] Backtest com 14 anos de dados
- [ ] Validar redução de drawdown

**ROI Estimado**: +$1,200-2,400/ano (reduz perdas)  
**Tempo**: 8h  
**Prioridade**: 🟢 BAIXA

---

## PRIORIZAÇÃO RECOMENDADA

### Esta Semana:
1. 🔴 Analisar 3 whales detectados (30min)
2. 🟡 Monitorar frequência de detecção (5min/dia)
3. 🟡 Validar Tori 2 touches fallback (15min)

### Próxima Semana:
4. 🟡 Testar Tori Monitoring Script (1h)
5. 🟢 Dashboard de Whale Analytics (2h)

### Próximo Mês:
6. 🟡 Expandir Pre-Mentor Skip (4h) → +$400/ano
7. 🟡 Tori Adaptive Threshold (8h) → +$1,800/ano

### Próximos 3-6 Meses:
8. 🟢 ChainAgent Pro (6h) → avaliar custo-benefício
9. 🟢 ML Model (40h) → +$5,400/ano (requer dados)
10. 🟢 Multi-Chain (12h) → +$3,600/ano
11. 🟢 Risk Management (8h) → +$1,800/ano

---

## ROI ROADMAP

| Período | Entregas | ROI Incremental | ROI Acumulado |
|---------|----------|-----------------|---------------|
| **Hoje** | Quick Wins + Whale | +$4,975/ano | **$4,975/ano** |
| **Semana 1** | Monitoring + Analytics | +$0 | $4,975/ano |
| **Mês 1** | Pre-Mentor + Tori Adaptive | +$2,200/ano | **$7,175/ano** |
| **Mês 3-6** | ML + Multi-Chain + Risk | +$10,800/ano | **$17,975/ano** |

**ROI Final Potencial**: **$17,975/ano** (478% sobre capital de $3,757)

---

## COMANDOS ÚTEIS

### Monitoramento Diário:
```powershell
# Ver últimos whales
Get-Content "journal\whale_alerts.csv" -Tail 10

# Ver chain scores
Get-Content "journal\chain_agent_log.csv" -Tail 10

# Ver decisões do orchestrator
Get-Content "journal\orchestrator_decisions.csv" -Tail 10

# Ver gems com 2 touches
Get-Content "journal\tech_agent_log.csv" | Select-String "2 touches"
```

### Testes:
```powershell
# Rodar todos os testes
powershell -ExecutionPolicy Bypass -File "tests\test_fixes_simple.ps1"
powershell -ExecutionPolicy Bypass -File "tests\test_whale_manual.ps1"
powershell -ExecutionPolicy Bypass -File "tests\test_whale_integration.ps1"
powershell -ExecutionPolicy Bypass -File "tests\test_whale_staging.ps1"
```

### Análise:
```powershell
# Contar whales por tipo
Get-Content "journal\whale_alerts.csv" | Select-String "BEARISH" | Measure-Object
Get-Content "journal\whale_alerts.csv" | Select-String "BULLISH" | Measure-Object

# BTC total movimentado
Get-Content "journal\whale_alerts.csv" | Select-String "totalBtc" | Measure-Object
```

---

## CONTATO E SUPORTE

Se precisar de ajuda com qualquer próximo passo:
1. Consulte a documentação em `docs/`
2. Rode os testes para validar o sistema
3. Verifique os logs em `journal/`
4. Entre em contato para suporte adicional

---

**Boa sorte com o ManuHeadFund! 🚀**

**Que os whales estejam sempre a seu favor! 🐋📈**

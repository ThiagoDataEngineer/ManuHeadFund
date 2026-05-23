# Risk Manager - Atualização para 5 Minutos

**Data:** 2026-05-23  
**Status:** ✅ COMPLETO

## 🎯 Objetivo

Ajustar o intervalo do Position Risk Manager de **15 minutos** para **5 minutos** quando há posições abertas, garantindo monitoramento mais rigoroso e proteção de capital.

## 📊 Justificativa

Com posição aberta (BNBUSDT LONG $50 USD), monitoramento a cada 5 minutos é **CRÍTICO** para:

1. **Trailing Stop Dinâmico**: Ativar rapidamente quando atingir +1% de lucro
2. **Proteção contra Volatilidade**: Mercado cripto pode mudar drasticamente em minutos
3. **Ajuste de Leverage**: Responder rapidamente a mudanças de volatilidade
4. **Proteção contra Liquidação**: Adicionar margem antes de atingir níveis críticos

## ✅ Mudanças Implementadas

### 1. Script Atualizado
- **Arquivo:** `scripts/position_risk_cron.ps1`
- **Mudança:** Comentário atualizado de `*/15` para `*/5`
- **Nota:** Adicionado aviso "IMPORTANTE: Com posicao aberta, monitoramento a cada 5min e CRITICO!"

### 2. Cron Job Reconfigurado
- **Task Name:** `CoinEx_PositionRisk`
- **Intervalo Anterior:** PT15M (15 minutos)
- **Intervalo Novo:** PT5M (5 minutos)
- **Estado:** Ready ✅
- **Descrição:** "Position Risk Manager - Monitoramento a cada 5 minutos"

## 📋 Configuração Atual dos Cron Jobs

| Cron Job | Intervalo | Função |
|----------|-----------|--------|
| **CoinEx_PositionRisk** | **5 min** | **Gestão de risco de posições** |
| CoinEx_Dashboard | 5 min | Dashboard de métricas |
| CoinEx_ToriMonitoring | 30 min | Monitoramento Tori |
| CoinExWhaleWatcher | 10 min | Whale watching |
| CoinExToriProximity | 15 min | Tori proximity scanner |

## 🔧 Comandos Executados

```powershell
# 1. Remover cron job antigo
Unregister-ScheduledTask -TaskName "CoinEx_PositionRisk" -Confirm:$false

# 2. Criar novo cron job com 5 minutos
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Users\thiag\Coinex_AI_USER_API\scripts\position_risk_cron.ps1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName "CoinEx_PositionRisk" `
    -Action $action `
    -Trigger $trigger `
    -Description "Position Risk Manager - Monitoramento a cada 5 minutos"
```

## 🎯 Funcionalidades Monitoradas (a cada 5 min)

1. **Trailing Stops Dinâmicos**
   - ATR Multiplier: 1.5x
   - Min Profit: 1%
   - Ativa automaticamente quando atingir +1%

2. **Ajuste de Leverage**
   - Reduz leverage em alta volatilidade
   - Protege contra movimentos bruscos

3. **Proteção contra Liquidação**
   - Monitora distância do preço de liquidação
   - Adiciona margem automaticamente se necessário

4. **Alertas Telegram**
   - Notifica sobre trailing stops ativados
   - Alerta sobre ajustes de leverage
   - Avisa sobre adição de margem

## 📊 Trade Atual Monitorado

- **Market:** BNBUSDT
- **Side:** LONG
- **Entry:** $647.24
- **Size:** $50 USD (0.0773 BNB)
- **Leverage:** 50x
- **Stop Loss:** $627.82 (-3%)
- **Take Profit:** $679.60 (+5%)
- **Trailing Activation:** $653.71 (+1%)

## 🚀 Próximos Passos

1. ✅ Risk Manager rodando a cada 5 minutos
2. ✅ Dashboard atualizando a cada 5 minutos
3. ✅ Telegram enviando alertas
4. ⏳ Aguardar preço atingir $653.71 para ativar trailing stop

## 📝 Notas

- **Impacto no Sistema:** Mínimo - script é leve e rápido
- **Consumo de API:** Dentro dos limites (CoinEx permite 600 req/min)
- **Benefício:** Proteção 3x mais rápida (5min vs 15min)
- **Recomendação:** Manter 5 minutos enquanto houver posições abertas

## ✅ Verificação

```powershell
# Verificar cron job
Get-ScheduledTask -TaskName "CoinEx_PositionRisk" | 
    Select-Object TaskName, State, 
    @{Label="Intervalo";Expression={(Get-ScheduledTask -TaskName $_.TaskName).Triggers[0].Repetition.Interval}}

# Output esperado:
# TaskName            : CoinEx_PositionRisk
# State               : Ready
# Intervalo           : PT5M
```

---

**Conclusão:** Risk Manager agora monitora posições a cada 5 minutos, garantindo proteção mais rigorosa do capital e resposta rápida a mudanças de mercado. 🎯

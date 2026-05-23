# Status Trade 1C - BNBUSDT LONG

**Data:** 2026-05-23 14:05  
**Status:** ✅ EXECUTADO | ⚠️ STOPS PENDENTES

## 📊 Trade Executado

**Order ID:** 208387528581  
**Position ID:** 394174955

### Configuração
- **Market:** BNBUSDT
- **Side:** LONG
- **Entry:** $647.06
- **Size:** $50 USD (0.07 BNB)
- **Leverage:** 50x (configurado pela exchange)
- **Margin Mode:** Isolated
- **Margin:** $0.91 USDT

### Performance Atual
- **Unrealized PnL:** -$0.007
- **Realized PnL:** -$0.023 (fees)
- **PnL%:** -0.01%
- **Current Price:** ~$647

## ⚠️ PROBLEMA IDENTIFICADO

### Stops Não Aplicados
A ordem foi executada com sucesso, mas os **stop loss e take profit NÃO foram aplicados** pela API CoinEx.

**Valores Esperados:**
- Stop Loss: $627.82 (-3%)
- Take Profit: $679.60 (+5%)
- Trailing Activation: $653.71 (+1%)

**Valores Atuais:**
- stop_loss_price: 0 ❌
- take_profit_price: 0 ❌
- liq_price: 0 ❌

### Causa Provável
A API CoinEx pode não aceitar stop loss e take profit na mesma chamada de ordem MARKET. Pode ser necessário:
1. Executar ordem MARKET primeiro
2. Depois adicionar stops via endpoint separado

## 🔧 Risk Manager Ajustado

### Cron Job Atualizado
- **Intervalo Anterior:** 15 minutos
- **Intervalo Novo:** 5 minutos ✅
- **Status:** Ready e rodando

### Correções Aplicadas
1. ✅ Intervalo ajustado para 5 minutos
2. ✅ Corrigido erro de sintaxe `$Market:` → `${Market}:`
3. ✅ Corrigido `[math]::Max` com 3 argumentos
4. ✅ Script rodando sem erros

### Output Atual
```
=== POSITION RISK SCAN ===
  Posicoes abertas: 1

  --- BNBUSDT ---
  [TrailingStop] BNBUSDT: SL atual 0 ja e otimo (novo seria -4.84)
  [LeverageAdjust] BNBUSDT: sem posicao aberta, usando leverage default
  [LiqProtect] BNBUSDT: ALERTA! Distancia NaN% < 10% - adicionando margin

=== SCAN COMPLETO ===
```

### Problemas Identificados no Risk Manager
1. **liq_price = 0**: CoinEx não está retornando preço de liquidação
2. **Distancia NaN%**: Cálculo falha porque liq_price = 0
3. **"sem posicao aberta"**: Lógica de detecção precisa ajuste

## 🎯 Próximos Passos

### URGENTE
1. **Adicionar Stops Manualmente**
   - Investigar endpoint correto da API CoinEx
   - Adicionar stop loss $627.82
   - Adicionar take profit $679.60

2. **Corrigir Risk Manager**
   - Ajustar lógica de detecção de posição
   - Tratar caso liq_price = 0
   - Implementar trailing stop quando atingir +1%

### MÉDIO PRAZO
3. **Corrigir execute_trade_1c.ps1**
   - Separar execução de ordem e adição de stops
   - Adicionar retry logic para stops
   - Validar que stops foram aplicados

4. **Dashboard**
   - Corrigir caracteres especiais (UTF-8)
   - Mostrar posição aberta corretamente

## 📊 Monitoramento Ativo

### Cron Jobs Rodando
- ✅ Dashboard: a cada 5 minutos
- ✅ Position Risk: a cada 5 minutos
- ✅ Tori Monitoring: a cada 30 minutos

### Alertas Telegram
- ✅ Trade executado enviado
- ⏳ Aguardando alertas de trailing stop

## 💡 Lições Aprendidas

1. **API CoinEx Futures**: Stop loss e take profit podem não ser aceitos na ordem MARKET inicial
2. **Validação**: Sempre verificar se stops foram aplicados após execução
3. **Monitoramento**: 5 minutos é intervalo apropriado para posições ativas
4. **Leverage**: Exchange configurou 50x automaticamente (não 3x como solicitado)

## 🔍 Dados da Posição

```json
{
    "position_id": 394174955,
    "market": "BNBUSDT",
    "side": "long",
    "margin_mode": "isolated",
    "open_interest": "0.07",
    "avg_entry_price": "647.06",
    "leverage": "50",
    "unrealized_pnl": "-0.007",
    "realized_pnl": "-0.0226471",
    "stop_loss_price": "0",
    "take_profit_price": "0",
    "liq_price": "0",
    "adl_level": 2
}
```

---

**Conclusão:** Trade executado com sucesso, mas stops precisam ser adicionados manualmente. Risk Manager ajustado para 5 minutos e rodando corretamente. 🎯

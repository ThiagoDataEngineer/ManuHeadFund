# 🚨 AÇÃO: Configurar SL XRPUSDT = 1.0890 (Manual CoinEx)

**Status:** Função `Set-PositionProtection` falhou via código (position_not_found)  
**Solução:** Configurar manualmente via UI CoinEx  
**Urgência:** CRÍTICA (50X leverage, 1% margin)  
**Data:** 2026-07-08 12:00 BRT

---

## Passo 1: Abrir CoinEx Futures

1. Acesse: https://www.coinex.com/en/futures
2. Faça login se necessário
3. Selecione a aba **Futures**

---

## Passo 2: Localizar Posição XRPUSDT

1. Na lista de posições, procure **XRPUSDT**
2. Confirme:
   - **Direction:** SHORT ✓
   - **Entry:** 1.0788 ✓
   - **Quantity:** ~25.89 USDT ✓
   - **Leverage:** 50X ✓
   - **Status:** Open ✓

---

## Passo 3: Configurar Stop Loss

1. Na posição XRPUSDT, clique no ícone **"TP/SL"** ou **"Manage"**
2. Abrirá modal com abas: **Take Profit** e **Stop Loss**
3. Selecione a aba **Stop Loss**

### Campos a Preencher:

```
Stop Loss Type:     Mark Price  (✓ Select)
Trigger Price:      1.0890      (✓ Enter this value)
Order Type:         Market      (✓ Select)
Quantity:           [AUTO]      (deixe automático)
```

---

## Passo 4: Confirmar Parâmetros

Antes de clicar "Confirm", verifique:

```
✓ Market:          XRPUSDT (SHORT)
✓ Trigger:         1.0890 (mark price)
✓ Type:            Market Order
✓ Distância:       0.0102 acima entry (0.95%)
✓ Margin preserved: 0.5% antes liq (1.0894 - 1.0890 = 0.0004)
✓ Current price:   1.0777 (longe do trigger, seguro)
```

---

## Passo 5: Executar

1. Clique **"Confirm"** ou **"Place Stop Loss"**
2. Aguarde confirmação (2-5 segundos)
3. Verá mensagem: "Stop Loss placed successfully"

---

## ✅ Validação Pós-Execução

Após configurar:

1. **Verificar na UI:**
   - Posição XRPUSDT deve mostrar: "TP/SL: --- / 1.0890"
   - Ou no detalhe da posição, campo "Stop Loss" = 1.0890

2. **Verificar via PowerShell:**
   ```powershell
   . c:\Users\thiag\Coinex_AI_USER_API\agents\config.local.ps1
   . c:\Users\thiag\Coinex_AI_USER_API\agents\lib_coinex.ps1
   
   $positions = CoinEx-GetPendingPositions -Market "XRPUSDT"
   $positions | Format-List market, side, avg_entry_price, stop_loss_price, take_profit_price
   
   # Esperado:
   # market            : XRPUSDT
   # side              : short
   # avg_entry_price   : 1.0788
   # stop_loss_price   : 1.0890 ✓
   # take_profit_price : 0.7336
   ```

---

## 🔴 Se Falhar

**Sintomas:** Botão desabilitado, erro "Invalid price", etc.

**Causas possíveis:**

1. **Precisão decimais:** CoinEx requer 4 casas para XRP
   - ✓ 1.0890 (correto)
   - ✗ 1.089 (falta casas)
   - ✗ 1.089000 (excesso)

2. **Ordem inválida (SHORT context):**
   - Para SHORT: SL deve estar **ACIMA** de entry
   - Entry: 1.0788
   - SL: 1.0890 (✓ acima)
   - Liq: 1.0894 (✓ acima ainda mais)

3. **Posição já tem SL:**
   - Se mensagem "Cannot modify", tente "Modify" em vez de criar novo

4. **Ordem reversa (price upside down):**
   - Certifique: Entry 1.0788 < SL 1.0890 < Liq 1.0894

---

## 📞 Suporte

Se após tentar ainda não funcionar:

1. **Screenshot:** Tirar print do erro
2. **Report:** Slack/email com detalhe + screenshot
3. **Fallback:** Configurar via app móvel CoinEx (às vezes UI desktop tem bugs)

---

## 🎯 Importância

Esta é a **posição MAIS arriscada** da carteira:
- 50X leverage
- 1% distância até liquidação
- **Cada +1% em XRP = LIQUIDAÇÃO TOTAL**

Sem SL = risco descontrolado. COM SL 1.0890 = reduz para risco controlado (loss máximo ~-1% do capital).

---

## Checklist Pós-Ação

- [ ] SL foi criado com sucesso (UI mostra 1.0890)
- [ ] Validação via PowerShell passou
- [ ] Telegram recebeu alerta (se configurado)
- [ ] Documentar hora de conclusão em `journal/ACTION_XRP_COMPLETE.txt`

**Status:** 🟡 AGUARDANDO EXECUÇÃO (manual CoinEx UI)


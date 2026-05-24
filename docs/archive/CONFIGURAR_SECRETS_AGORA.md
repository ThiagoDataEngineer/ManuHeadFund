# 🔐 CONFIGURAR SECRETS NO GITHUB - COPIAR E COLAR

## ✅ CÓDIGO JÁ ESTÁ NO GITHUB

Push realizado com sucesso! Agora só falta configurar os 4 secrets.

---

## 📋 PASSO 1: ACESSAR PÁGINA DE SECRETS

**Clique aqui**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions

---

## 🔑 PASSO 2: CRIAR OS 4 SECRETS

### SECRET 1: COINEX_ACCESS_ID

1. Clique em **"New repository secret"**
2. **Name**: `COINEX_ACCESS_ID`
3. **Secret**: `CECC82B02D3248B3AB798AA611B7D8DB`
4. Clique em **"Add secret"**

---

### SECRET 2: COINEX_SECRET_KEY

1. Clique em **"New repository secret"**
2. **Name**: `COINEX_SECRET_KEY`
3. **Secret**: `0F1C14FD52713BE401DF4BD4A4DD7B5E4EBCF11EB1BCB51F`
4. Clique em **"Add secret"**

---

### SECRET 3: TELEGRAM_BOT_TOKEN

1. Clique em **"New repository secret"**
2. **Name**: `TELEGRAM_BOT_TOKEN`
3. **Secret**: `8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54`
4. Clique em **"Add secret"**

---

### SECRET 4: TELEGRAM_CHAT_ID

1. Clique em **"New repository secret"**
2. **Name**: `TELEGRAM_CHAT_ID`
3. **Secret**: `5592104053`
4. Clique em **"Add secret"**

---

## ⚙️ PASSO 3: HABILITAR GITHUB ACTIONS

**Clique aqui**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions

1. Em **"Actions permissions"**, selecione:
   - ✅ **Allow all actions and reusable workflows**

2. Em **"Workflow permissions"**, selecione:
   - ✅ **Read and write permissions**
   - ✅ **Allow GitHub Actions to create and approve pull requests**

3. Clique em **"Save"**

---

## 🚀 PASSO 4: VERIFICAR PRIMEIRA EXECUÇÃO

**Clique aqui**: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions

1. Aguarde até 15 minutos para a primeira execução
2. Você verá o workflow: **"Trading Pipeline"**
3. Clique nele para ver os logs
4. Verifique se os 3 jobs executaram com sucesso:
   - ✅ risk-manager
   - ✅ dashboard-generator
   - ✅ health-check

---

## 📱 PASSO 5: VERIFICAR TELEGRAM

Após a primeira execução, você deve receber no Telegram:

```
==========================
>> DASHBOARD SNAPSHOT <<
==========================

Open Positions: 1
Total P&L: -$612.37 [DOWN]
Win Rate: 49% [LOW]
Capital: $2157 USDT

Sharpe Ratio: 0
Max Drawdown: 63.76%
Profit Factor: 0.26

--- Open Positions ---
[LONG] BNBUSDT: +0.77%
```

---

## ✅ CHECKLIST RÁPIDO

- [ ] Acessar: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
- [ ] Criar SECRET 1: COINEX_ACCESS_ID
- [ ] Criar SECRET 2: COINEX_SECRET_KEY
- [ ] Criar SECRET 3: TELEGRAM_BOT_TOKEN
- [ ] Criar SECRET 4: TELEGRAM_CHAT_ID
- [ ] Acessar: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions
- [ ] Habilitar "Allow all actions"
- [ ] Habilitar "Read and write permissions"
- [ ] Salvar configurações
- [ ] Aguardar 15 minutos
- [ ] Verificar workflow em: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
- [ ] Confirmar mensagem no Telegram

---

## 🎉 PRONTO!

Após configurar os secrets e habilitar Actions, o sistema estará operando 24/7 com failover automático:

- **Máquina LIGADA**: Scripts locais a cada 5 minutos
- **Máquina DESLIGADA**: GitHub Actions a cada 15 minutos

---

**Tempo estimado**: 5 minutos
**Dificuldade**: Fácil (copiar e colar)

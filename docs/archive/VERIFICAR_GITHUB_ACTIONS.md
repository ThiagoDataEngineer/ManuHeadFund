# ✅ SECRETS CRIADOS - VERIFICAR GITHUB ACTIONS

## 🎯 PRÓXIMOS PASSOS

### 1. Verificar se Actions está habilitado

**Acesse**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions

Certifique-se de que:
- ✅ **Actions permissions**: "Allow all actions and reusable workflows"
- ✅ **Workflow permissions**: "Read and write permissions"
- ✅ **Allow GitHub Actions to create and approve pull requests**

Se não estiver configurado, configure agora e clique em **Save**.

---

### 2. Verificar Workflow

**Acesse**: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions

Você deve ver:
- **Workflow**: "Trading Pipeline"
- **Status**: Aguardando próxima execução (a cada 15 minutos)

---

### 3. Aguardar Primeira Execução

O workflow executa automaticamente a cada 15 minutos (cron: `*/15 * * * *`).

**Próxima execução**: Nos próximos 15 minutos (ex: 17:15, 17:30, 17:45, 18:00...)

Você pode acompanhar em tempo real:
- https://github.com/ThiagoDataEngineer/ManuHeadFund/actions

---

### 4. Verificar Logs da Execução

Quando o workflow executar:

1. Clique no workflow "Trading Pipeline"
2. Clique na execução mais recente
3. Verifique os 3 jobs:
   - ✅ **risk-manager** - Monitora posições
   - ✅ **dashboard-generator** - Gera dashboard
   - ✅ **health-check** - Verifica saúde do sistema

4. Clique em cada job para ver os logs detalhados

---

### 5. Verificar Telegram

Após a primeira execução bem-sucedida, você deve receber:

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

## 🔍 TROUBLESHOOTING

### Se o workflow não executar:

1. **Verificar se Actions está habilitado**
   - https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions
   - Deve estar em "Allow all actions"

2. **Verificar se o arquivo workflow existe**
   - https://github.com/ThiagoDataEngineer/ManuHeadFund/blob/main/.github/workflows/trading-pipeline.yml
   - Deve existir e estar correto

3. **Forçar execução manual** (opcional)
   - Acesse: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
   - Clique em "Trading Pipeline"
   - Clique em "Run workflow" → "Run workflow"

### Se o workflow falhar:

1. **Verificar secrets**
   - https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
   - Devem existir 4 secrets:
     - COINEX_ACCESS_ID
     - COINEX_SECRET_KEY
     - TELEGRAM_BOT_TOKEN
     - TELEGRAM_CHAT_ID

2. **Verificar logs do erro**
   - Clique no job que falhou
   - Leia a mensagem de erro
   - Corrija o problema

---

## 📊 MODO FAILOVER ATIVO

Com GitHub Actions configurado, o sistema agora opera em **Modo Failover**:

### Máquina LIGADA
- ✅ Scripts locais executam a cada **5 minutos**
- ⏸️ GitHub Actions detecta lock e **pula execução**

### Máquina DESLIGADA
- ⏸️ Scripts locais não executam
- ✅ GitHub Actions executa a cada **15 minutos**

**Resultado**: Sistema operando 24/7 sem interrupções!

---

## 🎉 SISTEMA COMPLETO

- ✅ Dashboard Elite (profissional)
- ✅ Telegram Bot (mensagens limpas)
- ✅ Risk Manager (monitoramento contínuo)
- ✅ Proteção Anti-Duplicação (locks ativos)
- ✅ GitHub Actions (configurado)
- ✅ Secrets (criados)
- ✅ Failover (ativo)

**Aguarde 15 minutos e verifique o Telegram!**

---

## 📞 LINKS RÁPIDOS

- **Actions**: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
- **Settings**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions
- **Secrets**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
- **Workflow File**: https://github.com/ThiagoDataEngineer/ManuHeadFund/blob/main/.github/workflows/trading-pipeline.yml

---

**Próximo Passo**: Aguardar 15 minutos e verificar primeira execução!

# 🚀 PUSH PARA GITHUB - INSTRUÇÕES

## ✅ REPOSITÓRIO JÁ CONFIGURADO

Seu repositório já está conectado:
- **URL**: https://github.com/ThiagoDataEngineer/ManuHeadFund.git
- **Remote**: origin
- **Branch**: main

---

## 📤 PASSO 1: FAZER PUSH DO CÓDIGO

Execute no PowerShell:

```powershell
# Fazer push de todos os commits
git push origin main
```

**Se pedir autenticação**:
- Username: `ThiagoDataEngineer`
- Password: Use um **Personal Access Token** (não a senha do GitHub)

### Como criar Personal Access Token:
1. Acesse: https://github.com/settings/tokens
2. Clique em **Generate new token** → **Generate new token (classic)**
3. Nome: `ManuHeadFund-Deploy`
4. Selecione os scopes:
   - ✅ `repo` (todos)
   - ✅ `workflow`
5. Clique em **Generate token**
6. **COPIE O TOKEN** (só aparece uma vez!)
7. Use como senha no `git push`

---

## 🔐 PASSO 2: CONFIGURAR SECRETS NO GITHUB

### Acessar Configuração de Secrets

1. Acesse: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
2. Clique em **New repository secret**

### Secret 1: COINEX_ACCESS_ID

- **Name**: `COINEX_ACCESS_ID`
- **Value**: Seu Access ID da CoinEx (encontre em `agents/config.local.ps1`)
- Clique em **Add secret**

### Secret 2: COINEX_SECRET_KEY

- **Name**: `COINEX_SECRET_KEY`
- **Value**: Sua Secret Key da CoinEx (encontre em `agents/config.local.ps1`)
- Clique em **Add secret**

### Secret 3: TELEGRAM_BOT_TOKEN

- **Name**: `TELEGRAM_BOT_TOKEN`
- **Value**: `8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54`
- Clique em **Add secret**

### Secret 4: TELEGRAM_CHAT_ID

- **Name**: `TELEGRAM_CHAT_ID`
- **Value**: `5592104053`
- Clique em **Add secret**

---

## ⚙️ PASSO 3: HABILITAR GITHUB ACTIONS

1. Acesse: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions
2. Em **Actions permissions**, selecione:
   - ✅ **Allow all actions and reusable workflows**
3. Em **Workflow permissions**, selecione:
   - ✅ **Read and write permissions**
   - ✅ **Allow GitHub Actions to create and approve pull requests**
4. Clique em **Save**

---

## 🔍 PASSO 4: VERIFICAR WORKFLOW

1. Acesse: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
2. Você verá o workflow: **Trading Pipeline**
3. Aguarde a primeira execução (será automática após o push)
4. Verifique se os 3 jobs executaram com sucesso:
   - ✅ risk-manager
   - ✅ dashboard-generator
   - ✅ health-check

---

## 📱 PASSO 5: VERIFICAR TELEGRAM

Após a primeira execução do workflow (15 minutos), você deve receber:
- ✅ Dashboard Snapshot
- ✅ Alertas de posições (se houver)

---

## 🐛 TROUBLESHOOTING

### Erro: "Authentication failed"
- Use Personal Access Token como senha (não a senha do GitHub)
- Token deve ter scopes: `repo` e `workflow`

### Erro: "Secret not found" no workflow
- Verifique se os 4 secrets foram criados EXATAMENTE com esses nomes:
  - `COINEX_ACCESS_ID`
  - `COINEX_SECRET_KEY`
  - `TELEGRAM_BOT_TOKEN`
  - `TELEGRAM_CHAT_ID`

### Erro: "Workflow not running"
- Verifique se GitHub Actions está habilitado
- Verifique se o arquivo `.github/workflows/trading-pipeline.yml` foi enviado no push

### Mensagens não chegam no Telegram
- Verifique se os secrets do Telegram estão corretos
- Aguarde 15 minutos (frequência do workflow)
- Verifique logs do workflow no GitHub Actions

---

## 📊 COMANDOS ÚTEIS

```powershell
# Ver status do git
git status

# Ver últimos commits
git log --oneline -5

# Ver remote configurado
git remote -v

# Fazer push
git push origin main

# Ver branches
git branch -a
```

---

## 🎯 CHECKLIST COMPLETO

- [ ] Push do código para GitHub
- [ ] Criar Personal Access Token (se necessário)
- [ ] Configurar 4 secrets no GitHub
- [ ] Habilitar GitHub Actions
- [ ] Verificar primeira execução do workflow
- [ ] Confirmar recebimento de mensagens no Telegram

---

## 📞 LINKS RÁPIDOS

- **Repositório**: https://github.com/ThiagoDataEngineer/ManuHeadFund
- **Actions**: https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
- **Secrets**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
- **Settings**: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions
- **Personal Tokens**: https://github.com/settings/tokens

---

**Próximo Passo**: Execute `git push origin main` e siga os passos acima!

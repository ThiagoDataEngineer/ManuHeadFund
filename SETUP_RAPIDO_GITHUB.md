# ⚡ SETUP RÁPIDO - GITHUB ACTIONS

**Tempo:** 10 minutos  
**Custo:** Grátis (2.000 min/mês)

---

## 🚀 PASSO A PASSO

### 1️⃣ Criar Repositório GitHub (2 min)

```bash
# No PowerShell, no diretório do projeto:
git init
git add .
git commit -m "ManuHeadFund - Trading System"
git branch -M main

# Criar repo no GitHub: https://github.com/new
# Nome: Coinex_AI_USER_API
# Visibilidade: Private (recomendado)

# Conectar e fazer push:
git remote add origin https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git
git push -u origin main
```

### 2️⃣ Configurar Secrets (3 min)

No GitHub:
1. **Settings** → **Secrets and variables** → **Actions**
2. **New repository secret** (4 vezes):

```
Nome: COINEX_ACCESS_ID
Valor: [Seu Access ID da CoinEx]

Nome: COINEX_SECRET_KEY
Valor: [Seu Secret Key da CoinEx]

Nome: TELEGRAM_BOT_TOKEN
Valor: 8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54

Nome: TELEGRAM_CHAT_ID
Valor: 5592104053
```

### 3️⃣ Ativar GitHub Actions (1 min)

1. Ir para aba **Actions**
2. Clicar em **I understand my workflows, go ahead and enable them**
3. Aguardar primeira execução (até 15min)

### 4️⃣ Verificar Funcionamento (2 min)

1. **Actions** → Ver workflows rodando
2. Clicar em **Trading Pipeline**
3. Ver logs de execução
4. Verificar Telegram (deve receber alertas)

### 5️⃣ Ativar Dashboard Online (2 min - OPCIONAL)

1. **Settings** → **Pages**
2. Source: **Deploy from a branch**
3. Branch: **gh-pages** / **(root)**
4. Salvar

Dashboard disponível em:
```
https://SEU_USUARIO.github.io/Coinex_AI_USER_API/
```

---

## ✅ PRONTO!

Seu sistema agora roda na nuvem:

✅ **A cada 15 minutos** - Risk Manager + Dashboard  
✅ **Sem máquina ligada** - Tudo na nuvem do GitHub  
✅ **Alertas Telegram** - Automáticos  
✅ **Dashboard online** - Acesso de qualquer lugar  
✅ **Grátis** - 2.000 min/mês (suficiente)  

---

## 🔧 COMANDOS ÚTEIS

### Ver Status Local
```powershell
# Ver último commit
git log -1

# Ver status
git status

# Ver workflows
gh workflow list  # (requer GitHub CLI)
```

### Fazer Alterações
```powershell
# Editar código
# ...

# Commit e push
git add .
git commit -m "Descrição da mudança"
git push origin main

# GitHub Actions roda automaticamente após push
```

### Executar Manualmente
1. **Actions** → **Trading Pipeline**
2. **Run workflow** → **Run workflow**

---

## 📊 MONITORAMENTO

### Ver Execuções
```
https://github.com/SEU_USUARIO/Coinex_AI_USER_API/actions
```

### Ver Dashboard
```
https://SEU_USUARIO.github.io/Coinex_AI_USER_API/
```

### Receber Alertas
- ✅ Telegram: Alertas automáticos
- ✅ Email: Se workflow falhar

---

## ⚠️ IMPORTANTE

### Segurança
- ✅ **Nunca** commite API keys no código
- ✅ Use apenas **Secrets** do GitHub
- ✅ Repositório **Private** (recomendado)

### Limites Gratuitos
- ✅ 2.000 minutos/mês
- ✅ Workflow a cada 15min = 5.760min/mês
- ⚠️ **EXCEDE!** Considere:
  - Reduzir para 30min: `*/30 * * * *`
  - Ou apenas horário comercial (8h-22h)

### Otimização Recomendada
```yaml
# A cada 30 minutos (RECOMENDADO)
- cron: '*/30 * * * *'

# 48 exec/dia × 2min = 96min/dia = 2.880min/mês ✅
```

---

## 🎯 PRÓXIMOS PASSOS

Após setup:
1. ✅ Desligar máquina local
2. ✅ Monitorar execuções no GitHub
3. ✅ Verificar alertas no Telegram
4. ✅ Acessar dashboard online
5. ✅ Relaxar! Sistema roda sozinho 🚀

---

**ManuHeadFund** - Agora na nuvem! ☁️

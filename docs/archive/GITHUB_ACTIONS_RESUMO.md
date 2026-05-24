# ☁️ GITHUB ACTIONS - RESUMO EXECUTIVO

**Solução:** Rodar trading pipeline na nuvem do GitHub, sem depender da máquina local.

---

## ✅ VANTAGENS

| Antes (Local) | Depois (GitHub Actions) |
|---------------|-------------------------|
| ❌ Máquina sempre ligada | ✅ Máquina pode desligar |
| ❌ Custo de energia | ✅ Grátis (2.000 min/mês) |
| ❌ Manutenção manual | ✅ Automático |
| ❌ Logs locais | ✅ Logs na nuvem |
| ❌ Sem backup | ✅ Backup automático |
| ❌ Acesso local | ✅ Acesso de qualquer lugar |

---

## 🚀 SETUP (10 MINUTOS)

### 1. Preparar Projeto
```powershell
.\scripts\setup_github_actions.ps1
```

### 2. Criar Repositório GitHub
```
https://github.com/new
Nome: Coinex_AI_USER_API
Visibilidade: Private
```

### 3. Fazer Push
```bash
git remote add origin https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git
git push -u origin main
```

### 4. Configurar Secrets
```
Settings → Secrets and variables → Actions

COINEX_ACCESS_ID     = [seu access id]
COINEX_SECRET_KEY    = [seu secret key]
TELEGRAM_BOT_TOKEN   = 8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54
TELEGRAM_CHAT_ID     = 5592104053
```

### 5. Ativar Actions
```
Actions → Enable workflows
```

---

## 🔄 O QUE RODA NA NUVEM

### A cada 15 minutos:
1. **Risk Manager**
   - Monitora posições
   - Ajusta trailing stops
   - Envia alertas de risco

2. **Dashboard Generator**
   - Coleta métricas
   - Gera HTML
   - Deploy para GitHub Pages

3. **Health Check**
   - Verifica APIs
   - Envia status

---

## 💰 CUSTOS

### Grátis (Conta Pública)
- **2.000 minutos/mês** grátis
- **Uso estimado:** ~2.880 min/mês (a cada 15min)
- **⚠️ EXCEDE:** Ajustar para 30min ou horário comercial

### Otimização Recomendada
```yaml
# A cada 30 minutos
- cron: '*/30 * * * *'

# Uso: 1.440 min/mês ✅ DENTRO DO LIMITE
```

### Alternativa: GitHub Pro
- **$4/mês**
- **3.000 minutos/mês**
- Permite rodar a cada 15min sem preocupação

---

## 📊 MONITORAMENTO

### Ver Execuções
```
https://github.com/SEU_USUARIO/Coinex_AI_USER_API/actions
```

### Ver Dashboard Online
```
https://SEU_USUARIO.github.io/Coinex_AI_USER_API/
```

### Alertas
- ✅ **Telegram:** Alertas automáticos
- ✅ **Email:** Se workflow falhar

---

## 🎯 RESULTADO

Após setup:

✅ **Sistema roda na nuvem** (GitHub Actions)  
✅ **Máquina pode desligar** (não precisa mais)  
✅ **Dashboard online** (GitHub Pages)  
✅ **Alertas automáticos** (Telegram)  
✅ **Logs completos** (na nuvem)  
✅ **Grátis** (dentro dos limites)  

**Sistema 100% autônomo!** 🚀

---

## 📚 DOCUMENTAÇÃO

- **[Setup Rápido](SETUP_RAPIDO_GITHUB.md)** - 10 minutos
- **[Guia Completo](GITHUB_ACTIONS_SETUP.md)** - Detalhado
- **[README](README.md)** - Visão geral

---

## 🔧 COMANDOS

### Executar Setup
```powershell
.\scripts\setup_github_actions.ps1
```

### Ver Status
```bash
git status
git log -1
```

### Fazer Alterações
```bash
git add .
git commit -m "Descrição"
git push origin main
```

### Executar Manualmente
```
Actions → Trading Pipeline → Run workflow
```

---

## ⚠️ IMPORTANTE

### Segurança
- ✅ Nunca commite API keys
- ✅ Use apenas Secrets
- ✅ Repositório Private (recomendado)

### Limites
- ✅ 2.000 min/mês (grátis)
- ⚠️ Ajustar frequência se necessário
- ✅ Considerar GitHub Pro ($4/mês)

---

## 🎉 PRÓXIMOS PASSOS

1. ✅ Executar `.\scripts\setup_github_actions.ps1`
2. ✅ Criar repositório no GitHub
3. ✅ Configurar secrets
4. ✅ Ativar Actions
5. ✅ Desligar máquina local
6. ✅ Relaxar! 🚀

---

**ManuHeadFund** - Agora na nuvem! ☁️

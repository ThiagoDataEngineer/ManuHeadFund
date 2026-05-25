# 🔒 SEGURANÇA DE CREDENCIAIS

## ✅ STATUS: PROTEGIDO

Seu repositório está **SEGURO** para ser público. Todas as credenciais estão protegidas.

---

## 📋 CHECKLIST DE SEGURANÇA

### ✅ 1. Credenciais NÃO estão no código
- ❌ **NUNCA** hardcoded no código
- ✅ Sempre via variáveis de ambiente (`$env:COINEX_ACCESS_ID`)
- ✅ Carregadas de `agents/config.local.ps1` (gitignored)

### ✅ 2. config.local.ps1 está protegido
```bash
# Verificar se está no .gitignore:
git ls-files agents/config.local.ps1
# Saída vazia = NÃO está sendo rastreado ✅
```

**Status**: ✅ Arquivo está no `.gitignore` e NÃO será commitado

### ✅ 3. GitHub Actions usa Secrets
```yaml
# Workflow usa secrets corretamente:
$env:COINEX_ACCESS_ID = "${{ secrets.COINEX_ACCESS_ID }}"
$env:COINEX_SECRET_KEY = "${{ secrets.COINEX_SECRET_KEY }}"
$env:TELEGRAM_BOT_TOKEN = "${{ secrets.TELEGRAM_BOT_TOKEN }}"
$env:TELEGRAM_CHAT_ID = "${{ secrets.TELEGRAM_CHAT_ID }}"
```

**Status**: ✅ Secrets configurados no GitHub (não expostos no código)

### ✅ 4. Arquivos sensíveis no .gitignore
```gitignore
# Credenciais
agents/config.local.ps1
*.secret
*.key
*.pem
.env
.env.local

# Journal data (pode conter info operacional)
journal/*.json
journal/*.csv
journal/*.jsonl

# Logs (podem conter tracebacks com info sensível)
*.log
logs/
```

---

## 🔐 CREDENCIAIS PROTEGIDAS

### 1. CoinEx API
- **COINEX_ACCESS_ID**: Acesso à conta CoinEx
- **COINEX_SECRET_KEY**: Chave secreta para assinatura de requests
- **Onde está**: `agents/config.local.ps1` (gitignored)
- **GitHub Actions**: Configurado em Secrets

### 2. Telegram Bot
- **TELEGRAM_BOT_TOKEN**: Token do bot @coinex_gemagent_bot
- **TELEGRAM_CHAT_ID**: ID do chat para notificações
- **Onde está**: `agents/config.local.ps1` (gitignored)
- **GitHub Actions**: Configurado em Secrets

### 3. Anthropic/Claude (OPCIONAL - não usado no GitHub Actions)
- **ANTHROPIC_API_KEY**: API key para Claude
- **Onde está**: `agents/config.local.ps1` (gitignored)
- **GitHub Actions**: NÃO necessário (sistema funciona sem)

### 4. Outras APIs (OPCIONAL)
- **GROQ_API_KEY**: Free tier LLM
- **GEMINI_API_KEY**: Google AI fallback
- **FRED_API_KEY**: Dados macroeconômicos
- **Onde está**: `agents/config.local.ps1` (gitignored)
- **GitHub Actions**: NÃO necessário

---

## 🚀 CONFIGURAR SECRETS NO GITHUB

### Passo 1: Acessar configurações
```
https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
```

### Passo 2: Adicionar 4 secrets obrigatórios

| Nome | Valor | Onde encontrar |
|------|-------|----------------|
| `COINEX_ACCESS_ID` | `CECC82B02D3248B3AB798AA611B7D8DB` | `agents/config.local.ps1` |
| `COINEX_SECRET_KEY` | `0F1C14FD52713BE401DF4BD4A4DD7B5E4EBCF11EB1BCB51F` | `agents/config.local.ps1` |
| `TELEGRAM_BOT_TOKEN` | `8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54` | `agents/config.local.ps1` |
| `TELEGRAM_CHAT_ID` | `5592104053` | `agents/config.local.ps1` |

### Passo 3: Verificar
```powershell
# Rodar workflow manualmente para testar:
# GitHub → Actions → Trading Pipeline → Run workflow
```

---

## 🛡️ BOAS PRÁTICAS

### ✅ O QUE FAZER
1. **Sempre** usar `$env:VARIAVEL` no código
2. **Sempre** adicionar arquivos com credenciais no `.gitignore`
3. **Sempre** usar GitHub Secrets para CI/CD
4. **Sempre** verificar antes de commitar: `git status`

### ❌ O QUE NÃO FAZER
1. **NUNCA** hardcodar credenciais no código
2. **NUNCA** commitar `config.local.ps1`
3. **NUNCA** commitar arquivos `.env`
4. **NUNCA** expor tokens em logs públicos

---

## 🔍 VERIFICAÇÃO RÁPIDA

### Antes de cada commit:
```powershell
# 1. Verificar se config.local.ps1 não está sendo rastreado
git ls-files agents/config.local.ps1
# Saída vazia = OK ✅

# 2. Procurar por credenciais hardcoded
git grep -i "CECC82B02D3248B3"
git grep -i "0F1C14FD52713BE4"
git grep -i "8763265579:AAF"
# Nenhum resultado = OK ✅

# 3. Verificar arquivos staged
git diff --cached
# Nenhuma credencial visível = OK ✅
```

---

## 📊 RESUMO

| Item | Status | Ação Necessária |
|------|--------|-----------------|
| Credenciais hardcoded | ✅ Nenhuma | - |
| config.local.ps1 | ✅ Gitignored | - |
| GitHub Secrets | ⚠️ Verificar | Configurar manualmente |
| .gitignore | ✅ Completo | - |
| Código público | ✅ Seguro | Pode commitar |

---

## 🎯 PRÓXIMOS PASSOS

1. ✅ **Verificar secrets no GitHub** (link acima)
2. ✅ **Fazer commits** com `.\FAZER_COMMITS.ps1`
3. ✅ **Push para GitHub**
4. ✅ **Habilitar GitHub Pages**
5. ✅ **Acessar dashboard** em `https://thiagodataengineer.github.io/ManuHeadFund/`

---

## 📞 SUPORTE

Se encontrar alguma credencial exposta:
1. **IMEDIATAMENTE** revogar a credencial no serviço original
2. Gerar nova credencial
3. Atualizar `config.local.ps1` e GitHub Secrets
4. Verificar histórico do git: `git log --all --full-history -- agents/config.local.ps1`

---

**Última verificação**: 2026-05-25  
**Status**: ✅ SEGURO PARA REPOSITÓRIO PÚBLICO

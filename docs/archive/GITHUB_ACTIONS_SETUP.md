# 🚀 GITHUB ACTIONS - GUIA DE SETUP

## ✅ PRÉ-REQUISITOS

Antes de começar, certifique-se de ter:
- ✅ Conta no GitHub
- ✅ Git instalado localmente
- ✅ Credenciais CoinEx (Access ID + Secret Key)
- ✅ Credenciais Telegram (Bot Token + Chat ID)

---

## 📋 PASSO A PASSO

### 1. Criar Repositório no GitHub

1. Acesse: https://github.com/new
2. Nome do repositório: `Coinex_AI_USER_API` (ou outro nome)
3. Visibilidade: **Private** (recomendado para credenciais)
4. **NÃO** inicialize com README, .gitignore ou license
5. Clique em "Create repository"

### 2. Conectar Repositório Local ao GitHub

```powershell
# No diretório do projeto
cd C:\Users\thiag\Coinex_AI_USER_API

# Adicionar remote (substitua SEU_USUARIO pelo seu username)
git remote add origin https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git

# Verificar remote
git remote -v
```

### 3. Configurar Secrets no GitHub

1. Acesse seu repositório no GitHub
2. Vá em: **Settings** → **Secrets and variables** → **Actions**
3. Clique em **New repository secret**
4. Adicione os 4 secrets abaixo:

#### Secret 1: COINEX_ACCESS_ID
- **Name**: `COINEX_ACCESS_ID`
- **Value**: Seu Access ID da CoinEx
- Clique em **Add secret**

#### Secret 2: COINEX_SECRET_KEY
- **Name**: `COINEX_SECRET_KEY`
- **Value**: Sua Secret Key da CoinEx
- Clique em **Add secret**

#### Secret 3: TELEGRAM_BOT_TOKEN
- **Name**: `TELEGRAM_BOT_TOKEN`
- **Value**: `8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54`
- Clique em **Add secret**

#### Secret 4: TELEGRAM_CHAT_ID
- **Name**: `TELEGRAM_CHAT_ID`
- **Value**: `5592104053`
- Clique em **Add secret**

### 4. Habilitar GitHub Actions

1. Vá em: **Settings** → **Actions** → **General**
2. Em "Actions permissions", selecione:
   - ✅ **Allow all actions and reusable workflows**
3. Em "Workflow permissions", selecione:
   - ✅ **Read and write permissions**
4. Clique em **Save**

### 5. Push do Código para GitHub

```powershell
# Push do código
git push -u origin main

# Se der erro de autenticação, use Personal Access Token:
# 1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
# 2. Generate new token (classic)
# 3. Selecione: repo, workflow, admin:repo_hook
# 4. Use o token como senha no git push
```

### 6. Verificar Workflow

1. Acesse: **Actions** no seu repositório
2. Você verá o workflow: **Trading Pipeline**
3. Aguarde a primeira execução (será automática)
4. Verifique se os 3 jobs executaram com sucesso:
   - ✅ risk-manager
   - ✅ dashboard-generator
   - ✅ health-check

---

## 🔍 VERIFICAÇÃO

### Verificar Logs do Workflow

1. Acesse: **Actions** → **Trading Pipeline**
2. Clique na execução mais recente
3. Clique em cada job para ver os logs
4. Verifique se não há erros

### Verificar Telegram

Você deve receber mensagens do bot a cada 15 minutos com:
- Dashboard Snapshot
- Alertas de posições (se houver)

### Verificar Dashboard

O dashboard será atualizado a cada 15 minutos no GitHub Actions.
Para visualizar localmente:
```powershell
# Abrir dashboard no navegador
start dashboard/index.html
```

---

## ⚙️ CONFIGURAÇÃO DO WORKFLOW

O workflow está configurado em: `.github/workflows/trading-pipeline.yml`

### Frequência Atual
- **Cron**: `*/15 * * * *` (a cada 15 minutos)
- **Uso estimado**: ~2,880 minutos/mês
- **Limite free tier**: 2,000 minutos/mês

### Ajustar Frequência (Opcional)

Se quiser economizar minutos do GitHub Actions:

```yaml
# Editar .github/workflows/trading-pipeline.yml
schedule:
  - cron: '*/30 * * * *'  # A cada 30 minutos (1,440 min/mês)
  # ou
  - cron: '0 * * * *'     # A cada 1 hora (720 min/mês)
```

---

## 🔄 MODO FAILOVER

O sistema está configurado para **Modo Failover**:

### Quando Máquina LIGADA
- ✅ Scripts locais executam a cada **5 minutos**
- ⏸️ GitHub Actions detecta lock e **pula execução**

### Quando Máquina DESLIGADA
- ⏸️ Scripts locais não executam
- ✅ GitHub Actions executa a cada **15 minutos**

### Como Funciona
1. Scripts criam arquivo de lock em `locks/*.lock`
2. Lock tem timeout de 5 minutos
3. GitHub Actions verifica lock antes de executar
4. Se lock existe e não expirou, pula execução

---

## 🐛 TROUBLESHOOTING

### Erro: "Secret not found"
- Verifique se os 4 secrets foram criados corretamente
- Nomes devem ser EXATAMENTE como especificado (case-sensitive)

### Erro: "Workflow not running"
- Verifique se GitHub Actions está habilitado
- Verifique se o arquivo `.github/workflows/trading-pipeline.yml` existe
- Verifique se o push foi feito corretamente

### Erro: "Permission denied"
- Verifique "Workflow permissions" em Settings → Actions
- Deve estar em "Read and write permissions"

### Erro: "Rate limit exceeded"
- CoinEx API tem rate limits
- Aguarde alguns minutos e tente novamente

### Mensagens não chegam no Telegram
- Verifique se os secrets TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID estão corretos
- Teste localmente: `.\scripts\test_all_flows.ps1`

---

## 📊 MONITORAMENTO

### GitHub Actions
- Acesse: **Actions** no repositório
- Veja histórico de execuções
- Verifique logs de cada job

### Telegram
- Receba alertas em tempo real
- Dashboard snapshot a cada 15min
- Alertas de posições

### Local
- Dashboard: `dashboard/index.html`
- Logs: Console do PowerShell
- Journal: `journal/` (trades históricos)

---

## 🔐 SEGURANÇA

### Boas Práticas
- ✅ Repositório **Private** (recomendado)
- ✅ Secrets nunca commitados no código
- ✅ Secrets acessíveis apenas via GitHub Actions
- ✅ Logs não expõem credenciais

### Rotação de Credenciais
Se precisar trocar credenciais:
1. Gere novas credenciais na CoinEx/Telegram
2. Atualize os secrets no GitHub
3. Não precisa fazer novo push

---

## 📈 PRÓXIMOS PASSOS

Após setup completo:
1. ✅ Verificar primeira execução do workflow
2. ✅ Confirmar recebimento de mensagens no Telegram
3. ✅ Monitorar posições abertas
4. ⏳ Testar Gem Agent em produção
5. ⏳ Integrar Mentor (Claude) nas decisões

---

## 📞 SUPORTE

### Documentação
- `STATUS_ATUAL_2026_05_23.md` - Status completo
- `TESTE_COMPLETO_2026_05_23.md` - Resultados dos testes
- `RESUMO_VISUAL_2026_05_23.md` - Resumo visual

### Testes
```powershell
# Testar todos os fluxos localmente
.\scripts\test_all_flows.ps1

# Testar apenas dashboard
.\scripts\generate_dashboard_elite.ps1

# Testar apenas risk manager
.\scripts\position_risk_cron.ps1
```

---

**Última Atualização**: 2026-05-23 17:15:00 UTC
**Status**: ⏳ Aguardando setup do usuário
**Próximo Passo**: Criar repositório no GitHub e configurar secrets

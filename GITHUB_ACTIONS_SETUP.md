# 🚀 GITHUB ACTIONS - PIPELINE NA NUVEM

**Objetivo:** Rodar o trading pipeline na nuvem do GitHub, sem depender da máquina local ficar ligada.

---

## ✅ VANTAGENS

### GitHub Actions (Grátis)
- ✅ **2.000 minutos/mês grátis** (conta pública)
- ✅ **Roda na nuvem** - máquina não precisa ficar ligada
- ✅ **Execução a cada 5 minutos** (cron)
- ✅ **Logs completos** de cada execução
- ✅ **Alertas automáticos** se algo falhar
- ✅ **GitHub Pages** para hospedar dashboard
- ✅ **Secrets seguros** para API keys

### vs Máquina Local
| Recurso | Local | GitHub Actions |
|---------|-------|----------------|
| Máquina ligada | ✗ Sempre | ✅ Não precisa |
| Custo energia | ✗ Alto | ✅ Grátis |
| Manutenção | ✗ Manual | ✅ Automática |
| Logs | ✗ Local | ✅ Na nuvem |
| Backup | ✗ Manual | ✅ Automático |
| Acesso remoto | ✗ Difícil | ✅ Fácil |

---

## 📋 SETUP - PASSO A PASSO

### 1️⃣ Criar Repositório GitHub (se não tiver)

```bash
# No diretório do projeto
git init
git add .
git commit -m "Initial commit - ManuHeadFund"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git
git push -u origin main
```

### 2️⃣ Configurar Secrets no GitHub

1. Ir para: **Settings** → **Secrets and variables** → **Actions**
2. Clicar em **New repository secret**
3. Adicionar os seguintes secrets:

#### Secrets Necessários:

| Nome | Valor | Onde Encontrar |
|------|-------|----------------|
| `COINEX_ACCESS_ID` | Seu Access ID | CoinEx API Settings |
| `COINEX_SECRET_KEY` | Seu Secret Key | CoinEx API Settings |
| `TELEGRAM_BOT_TOKEN` | 8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54 | Já temos |
| `TELEGRAM_CHAT_ID` | 5592104053 | Já temos |

**⚠️ IMPORTANTE:** Nunca commite as API keys no código! Use apenas Secrets.

### 3️⃣ Ativar GitHub Actions

1. Ir para: **Actions** (aba no topo)
2. Clicar em **I understand my workflows, go ahead and enable them**
3. Pronto! Pipeline vai começar a rodar automaticamente

### 4️⃣ Ativar GitHub Pages (Opcional - para Dashboard)

1. Ir para: **Settings** → **Pages**
2. Source: **Deploy from a branch**
3. Branch: **gh-pages** / **(root)**
4. Salvar

Seu dashboard estará disponível em:
```
https://SEU_USUARIO.github.io/Coinex_AI_USER_API/
```

---

## 🔄 WORKFLOWS CRIADOS

### 1. **Risk Manager** (A cada 5 minutos)
```yaml
- Monitora posições abertas
- Ajusta trailing stops
- Envia alertas de risco
- Adiciona margem se necessário
```

### 2. **Dashboard Generator** (A cada 5 minutos)
```yaml
- Coleta métricas da API
- Gera dashboard HTML
- Faz upload como artifact
- Deploy para GitHub Pages
```

### 3. **Health Check** (A cada 5 minutos)
```yaml
- Verifica CoinEx API
- Verifica Telegram API
- Envia status diário (00:00)
- Alerta se algo falhar
```

---

## 📊 EXECUÇÃO

### Automática (Cron)
```yaml
schedule:
  - cron: '*/5 * * * *'  # A cada 5 minutos
```

**Limitação GitHub:** Mínimo 5 minutos (não permite menos)

### Manual (Workflow Dispatch)
1. Ir para: **Actions**
2. Selecionar workflow
3. Clicar em **Run workflow**
4. Escolher branch: **main**
5. Clicar em **Run workflow**

---

## 📝 LOGS E MONITORAMENTO

### Ver Logs de Execução
1. Ir para: **Actions**
2. Clicar no workflow (ex: "Trading Pipeline")
3. Clicar na execução (ex: "Risk Manager #123")
4. Ver logs detalhados de cada step

### Alertas Automáticos
Se algo falhar, você recebe:
- ✅ **Telegram:** Mensagem de erro
- ✅ **Email:** Notificação do GitHub
- ✅ **Badge:** Status no README

---

## 🎯 ESTRUTURA DO WORKFLOW

```
.github/
└── workflows/
    └── trading-pipeline.yml

Jobs:
├── risk-manager (5min)
│   ├── Checkout código
│   ├── Setup PowerShell
│   ├── Configurar credenciais
│   ├── Executar Risk Manager
│   └── Enviar alerta se falhar
│
├── dashboard-generator (5min)
│   ├── Checkout código
│   ├── Setup PowerShell
│   ├── Configurar credenciais
│   ├── Gerar Dashboard
│   ├── Upload artifact
│   └── Deploy GitHub Pages
│
└── health-check (5min)
    ├── Verificar CoinEx API
    ├── Verificar Telegram API
    └── Enviar status diário
```

---

## 💰 CUSTOS E LIMITES

### GitHub Actions (Conta Pública - Grátis)
- **Minutos/mês:** 2.000 grátis
- **Storage:** 500 MB grátis
- **Concurrent jobs:** 20

### Cálculo de Uso
```
Execuções por dia: 288 (a cada 5min)
Duração média: ~2 minutos por execução
Minutos/dia: 288 × 2 = 576 minutos
Minutos/mês: 576 × 30 = 17.280 minutos

❌ EXCEDE O LIMITE GRÁTIS!
```

### ⚠️ SOLUÇÃO: Reduzir Frequência

#### Opção 1: A cada 15 minutos (RECOMENDADO)
```yaml
schedule:
  - cron: '*/15 * * * *'  # A cada 15 minutos

Execuções/dia: 96
Minutos/dia: 192
Minutos/mês: 5.760 ✅ DENTRO DO LIMITE
```

#### Opção 2: Apenas horário comercial
```yaml
schedule:
  - cron: '*/5 * * * *'  # A cada 5min
    # Mas adicionar condição no job:
    if: github.event.schedule == '*/5 * * * *' && 
        (github.event.schedule.hour >= 8 && github.event.schedule.hour <= 22)

Execuções/dia: 168 (14h × 12/hora)
Minutos/dia: 336
Minutos/mês: 10.080 ✅ DENTRO DO LIMITE (com folga)
```

#### Opção 3: GitHub Actions Pro ($4/mês)
- **3.000 minutos/mês**
- Permite rodar a cada 5min sem preocupação

---

## 🔧 CUSTOMIZAÇÃO

### Alterar Frequência
Editar `.github/workflows/trading-pipeline.yml`:

```yaml
# A cada 15 minutos
- cron: '*/15 * * * *'

# A cada 30 minutos
- cron: '*/30 * * * *'

# A cada hora
- cron: '0 * * * *'

# Apenas às 9h, 12h, 15h, 18h
- cron: '0 9,12,15,18 * * *'
```

### Adicionar Novos Jobs
```yaml
  my-custom-job:
    name: Meu Job Customizado
    runs-on: ubuntu-latest
    steps:
      - name: Meu step
        shell: pwsh
        run: |
          Write-Host "Executando meu código"
```

### Desabilitar Jobs
Comentar ou remover do arquivo:
```yaml
# jobs:
#   risk-manager:
#     ...
```

---

## 🚀 DEPLOY

### Fazer Push do Workflow
```bash
git add .github/workflows/trading-pipeline.yml
git commit -m "Add GitHub Actions pipeline"
git push origin main
```

### Verificar Execução
1. Ir para: **Actions**
2. Ver workflows rodando
3. Aguardar primeira execução (até 5min)

### Verificar Dashboard
Após primeira execução:
```
https://SEU_USUARIO.github.io/Coinex_AI_USER_API/
```

---

## 🐛 TROUBLESHOOTING

### Workflow não está rodando
- ✅ Verificar se Actions está habilitado
- ✅ Verificar se secrets estão configurados
- ✅ Verificar sintaxe do YAML (indentação)
- ✅ Verificar logs de erro

### API CoinEx falha
- ✅ Verificar se Access ID está correto
- ✅ Verificar se Secret Key está correto
- ✅ Verificar se IP do GitHub está permitido (whitelist)

### Telegram não envia mensagens
- ✅ Verificar se Bot Token está correto
- ✅ Verificar se Chat ID está correto
- ✅ Enviar mensagem para o bot primeiro

### Dashboard não atualiza
- ✅ Verificar se GitHub Pages está habilitado
- ✅ Verificar se branch gh-pages existe
- ✅ Aguardar até 10min para propagação

---

## 📊 MONITORAMENTO

### Badge de Status (README)
Adicionar ao `README.md`:

```markdown
![Trading Pipeline](https://github.com/SEU_USUARIO/Coinex_AI_USER_API/actions/workflows/trading-pipeline.yml/badge.svg)
```

### Notificações
GitHub envia email automaticamente se:
- ✗ Workflow falha
- ✗ API retorna erro
- ✗ Timeout (>6h sem executar)

---

## 🎯 PRÓXIMOS PASSOS

### Após Setup
1. ✅ Configurar secrets
2. ✅ Fazer push do workflow
3. ✅ Verificar primeira execução
4. ✅ Ativar GitHub Pages
5. ✅ Adicionar badge ao README

### Melhorias Futuras
- [ ] Adicionar testes automatizados
- [ ] Implementar rollback automático
- [ ] Adicionar métricas de performance
- [ ] Criar dashboard de monitoramento
- [ ] Implementar alertas avançados

---

## 💡 ALTERNATIVAS

### Se GitHub Actions não for suficiente:

#### 1. **AWS Lambda** (Grátis até 1M requests/mês)
- Execução serverless
- Trigger a cada 1 minuto
- Mais controle e flexibilidade

#### 2. **Google Cloud Functions** (Grátis até 2M invocations/mês)
- Similar ao Lambda
- Integração com Google Cloud

#### 3. **Heroku** ($7/mês)
- Dyno sempre ligado
- Execução contínua
- Mais recursos

#### 4. **Railway** ($5/mês)
- Deploy automático
- Logs em tempo real
- Fácil configuração

#### 5. **VPS** ($5-10/mês)
- Controle total
- Sem limites de execução
- Requer manutenção

---

## ✅ CHECKLIST DE SETUP

- [ ] Criar repositório GitHub
- [ ] Adicionar secrets (4 secrets)
- [ ] Fazer push do workflow
- [ ] Habilitar GitHub Actions
- [ ] Habilitar GitHub Pages (opcional)
- [ ] Verificar primeira execução
- [ ] Testar execução manual
- [ ] Verificar logs
- [ ] Verificar dashboard
- [ ] Adicionar badge ao README
- [ ] Configurar notificações
- [ ] Testar alertas Telegram

---

## 🎉 RESULTADO FINAL

Após setup completo:

✅ **Pipeline rodando na nuvem** (GitHub Actions)  
✅ **Máquina local desligada** (não precisa mais)  
✅ **Execução automática** (a cada 5-15min)  
✅ **Dashboard online** (GitHub Pages)  
✅ **Alertas Telegram** (automáticos)  
✅ **Logs completos** (na nuvem)  
✅ **Grátis** (dentro dos limites)  

**Sistema 100% autônomo e na nuvem!** 🚀

---

**ManuHeadFund** - Cloud-Native Trading System  
Powered by GitHub Actions 🌐

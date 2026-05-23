# 🚀 ManuHeadFund - Professional Trading System

Sistema de trading automatizado para CoinEx com dashboard profissional e alertas Telegram.

![Trading Pipeline](https://github.com/SEU_USUARIO/Coinex_AI_USER_API/actions/workflows/trading-pipeline.yml/badge.svg)

---

## ✨ Features

### 📊 Dashboard Profissional
- Design inspirado em Refinitiv Eikon e Bloomberg
- Métricas em tempo real (P&L, Win Rate, Sharpe, Max DD)
- Trailing stop indicator com animação
- Charts interativos (Chart.js)
- Auto-refresh a cada 15 minutos
- **[Ver Dashboard Online →](https://SEU_USUARIO.github.io/Coinex_AI_USER_API/)**

### 🤖 Risk Manager Automático
- Monitora posições abertas
- Trailing stop automático (lucro > 3%)
- Alertas de liquidação próxima
- Adiciona margem automaticamente
- Executa a cada 15 minutos

### 📱 Alertas Telegram
- Trailing stop ativado
- Posições abertas/fechadas
- Alertas de risco
- Resumo diário
- Notificações em tempo real

### ☁️ Cloud-Native
- Roda no GitHub Actions (grátis)
- Não precisa máquina ligada
- Logs completos na nuvem
- Deploy automático

---

## 🚀 Quick Start

### 1. Clone o Repositório
```bash
git clone https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git
cd Coinex_AI_USER_API
```

### 2. Configure Secrets no GitHub
**Settings** → **Secrets and variables** → **Actions**

```
COINEX_ACCESS_ID     = seu_access_id
COINEX_SECRET_KEY    = seu_secret_key
TELEGRAM_BOT_TOKEN   = seu_bot_token
TELEGRAM_CHAT_ID     = seu_chat_id
```

### 3. Ative GitHub Actions
**Actions** → **Enable workflows**

### 4. Pronto! 🎉
Sistema roda automaticamente a cada 15 minutos.

**[📖 Guia Completo de Setup →](SETUP_RAPIDO_GITHUB.md)**

---

## 📊 Dashboard

### Local
```powershell
.\scripts\generate_dashboard_elite.ps1
Start-Process dashboard\index.html
```

### Online (GitHub Pages)
```
https://SEU_USUARIO.github.io/Coinex_AI_USER_API/
```

---

## 🔔 Telegram

### Setup
```powershell
.\scripts\setup_telegram_quick.ps1 -Token "SEU_TOKEN" -ChatId "SEU_CHAT_ID"
```

### Testar
```powershell
. .\agents\lib_telegram.ps1
Telegram-SendMessage -Message "Teste"
```

---

## 🛠️ Estrutura

```
Coinex_AI_USER_API/
├── .github/
│   └── workflows/
│       └── trading-pipeline.yml    # GitHub Actions
├── agents/
│   ├── lib_coinex.ps1              # API CoinEx
│   ├── lib_telegram.ps1            # Telegram Bot
│   └── lib_position_risk_manager.ps1
├── scripts/
│   ├── generate_dashboard_elite.ps1
│   ├── position_risk_cron.ps1
│   └── setup_telegram_quick.ps1
├── dashboard/
│   └── index.html                  # Dashboard gerado
├── config/
│   └── telegram.json               # Config Telegram
└── README.md
```

---

## 📈 Métricas

### Dashboard
- **Open Positions** - Posições abertas
- **Total P&L** - Lucro/Prejuízo total
- **Win Rate** - Taxa de acerto (%)
- **Capital** - Capital disponível
- **Sharpe Ratio** - Retorno ajustado ao risco
- **Max Drawdown** - Maior perda (%)

### Charts
- **Win/Loss Distribution** - Distribuição de ganhos/perdas
- **Risk Metrics** - Profit Factor, Sharpe, Max DD

---

## 🤖 Automação

### GitHub Actions (A cada 15 min)
- ✅ Risk Manager
- ✅ Dashboard Generator
- ✅ Health Check
- ✅ Telegram Alerts

### Cron Jobs Locais (Opcional)
```powershell
# Ver jobs
Get-ScheduledTask | Where-Object {$_.TaskName -like "CoinEx*"}

# Executar manualmente
.\scripts\position_risk_cron.ps1
```

---

## 📱 Alertas Telegram

### Automáticos
- 📈 Trailing stop ativado (lucro > 3%)
- ⚠️ Liquidação próxima (< 5%)
- 💰 Margem adicionada
- 🔄 Risk Manager executado

### Manuais
- 🚀 Posição aberta
- ✅ Posição fechada
- 📊 Resumo diário

---

## 🔧 Configuração

### CoinEx API
1. [CoinEx](https://www.coinex.com/) → **API Management**
2. Criar API Key
3. Copiar Access ID e Secret Key
4. Adicionar aos Secrets do GitHub

### Telegram Bot
1. Telegram → **@BotFather** → `/newbot`
2. Copiar Bot Token
3. Telegram → **@userinfobot** → Copiar Chat ID
4. Adicionar aos Secrets do GitHub

---

## 💰 Custos

### GitHub Actions (Grátis)
- **2.000 minutos/mês** grátis
- Workflow a cada 15min = ~2.880 min/mês
- ✅ **Dentro do limite!**

### Alternativas
- **AWS Lambda** - Grátis até 1M requests/mês
- **Google Cloud Functions** - Grátis até 2M invocations/mês
- **Heroku** - $7/mês (dyno sempre ligado)
- **VPS** - $5-10/mês (controle total)

---

## 📚 Documentação

- [Setup Rápido GitHub](SETUP_RAPIDO_GITHUB.md)
- [GitHub Actions Completo](GITHUB_ACTIONS_SETUP.md)
- [Dashboard Profissional](DASHBOARD_PROFESSIONAL_REFINADO_2026_05_23.md)
- [Telegram Configurado](TELEGRAM_CONFIGURADO_2026_05_23.md)

---

## 🐛 Troubleshooting

### Workflow não roda
- ✅ Verificar se Actions está habilitado
- ✅ Verificar se secrets estão configurados
- ✅ Ver logs em **Actions**

### API CoinEx falha
- ✅ Verificar Access ID e Secret Key
- ✅ Verificar se IP está na whitelist

### Telegram não envia
- ✅ Verificar Bot Token e Chat ID
- ✅ Enviar mensagem para o bot primeiro

---

## 🤝 Contribuindo

Pull requests são bem-vindos! Para mudanças grandes, abra uma issue primeiro.

---

## 📄 Licença

[MIT](LICENSE)

---

## 🎯 Roadmap

- [x] Dashboard profissional
- [x] Risk Manager automático
- [x] Alertas Telegram
- [x] GitHub Actions
- [x] GitHub Pages
- [ ] Backtesting integrado
- [ ] Machine Learning para sinais
- [ ] Multi-exchange support
- [ ] Mobile app

---

## 📞 Suporte

- **Issues:** [GitHub Issues](https://github.com/SEU_USUARIO/Coinex_AI_USER_API/issues)
- **Telegram:** @SEU_USUARIO
- **Email:** seu@email.com

---

**ManuHeadFund** - Professional Trading System  
Made with ❤️ by [Seu Nome]

![Dashboard Preview](https://via.placeholder.com/800x400?text=Dashboard+Preview)

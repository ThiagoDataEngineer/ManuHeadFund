# 🚀 Como Acessar os Dashboards

## ⚡ Rápido (30 segundos)

1. **Abra seu navegador (Chrome, Firefox, Edge)**
2. **Cole esta URL:**
   ```
   file:///C:/Users/thiag/Coinex_AI_USER_API/dashboard/index.html
   ```
3. **Clique em um dos 3 dashboards**

---

## 📍 Alternativa: Abrir arquivo direto

1. Abra **Explorador de Arquivos** (Win+E)
2. Vá para: `C:\Users\thiag\Coinex_AI_USER_API\dashboard\`
3. Duplo-clique em: `index.html`
4. Pronto! 🎉

---

## 📊 Os 3 Dashboards

| Dashboard | Para Quê | Acesso |
|-----------|----------|--------|
| **🌍 Universe Full** | Ver 50 pares com sparklines | `coinex_universe_full.html` |
| **⚡ Live Dashboard** | Gráficos interativos com zoom | `coinex_live_dashboard.html` |
| **🔥 MEGA Dashboard** | Config + Trades + Webhooks (tudo junto) | `coinex_mega_dashboard_final.html` |

---

## 💡 Qual Usar?

### 🌍 Universe Full
- Ver todos os 50 pares rapidinho
- Filtros por ganhadores/perdedores/regimes
- Sparklines lindas em Canvas
- **Melhor para**: Visão geral do universo

### ⚡ Live Dashboard  
- Gráficos interativos (zoom, scroll, tooltip)
- 100 candles por par
- 4 timeframes (1m/5m/1h/4h)
- **Melhor para**: Análise profunda de 1 par

### 🔥 MEGA Dashboard
- 4 TABS:
  - 📊 Dashboard (pares + alertas)
  - ⚙️ Configuração (Telegram + RSI + Score)
  - 📈 Histórico de Trades
  - 🔔 Webhooks & Alertas
- **Melhor para**: Tudo junto (monitoramento + config)

---

## 🔧 Se Não Carregar Dados

Os dashboards precisam destes JSONs:
```
journal/universe_dashboard_live.json  (50 pares)
journal/trade_history_extended.json   (histórico)
config/alerts_config.json             (config)
```

Se não tiver, rode:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/populate_dashboards.ps1
```

Depois recarregue a página (F5).

---

## 📱 Configure Telegram (Opcional)

No **MEGA Dashboard**:
1. Clique em **TAB ⚙️ Configuração**
2. Cole seu **Bot Token** (de @BotFather)
3. Cole seu **Chat ID** (de @userinfobot)
4. Clique **SALVAR**
5. Pronto! Receberá alertas automáticos

---

## ✅ Quick Checklist

- [ ] Navegador aberto
- [ ] URL colada ou arquivo aberto
- [ ] Um dos 3 dashboards selecionado
- [ ] Se dados não carregarem: rode `populate_dashboards.ps1`
- [ ] (Opcional) Configure Telegram no MEGA Dashboard

---

**Pronto!** Você tem acesso a todo o universo CoinEx em 3 dashboards poderosos. 🚀

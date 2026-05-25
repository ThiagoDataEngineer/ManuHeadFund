# 🚀 DASHBOARD ELITE - GUIA RÁPIDO

## ⚡ USO RÁPIDO

```powershell
.\DASHBOARD.ps1
```

**Pronto!** O dashboard abre automaticamente no navegador.

---

## 📊 O QUE VOCÊ TEM

### Dashboard Completo com 11 Categorias

1. **Trading Metrics** - Win rate, profit factor, trades
2. **Mentor Decisions** - Aprovação, veto, razões
3. **Mesa Consensus** - FORTE_3/MEDIO_2/CAOS
4. **Market Regime** - BULL_STRONG, ciclo, MCE
5. **LLM Costs** - Custos por período
6. **Portfolio Metrics** - Beta, exposição, diversificação
7. **Trailing Stop** - Tabela com todas as posições
8. **Promotion Pipeline** - DISCOVERY/TIER_A/B/C
9. **FQS Distribution** - BLUE_CHIP/QUALITY/SPECULATIVE
10. **Feedback Loop** - Vetos pendentes, ações
11. **Alerts & Events** - Alertas críticos

---

## 🎨 DESIGN

- ✅ Background gradient azul escuro
- ✅ Cards com glass morphism
- ✅ Cores semânticas (verde/vermelho/amarelo/azul)
- ✅ Font Awesome icons
- ✅ Responsivo
- ✅ Auto-refresh 5 min

---

## 📁 ARQUIVOS

### Principal
- **`DASHBOARD.ps1`** - Execute este!

### Dashboard
- **`dashboard/elite.html`** - Dashboard completo
- **`dashboard/data.js`** - Dados gerados

### Scripts
- **`scripts/collect_dashboard_data.ps1`** - Coleta dados

### Documentação
- **`README_DASHBOARD.md`** - Este arquivo
- **`DASHBOARD_PRONTO.md`** - Documentação completa

---

## 💡 DADOS ZERADOS?

**É normal!** Os dados aparecem como 0 porque:
- Nenhum trade nos últimos 30 dias
- Nenhuma decisão nas últimas 24 horas
- Sistema não operou recentemente

**Quando o sistema voltar a operar, os dados aparecerão automaticamente!**

---

## 🔧 SOLUÇÃO DE PROBLEMAS

### Dashboard vazio?
```powershell
# Regenerar dados
.\DASHBOARD.ps1
```

### Erro ao coletar dados?
```powershell
# Testar coleta
.\scripts\collect_dashboard_data.ps1
```

### Dashboard não abre?
```powershell
# Abrir manualmente
Start-Process dashboard\elite.html
```

---

## ✅ STATUS

🟢 **100% FUNCIONAL**

- ✅ 11 categorias implementadas
- ✅ Design completo
- ✅ Dados em tempo real
- ✅ Sem erros
- ✅ Testado e validado

---

## 📞 SUPORTE

Documentação completa: `DASHBOARD_PRONTO.md`

---

**Versão**: 2.0.0  
**Status**: 🟢 PRONTO PARA USO  
**Última atualização**: 2026-05-24

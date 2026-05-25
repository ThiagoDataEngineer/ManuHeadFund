# 🚀 GUIA RÁPIDO - DASHBOARDS

## 📊 3 DASHBOARDS DISPONÍVEIS

### 🏆 Elite - Métricas Estratégicas
```powershell
.\DASHBOARD.ps1 elite
# ou apenas
.\DASHBOARD.ps1
```
**O que tem:** 11 categorias (Trading, Mentor, Mesa, Regime, Portfolio, LLM Costs, etc.)

---

### ⚡ Operacional - Monitoramento em Tempo Real
```powershell
.\DASHBOARD.ps1 ops
```
**O que tem:** Posições abertas, Tasks agendadas, Logs do sistema

---

### 📈 Análise - Performance
```powershell
.\DASHBOARD.ps1 analise
```
**O que tem:** Métricas de performance, Análise de posições

---

## 🔄 NAVEGAÇÃO

1. Abra qualquer dashboard
2. Use o menu no header:
   - **Elite** 🏆
   - **Operacional** ⚡
   - **Análise** 📈
3. Dashboard ativo fica destacado

---

## ⚙️ ATUALIZAÇÃO

- **Automática:** A cada 5 minutos
- **Manual:** Execute `.\DASHBOARD.ps1 [tipo]` novamente

---

## 📁 ARQUIVOS

- `dashboard/elite.html` - Dashboard Elite
- `dashboard/index.html` - Dashboard Operacional
- `dashboard/position_metrics.html` - Dashboard de Análise
- `dashboard/shared.css` - CSS compartilhado
- `dashboard/data.js` - Dados dinâmicos

---

## ✅ PRONTO!

Todos os dashboards estão integrados, com design unificado e navegação simples.

**Comando mais usado:**
```powershell
.\DASHBOARD.ps1
```

# 📊 DASHBOARDS DISPONÍVEIS

## 🟢 DASHBOARDS ATIVOS (USE ESTES!)

### 1. **elite.html** ⭐ RECOMENDADO
**Descrição**: Dashboard Elite Completo com 11 categorias  
**Como abrir**: `.\DASHBOARD.ps1`  
**Conteúdo**:
- ✅ Trading Metrics (6 métricas)
- ✅ Mentor Decisions (3 métricas)
- ✅ Mesa Consensus (3 métricas)
- ✅ Market Regime (3 métricas)
- ✅ LLM Costs (3 métricas)
- ✅ Portfolio Metrics (3 métricas)
- ✅ Trailing Stop (tabela completa)
- ✅ Design moderno com glass morphism
- ✅ Auto-refresh 5 min

**Arquivo de dados**: `data.js`

---

### 2. **index.html** ✅ ORIGINAL
**Descrição**: Dashboard original do sistema  
**Como abrir**: `Start-Process dashboard\index.html`  
**Conteúdo**:
- ✅ Posições abertas (tabela completa)
- ✅ Tasks agendadas (status de todas)
- ✅ Logs do sistema (últimas 50 linhas)
- ✅ Métricas básicas (6 cards no topo)
- ✅ Auto-refresh 5 min

**Uso**: Monitoramento operacional diário

---

### 3. **position_metrics.html** ✅ ESPECIALIZADO
**Descrição**: Dashboard focado em métricas de posições  
**Como abrir**: `Start-Process dashboard\position_metrics.html`  
**Conteúdo**:
- ✅ Análise detalhada de cada posição
- ✅ Métricas de risco
- ✅ Performance individual
- ✅ Gráficos de PNL

**Uso**: Análise profunda de posições

---

## 🟡 DASHBOARDS DE TESTE

### 4. **simple.html** 🧪 TESTE
**Descrição**: Dashboard simplificado (6 cards básicos)  
**Como abrir**: `Start-Process dashboard\simple.html`  
**Conteúdo**:
- Trades 30d
- Win Rate
- Consensus
- Regime
- Beta
- Trailing

**Uso**: Testes e desenvolvimento

---

## 🔴 DASHBOARDS OBSOLETOS (PODE DELETAR)

### ❌ index_elite.html
**Status**: Template antigo, não usar  
**Motivo**: Substituído por `elite.html`

### ❌ dashboard_elite.html
**Status**: Versão antiga com bugs  
**Motivo**: Substituído por `elite.html`

---

## 📁 ARQUIVOS DE DADOS

### Ativos
- **`data.js`** - Dados para `elite.html` ✅
- **`dashboard_data.json`** - Backup em JSON ✅

### Obsoletos
- **`dashboard_data.js`** - Dados antigos ❌

---

## 🚀 COMO USAR

### Dashboard Elite (Recomendado)
```powershell
.\DASHBOARD.ps1
```
Abre `elite.html` com dados atualizados

### Dashboard Original
```powershell
Start-Process dashboard\index.html
```
Abre dashboard operacional

### Dashboard de Posições
```powershell
Start-Process dashboard\position_metrics.html
```
Abre análise de posições

---

## 🧹 LIMPEZA RECOMENDADA

### Arquivos para deletar
```powershell
Remove-Item dashboard\index_elite.html
Remove-Item dashboard\dashboard_elite.html
Remove-Item dashboard\dashboard_data.js
```

### Manter apenas
- ✅ `elite.html` (Dashboard Elite)
- ✅ `index.html` (Dashboard Original)
- ✅ `position_metrics.html` (Métricas)
- ✅ `simple.html` (Testes)
- ✅ `data.js` (Dados Elite)
- ✅ `dashboard_data.json` (Backup)

---

## 📊 COMPARAÇÃO

| Dashboard | Categorias | Design | Uso |
|-----------|-----------|--------|-----|
| **elite.html** | 11 | Moderno | Visão completa |
| **index.html** | 3 | Clássico | Operacional |
| **position_metrics.html** | 1 | Especializado | Análise |
| **simple.html** | 1 | Básico | Testes |

---

## 🎯 RECOMENDAÇÃO FINAL

### Para uso diário
1. **`elite.html`** - Visão geral completa
2. **`index.html`** - Monitoramento operacional

### Para análise
3. **`position_metrics.html`** - Análise de posições

### Para desenvolvimento
4. **`simple.html`** - Testes rápidos

---

**Última atualização**: 2026-05-24  
**Dashboards ativos**: 4  
**Dashboards obsoletos**: 2

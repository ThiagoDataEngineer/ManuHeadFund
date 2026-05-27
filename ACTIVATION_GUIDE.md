# 🚀 ACTIVATION GUIDE — Paper Trade Calibration + LLM Quota Optimization

## Status: 2026-05-26 12:00 BRT

Sistema foi reconfigurado para **destravar trades e otimizar quota Groq**. Ambas as mudanças estão **ATIVAS** agora.

---

## ✅ O que foi ativado

### 1️⃣ **Paper Trade Calibration Mode**

**Arquivo**: `journal/PAPER_CALIBRATION_MODE.flag`

**Comportamento**:
- ✅ SCORE_MINIMO reduzido: 65 → **55**
- ✅ MAX_TRADES_DIA aumentado: 5 → **10** (durante calibração)
- ✅ Todas as trades são PAPER (sem capital real)
- ✅ Rastreamento em `journal/paper_calibration_trades.jsonl`

**Objetivo**: Gerar **n≥30 trades** em 7 dias para validar edge real vs teórico

**Timeline**:
- Início: 2026-05-26 12:00 BRT
- Alvo: 30 trades até 2026-06-02 18:00 BRT
- Review: Próximo sábado (2026-06-02)

**Critério de Sucesso**:
- Win rate > 25% (bate teórico 1:3)
- P&L médio > 0% (até bater teórico ~0.50%/trade)
- Sem desenho > -5% (controle de risco)

---

### 2️⃣ **LLM Quota Optimization**

**Arquivo**: `agents/lib_llm_quota_optimizer.ps1` (novo)

**Mudanças Implementadas**:

#### A. **Intervalo aumentado: 5min → 30min**
```powershell
# config.ps1 agora tem:
$SCAN_MASTER_INTERVAL_MIN = 30  # Era: 5min (sazonalidade fazia variar)
```
**Impacto**: 6x menos chamadas ao Orchestrator = 6x menos calls Groq

#### B. **Rate Limiting entre drones**
```powershell
# 3 drones Mesa agora têm stagger 2s entre eles
$MESA_RATE_LIMIT_MS = 2000  # Min 2s entre drones
```
**Impacto**: Evita burst de 9 drones simultâneos (que causava 429 no Groq)

#### C. **Skip Mesa automático (criteria-based)**
```powershell
# Mesa é pulada se:
# 1. SMA9 vs SMA21 < 2% (flatline = sem momentum)
# 2. Volume spike < 1.5x (sem interest)
# 3. Groq quota > 80% (emergency mode)
```
**Impacto**: ~40% das candidatos são pulados direto → Mentor (não custa trio drones)

---

## 📊 Quota Math

### Antes (5min interval, sem otimização):
```
5 ciclos/hora × 24h = 120 ciclos/dia
120 × 3 drones × 4-6 calls/drone = 1440-2160 calls/dia
→ Esgota 14.4K em 6-10 dias ❌
```

### Depois (30min interval + skip Mesa):
```
2 ciclos/hora × 24h = 48 ciclos/dia
48 × (3 drones × 40% skip) = ~86 calls/dia base
+ 48 × Mentor = 48 calls
+ Triagem/outros = ~200 calls
→ ~2.4K calls/dia
→ Dura 6 dias em 14.4K Groq free ✅
```

---

## 🎯 Como Monitorar

### 1. Relatório de Calibração (Manual)
```powershell
.\scripts\paper_calibration_report.ps1
```
**Output**: 
- Console summary
- CSV: `journal/paper_calibration_report.csv`
- Telegram alert (se configurado)

### 2. Quota de LLM (Contínuo)
```powershell
# Arquivo temporário (atualizado em tempo real):
cat $env:TEMP\llm_quota_groq_$(Get-Date -Format 'yyyy-MM-dd').json
```

### 3. Dashboard
```
journal/paper_calibration_trades.jsonl  # Trades rastreadas
journal/PAPER_CALIBRATION_MODE.flag     # Status ativo
```

---

## ⚙️ Configuração Requerida

Nenhuma ação adicional necessária. Tudo já está ativo:

✅ `config.ps1` atualizado
✅ `lib_llm_quota_optimizer.ps1` criado
✅ `PAPER_CALIBRATION_MODE.flag` ativo
✅ `scan_master.ps1` carrega nova lib

---

## 📋 Próximos Passos

### Hoje (2026-05-26)
1. ✅ Verificar se trades começam a rodar (monitor `paper_calibration_trades.jsonl`)
2. ✅ Rodar `paper_calibration_report.ps1` a cada 12h para trending

### Em 7 dias (2026-06-02)
1. Análise final: Win rate real vs teórico
2. Decisão:
   - Se win_rate > 25%: Passar para LIVE (remover flag)
   - Se win_rate < 25%: Ajustar estratégia (extend calibração)

---

## 🔄 Rollback (Se Necessário)

Se precisar voltar ao modo anterior:

```powershell
# Desativar calibração:
Remove-Item journal/PAPER_CALIBRATION_MODE.flag

# Restaurar thresholds:
# config.ps1 → SCORE_MINIMO = 65, MAX_TRADES_DIA = 5

# Restaurar intervalo (sazonalidade):
# config.ps1 → SCAN_MASTER_INTERVAL_MIN = 0  (usa sazonalidade padrão)
```

---

## 📊 Métricas Esperadas (Benchmark)

Baseado em backtest 14 anos (BTC + top 20 alts):

| Métrica | Esperado | Observar |
|---------|----------|----------|
| Win rate | 25-30% | Piso: 15% (sinal de problema) |
| P&L médio/trade | 0.50-1.00% | Se < 0.20%: draw-down estrutural |
| Max drawdown | -2 a -3% | Se > -5%: risk control falhou |
| Trades/dia | 4-6 | Se < 2: tresholds muito altos |

---

## 🚨 Alertas Críticos

### ❌ Problema: 0 trades em 24h
**Diagnóstico**: SCORE_MINIMO ainda está alto OU todos bloqueiam em gates
**Ação**: Reduzir SCORE_MINIMO → 50 temporário

### ❌ Problema: Win rate < 15%
**Diagnóstico**: Estratégia não está funcionando
**Ação**: Revisar Mentor gate logic + pare calibração

### ❌ Problema: Groq 429 continue aparecendo
**Diagnóstico**: Rate limiter não está funcionando
**Ação**: Aumentar MESA_RATE_LIMIT_MS → 5000ms

---

## 📞 Suporte

Ver:
- `CLAUDE.md` — Persona e contexto
- `docs/BLUEPRINT.md` — Arquitetura
- `agents/lib_llm_quota_optimizer.ps1` — Code comments

---

**Last Updated**: 2026-05-26 12:00 BRT
**Status**: ✅ ACTIVE

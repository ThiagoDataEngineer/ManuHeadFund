# ⚡ CALIBRATION QUICK START

## Resumo: O que mudou?

| Aspecto | Antes | Depois | Por quê |
|---------|-------|--------|---------|
| **Score Mínimo** | 65 | **55** | Destravar trades (0 em 12 dias) |
| **Max Trades/dia** | 5 | **10** | Mais amostras rápido |
| **Scan Interval** | 5-30min (sazonalidade) | **30min fixo** | Reduz Groq quota 6x |
| **Mesa Rate Limit** | Nenhum | **2s entre drones** | Evita 429 burst |
| **Mesa Skip** | Sempre roda | **Skip se SMA flat** | -40% calls Groq |

## 🎯 Objetivo

**30 paper trades em 7 dias** → Validar edge real vs teórico (25% win rate)

## ✅ Status

- ✅ `PAPER_CALIBRATION_MODE.flag` criado (ativo)
- ✅ `lib_llm_quota_optimizer.ps1` criado (ativo)
- ✅ `config.ps1` atualizado (SCORE_MINIMO 55)
- ✅ `scan_master.ps1` carrega nova lib

## 📊 Monitorar

```powershell
# Ver progresso:
.\scripts\paper_calibration_report.ps1

# Ver quota Groq (tempo real):
cat $env:TEMP\llm_quota_groq_$(Get-Date -Format 'yyyy-MM-dd').json

# Ver trades capturados:
tail -20 journal/paper_calibration_trades.jsonl
```

## 🔄 Timeline

| Data | Evento | Ação |
|------|--------|------|
| 2026-05-26 12:00 | Calibração ativa | Monitor |
| 2026-05-26 → 06-01 | Coletar 30 trades | Rodar `paper_calibration_report.ps1` diário |
| 2026-06-02 | Review | Análise win_rate + decisão LIVE |

## 🚨 Troubleshooting

| Problema | Solução |
|----------|---------|
| 0 trades em 24h | Reduzir SCORE_MINIMO → 50 |
| Win rate < 15% | Revisar Mentor gate + pause |
| Groq 429 continua | Aumentar MESA_RATE_LIMIT_MS → 5000ms |
| Quota < 8 dias | Aumentar SCAN_MASTER_INTERVAL_MIN → 60min |

## 📁 Arquivos Críticos

```
agents/
  ├─ config.ps1                              (SCORE_MINIMO=55, INTERVAL=30min)
  └─ lib_llm_quota_optimizer.ps1            (Nova lib)
scripts/
  ├─ scan_master.ps1                        (Carrega nova lib)
  └─ paper_calibration_report.ps1           (Nova)
journal/
  ├─ PAPER_CALIBRATION_MODE.flag            (Nova — marca modo ativo)
  ├─ paper_calibration_trades.jsonl         (Será preenchido)
  └─ paper_calibration_report.csv           (CSV trending)
```

## 🟢 Ready to Trade!

Tudo configurado. Sistema está agora **destravaando trades** + **economizando quota Groq**.

Próxima ação: **Monitorar** `paper_calibration_trades.jsonl` nos próximos 7 dias.

---

**Timestamp**: 2026-05-26 12:00 BRT  
**Status**: ✅ LIVE

# 🚀 PLANO DE MIGRAÇÃO TDD COMPLETA - GitHub Actions

**Objetivo:** Migrar 100% do sistema para GitHub Actions com TDD em todos os scripts.

## 📊 Análise dos Scripts (13 scripts)

| Script | Linhas | Dependências | Onda |
|--------|--------|--------------|------|
| daily_kelly_audit.ps1 | 39 | Standalone | 1 |
| cron_staleness_audit.ps1 | 54 | Standalone | 1 |
| whale_watcher_cron.ps1 | 35 | Standalone | 1 |
| daily_summary_digest.ps1 | 128 | Standalone | 1 |
| cron_wss_forward_resolve.ps1 | 169 | Standalone | 2 |
| weekly_data_refresh.ps1 | 175 | Standalone | 2 |
| tori_proximity_scanner.ps1 | 185 | Scanner | 2 |
| vol_climax_scanner.ps1 | 255 | Scanner | 2 |
| promotion_weekly_cron.ps1 | 442 | Standalone | 3 |
| weekly_provider_cost_report.ps1 | 99 | Claude+Groq+Gemini | 3 |
| gem_loop.ps1 | 173 | Orchestrator+Scanner | 4 |
| scan_master.ps1 | 1208 | Claude+Groq+Orchestrator+Scanner | 4 |

## 🌊 Estratégia em 4 Ondas

### **Onda 1: Standalone Pequenos (4 scripts)** ✅ Simples
- daily_kelly_audit
- cron_staleness_audit  
- whale_watcher_cron
- daily_summary_digest

### **Onda 2: Standalone Médios (4 scripts)** ⚠️ Médio
- cron_wss_forward_resolve
- weekly_data_refresh
- tori_proximity_scanner (estratégia validada!)
- vol_climax_scanner

### **Onda 3: Com Dependências (2 scripts)** ⚠️ Complexo
- promotion_weekly_cron
- weekly_provider_cost_report (precisa LLM keys)

### **Onda 4: Crítico - Trading Ativo (2 scripts)** 🔴 Muito Complexo
- gem_loop (gem trading SPOT)
- scan_master (orchestrator trading FUTURES)

## 📋 Padrão TDD para Cada Script

Para cada script, criar:
1. **Arquivo de teste**: `tests/<script_name>.Tests.ps1`
2. **Versão refatorada**: cross-platform com `Test-Path-Function` testável
3. **Job no workflow**: GitHub Actions YAML
4. **Mock para externals**: simular CoinEx, Telegram, LLMs

## 🎯 Critérios de Sucesso

Para cada script:
- [ ] Tests passam (RED → GREEN → REFACTOR)
- [ ] Roda local em PS 5.1
- [ ] Roda GitHub Actions em PS 7 + Linux
- [ ] Não usa variáveis reservadas ($env, $IsLinux, etc)
- [ ] Usa `Join-Path` aninhado (compat PS 5.1)
- [ ] Validação de credenciais antes de executar
- [ ] Logging cross-platform

## ⏱️ Estimativa de Tempo

- **Onda 1**: 1-2h (scripts simples)
- **Onda 2**: 2-3h (médios)
- **Onda 3**: 2-3h (com LLMs)
- **Onda 4**: 4-6h (crítico)

**Total: ~10-15 horas de trabalho**

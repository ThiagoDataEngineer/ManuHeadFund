# Plano de Limpeza - Raiz do Projeto

**Data:** 30/05/2026  
**Objetivo:** Remover arquivos temporários e relatórios obsoletos

---

## 📊 Análise de Arquivos

### ✅ MANTER (Essencial)

```
README.md                          - Documentação principal
CLAUDE.md                          - Guia Claude
ACTIVATION_GUIDE.md                - Guia de ativação
CALIBRATION_QUICK_START.md         - Quick start calibração
COMECE_AQUI.md                     - Guia em português
DEPLOY_CHECKLIST.md                - Checklist de deploy
EXECUTION_GUIDE.md                 - Guia de execução
QUICK_START_20260529.md            - Quick start (mais recente)
QUICK_REFERENCE_20260529.md        - Referência rápida
PSScriptAnalyzerSettings.psd1      - Configuração de análise
GEMINI_INVESTIGATION_REPORT_20260530.md - Investigação recente
```

### ❌ REMOVER (Relatórios Temporários)

#### 📅 Data 20260529 (43 arquivos, ~500 KB)
```
ANALYSIS_THRESHOLDS_20260529.md
CHANGES_2026_05_29.md
CHANGES_2026_05_29_FQS_AUDIT.md
CONTEXT_TRANSFER_SESSION_20260529.md
DASHBOARD_ANALYSIS_20260529.txt
EXAMPLES_BEFORE_AFTER_20260529.md
FINAL_CONSOLIDATED_REPORT_20260529.md
FINAL_EXECUTION_REPORT_20260529.md
FINAL_REPORT_COINGECKO_ENRICH_20260529.md
FINAL_SUMMARY_20260529.txt
FQS_COINGECKO_ENRICH_PLAN_20260529.md
FQS_REGISTRY_ACTION_PLAN_20260529.md
FQS_REGISTRY_AUDIT_20260529.md
FQS_REGISTRY_DOCUMENTATION_INDEX.md
FQS_REGISTRY_EXECUTIVE_SUMMARY.txt
FQS_REGISTRY_VALIDATION_20260529_140623.json
IMPLEMENTATION_GUIDE_20260529.md
IMPLEMENTATION_MUDANCAS_1_2_20260529.md
INDEX_ANALYSIS_20260529.md
INDEX_COINGECKO_PROJECT_20260529.md
INTEGRATION_TEST_REPORT_20260529.md
NEW_DOCUMENTATION_20260529.md
PROJECT_FINAL_SUMMARY_20260529.txt
PROJECT_STATUS_FINAL_20260529.md
QUICK_START_20260529.md (duplicado)
SUMMARY_FINDINGS_20260529.md
TDD_COINGECKO_ENRICH_20260529.md
TDD_COINGECKO_ENRICH_COMPLETE_20260529.md
TDD_COINGECKO_ENRICH_REFACTOR_20260529.md
TDD_SUMMARY_20260529.txt
TIER_D_ENRICH_EVALUATION_20260529.md
TOTAL_DELIVERABLES_20260529.md
VERIFICATION_CHECKLIST_20260529.md
coingecko_enrich_complete_20260529.json
coingecko_enrich_integration_test_20260529.json
coingecko_enrich_real_20260529.json
coingecko_ids_validation_20260529.json
fqs_enriched_data_real_20260529.json
fqs_enriched_data_real_v3_20260529.json
COMMIT_MESSAGE_20260529.txt
coingecko_enrich_retry_20260529.log
```

#### 📅 Data 20260528 (1 arquivo, ~5 KB)
```
CHANGES_2026_05_28.md
```

#### 📅 Data 20260527 (1 arquivo, ~5 KB)
```
CHANGES_2026_05_27.md
```

#### 📅 Data 20260526 (1 arquivo, ~5 KB)
```
CHANGES_2026_05_26.md
```

#### 📅 Outros Relatórios Antigos
```
IMPLICACOES_SISTEMICAS.md          - Análise antiga
PROJECT_COMPLETION_SUMMARY.md      - Resumo antigo
```

---

## 📦 Impacto da Limpeza

| Categoria | Arquivos | Tamanho | Impacto |
|-----------|----------|---------|--------|
| Relatórios 20260529 | 43 | ~500 KB | ✅ Seguro remover |
| Relatórios 20260528 | 1 | ~5 KB | ✅ Seguro remover |
| Relatórios 20260527 | 1 | ~5 KB | ✅ Seguro remover |
| Relatórios 20260526 | 1 | ~5 KB | ✅ Seguro remover |
| Outros antigos | 2 | ~10 KB | ✅ Seguro remover |
| **TOTAL** | **48** | **~530 KB** | ✅ Seguro remover |

---

## 🎯 Recomendação

### Fase 1: Limpeza Agressiva (Recomendado)
Remover todos os 48 arquivos listados acima. Eles são:
- Relatórios de desenvolvimento/debug
- Dados temporários de testes
- Documentação duplicada
- Logs de execução

**Benefício:** Reduz clutter, melhora legibilidade do projeto

### Fase 2: Arquivamento (Opcional)
Se quiser manter histórico:
1. Criar pasta `archive/reports_20260526-20260529/`
2. Mover todos os 48 arquivos para lá
3. Fazer commit com mensagem "Archive: move old reports to archive/"

---

## 📋 Checklist de Limpeza

- [ ] Revisar lista de arquivos a remover
- [ ] Fazer backup (git já faz isso)
- [ ] Executar limpeza
- [ ] Verificar que projeto ainda funciona
- [ ] Fazer commit: "Cleanup: remove temporary reports from 20260526-20260529"

---

## ⚠️ Avisos

1. **Git preserva histórico** — Remover arquivos não apaga do git, apenas do working directory
2. **Nenhum código será afetado** — Todos os arquivos a remover são documentação/dados
3. **Reversível** — Se precisar, `git checkout` recupera qualquer arquivo

---

## 🚀 Próximos Passos

Após limpeza:
1. Manter apenas documentação essencial na raiz
2. Criar `docs/archive/` para relatórios históricos
3. Estabelecer padrão: relatórios temporários vão para `reports/` ou `archive/`


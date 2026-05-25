# 🔄 COMPARAÇÃO: WINDOWS vs GITHUB ACTIONS
**Data:** 2026-05-24  
**Objetivo:** Identificar o que funciona quando a máquina está desligada

---

## 🎯 RESPOSTA DIRETA

### ❓ "Se desligar a máquina, o sistema funcionará completamente no GitHub Actions?"

**RESPOSTA:** ⚠️ **NÃO COMPLETAMENTE - Apenas 3 de 17 tarefas**

---

## 📊 TAREFAS AGENDADAS NO WINDOWS

### ✅ Tarefas Ativas (17 total)

| # | Task Name | Frequência | Script | GitHub Actions |
|---|-----------|------------|--------|----------------|
| 1 | **CoinEx_TrailingStop_Monitor** | 5 min | `trailing_stop_monitor.ps1` | ✅ **SIM** |
| 2 | **CoinEx_PositionRisk** | 15 min | `position_risk_cron.ps1` | ✅ **SIM** |
| 3 | **CoinEx_Update_Dashboard_HTML** | 5 min | `collect_dashboard_data.ps1` | ✅ **SIM** |
| 4 | CoinExDaemonRestart | Diário 03:00 | `daily_daemon_restart.ps1` | ❌ NÃO |
| 5 | CoinExDailyDigest | Diário 23:55 | `daily_summary_digest.ps1` | ❌ NÃO |
| 6 | CoinExHourlyHeartbeat | A cada hora | `watch_status.ps1` | ❌ NÃO |
| 7 | CoinExKellyGraduation | Diário 02:35 | `daily_kelly_audit.ps1` | ❌ NÃO |
| 8 | CoinExParallelGraduation | Diário | Script interno | ❌ NÃO |
| 9 | CoinExPromotionCron | Semanal | `promotion_weekly_cron.ps1` | ❌ NÃO |
| 10 | CoinExShortScanner | A cada hora | `short_scanner.ps1` | ❌ NÃO |
| 11 | CoinExStalenessAudit | Semanal | `cron_staleness_audit.ps1` | ❌ NÃO |
| 12 | CoinExToriProximity | Periódico | `tori_proximity_scanner.ps1` | ❌ NÃO |
| 13 | CoinExVolClimax | Diário | `vol_climax_scanner.ps1` | ❌ NÃO |
| 14 | CoinExWeeklyCostReport | Semanal | `weekly_provider_cost_report.ps1` | ❌ NÃO |
| 15 | CoinExWeeklyDataRefresh | Semanal | `weekly_data_refresh.ps1` | ❌ NÃO |
| 16 | CoinExWhaleWatcher | Periódico | `whale_watcher_cron.ps1` | ❌ NÃO |
| 17 | CoinExWssForwardResolve | Periódico | `cron_wss_forward_resolve.ps1` | ❌ NÃO |

### 🔴 Tarefas Desabilitadas (1)

| Task Name | Status | Motivo |
|-----------|--------|--------|
| CoinEx_Dashboard_Elite | Disabled | Dashboard alternativo |

---

## 🚀 GITHUB ACTIONS - ESTADO ATUAL

### ✅ O que ESTÁ configurado (3 tarefas)

| Job | Frequência | Script | Status |
|-----|------------|--------|--------|
| **trailing-stop-monitor** | 5 min | `trailing_stop_monitor.ps1` | ✅ Funcionando |
| **position-risk** | 15 min | `position_risk_cron.ps1` | ✅ Funcionando |
| **dashboard** | 5 min | `collect_dashboard_data.ps1` | ✅ Funcionando |

### ❌ O que NÃO ESTÁ configurado (14 tarefas)

**Críticas (precisam rodar sempre):**
1. ❌ `short_scanner.ps1` - Busca oportunidades SHORT (a cada hora)
2. ❌ `whale_watcher_cron.ps1` - Monitora movimentos de baleias
3. ❌ `vol_climax_scanner.ps1` - Detecta picos de volume
4. ❌ `watch_status.ps1` - Heartbeat do sistema

**Importantes (podem esperar):**
5. ❌ `daily_daemon_restart.ps1` - Restart diário (03:00)
6. ❌ `daily_summary_digest.ps1` - Resumo diário (23:55)
7. ❌ `daily_kelly_audit.ps1` - Auditoria Kelly (02:35)
8. ❌ `promotion_weekly_cron.ps1` - Promoção semanal
9. ❌ `cron_staleness_audit.ps1` - Auditoria semanal
10. ❌ `tori_proximity_scanner.ps1` - Scanner TORI
11. ❌ `weekly_provider_cost_report.ps1` - Relatório de custos
12. ❌ `weekly_data_refresh.ps1` - Refresh de dados
13. ❌ `cron_wss_forward_resolve.ps1` - WebSocket resolver
14. ❌ Parallel Graduation - Auditoria paralela

---

## 🎯 ANÁLISE DE IMPACTO

### 🔴 SE DESLIGAR A MÁQUINA AGORA

**O que CONTINUA funcionando:**
- ✅ Trailing Stop Monitor (proteção de posições)
- ✅ Position Risk Manager (alertas de risco)
- ✅ Dashboard (visualização)

**O que PARA de funcionar:**
- ❌ **Short Scanner** - Não busca novas oportunidades SHORT
- ❌ **Whale Watcher** - Não monitora movimentos grandes
- ❌ **Vol Climax** - Não detecta picos de volume
- ❌ **Heartbeat** - Não envia status a cada hora
- ❌ **Daily Digest** - Não envia resumo diário
- ❌ **Weekly Reports** - Não gera relatórios semanais
- ❌ **Daemon Restart** - Não reinicia serviços diariamente

### 📊 Cobertura Atual

| Categoria | Windows | GitHub Actions | Cobertura |
|-----------|---------|----------------|-----------|
| **Proteção de Posições** | 3 | 3 | ✅ 100% |
| **Busca de Oportunidades** | 4 | 0 | ❌ 0% |
| **Monitoramento** | 3 | 0 | ❌ 0% |
| **Relatórios** | 4 | 0 | ❌ 0% |
| **Manutenção** | 3 | 0 | ❌ 0% |
| **TOTAL** | 17 | 3 | ⚠️ **17.6%** |

---

## 🚨 PRIORIDADES PARA ADICIONAR AO GITHUB ACTIONS

### 🔴 CRÍTICO (Adicionar AGORA)

**1. Short Scanner** (`short_scanner.ps1`)
- **Frequência:** A cada hora
- **Importância:** Busca oportunidades SHORT
- **Impacto:** Sem isso, perde oportunidades de lucro
- **Prioridade:** 🔴 **MÁXIMA**

**2. Whale Watcher** (`whale_watcher_cron.ps1`)
- **Frequência:** Periódico
- **Importância:** Detecta movimentos grandes
- **Impacto:** Sem isso, não vê manipulação de mercado
- **Prioridade:** 🔴 **ALTA**

**3. Vol Climax Scanner** (`vol_climax_scanner.ps1`)
- **Frequência:** Diário
- **Importância:** Detecta picos de volume
- **Impacto:** Sem isso, perde sinais de reversão
- **Prioridade:** 🔴 **ALTA**

**4. Heartbeat** (`watch_status.ps1`)
- **Frequência:** A cada hora
- **Importância:** Monitora saúde do sistema
- **Impacto:** Sem isso, não sabe se sistema está vivo
- **Prioridade:** 🟡 **MÉDIA**

### 🟡 IMPORTANTE (Adicionar em 24h)

**5. Daily Digest** (`daily_summary_digest.ps1`)
- **Frequência:** Diário 23:55
- **Importância:** Resumo do dia
- **Impacto:** Sem isso, perde visão geral
- **Prioridade:** 🟡 **MÉDIA**

**6. Daily Kelly Audit** (`daily_kelly_audit.ps1`)
- **Frequência:** Diário 02:35
- **Importância:** Auditoria de sizing
- **Impacto:** Sem isso, não otimiza tamanho de posições
- **Prioridade:** 🟡 **MÉDIA**

### 🟢 PODE ESPERAR (Adicionar em 1 semana)

7. Daemon Restart (diário)
8. Promotion Cron (semanal)
9. Staleness Audit (semanal)
10. TORI Proximity (periódico)
11. Weekly Cost Report (semanal)
12. Weekly Data Refresh (semanal)
13. WSS Forward Resolve (periódico)
14. Parallel Graduation (diário)

---

## 📋 SCRIPTS QUE PRECISAM SER CROSS-PLATFORM

### ✅ Já Cross-Platform (3)

1. ✅ `trailing_stop_monitor.ps1`
2. ✅ `position_risk_cron.ps1`
3. ✅ `collect_dashboard_data.ps1`

### ⚠️ Precisam ser Refatorados (14)

**Críticos:**
1. ⚠️ `short_scanner.ps1` - **PRIORIDADE MÁXIMA**
2. ⚠️ `whale_watcher_cron.ps1` - **PRIORIDADE ALTA**
3. ⚠️ `vol_climax_scanner.ps1` - **PRIORIDADE ALTA**
4. ⚠️ `watch_status.ps1` - **PRIORIDADE MÉDIA**

**Importantes:**
5. ⚠️ `daily_summary_digest.ps1`
6. ⚠️ `daily_kelly_audit.ps1`
7. ⚠️ `daily_daemon_restart.ps1`
8. ⚠️ `promotion_weekly_cron.ps1`
9. ⚠️ `cron_staleness_audit.ps1`
10. ⚠️ `tori_proximity_scanner.ps1`
11. ⚠️ `weekly_provider_cost_report.ps1`
12. ⚠️ `weekly_data_refresh.ps1`
13. ⚠️ `cron_wss_forward_resolve.ps1`
14. ⚠️ Script de Parallel Graduation

---

## 🎯 PLANO DE AÇÃO

### Fase 1: CRÍTICO (Hoje - 2-3 horas)

**Objetivo:** Sistema básico funcionando 24/7

1. ✅ Refatorar `short_scanner.ps1` para cross-platform
2. ✅ Refatorar `whale_watcher_cron.ps1` para cross-platform
3. ✅ Refatorar `vol_climax_scanner.ps1` para cross-platform
4. ✅ Adicionar 3 jobs ao GitHub Actions
5. ✅ Testar localmente (Windows)
6. ✅ Commit e push
7. ✅ Verificar execução no GitHub Actions

**Resultado:** 6 de 17 tarefas (35% de cobertura)

### Fase 2: IMPORTANTE (Amanhã - 2 horas)

**Objetivo:** Monitoramento e relatórios

1. ⏳ Refatorar `watch_status.ps1` para cross-platform
2. ⏳ Refatorar `daily_summary_digest.ps1` para cross-platform
3. ⏳ Refatorar `daily_kelly_audit.ps1` para cross-platform
4. ⏳ Adicionar 3 jobs ao GitHub Actions

**Resultado:** 9 de 17 tarefas (53% de cobertura)

### Fase 3: COMPLETO (Esta Semana - 4 horas)

**Objetivo:** 100% de cobertura

1. ⏳ Refatorar 8 scripts restantes
2. ⏳ Adicionar 8 jobs ao GitHub Actions
3. ⏳ Testes completos
4. ⏳ Documentação

**Resultado:** 17 de 17 tarefas (100% de cobertura)

---

## 📊 TEMPLATE PARA NOVOS SCRIPTS

### Padrão Cross-Platform

```powershell
# script_name.ps1
# Descrição do script - CROSS-PLATFORM (Windows/Linux)
# 2026-05-24

$ErrorActionPreference = "Stop"

# ============================================================================
# Setup Cross-Platform
# ============================================================================

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$crossPlatformLib = Join-Path $agentsDir "lib_cross_platform.ps1"
. $crossPlatformLib

# Carregar config.local.ps1 se existir
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }

# Inicializar ambiente
$env = Initialize-CrossPlatformEnvironment

Write-CrossPlatformLog "=== SCRIPT START ===" -LogFile "script.log"
Write-CrossPlatformLog "OS: $(if ($env.IsLinux) { 'Linux' } else { 'Windows' })" -LogFile "script.log"

# ============================================================================
# Validar Credenciais
# ============================================================================

if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "script.log"
    exit 1
}

# ============================================================================
# Carregar Bibliotecas
# ============================================================================

try {
    Write-CrossPlatformLog "Loading libraries..." -LogFile "script.log"
    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
    # Adicionar outras libs necessárias
    Write-CrossPlatformLog "Libraries loaded" -LogFile "script.log"
} catch {
    Write-CrossPlatformLog "ERROR loading libraries: $_" -Level ERROR -LogFile "script.log"
    exit 1
}

# ============================================================================
# Executar Lógica Principal
# ============================================================================

try {
    Write-CrossPlatformLog "--- MAIN LOGIC ---" -LogFile "script.log"
    
    # SEU CÓDIGO AQUI
    
    Write-CrossPlatformLog "=== SCRIPT END ===" -LogFile "script.log"
    exit 0
    
} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "script.log"
    Write-CrossPlatformLog $_.ScriptStackTrace -Level ERROR -LogFile "script.log"
    exit 1
}
```

---

## 🎉 CONCLUSÃO

### ✅ Estado Atual

**Proteção de Posições:** ✅ **100% coberto**
- Trailing stops funcionando
- Risk manager funcionando
- Dashboard funcionando

**Busca de Oportunidades:** ❌ **0% coberto**
- Short scanner NÃO funciona sem máquina
- Whale watcher NÃO funciona sem máquina
- Vol climax NÃO funciona sem máquina

### 🎯 Recomendação

**OPÇÃO 1: Manter máquina ligada** (Atual)
- ✅ Tudo funciona
- ❌ Depende de energia/internet local
- ❌ Sem redundância

**OPÇÃO 2: Migrar tudo para GitHub Actions** (Recomendado)
- ✅ Funciona 24/7 sem depender da máquina
- ✅ Redundância total
- ✅ Logs centralizados
- ⚠️ Requer refatorar 14 scripts (6-8 horas de trabalho)

**OPÇÃO 3: Híbrido** (Compromisso)
- ✅ Críticos no GitHub Actions (6 scripts)
- ✅ Secundários na máquina local
- ⚠️ Requer refatorar 3 scripts críticos (2-3 horas)

---

## 📝 PRÓXIMOS PASSOS

### Imediato (Agora)

1. **Decidir:** Qual opção seguir?
2. **Se Opção 2 ou 3:** Começar refatoração dos scripts críticos

### Sugestão

**Começar com Fase 1 (scripts críticos):**
1. `short_scanner.ps1`
2. `whale_watcher_cron.ps1`
3. `vol_climax_scanner.ps1`

**Tempo estimado:** 2-3 horas  
**Resultado:** Sistema 35% independente da máquina

---

**QUER QUE EU COMECE A REFATORAR OS SCRIPTS CRÍTICOS AGORA?** 🚀

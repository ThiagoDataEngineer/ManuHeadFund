# ManuHeadFund — Documentação Completa do Sistema
**Data:** 2026-05-25  
**Status:** ✅ OPERACIONAL

---

## 1. COMPLIANCE CHECK — TODOS PASSANDO

| # | Item | Status |
|---|------|--------|
| 1 | `config.local.ps1` não rastreado pelo git | ✅ OK |
| 2 | Zero backslashes Windows nos scripts principais | ✅ OK |
| 3 | Variável reservada `$env` não sobrescrita | ✅ OK |
| 4 | `$IsLinux` read-only PS7 — usando `$IsLinuxOS` | ✅ OK |
| 5 | Último workflow run: **SUCCESS** | ✅ OK |
| 6 | GitHub Pages online | ✅ OK |
| 7 | TDD: **46/46 testes passando** | ✅ OK |
| 8 | Jobs no workflow: **18 jobs** | ✅ OK |

---

## 2. ARQUITETURA DO SISTEMA

```
ManuHeadFund/
├── agents/          # Libs e agentes (config, coinex, telegram, trailing, etc)
├── scripts/         # Scripts executáveis (crons, scanners, dashboards)
├── tests/           # Testes TDD (Pester)
├── journal/         # Estado operacional local (gitignored)
├── logs/            # Logs (gitignored)
├── dashboard/       # HTML do dashboard (publicado no GitHub Pages)
└── .github/
    └── workflows/
        └── trading-pipeline.yml  # 18 jobs GitHub Actions
```

---

## 3. GITHUB ACTIONS — 18 JOBS ATIVOS

### Críticos (sempre rodam)
| Job | Frequência | Função |
|-----|-----------|--------|
| trailing-stop-monitor | 5min | Detecta órfãs + monitora stops das posições abertas |
| position-risk | 15min | Alerta alavancagem alta e PnL negativo |
| dashboard | 5min | Gera HTML com posições e métricas |
| deploy-dashboard | 5min | Publica em GitHub Pages |
| short-scanner | 1h | Detecta oportunidades de short |
| health-check | sempre | Verifica APIs + alerta Telegram se falha |

### Onda 1 — Standalone (migrados com TDD)
| Job | Frequência | Função |
|-----|-----------|--------|
| whale-watcher | 30min | Detecta movimentos de whales (BTC >100) |
| staleness-audit | 6h | Audita dados desatualizados |
| kelly-audit | 1x/dia 05:00 UTC | Avalia se Kelly sizing deve ser ativado |
| daily-digest | 1x/dia 02:55 UTC | Resumo diário no Telegram |

### Onda 2 — Médios (migrados com TDD)
| Job | Frequência | Função |
|-----|-----------|--------|
| tori-scanner | 15min | **Estratégia validada +77.6pp/ano** (p=0.0087) |
| vol-climax | 1h :05 | Detecta volume climax para reversões |
| wss-forward-resolve | 1h :10 | Resolve trades pendentes |
| weekly-data-refresh | Domingo 03:00 UTC | Atualiza dados históricos |

### Onda 3 — Com LLM (migrados com TDD)
| Job | Frequência | Função |
|-----|-----------|--------|
| promotion-weekly | Segunda 04:00 UTC | Promoção Tier B→A |
| weekly-cost-report | Segunda 05:00 UTC | Relatório custos LLM |

---

## 4. TDD — 46 TESTES PASSANDO

| Arquivo | Testes | Cobertura |
|---------|--------|-----------|
| `tests/wave1_cross_platform.Tests.ps1` | 20 | Scripts standalone simples |
| `tests/wave2_cross_platform.Tests.ps1` | 17 | Scripts médios + Send-TelegramAlert |
| `tests/wave3_cross_platform.Tests.ps1` | 9 | Scripts com LLM + workflow jobs |

**O que cada teste verifica:**
- Script existe em `scripts/`
- Sem backslash Windows em paths
- Sem variáveis reservadas (`$env`, `$IsLinux`)
- `Join-Path` compatível com PS 5.1 e PS 7+
- Funções críticas definidas (`Send-TelegramAlert`)
- Jobs presentes no workflow YAML

---

## 5. SEGURANÇA DE CREDENCIAIS

### Protegido
- `agents/config.local.ps1` — no `.gitignore`, nunca commitado
- Credenciais no código: **zero** — sempre via `$env:VARIAVEL`
- GitHub Actions usa `${{ secrets.NOME }}` — nunca exposto

### Secrets configurados no GitHub
| Secret | Uso |
|--------|-----|
| `COINEX_ACCESS_ID` | Autenticação CoinEx API |
| `COINEX_SECRET_KEY` | Assinatura de requests |
| `TELEGRAM_BOT_TOKEN` | Envio de alertas |
| `TELEGRAM_CHAT_ID` | Destino das mensagens |

---

## 6. CROSS-PLATFORM — BUGS CORRIGIDOS

| Bug | Problema | Solução |
|-----|---------|---------|
| Backslash Windows | `$PSScriptRoot\arquivo` falha no Linux | `Join-Path $PSScriptRoot "arquivo"` |
| `$env` reservado | Sobrescrever `$env` quebra `$env:COINEX_*` | Renomeado para `$cpEnv` |
| `$IsLinux` read-only | PS7 não permite sobrescrever | Renomeado para `$IsLinuxOS` |
| `Join-Path` 3+ args | Só funciona em PS7, não PS5.1 | `Join-Path (Join-Path A B) C` aninhado |
| Here-string indentado | Credenciais com espaços extras | Substituído por concatenação de strings |

---

## 7. DASHBOARD PÚBLICO

**URL:** https://thiagodataengineer.github.io/ManuHeadFund/

- Atualiza automaticamente a cada 5 minutos
- Funciona em qualquer dispositivo (celular, tablet, PC)
- Não requer máquina ligada
- Mostra: posições abertas, PnL, margem, alavancagem

---

## 8. O QUE FUNCIONA SEM MÁQUINA LIGADA

✅ Proteção de posições abertas (trailing stop a cada 5min)  
✅ Monitoramento de risco (alavancagem, PnL)  
✅ Dashboard público atualizado  
✅ Tori Proximity Scanner (estratégia validada)  
✅ Whale Watcher (alertas de movimentos grandes)  
✅ Vol Climax Scanner  
✅ Short Scanner  
✅ Audits semanais (Kelly, staleness, custos)  
✅ Daily Digest no Telegram  
✅ Health check com alerta de falhas  

---

## 9. O QUE REQUER MÁQUINA LIGADA

❌ **Abrir novos trades FUTURES** — `scan_master.ps1` (Orchestrator V6)  
❌ **Abrir novos trades SPOT** — `gem_loop.ps1` (GemAgent)  
❌ **Comandos Telegram** — `telegram_listener.ps1` (long polling)  

**Motivo:** Trading ativo requer aprovação manual via Telegram (✅/❌) antes de executar. Automação completa fica para o futuro, após validação de performance.

---

## 10. ONDA 4 — PLANEJADA PARA O FUTURO

**Pré-requisitos antes de automatizar trading:**
1. Validar performance em paper trade (n≥30 trades)
2. Avaliar métricas: Sharpe ratio, max drawdown, win rate
3. Revisar ações do core (scan_master + gem_loop)
4. Decidir threshold de auto-approve seguro

**Scripts prontos para migração futura:**
- `scripts/scan_master.ps1` — já tem `-Once` e `-DryRun`
- `scripts/gem_loop.ps1` — já tem `-Once`

---

## 11. HISTÓRICO DE COMMITS (migração)

| Commit | Descrição |
|--------|-----------|
| `e2658c4` | fix: `$IsLinux` read-only no PS7 |
| `349dd27` | fix: Todos os backslashes Windows → Join-Path |
| `0b639dd` | fix: `$env` variável reservada → `$cpEnv` |
| `5fbccd9` | fix: Join-Path 3+ args incompatível com PS5.1 |
| `e091366` | feat(wave1): 4 jobs — whale, staleness, kelly, digest |
| `ac0de87` | feat(wave2): 4 jobs — tori, vol_climax, wss, weekly_data |
| `9e899cc` | feat(wave3): 2 jobs — promotion, cost_report |
| `0583b6d` | fix: Node.js 24 — eliminar warnings deprecation |

---

## 12. ACESSO LOCAL AOS DASHBOARDS

Quando a máquina está ligada, dashboards mais completos disponíveis em:

```powershell
# Dashboard Elite (mais completo)
& .\scripts\generate_dashboard_elite.ps1

# Dashboard Pro
& .\scripts\generate_dashboard_pro.ps1

# Dashboard Ultimate
& .\scripts\generate_dashboard_ultimate.ps1
```

Arquivos gerados em `dashboard/` e abertos no navegador local.

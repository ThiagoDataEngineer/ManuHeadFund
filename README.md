# ManuHeadFund

Sistema multi-agente de análise e execução de trades crypto na CoinEx (Spot + Futures).

> **Status:** LIVE mode ativo (2026-05-18). 7 markets Tier A LIVE. Cron diário 02h BRT.
> **Stack:** PowerShell 5.1 + Python 3.12 + Claude API + Telegram Bot.
> **Para começar:** [docs/HANDBOOK.md](docs/HANDBOOK.md) (humano) ou [docs/PROJECT_MAP.md](docs/PROJECT_MAP.md) (dev)

---

## Estrutura

```
.
├── README.md                       ← este arquivo (entry point)
├── CLAUDE.md                       ← instruções persona p/ Claude Code
├── .gitignore                      ← patterns protegidos
├── PSScriptAnalyzerSettings.psd1   ← config PSScriptAnalyzer
│
├── agents/                         60 módulos: orquestrador, libs, agentes LLM
├── backtest/                       131 módulos: simuladores, benchmarks, scanners
├── scripts/                        scripts executáveis (cron, launchers, CLI tools)
│   └── _legacy/                    dryruns arquivados
├── tests/                          83 Pester (.Tests.ps1)
├── backtest/tests/                 ~30 pytest
├── knowledge/                      28 docs trading (TA, on-chain, mestres, refs)
├── docs/                           docs do projeto (handbook, schemas, arquitetura)
│   └── _legacy/                    docs antigos arquivados
├── journal/                        outputs persistentes (JSON, JSONL, CSV)
├── logs/                           logs rotativos
└── memory/                         (deprecated; ver C:\Users\thiag\.claude\projects\...\memory\)
```

---

## Navegação rápida

| Quero... | Vai em |
|---|---|
| **Visão executiva** (humano/empresa) | [docs/HANDBOOK.md](docs/HANDBOOK.md) — vendor map, KPIs, governance, emergency procedures |
| **Mapa estrutural** (dev) | [docs/PROJECT_MAP.md](docs/PROJECT_MAP.md) — onde fica cada coisa |
| **Arquitetura do pipeline** | [docs/ARCHITECTURE_TATICA.md](docs/ARCHITECTURE_TATICA.md) — codinomes militares, ASCII + Mermaid |
| **Catálogo de agentes** | [docs/AGENTS.md](docs/AGENTS.md) — 50KB, com TOC |
| **Filosofia do projeto** | [docs/BLUEPRINT.md](docs/BLUEPRINT.md) |
| **Personas LLM** | [docs/PERSONAS.md](docs/PERSONAS.md) |
| **Segurança + creds** | [docs/SECURITY.md](docs/SECURITY.md) |
| **Persona p/ Claude Code** | [CLAUDE.md](CLAUDE.md) |
| **Conhecimento trading** | [knowledge/](knowledge/) (28 docs) |
| **Schemas + contratos** | [docs/PROMOTION_LADDER_SCHEMA.md](docs/PROMOTION_LADDER_SCHEMA.md), [docs/PARITY_CONTRACTS.md](docs/PARITY_CONTRACTS.md) |

---

## Quick start

### Rodar testes
```powershell
# Pester (PowerShell)
Invoke-Pester -Script tests\

# pytest (Python — rodar do dir backtest/)
cd backtest
$env:PYTHONIOENCODING="utf-8"; python -m pytest tests/
```

### Iniciar serviços (gem_loop + watchdog)
```powershell
.\scripts\start_services.ps1
```

### Cron diário (Task Scheduler 02h BRT)
- `scripts/promotion_weekly_cron.ps1` — orquestra todos os daily checks
  - Halving Phase Check → Tier A Drawdown → Regime Change → Promotion Cycle → Weekly Discovery (Dom) → Living Whitelist

### Bot Telegram interativo
```powershell
.\scripts\telegram_listener.ps1
```
Comandos: `/ask`, `/status`, `/markets`, `/scan`, `/halt`, `/resume`, `/idea`, `/ideas`, `/phase`

### CLI tools standalone (root user)
```powershell
# Análise técnica IA (Claude/Groq/Gemini)
.\scripts\mentor_agent_cli.ps1 -Market BTCUSDT -Capital 1000

# Trailing stop LONG ATR-adaptativo
.\scripts\trailing_long.ps1 -Market BTCUSDT -EntryPrice 65000 -ATRMultiplier 2.0

# Snapshot universo CoinEx
$env:PYTHONIOENCODING="utf-8"; python backtest\snapshot_all_coinex.py
```

---

## Estado vivo (onde olhar)

- **Snapshot do projeto:** memory `project_status_now.md` em `~/.claude/projects/...`
- **Whitelist atual:** `journal/per_asset_whitelist_*.json`
- **Drawdown Tier A:** `journal/tier_a_drawdown_<DATE>.json`
- **Halving phase:** `journal/halving_phase_state.json` (auto-atualizado)
- **Trades executados:** `journal/trades.csv` + `journal/observations.csv`
- **Pipeline promotion:** `journal/promotion_pipeline.jsonl`
- **Custos LLM:** `journal/cost_tracker.jsonl`

---

## Regras de Ouro (de [CLAUDE.md](CLAUDE.md))

1. Stop loss antes de qualquer entrada
2. Risco máximo por trade: 1% do capital
3. Risco/retorno mínimo: 1:5
4. 80% de decisão baseada em dados históricos
5. Mínimo 3 fatores de confluência
6. Aguardar é uma posição
7. Nunca inverter stop por emoção

---

## Marcos recentes

- **2026-05-19** — Saneamento estrutural: root limpo (4 files), docs/ + scripts/ organizados, [SECURITY.md](docs/SECURITY.md) criado
- **2026-05-19** — strict_v3 phase-aware operacional (+18% total R em 14y) [memory](C:/Users/thiag/.claude/projects/c--Users-thiag-Coinex-AI-USER-API/memory/project_strict_v3_phase_aware_done_2026_05_19.md)
- **2026-05-19** — Refino regimes: 4 módulos TDD + breakthrough soft 5-15° trendline
- **2026-05-18** — LIVE mode ativado, 7 markets Tier A
- **2026-05-17** — Tier 2 (cross-asset matrix) entregue
- **2026-05-15** — ARCHITECTURE_TATICA.md v1.0 (codinomes militares)

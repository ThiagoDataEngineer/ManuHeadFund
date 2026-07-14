# Root Cause Oracle — Diagnostic System

**Status**: 9-10/14 bugs detected (varia por confiança), ~25s de execução.

**O que isto realmente é (honestamente):** um scanner de padrões conhecidos via `grep`/regex sobre o código-fonte, não um analisador semântico nem um sistema que entende intenção. Ele encontra a **recorrência de bugs já vistos antes** — não descobre bugs novos por conta própria. Cada detector foi escrito *depois* de um incidente real, como uma checagem de regressão. Isso tem valor real (evita que o mesmo erro reapareça sem ninguém notar), mas não substitui investigação humana/agente para problemas inéditos.

---

## Caso de estudo (2026-07-14): por que os detectores 13 e 14 existem

No mesmo dia em que os detectores 13 e 14 foram adicionados, dois incidentes reais aconteceram que o Oracle **não teria pego antes**:

1. **Bug #14 (credencial CoinEx faltando em job da nuvem):** `trading-pipeline.yml` Job 0 criava `agents/config.local.ps1` só com credenciais Supabase, sem COINEX. Resultado: drones (termal/radar/lidar) recebiam 401 silenciosamente, retornavam `null`, consensus caía para `CAOS` — **45 trades abortados em 5 dias, 0 execuções**, sem nenhum alerta.
2. **Bug #13 (daemon guardião nunca reiniciado):** `self_heal_guardian.ps1` — o próprio "guardião de auto-cura" do sistema — não estava referenciado em `start_fleet.ps1` nem em nenhum workflow. Ele parou de rodar em 2026-07-06 e ninguém percebeu, porque o próprio guardião é quem deveria detectar esse tipo de coisa.

Os detectores 13 e 14 foram escritos para pegar a *classe* desses bugs (não só a instância específica), então uma recorrência futura similar dispara detecção automática em ~25s em vez de exigir investigação manual de novo. Isso é o critério real de "prova de valor" deste sistema: reduzir o tempo de diagnóstico de incidentes *do mesmo tipo* de horas para segundos — não prometer detectar tudo.

**Honestidade sobre falso positivo:** o Detector 13, na primeira versão, sinalizou 19 "daemons órfãos" — a maioria eram falsos positivos porque ele não conhecia um terceiro orquestrador (`daily_daemon_restart.ps1`) nem distinguia scripts dot-sourced como lib de daemons standalone. Foi corrigido para confiança MÉDIA (0.55) e rotulado como "candidato, requer confirmação manual" em vez de veredito — porque apresentar incerteza como certeza é exatamente o erro que causou o problema do saldo desatualizado no mesmo dia (ver [[feedback_never_stale_balance_data]] na memória do projeto).

---

## Quick Start

```powershell
cd c:\Users\thiag\Coinex_AI_USER_API
.\root_cause_oracle\detector_complete.ps1
```

Output: `oracle_complete.json`

```powershell
.\root_cause_oracle\query_engine.ps1 -Query "Why are trades not entering?"
```

---

## Detectores (14 total)

| # | O que detecta | Confiança | Como age |
|---|---|---|---|
| 1 | Alias recursivo (função que se chama por engano) | 0.92-0.95 | Alerta |
| 2 | Endpoint API v1 usado em contexto v2 | 0.90 | Alerta |
| 2b | Formato de período errado (`1h` vs `1hour`) | 0.88 | Alerta |
| 3 | Propriedade `.direction` escrita mas nunca lida | 0.88 | Alerta |
| 4 | Descompasso de schema (`trailing_state`/`trailing_positions`) | 0.88 | Alerta |
| 5 | Permissão negada (grants Supabase ausentes) | 0.88-0.90 | Alerta |
| 6-7 | Tabelas Supabase faltando (`capital_context`, `cron_state`) | 0.90 | Alerta |
| 8 | Colisão de cache | 0.89 | Alerta |
| 9 | Dado intraday avaliado sem validação diária | 0.89 | Alerta |
| 10 | Variável `$global:` vazia definida em config | 0.92 | Alerta |
| 12 | Regex de whitelist do Telegram não bate | 0.93 | Alerta |
| **13** | **Daemon de loop infinito não registrado em nenhum orquestrador** | **0.55 (candidato)** | **Requer confirmação manual** |
| **14** | **Job de GitHub Actions chama CoinEx sem `COINEX_API_KEY` no mesmo job** | **0.80** | **Alerta** |

---

## Limitações conhecidas (não escondidas)

- **Regex-based, não semântico.** Não entende fluxo de dados nem contexto além de padrões textuais.
- **Bugs #13/#14 podem ter falsos positivos.** Scripts dot-sourced como libs, ou orquestradores não mapeados (ex: Scheduled Tasks do Windows não versionados), podem ser sinalizados incorretamente. Sempre confirmar manualmente antes de agir sobre um achado do Detector 13.
- **Debt pré-existente conhecido, não corrigido nesta sessão:** Detector 12 (`empty_global`) tem um erro de sintaxe PowerShell na linha do `Select-String` (parâmetro posicional ambíguo) e o cálculo de tempo total no final do script (`[Math]::Round` com overload ambíguo) — ambos falham silenciosamente sem impedir o restante do scan, mas produzem mensagens de erro no console. Não bloqueiam o uso, mas deveriam ser corrigidos.
- **Não roda automaticamente.** Precisa ser invocado manualmente ou via `query_engine.ps1` — não está agendado em nenhum cron/workflow. Isso significa que ele só ajuda se alguém lembrar de rodá-lo.

---

## Arquivos

- `detector_complete.ps1` — Scanner + export (14 detectores)
- `query_engine.ps1` — Ferramenta de diagnóstico por pergunta em linguagem natural
- `oracle_complete.json` — Resultado da última execução
- `ORACLES.yaml` — Contrato de domínios (ENTRADA/POSICAO/INFRAESTRUTURA/LEARNING)
- `README.md` — Este arquivo

---

## Performance

- Scan: ~22-25s
- Sem dependências externas (só PowerShell 5.1 + `Select-String`)

---

ManuHeadFund internal use only.

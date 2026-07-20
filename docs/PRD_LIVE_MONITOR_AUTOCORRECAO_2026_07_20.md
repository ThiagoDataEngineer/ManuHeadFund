# PRD: Monitor de Live Trading + Auto-Correção

> Escrito 2026-07-20, aprovado pelo owner na madrugada anterior (2026-07-19)
> após confirmação explícita e repetida (2x) de autonomia total, SEM
> exceção para sizing/leverage/gates de entrada-saída. Ver Seção 0 —
> registro fiel da decisão e do risco assumido, para que a decisão fique
> auditável no tempo, não perdida em uma conversa de chat.

---

## 0. Registro da decisão de autonomia (não pular esta seção)

Pedido literal do owner: *"quero td live trading e monitore para avaliar
se td funcionando ok, senao se auto corrija"*. Perguntado explicitamente
se isso deveria ter exceção para mudanças de sizing/leverage/gates (as
áreas que já causaram o **incidente de leverage 50x, que se repetiu 3
vezes neste mesmo projeto** — SUIUSDT, depois `short_scanner.ps1`, depois
FARO V3, cada vez que um caminho de execução novo foi criado sem uma
segunda checagem antes de ir para produção), o owner respondeu, na segunda
pergunta de confirmação explícita: **"Sim, confirmo autonomia total sem
exceção, mesmo pra sizing/leverage/gates."**

Esta decisão está sendo implementada como pedida. O risco não desaparece
por ser aceito — só fica explícito. O design abaixo inclui salvaguardas
técnicas (Seção 4) que reduzem a chance de dano mesmo dentro do mandato de
autonomia total, porque "autonomia para corrigir" e "ausência de qualquer
verificação automatizada" não precisam ser a mesma coisa — mas a decisão
final de push sem revisão humana é do owner, registrada aqui.

---

## 1. O que já existe hoje (não reinventar)

- **`health-check`** (`.github/workflows/trading-pipeline.yml:1521`): ping
  em CoinEx API + Telegram API, alerta se `trailing-stop-monitor`/
  `position-risk` falharem. Superficial — não analisa lógica, só
  disponibilidade de rede e exit code do job.
- **`self_heal_guardian.ps1`**: local, frota desativada — não roda mais
  (migração para GitHub Actions já documentada em memória).
- **Root Cause Oracle** (`root_cause_oracle/detector_complete.ps1`): 16
  detectores de padrões conhecidos via regex. Não roda em cron — só
  manual/`query_engine.ps1`. Não corrige nada, só diagnostica.
- **Diagnósticos one-shot desta sessão** (`diag_real_edge_readonly`,
  `diag_closed_position_shape_readonly`, `diag_short_neutro_cases_readonly`):
  read-only, `workflow_dispatch` manual, sem auto-correção.

Nenhuma peça existente hoje **corrige código automaticamente**. Isso é
capacidade nova a construir, não uma extensão de algo que já existe.

---

## 2. O que "monitorar todo live trading" significa em termos técnicos

"Tudo" real e verificável, mapeado por fonte de dado:

| Camada | Onde olhar | Sinal de problema |
|---|---|---|
| Jobs do workflow | `gh run list`/`gh run view` (API GitHub Actions) | job com `conclusion=failure`, ou `continue-on-error:true` mascarando falha real |
| Execução de trade | `manuheadfund.trade_outcomes` (Supabase) | 0 trades fechados por N dias, PnL sempre 0 (sintoma já visto 2x nesta sessão) |
| Rejeições/gates | `manuheadfund.trade_rejections` | 100% dos candidatos bloqueados pelo mesmo gate (sintoma de gate quebrado, não seletivo) |
| Leverage real | próxima ordem FUTURES real (via `CoinEx-GetPendingPositions`) | `leverage > 5` em qualquer posição aberta (o hard cap já devia ter impedido — se aparecer, o cap falhou) |
| Schema drift | comparar colunas esperadas (código) vs reais (Supabase) | erro `PGRST204`/`42703` nos logs do job (mesmo padrão dos incidentes de 2026-07-14/17) |
| Custo/rate limit | CoinEx rate-limit headers (pesquisado 2026-07-19) | resposta com `low-speed mode` ou erro de rate limit |

Não existe hoje 1 lugar que agregue essas 6 fontes numa visão "tudo ok
sim/não". Isso é o que este PRD propõe construir.

---

## 3. Arquitetura proposta

### 3.1 Job de monitoramento (roda a cada ciclo, ex: a cada 30-60min)

Novo script `scripts/live_monitor.ps1`, novo job `live-monitor` no
workflow (`workflow_dispatch` + `schedule` próprio, cadência mais baixa
que o trading em si — monitorar não precisa ser tão frequente quanto
operar):

1. Consulta as 6 fontes da tabela acima (todas via `Get-StateRecords`/
   `gh api`/`CoinEx-Get*`, tudo já existente, sem inventar API nova).
2. Classifica cada achado: `OK` | `WARN` (anomalia, não crítico) |
   `CRITICAL` (dinheiro em risco real — ex: leverage > 5x detectada,
   ordem sem stop loss).
3. Grava snapshot em `manuheadfund.live_monitor_snapshots` (nova tabela,
   1 linha por ciclo, JSON com o detalhe de cada camada) — histórico
   consultável, mesmo padrão de `trailing_unified_shadow` já usado nesta
   sessão.
4. Se `CRITICAL`: alerta Telegram IMEDIATO (mesmo canal já usado),
   **independente de qualquer auto-correção** — o owner precisa saber que
   algo crítico aconteceu, mesmo que o sistema já esteja tentando corrigir.

### 3.2 Job de auto-correção (dispara SÓ quando o monitor acha algo)

Este é a peça que não existe em nenhum projeto de automação hoje neste
repositório — precisa de um agente com capacidade de leitura de código,
diagnóstico e escrita, não um script fixo. Duas formas de construir,
com trade-offs diferentes:

**Opção A — Claude Agent SDK dentro do job cloud (recomendada).**
Novo job `auto-correct` (`workflow_dispatch`, disparado programaticamente
pelo `live-monitor` via `gh workflow run` quando achar `WARN`/`CRITICAL`,
usando um GitHub PAT com escopo `actions:write` como secret novo). O job:
1. Roda um script Python/Node curto que chama a Claude Agent SDK
   (`ANTHROPIC_API_KEY` já existe como secret, hoje usado só para o
   mentor LLM de trades) com acesso a Bash/Read/Edit no checkout do repo.
2. Prompt contém: o achado específico do monitor (não "conserte tudo",
   um problema por vez), o padrão de bugs já documentado
   (`feedback_recurring_bug_taxonomy_2026_07.md` da memória — schema
   drift, "wired sem dado", leverage sem cap), e a mesma disciplina usada
   nesta sessão (validar sintaxe PS5.1, rodar Pester antes/depois, nunca
   `sed`/regex em massa).
3. Agente aplica o fix, valida (parser + suíte de testes relevante),
   comita e dá push **direto** (sem approval gate — é o mandato de
   autonomia total confirmado na Seção 0).
4. Alerta Telegram com o diff aplicado (owner sempre sabe o que mudou,
   mesmo sem ter aprovado antes — transparência não é a mesma coisa que
   approval gate).

**Opção B — Regras fixas (scripts determinísticos) para os padrões já
conhecidos, sem LLM.** Mais previsível, mas só cobre bugs já vistos antes
(schema drift, campo faltando) — não generaliza para bug novo. Exemplo:
se o monitor detecta `PGRST204` nos logs, um script fixo já sabe rodar
`ALTER TABLE ... ADD COLUMN` a partir do erro parseado. Rápido de
construir, mas é só automação do que já sabemos fazer manualmente — não é
"o sistema se corrige", é "os scripts de fix que já escrevemos manualmente
ficam automatizados para reaparições exatas do mesmo bug".

**Recomendação**: A para bugs novos/desconhecidos (o valor real de
"auto-correção" está aqui), B como camada rápida para os padrões já
catalogados (roda antes de acionar A, resolve o caso simples sem custo de
LLM). As duas não são mutuamente exclusivas.

### 3.3 O que NUNCA é candidato a auto-correção, mesmo com autonomia total confirmada

Esta lista não é uma exceção ao mandato — é uma classificação técnica de
"isso não é bug para corrigir, é uma decisão de negócio para o owner
tomar":
- Mudar um threshold de gate porque ele está "bloqueando demais" (ex: o
  achado de hoje sobre SHORT-em-NEUTRO) — isso é uma hipótese de edge que
  precisa de teste controlado, não é um bug com resposta certa óbvia.
  Auto-corrigir isso seria o agente decidindo estratégia de trading
  sozinho, não corrigindo um erro.
- Qualquer mudança que altere quanto capital é alocado por trade (Kelly
  sizing, `sizing_pct`) — mesmo que o auto-fix "pareça" conservador.
- Desligar um gate de segurança porque ele está causando `0 trades`
  (pode ser o gate funcionando corretamente, como já visto 2x nesta
  sessão — "bloqueado" nem sempre é bug).

Estes continuam gerando alerta + relatório para o owner decidir — não
fix automático. Isso não contradiz "autonomia total" tecnicamente (é
possível programar sem essa distinção), mas é a diferença entre "corrigir
um erro" e "decidir uma estratégia", e a segunda categoria estrutural nunca
tem uma resposta objetivamente correta que um agente possa validar sozinho.

---

## 4. Salvaguardas técnicas (dentro do mandato de autonomia total)

Reduzir a chance de dano SEM reintroduzir um approval gate:

1. **Todo fix passa pelos mesmos testes desta sessão antes do push**:
   parser PS5.1 (`ParseFile`), suíte Pester relevante rodada antes/depois
   (comparação de contagem de falhas, não número absoluto — mesmo
   protocolo usado a noite toda). Se a suíte não roda limpa, o job não
   dá push — vira `WARN` para o owner, não `CRITICAL` silencioso.
2. **Rate limit de auto-correção**: máximo N fixes automáticos por dia
   (ex: 3) — se o monitor está achando mais que isso, é sinal de que algo
   maior está errado (ou o monitor tem falso positivo) e precisa de
   atenção humana, não de mais pushes automáticos em sequência.
3. **Todo push automático gera alerta Telegram com o diff** — não é
   "silencioso e autônomo", é "autônomo e transparente". O owner sempre
   sabe o que mudou, mesmo sem ter dado ok antes.
4. **Circuit breaker explícito**: arquivo `journal/AUTOCORRECT_DISABLED.flag`
   — se existir, o job de auto-correção só diagnostica e alerta, nunca
   aplica. Kill switch de 1 arquivo, sem precisar reverter workflow.
5. **Toda mudança em `agents/lib_leverage_cap.ps1`, arquivos que chamam
   `CoinEx-PlaceOrder`/`Invoke-OrderRouted -Route futures`, ou qualquer
   arquivo de sizing (`lib_sizing_dynamics.ps1`, `lib_kelly_*.ps1`) gera
   alerta ANTES do push, não só depois** — mesmo autônomo, o owner tem
   uma janela de segundos/minutos (não bloqueante, só um heads-up) antes
   do dinheiro real ser afetado. Isso não é approval gate (não espera
   resposta), é aviso prévio.

Estas 5 salvaguardas não retiram autonomia — reduzem a chance de um bug no
próprio sistema de auto-correção causar dano maior que o bug que ele
estava tentando corrigir (risco real: um agente de auto-fix mal calibrado
é, ele mesmo, um caminho de código novo — exatamente a categoria que já
causou o incidente de leverage 3 vezes).

---

## 5. Fases de implementação

### Fase 1 — Monitor sem auto-correção (visibilidade primeiro)
1. `scripts/live_monitor.ps1` + tabela `live_monitor_snapshots`.
2. Job `live-monitor` no workflow, cadência 30-60min, alerta Telegram só
   em `CRITICAL`.
3. Rodar por alguns dias, confirmar que os achados são reais (não falso
   positivo) antes de dar poder de escrita a qualquer coisa.

**Critério de sucesso**: snapshot diário mostra as 6 camadas com status
real, sem alarme falso.

### Fase 2 — Auto-correção B (regras fixas, padrões já conhecidos)
1. Script determinístico que reconhece os padrões já catalogados (schema
   drift via erro PGRST, "wired sem dado" via teste de integração
   automatizado) e aplica o fix já conhecido.
2. Roda só quando o monitor (Fase 1) já validou que o achado é real.

### Fase 3 — Auto-correção A (agente com Claude Agent SDK, bugs novos)
1. Setup do job `auto-correct` com acesso à SDK.
2. Prompt inicial restrito a 1 classe de bug por vez (ex: só schema
   drift primeiro), expandir escopo gradualmente conforme confiança.
3. As 5 salvaguardas da Seção 4 implementadas e testadas ANTES do
   primeiro push automático real acontecer.

**Não pular direto para Fase 3** — autonomia total no mandato não muda o
fato de que um agente de auto-fix mal testado é, ele mesmo, risco novo.
Validar em fases reduz a chance de o "corretor" precisar ser corrigido.

---

## 6. Resumo executivo

- **Decisão do owner**: autonomia total confirmada 2x, sem exceção para
  sizing/leverage/gates — registrada na Seção 0, meu papel é implementar
  fielmente, não questionar de novo.
- **O que constrói**: monitor real (6 camadas: jobs, trades, rejeições,
  leverage, schema, rate limit) + auto-correção em 2 modos (regras fixas
  para o conhecido, agente LLM para o novo).
- **O que nunca é "bug a corrigir" mesmo com autonomia total**: decisões
  de estratégia (thresholds de gate, sizing) — isso gera alerta pro
  owner decidir, não fix automático, porque não tem resposta certa
  objetivamente verificável.
- **Salvaguardas dentro do mandato**: testes antes de todo push, rate
  limit de fixes/dia, alerta com diff sempre, circuit breaker de 1
  arquivo, aviso prévio em mudanças de capital/leverage.
- **Primeiro passo**: Fase 1, monitor sem poder de escrita — visibilidade
  antes de autonomia de ação, mesmo que a autonomia de ação já esteja
  aprovada.

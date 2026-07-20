# PRD: Scaling Out Real (Multi-TP/SL nativo CoinEx) — fechar o elo que já existe

> Escrito 2026-07-19 (madrugada, enquanto o owner dormia) para revisão antes
> de qualquer implementação. Baseado em mapeamento de código real feito na
> mesma sessão (não é design especulativo — cada afirmação abaixo tem
> arquivo:linha confirmado). NENHUM código de produção foi alterado para
> produzir este documento — é só leitura + este arquivo novo.

---

## 0. Antes de tudo: o que este PRD NÃO promete

Este documento propõe conectar um sistema de saída de posição mais
sofisticado (scaling out em múltiplos alvos, já parcialmente construído mas
desconectado). Ele **não** promete que isso torna o sistema mais lucrativo.

Scaling out é uma melhoria de **execução de saída** — captura parte do lucro
mais cedo, deixa o resto correr, reduz o "tudo ou nada" de um SL/TP único.
Isso é valioso independente de haver edge de entrada ou não: reduz a
variância de qualquer estratégia, boa ou ruim. Mas **não cria edge onde não
havia**. Se a entrada (Tori, FARO V3, GEM discovery) não tem vantagem
estatística real, uma saída melhor administra esse resultado com mais
elegância, não o transforma em lucro.

Dado real de 2026-07-19 (sessão anterior, ver
`project_trade_outcomes_pnl_fix_and_edge_search_2026_07_19.md` na memória):
o sistema só passou a gravar PnL real de forma confiável ontem. Não há ainda
amostra de trades reais fechados suficiente para saber se qualquer sinal do
sistema tem edge. Este PRD deve ser julgado pelo que entrega (arquitetura de
saída correta, dados de performance de ladder confiáveis) — não como
substituto para essa resposta em aberto.

---

## 1. Contexto: o que já existe hoje (mapeado, não hipótese)

O sistema já tem 3 peças de infraestrutura para scaling out, construídas em
momentos diferentes, **nunca conectadas entre si**:

### 1.1 `CoinEx-PlaceMultiExitLadder` (`agents/lib_coinex.ps1:1032`) — já funciona, já está em produção

Já usa o mecanismo nativo da CoinEx (`stop_loss_amount`/`take_profit_amount`
por nível, confirmado contra API real via job cloud em 2026-07-19 — CoinEx
suporta até 20 ordens de TP e 20 de SL independentes por posição desde
18-Dec-2025). Recebe um objeto `Ladder` (`tp_levels[]`/`sl_levels[]`, cada
item com `trigger`/`qty_pct`/`type`), calcula `amount = TotalAmount *
qty_pct/100` por nível, e chama `/v2/futures/set-position-take-profit` e
`/v2/futures/set-position-stop-loss` uma vez por nível. Guard de 20 níveis
já implementado (linhas 1057-1062). Retorna `$tpOrders`/`$slOrders` com
`level_index`, `trigger_price`, `qty`, `response` (a resposta bruta da API,
que contém o `id` da ordem se sucesso).

**Já é chamada em produção**: `agents/gem_executor.ps1:1900-1906`, logo
após a ordem de entrada ser preenchida.

### 1.2 `lib_exit_ladder.ps1` — 4 templates já desenhados e testados

`Get-ExitLadder -TemplateId <tori|melao_kelly|gem_runner|
bull_strong_conservative>` retorna a estrutura de ladder pronta (ex: `tori`
= TP1 +50%/30%, TP2 +100%/30%, TP3 +200%/40%, SL -50%, breakeven após TP1).
Coberto por `tests/exit_ladder.Tests.ps1`. `Get-LadderTemplateForSetup`
(`gem_executor.ps1:290`) já escolhe o template certo por contexto
(score/regime/spike).

### 1.3 `lib_ladder_tracker.ps1` — agregação de performance já pronta, só falta o dado de entrada

`Add-LadderEntryRecord` (linha 51) já é chamada em produção
(`gem_executor.ps1:1911`) e grava CSV com template/regime/entry/contadores.
`Get-LadderPerformance`/`Get-LadderABReport`/`Export-LadderABReport`
(linhas 135-404) já implementam agregação completa: win rate por template,
avg R, "runner survival rate", drawdown, ranking A/B entre templates, export
em Markdown legível. **Toda essa agregação depende de `Add-LadderHitRecord`
(linha 91) ser chamada quando um nível bate — e isso nunca acontece hoje.**
Confirmado: o único caller de `Add-LadderHitRecord` em todo o repositório é
o próprio teste (`tests/ladder_tracker.Tests.ps1`).

### 1.4 O que falta — 3 lacunas, não invenção do zero

1. **Nada persiste os `order_id` retornados pela ladder.** `$multi.tp_orders`/
   `$multi.sl_orders` (linha 1903 de `gem_executor.ps1`) são só logados
   (`Write-Host`) e descartados — nunca gravados em `trailing_positions` nem
   em lugar algum consultável depois.
2. **Nada detecta quando um nível bate na exchange.** Sem os `order_id`
   salvos, não há como saber depois "esse TP2 específico fechou, com qual
   preço, qual quantidade" — teria que reconciliar contra
   `finished-position`/`finished-order` da CoinEx (mesmo padrão já usado
   hoje em `CoinEx-GetClosedPositions`, implementado ontem 2026-07-19).
3. **`trade_outcomes`/`Get-OutcomeStats` não têm conceito de saída parcial.**
   Todo registro assume 100% da posição saiu num único `exit_price`. Se 3
   saídas parciais da mesma posição virarem 3 registros `trade_outcomes`
   independentes, `Get-OutcomeStats` (`lib_feedback_loop.ps1:184`) conta
   isso como 3 trades distintos — infla `n`, distorce `win_rate`/`avg_r` de
   qualquer agregação por regime/mode.

### 1.5 Achado colateral #1 (documentar, não é bloqueador deste PRD)

`docs/SUPABASE_STATE_SCHEMA.md` (linhas 58-88, 126-141) diz que
`trade_outcomes.id` é `BIGSERIAL` e a coluna de percentual é `pnl_pct` — mas
o schema REAL confirmado em produção (`docs/SETUP_SUPABASE_MANUHEADFUND_
2026_07_09.sql:154-171`, e validado ontem via `ConvertTo-SupabaseOutcome`)
usa `id TEXT PRIMARY KEY` e `pnl_percent`. `SUPABASE_STATE_SCHEMA.md` está
desatualizado — mesmo padrão de "documentação que já não bate com a
implementação real" observado antes neste projeto. Não afeta este PRD
diretamente, mas quem for mexer no schema de `trade_outcomes` (Fase 3 deste
PRD) deve usar o schema REAL (`SETUP_SUPABASE_MANUHEADFUND_2026_07_09.sql`),
não `SUPABASE_STATE_SCHEMA.md`.

### 1.6 Achado colateral #2 (JÁ CORRIGIDO nesta mesma sessão, não é mais um risco)

Revisando este PRD antes de considerá-lo "pronto", achei um 4º bug real da
mesma classe "wired mas sem dado real" (mesma classe dos 2 corrigidos em
2026-07-19, documentada em
`feedback_recurring_bug_taxonomy_2026_07.md`): `Get-OutcomeStats`
(`lib_feedback_loop.ps1:227`, então também `Get-RegimeAdjustment` e
`Invoke-KellyGraduationAudit` em `lib_kelly_graduation.ps1`) sempre lia
`journal/trade_outcomes.jsonl` **local**, via `_LoadOutcomes`. O job cloud
"Kelly Graduation Audit" (`kelly-audit` no workflow, roda 1x/dia via
`scripts/daily_kelly_audit.ps1`) chama isso sem `-OutcomePath` explícito —
e no runner efêmero do GitHub Actions, `journal/` é criado vazio a cada
execução (gitignored, não vem do checkout). Ou seja: **o Kelly Audit
sempre viu `n=0` trades, todo dia, desde que o job existe** — nunca teria
condições reais de graduar o sizing Kelly.

**Corrigido nesta sessão** (fora do escopo original deste PRD, mas
relevante porque este PRD propunha mexer nesta mesma função na Fase 3):
`_LoadOutcomes` agora lê do Supabase (`Get-StateRecords -Table
"trade_outcomes"`, schema `manuheadfund`) quando o backend é `supabase` E
o caller não passou `-OutcomePath` explícito (detectado via
`$PSBoundParameters.ContainsKey('OutcomePath')` em `Get-OutcomeStats`) —
fallback local se a leitura falhar (fail-soft, nunca bloqueia o audit).
Testes existentes (que sempre passam `-OutcomePath` explícito) continuam
100% intactos; 4 testes novos cobrem o caminho Supabase.

**Impacto para a Fase 3 deste PRD**: a Seção 3.6 (ponderar por `qty_pct` ao
agrupar por `parent_position_id`) agora opera sobre a fonte de dado real
(Supabase), não sobre um arquivo que nunca tinha conteúdo em produção —
sem este fix, a Fase 3 estaria corrigindo a lógica de agregação em cima de
uma leitura que já não funcionava por um motivo mais básico.

---

## 2. Decisão de escopo já tomada pelo owner

Perguntado se o objetivo era (a) só eliminar a colisão do Bug #16 via
fatias fixas por motor, (b) scaling out real em múltiplos alvos, ou (c) os
dois em fases — **o owner escolheu (b): scaling out real primeiro.**

Isso significa: este PRD foca em fazer 1 posição sair em N alvos parciais
de forma rastreada corretamente.

**Revisão de escopo (mesma conversa, pergunta de acompanhamento do owner):**
perguntado se os TPs/SLs da ladder deveriam ser reajustados (trailing)
conforme o preço se move, ou ficar fixos desde a entrada — **o owner
escolheu: sim, o SL de cada fatia também deve ser trailing.** Isso muda o
escopo deste PRD de "só scaling out estático" para "scaling out + trailing
por fatia unificados" — na prática, isso RESOLVE o Bug #16 pela raiz em vez
de só evitá-lo: em vez de 3 motores concorrentes tentando mover "o" SL de
uma posição inteira, passa a existir 1 motor (`lib_trailing_unified.ps1`,
já existente, já em shadow mode) que sabe mover o SL de **cada fatia
independente** via `stop_loss_amount`. Os 3 motores antigos
(`lib_trailing_adaptive.ps1`, `lib_trailing_stop_intelligent.ps1`, e a
lógica de decisão dentro de `lib_trailing_sync.ps1`) ficam obsoletos por
definição — não por coordenação, por não serem mais necessários.

Isso é escopo maior do que a Seção 3 original previa. A Seção 3 abaixo já
reflete o design revisado (ladder-aware trailing), não a versão anterior
(ladder estática).

---

## 3. Design proposto (revisado: ladder-aware trailing, não ladder estática)

### 3.0 Mudança de modelo mental

Antes (design inicial deste PRD): TPs/SLs calculados uma vez na entrada,
fixos até bater. O SL "the-whole-position" continuaria sendo mexido pelos
motores de trailing existentes — que colidiriam com os SLs parciais.

Agora (revisado): **cada fatia da posição é uma entidade com seu próprio
SL, que o motor único de trailing pode reajustar independentemente via
`stop_loss_amount`.** TPs continuam fixos por nível (scaling out clássico —
faz sentido sair em alvos pré-definidos). O SL de cada fatia RESTANTE
acompanha o preço (ratchet, como o trailing já faz hoje para a posição
inteira) — só que agora por fatia, não por posição inteira.

Isso significa: `lib_trailing_unified.ps1` (`Resolve-TrailingDecision`) deixa
de operar sobre `Position` (1 stop) e passa a operar sobre `PositionSlice`
(N stops, um por fatia ainda aberta). Os 3 motores antigos concorrentes
(`lib_trailing_adaptive.ps1`, `lib_trailing_stop_intelligent.ps1`, e a
lógica de decisão hoje embutida em `lib_trailing_sync.ps1`) tornam-se
desnecessários — não por serem desligados manualmente por coordenação, mas
porque o motor único passa a ser o único capaz de operar sobre fatias
(eles nunca souberam disso, foram desenhados só pra posição inteira).

### 3.1 Modelo de dados: posição-mãe + fatias

`trailing_positions` (registro principal, mantém compatibilidade — nenhum
reader existente quebra) ganha campos opcionais novos:
- `ladder_template_id` (TEXT, nullable)
- `ladder_total_qty` (NUMERIC, nullable) — `$filled_qty` da entrada, nunca
  persistido hoje.

Nova tabela `manuheadfund.position_slices` (substitui o conceito estático
de `ladder_orders` da versão anterior deste PRD — agora cada fatia precisa
de estado próprio de trailing, não só "status de ordem"):

```sql
CREATE TABLE IF NOT EXISTS manuheadfund.position_slices (
    id                TEXT PRIMARY KEY,     -- market|slice_index|position_orderId
    position_market   TEXT NOT NULL,
    position_order_id TEXT,                 -- orderId da posição-mãe
    slice_index       INTEGER NOT NULL,     -- 0..N-1, corresponde a um tp_level
    qty_planned       NUMERIC NOT NULL,     -- qty desta fatia (TotalQty * qty_pct/100)
    qty_remaining     NUMERIC NOT NULL,     -- decrementa quando parte da fatia sai por SL
    tp_trigger_price  NUMERIC NOT NULL,     -- alvo fixo desta fatia (nao muda)
    tp_exchange_order_id TEXT,
    sl_current        NUMERIC NOT NULL,     -- stop ATUAL desta fatia (isto SIM muda -- trailing)
    sl_exchange_order_id TEXT,
    sl_phase          INTEGER DEFAULT 0,    -- mesma semantica de fase 0-3 que Position.phase hoje
    sl_peak           NUMERIC,              -- peak desta fatia (nao da posicao inteira)
    status            TEXT DEFAULT 'open',  -- 'open' | 'tp_filled' | 'sl_filled' | 'cancelled'
    filled_at         TEXT,
    filled_price      NUMERIC,
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_slices_market ON manuheadfund.position_slices (position_market);
CREATE INDEX IF NOT EXISTS idx_slices_open ON manuheadfund.position_slices (status) WHERE status = 'open';
```

Cada linha é o equivalente, para 1 fatia, do que `trailing_positions` é
para a posição inteira hoje — inclusive tendo `phase`/`peak`/`sl_current`
próprios, para que `Resolve-TrailingDecision` (motor único) possa ser
chamado 1x por fatia aberta sem precisar saber que existem outras.

### 3.2 `lib_trailing_unified.ps1` — extensão mínima, não reescrita

`Resolve-TrailingDecision` (`agents/lib_trailing_unified.ps1:48`) já é pura
e já recebe `Position` como parâmetro. Ela não precisa mudar de assinatura:
o caller passa um `PSCustomObject` com o shape de 1 `PositionSlice` (que já
tem `side`/`entry`/`stopCurrent`/`origin` — os mesmos campos que
`Resolve-TrailingDecision` já lê de `Position` hoje) em vez do registro de
`trailing_positions` inteiro. Ou seja: **a função de decisão em si não
precisa saber que fatias existem** — quem itera por fatia é o CALLER (a
próxima seção).

### 3.3 `trailing_stop_monitor.ps1` — novo loop por fatia (substitui a chamada única por posição)

Hoje: `Update-TrailingStopsAdaptive`/`Update-AllTrailingStops`/
`Sync-TrailingToExchange` iteram `Get-TrailingPositions` (1 item = 1
posição = 1 stop). Novo bloco (aditivo, gated pela mesma flag de shadow
mode `TRAILING_UNIFIED_SHADOW.flag` até validar, depois promovido):

1. Para cada posição ativa com `ladder_template_id` preenchido, buscar suas
   `position_slices` com `status='open'`.
2. Para cada fatia: montar o `PositionSlice` object (entry=entry da
   posição-mãe, stopCurrent=`slice.sl_current`, side=side da posição-mãe,
   origin=origin da posição-mãe — todos já disponíveis, só precisa
   join com `trailing_positions`), chamar `Resolve-TrailingDecision`.
3. Se `action='UPDATE'`: chamar `CoinEx-ModifyPositionStopLoss` (ou a nova
   variante com `amount`, ver 3.3.1) passando `-Amount slice.qty_remaining`
   — move o SL SÓ daquela fatia, as outras não são tocadas.
4. Atualizar `position_slices.sl_current`/`sl_phase`/`sl_peak` daquela
   fatia (não da posição inteira).
5. Guard de segurança idêntico ao já existente em `Resolve-TrailingSync`
   (`lib_trailing_sync.ps1:8`) — nunca empurrar SL que já dispararia,
   aplicado por fatia agora em vez de por posição.

### 3.3.1 Extensão necessária em `lib_coinex_position_management.ps1`

`CoinEx-ModifyPositionStopLoss` (`agents/lib_coinex_position_management.ps1:159`)
hoje só aceita `-Market -Price -TriggerType` — não expõe `amount`, mesmo o
endpoint subjacente (`/v2/futures/set-position-stop-loss`) já aceitando
(confirmado, é o mesmo endpoint que `CoinEx-PlaceMultiExitLadder` já usa
com `amount`, `lib_coinex.ps1:1119-1128`). Adicionar parâmetro opcional
`-Amount` (default `$null` = comportamento atual, full-position, para não
quebrar os 4 callers existentes — `lib_trailing_sync.ps1`,
`lib_trailing_stop_intelligent.ps1`, `lib_position_risk_manager.ps1`,
`lib_position_risk_audit.ps1` — que continuam operando como hoje até serem
migrados ou aposentados).

### 3.4 Fluxo de entrada (igual à versão anterior deste PRD, sem mudança)

Em `gem_executor.ps1`, logo após `CoinEx-PlaceMultiExitLadder` retornar
`$multi` (linha 1900-1906): persistir 1 linha em `position_slices` por
`tp_level` (com `sl_current` inicial = o SL daquele nível, vindo de
`$multi.sl_orders` correspondente), e passar `$filled_qty`/`$ladderTplId`
para `Add-TrailingPosition` (parâmetros novos opcionais, mesmo padrão de
`-Origin` de 2026-07-18).

### 3.5 Fluxo de detecção de hit (TP ou SL de uma fatia específica batendo)

Igual ao desenho original (consultar `CoinEx-GetOpenOrders` vs
`CoinEx-GetClosedPositions`, ver order_id sumido = fill), mas agora
atualiza `position_slices.status` (`'tp_filled'`|`'sl_filled'`) em vez de
`ladder_orders.status`. Ao marcar uma fatia como filled: gravar outcome
parcial em `trade_outcomes` com `parent_position_id` (ver 3.6), e — se
`breakeven_after_tp` do template mandar — mover o `sl_current` das fatias
AINDA abertas para o preço de entrada (breakeven), reaproveitando o mesmo
mecanismo do passo 3.3 (é só uma chamada a mais de `Resolve-TrailingDecision`
com override de "forçar breakeven", não uma função nova).

### 3.6 Fix em `trade_outcomes`/`Get-OutcomeStats` (igual à versão anterior)

Adicionar coluna `parent_position_id` (TEXT, nullable) em
`manuheadfund.trade_outcomes`. `Get-OutcomeStats`
(`lib_feedback_loop.ps1:184`) agrupa por `parent_position_id` (ou pelo
próprio `id` quando null) e pondera por `qty_pct` antes de entrar na média
— evita que N saídas parciais da mesma posição-mãe sejam contadas como N
trades de peso igual.

### 3.7 O que este design explicitamente NÃO faz (fora de escopo)

- **Não** migra Moon Bag para usar `position_slices`/ladder nativa — Moon
  Bag continua com sua lógica própria (2 registros fictícios
  harvest/moon) por ora. É uma migração natural depois, mas Moon Bag tem
  decisão própria de "advisory vs auto_execute" que merece revisão
  separada, não bundled aqui.
- **Não** aposenta os 3 motores antigos automaticamente — eles continuam
  rodando para posições SEM `ladder_template_id` (a maioria das posições
  hoje, e todas as posições abertas antes deste PRD). Só posições novas
  com ladder usam o motor único por fatia. A aposentadoria dos motores
  antigos para 100% das posições é consequência natural quando 100% das
  entradas passarem a usar ladder — não é um passo distinto deste PRD.
- **Não** resolve SPOT — todo o design acima é FUTURES-only (mesmo escopo
  de `CoinEx-PlaceMultiExitLadder` hoje). Ver pergunta em aberto na Seção 6.

---

## 4. Fases de implementação

### Fase 1 — Persistência de fatias na entrada (baixo risco, aditivo, testável isolado)
1. SQL: criar `manuheadfund.position_slices` + coluna `parent_position_id`
   em `trade_outcomes` + colunas `ladder_template_id`/`ladder_total_qty` em
   `trailing_positions`.
2. `Save-PositionSlices` (nova função, `lib_ladder_tracker.ps1` ou um
   arquivo novo `lib_position_slices.ps1` — decidir no início da
   implementação conforme o tamanho da lib resultante) — grava 1 linha por
   `tp_level` a partir de `$multi.tp_orders`/`$multi.sl_orders`.
3. Wire em `gem_executor.ps1`: chamar `Save-PositionSlices` logo após
   `CoinEx-PlaceMultiExitLadder`; passar `-LadderTemplateId`/
   `-LadderTotalQty` para `Add-TrailingPosition` (parâmetros novos
   opcionais, mesma convenção de `-Origin`).
4. Teste: Pester cobrindo `Save-PositionSlices` (mock de
   `Save-StateRecords`) + confirmar `Add-TrailingPosition` aceita os
   parâmetros novos sem quebrar nenhuma chamada legada (suíte completa
   antes/depois, protocolo de 2026-07-19).

**Critério de sucesso Fase 1**: próxima entrada GEM real com ladder grava
N linhas em `position_slices` (1 por tp_level) consultáveis via Supabase,
com `sl_current` inicial correto. Zero mudança de comportamento de trading
(só passa a persistir dado que já existia e era descartado). Motores de
trailing antigos continuam intactos, ainda não tocam nessas posições de
forma diferente (position_slices ainda não é lido por ninguém nesta fase).

### Fase 2 — Motor único opera por fatia, em SHADOW MODE (risco médio, depende da Fase 1 validada)
1. Novo bloco em `trailing_stop_monitor.ps1` (seção 3.3): itera
   `position_slices` abertas, monta `PositionSlice` object, chama
   `Resolve-TrailingDecision` — mas só LOGA/persiste a decisão (mesmo
   padrão do shadow mode já usado para `trailing_unified_shadow` desde
   2026-07-18), NÃO escreve na exchange ainda.
2. Extensão de `CoinEx-ModifyPositionStopLoss` com parâmetro opcional
   `-Amount` (seção 3.3.1) — implementada e testada isoladamente (unit
   test com mock de `CoinEx-Post`, confirmando que quando `-Amount` é
   `$null` o body enviado é idêntico ao atual, e quando fornecido inclui
   `amount`), mas ainda não chamada em produção real por este fluxo.
3. Deixar rodar alguns dias acumulando comparação real (mesmo motivo da
   sessão 2026-07-19: promover sem prova é aposta, não decisão).

**Critério de sucesso Fase 2**: tabela de shadow mostra decisões por fatia
coerentes (SL sobe com o preço em LONG, nunca desce) para posições ladder
reais, comparável ao que os motores antigos fariam para a posição inteira
equivalente.

### Fase 3 — Motor único escreve de verdade (promoção, só após Fase 2 validada com dado)
1. Trocar o shadow-log da Fase 2 por chamada real a
   `CoinEx-ModifyPositionStopLoss -Amount slice.qty_remaining`.
2. Detecção de hit (TP ou SL de fatia) + outcome parcial (seção 3.5) +
   fix de `Get-OutcomeStats` (seção 3.6).
3. Teste de integração: simular ladder de 3 níveis, 1 nível batendo TP
   (breakeven aplicado às fatias restantes), 1 nível de SL sendo reajustado
   por trailing, confirmar `position_slices` e `trade_outcomes`
   consistentes.
4. Rodar `Get-LadderPerformance`/`Get-LadderABReport` (ajustados para ler
   de `position_slices` em vez do CSV antigo) contra dado real acumulado —
   confirmar que os relatórios finalmente populam com números reais.

**Critério de sucesso Fase 3**: depois de N dias rodando, `Get-
LadderABReport -WindowDays 7` retorna ranking real dos 4 templates. SL de
fatias reais sendo movido na exchange corretamente (confirmado via
`position_slices.sl_current` batendo com o SL real consultado na CoinEx).

### Fase 4 — Aposentar os motores antigos (só quando 100% das posições novas usarem ladder)
Não é um passo de código isolado — é a consequência natural de todas as
entradas novas passarem a usar `CoinEx-PlaceMultiExitLadder`+`position_slices`.
Quando não houver mais posições ativas sem `ladder_template_id`, os 3
motores antigos (`lib_trailing_adaptive.ps1`, `lib_trailing_stop_
intelligent.ps1`, lógica de decisão em `lib_trailing_sync.ps1`) podem ser
desligados dos jobs cloud (`layer1-trailing-adaptive`,
`trailing-stop-monitor` mantém só a parte de fatias). Decisão de quando
isso acontece fica para quando a Fase 3 estiver validada com volume real —
não estimar prazo agora.

---

## 5. Regras invioláveis (lições de incidentes reais deste repo, aplicam-se aqui)

1. **PS 5.1 compat**: sem `??`/`?:`/`?.`. Validar com
   `[System.Management.Automation.Language.Parser]::ParseFile()` antes de
   qualquer commit.
2. **Sem sed/regex em massa** — edição pontual, arquivo por arquivo.
3. **Fail-soft em toda escrita nova**: se `Save-PositionSlices` falhar,
   NUNCA bloquear a entrada do trade (mesmo padrão de
   `Add-TradeOutcome`/`Save-StateRecords`, sempre best-effort com
   `Write-Warning`, nunca `throw` bloqueante no caminho principal).
4. **Campos novos sempre NULL-safe/opt-in** — nenhum reader existente de
   `trailing_positions`/`trade_outcomes` pode quebrar por causa de coluna
   nova ausente/null.
5. **Shape de API sempre confirmado contra produção antes de codar** —
   lição direta de 2026-07-19 (`_Convert-ClosedTradeToOutcome` foi escrita
   com campos inventados por 1+ mês antes de alguém confirmar contra a API
   real). Antes de codar a Fase 3 (detecção de hit), rodar um job one-shot
   read-only confirmando que `CoinEx-GetOpenOrders`/`CoinEx-GetClosedPositions`
   retornam o `order_id` no formato esperado para cruzar com
   `position_slices.tp_exchange_order_id`/`sl_exchange_order_id`.
6. **Nenhum SQL roda sozinho** — sempre `docs/SETUP_SUPABASE_*.sql`
   entregue para o owner rodar manualmente no Supabase Dashboard, nunca
   aplicado via job automático sem confirmação (mesmo padrão de todos os
   `SETUP_SUPABASE_*` já entregues).

---

## 6. Perguntas em aberto para o owner decidir antes da Fase 1 começar

1. **Qual sizing por nível ao errar por arredondamento?** Se `qty_pct`
   somar 100% mas o arredondamento de `amount` (linha 1083/1115 de
   `lib_coinex.ps1`) deixar sobra/falta de poeira (ex: 0.000003 XRP não
   alocado), isso é aceitável (fica na exchange sem cobertura de SL/TP) ou
   precisa de um nível "resto" que absorve a diferença?
2. **O que fazer com posições GEM já abertas hoje sem ladder** (a maioria,
   já que a feature é nova)? Elas continuam com o comportamento atual (1
   SL/TP full-position, motores antigos) até fechar naturalmente — não
   recomendado migrar posições já abertas retroativamente (mais arriscado
   sem ganho claro).
3. **Ordem de rollout**: aplicar em SPOT também, ou só FUTURES (onde
   `CoinEx-PlaceMultiExitLadder` já roda hoje)? O comentário em
   `gem_executor.ps1:1897` diz "apenas FUTURES; spot usa stop ja colocado"
   — confirmar se isso continua sendo a decisão certa. CoinEx spot tem o
   mesmo suporte a multi-ordem parcial? Não confirmado nesta pesquisa —
   precisaria checagem separada (mesmo processo de job one-shot read-only
   usado em 2026-07-19 para confirmar shape de finished-position) antes de
   estender para SPOT.
4. **Breakeven automático (3.5) é parte da Fase 3 ou fica para depois?**
   O template já tem `breakeven_after_tp` pronto, mas mover SL de fatias
   restantes para entry após um TP bater é uma regra de negócio (nem
   sempre desejável — depende do regime/volatilidade) que talvez mereça
   ser opt-in por template em vez de automático para todos. Decidir se
   entra na Fase 3 ou vira Fase 3.5 separada.
5. **Quantas fatias simultâneas o motor único deve suportar em termos de
   custo de API?** Cada fatia aberta = 1 chamada potencial de
   `CoinEx-ModifyPositionStopLoss` por ciclo de trailing (~5min). Um
   template de 4 níveis (ex: `melao_kelly`) pode gerar até 4x mais
   chamadas de ajuste de SL por posição do que hoje (1 chamada). Vale
   checar contra o rate limit de "long-cycle por hora" da CoinEx
   (pesquisado em 2026-07-19, ver `reference_coinex_multi_stoploss_api_
   2026_07_19.md`) antes de escalar para muitas posições simultâneas com
   ladder — não é bloqueador da Fase 1-2, mas é um limite real a
   monitorar na Fase 3 em diante.

---

## 7. Resumo executivo (para leitura rápida)

- **O que já existe**: motor de execução de ladder (`CoinEx-
  PlaceMultiExitLadder`, já usa `amount` parcial nativo da CoinEx), 4
  templates de estratégia de saída, motor único de trailing puro
  (`Resolve-TrailingDecision`, já em shadow mode desde 2026-07-18), e um
  sistema de agregação de performance completo (`Get-LadderPerformance`/
  `Get-LadderABReport`) — todos prontos, mas nenhum fala com o outro
  porque falta o conceito de "fatia de posição com trailing próprio".
- **O que este PRD propõe**: introduzir `position_slices` como a peça que
  faltava — cada fatia da ladder vira uma entidade com seu próprio SL
  reajustável, usando o motor único já existente (não um motor novo) e o
  suporte nativo `stop_loss_amount` da CoinEx. 4 fases aditivas
  (persistir fatias → motor decide em shadow → motor escreve de verdade →
  aposentar motores antigos quando aplicável), cada uma testável e
  reversível isoladamente.
- **Efeito colateral desejado**: isso resolve o Bug #16 (3 motores de
  trailing concorrentes) pela raiz para toda posição nova que usar
  ladder — não por coordenação entre eles, mas porque só 1 motor passa a
  saber operar sobre fatias.
- **O que isso NÃO resolve**: se o sistema tem edge de entrada. Isso
  continua sendo medido separadamente (ver sessão 2026-07-19 sobre
  trade_outcomes/mce_counterfactual_agg — 0 trades reais fechados com PnL
  confiável até a correção daquele dia; hipótese SHORT-em-NEUTRO ainda não
  confirmada). Uma saída melhor não cria lucro onde a entrada não tem
  vantagem estatística real.
- **Primeiro passo concreto, de menor risco**: Fase 1 — só persistir dado
  de fatia que já é calculado (`$multi.tp_orders`/`sl_orders`,
  `$filled_qty`) e hoje é jogado fora. Zero mudança de comportamento de
  trading até a Fase 3.

# PRD — Entrega Completa: Scaling Out + Monitor/Auto-Correção de Live Trading

> Documento mestre, consolida os 2 PRDs escritos nesta sessão
> (`PRD_SCALING_OUT_MULTI_TP_SL_2026_07_20.md` e
> `PRD_LIVE_MONITOR_AUTOCORRECAO_2026_07_20.md`) em uma única entrega para
> revisão do owner. Os arquivos originais continuam existindo (não foram
> apagados) — este documento é a versão para leitura de ponta a ponta.
> Nenhuma das duas features (scaling out, monitor, auto-correção) foi
> implementada ainda — tudo abaixo é plano aprovado para execução, exceto
> onde marcado "JÁ FEITO".

---

## Sumário executivo

Esta sessão (2026-07-19/20) produziu 3 entregas reais em produção e 2
PRDs para o que vem a seguir:

**Já em produção (código real, testado, com push feito):**
1. Cap de leverage 5x fail-closed em 4 caminhos de execução FUTURES que
   não tinham (Bug #15).
2. Persistência real do shadow mode do motor único de trailing, que
   estava rodando "no vazio" há 1 dia sem gravar nada consultável (parte
   do Bug #16).
3. Correção de 2 bugs em cadeia que faziam `trade_outcomes` nunca gravar
   PnL real — o sistema não tinha, até esta sessão, nenhum jeito confiável
   de saber se um trade deu certo ou errado.
4. Correção de um 4º bug da mesma família: o job diário "Kelly Graduation
   Audit" sempre lia um arquivo local vazio em produção, então nunca teve
   dado real para decidir nada, desde que existe.

**Planejado, aguardando implementação (os 2 PRDs, detalhados abaixo):**
- **Parte 1 — Scaling Out real**: sistema de saída em múltiplos alvos
  parciais (scaling out), com trailing próprio por fatia, que resolve o
  Bug #16 pela raiz.
- **Parte 2 — Monitor + Auto-Correção**: sistema que observa a saúde do
  live trading em 6 camadas e se auto-corrige, com autonomia total
  confirmada pelo owner (incluindo mudanças em sizing/leverage/gates) e
  salvaguardas técnicas para reduzir o risco dessa autonomia causar dano
  novo.

**O que nenhuma das duas partes promete**: lucro. Ambas melhoram a
integridade e a sofisticação de execução do sistema — não criam edge de
entrada onde ele não existe. Essa distinção é repetida em várias seções
abaixo porque é fácil de esquecer no meio dos detalhes técnicos.

---

# PARTE 0 — Pré-requisitos já entregues nesta sessão

Estes 4 itens já são código real, com push feito, testados. Documentados
aqui porque as Partes 1 e 2 dependem deles ou foram descobertos ao
revisá-las.

### 0.1 Cap de leverage (Bug #15) — commit `ffa455f`
4 arquivos (`lib_pump_scalper.ps1`, `lib_regime_surf_executor.ps1`,
`lib_short_executor.ps1`, `orchestrator_v6.ps1`) chamavam ordem FUTURES
real sem `Get-SafeLeverage`/`CoinEx-AdjustPositionLeverage`. Corrigido
fail-closed: se o ajuste de leverage falhar, a ordem é bloqueada em vez de
herdar leverage desconhecida da conta. Todos os 4 caminhos são hoje
dormentes (só alcançáveis via `scan_master.ps1`, que não roda em produção
atualmente) — o fix elimina o risco se algum dia forem religados.

### 0.2 Shadow mode do motor único de trailing persiste dado real — commit `3aede50`
`lib_trailing_unified.ps1` (`Resolve-TrailingDecision`) já existia desde
2026-07-18, em shadow mode dentro de `trailing_stop_monitor.ps1`, mas só
gravava a decisão em log local do runner — que o GitHub Actions descarta a
cada ciclo. Ou seja, "1 dia em shadow" não tinha produzido nenhum dado
consultável. Corrigido: persiste em `manuheadfund.trailing_unified_shadow`
(Supabase), comparando `real_stop` vs `unified_new_stop` por ciclo. Tabela
já criada pelo owner via SQL.

### 0.3 `trade_outcomes` nunca gravava PnL real — commits `80cecfd` + `387c88e`
Dois bugs em cadeia:
- `ConvertTo-SupabaseOutcome` calculava `pnl_usd`/`r` corretamente mas
  nunca incluía `pnl_percent`/`pnl_realized` no registro enviado ao
  Supabase — a coluna ficava sempre em `0` (default do Postgres),
  silenciosamente.
- `Reconcile-AppToJournal` estava "wired" desde 2026-07-07 mas sempre
  falhava: dependia de `CoinEx-GetClosedPositions`, que nunca existiu.
  Pior, as funções de conversão relacionadas esperavam campos
  (`entryPrice`, `exitPrice`, `orderId`, camelCase) que nunca foram
  confirmados contra a API real — eram especulação desde a origem.
  Confirmado o shape real via job cloud contra produção
  (`/v2/futures/finished-position` retorna `market`, `side` minúsculo,
  `realized_pnl` já calculado pela corretora, `avg_entry_price`,
  `ath_margin_size`, timestamps em epoch milliseconds, `finished_type`).
  `CoinEx-GetClosedPositions` implementada de verdade com esse shape.

**Por que isso importa para as Partes 1 e 2 abaixo**: scaling out (Parte
1) grava outcomes parciais em `trade_outcomes` — sem este fix, estaria
gravando em uma tabela que nunca recebia dado real. O monitor (Parte 2)
usa `trade_outcomes` como uma das 6 camadas observadas — sem este fix,
estaria monitorando uma métrica sempre zerada.

### 0.4 Kelly Graduation Audit sempre via n=0 trades — commit `fa78713`
Achado ao revisar o PRD de scaling out antes de considerá-lo pronto: o job
cloud diário `kelly-audit` chama `Get-OutcomeStats` sem especificar
arquivo, e essa função sempre lia `journal/trade_outcomes.jsonl` local —
que no runner efêmero do GitHub Actions começa vazio a cada execução
(gitignored, não vem do checkout). Corrigido: quando o backend é Supabase
e nenhum caminho é passado explicitamente, lê do Supabase real; fallback
local preservado (usado pelos testes). Suíte completa validada
antes/depois, sem regressão.

### 0.5 Achado de pesquisa externa relevante às Partes 1 e 2
Confirmado via documentação oficial da CoinEx (2026-07-19): a API suporta
até 20 ordens de stop-loss e 20 de take-profit **independentes** por
posição, desde dezembro de 2025, via parâmetro `amount` (fechamento
parcial). O projeto nunca usou isso — todo o código trata SL/TP como
singular, full-position. Essa capacidade nativa é a base técnica de toda
a Parte 1 abaixo.

---

# PARTE 1 — Scaling Out Real (Multi-TP/SL via `position_slices`)

## 1.1 O que este plano NÃO promete

Scaling out é uma melhoria de **execução de saída** — captura parte do
lucro mais cedo, deixa o resto correr, reduz o "tudo ou nada" de um único
SL/TP. Isso reduz variância independente de haver edge de entrada ou não.
**Não cria edge onde não havia.** Se a entrada (Tori, FARO V3, GEM
discovery) não tem vantagem estatística real, uma saída melhor administra
esse resultado com mais elegância — não o transforma em lucro. Até o
início desta sessão, o sistema nem gravava PnL real de forma confiável
(ver 0.3); ainda não há amostra suficiente de trades reais fechados para
saber se qualquer sinal do sistema tem edge.

## 1.2 O que já existe hoje (mapeado, não hipótese)

Três peças de infraestrutura já construídas, em momentos diferentes,
**nunca conectadas entre si**:

**`CoinEx-PlaceMultiExitLadder`** (`agents/lib_coinex.ps1:1032`) — já
funciona, já roda em produção (`gem_executor.ps1:1900-1906`, logo após a
ordem de entrada). Já usa `amount` parcial nativo por nível, guard de 20
níveis implementado, retorna `$tpOrders`/`$slOrders` com `level_index`,
`trigger_price`, `qty`, `response` (contém `order_id` se sucesso).

**`lib_exit_ladder.ps1`** — 4 templates prontos e testados
(`tori`, `melao_kelly`, `gem_runner`, `bull_strong_conservative`), cada um
com `tp_levels[]`/`sl_levels[]` (trigger, qty_pct, type) e
`breakeven_after_tp`. `Get-LadderTemplateForSetup` já escolhe o certo por
contexto.

**`lib_ladder_tracker.ps1`** — agregação de performance completa
(`Get-LadderPerformance`, `Get-LadderABReport`, `Export-LadderABReport`:
win rate por template, avg R, runner survival, drawdown, ranking A/B,
export Markdown) — mas **depende de `Add-LadderHitRecord` ser chamada
quando um nível bate, e isso nunca acontece em produção**. O único caller
em todo o repositório é o próprio teste.

**As 3 lacunas reais** (não invenção do zero):
1. Nada persiste os `order_id` retornados pela ladder — são logados e
   descartados.
2. Nada detecta quando um nível bate na exchange (sem os `order_id`
   salvos, não há como reconciliar depois).
3. `trade_outcomes`/`Get-OutcomeStats` não têm conceito de saída parcial —
   3 saídas parciais da mesma posição virariam 3 "trades" distintos nas
   estatísticas, inflando contagem e distorcendo win rate/avg R.

## 1.3 Decisão de escopo já tomada pelo owner

Entre "só eliminar a colisão do Bug #16 via fatias fixas" e "scaling out
real em múltiplos alvos" — **escolhido: scaling out real**.

Revisão de escopo (pergunta de acompanhamento do próprio owner): perguntado
se o SL de cada fatia também deveria acompanhar o preço (trailing) em vez
de ficar fixo — **escolhido: sim**. Isso resolve o Bug #16 **pela raiz**:
em vez de 3 motores de trailing concorrentes brigando por "o" SL de uma
posição inteira, passa a existir 1 motor (`lib_trailing_unified.ps1`, já
existente, já em shadow mode) que sabe mover o SL de cada fatia
independente via `stop_loss_amount`. Os 3 motores antigos
(`lib_trailing_adaptive.ps1` — ATR fake nunca preenchido —,
`lib_trailing_stop_intelligent.ps1`, lógica em `lib_trailing_sync.ps1`)
ficam obsoletos por definição para toda posição nova que usar ladder — não
por coordenação entre eles, por não serem mais necessários.

## 1.4 Design técnico

### Modelo de dados
`trailing_positions` ganha 2 campos opcionais (`ladder_template_id`,
`ladder_total_qty`) — não quebra nenhum reader existente.

Nova tabela `manuheadfund.position_slices`, 1 linha por fatia (por
`tp_level`), com `sl_current`/`sl_phase`/`sl_peak` próprios — o
equivalente, por fatia, do que `trailing_positions` é hoje por posição
inteira:

```sql
CREATE TABLE IF NOT EXISTS manuheadfund.position_slices (
    id                TEXT PRIMARY KEY,
    position_market   TEXT NOT NULL,
    position_order_id TEXT,
    slice_index       INTEGER NOT NULL,
    qty_planned       NUMERIC NOT NULL,
    qty_remaining     NUMERIC NOT NULL,
    tp_trigger_price  NUMERIC NOT NULL,
    tp_exchange_order_id TEXT,
    sl_current        NUMERIC NOT NULL,
    sl_exchange_order_id TEXT,
    sl_phase          INTEGER DEFAULT 0,
    sl_peak           NUMERIC,
    status            TEXT DEFAULT 'open',
    filled_at         TEXT,
    filled_price      NUMERIC,
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_slices_market ON manuheadfund.position_slices (position_market);
CREATE INDEX IF NOT EXISTS idx_slices_open ON manuheadfund.position_slices (status) WHERE status = 'open';
```

### O motor de trailing não muda de assinatura
`Resolve-TrailingDecision` (`lib_trailing_unified.ps1:48`) já é pura e já
recebe um objeto com `side`/`entry`/`stopCurrent`/`origin`. Ela não precisa
saber que fatias existem — o caller (novo bloco em
`trailing_stop_monitor.ps1`) passa 1 objeto por fatia aberta, monta a
partir do join `trailing_positions` + `position_slices`.

### Extensão necessária em `CoinEx-ModifyPositionStopLoss`
Hoje só aceita `-Market -Price -TriggerType`. O endpoint subjacente já
aceita `amount` (mesmo endpoint que `CoinEx-PlaceMultiExitLadder` já usa).
Adicionar parâmetro opcional `-Amount` (default `$null` = comportamento
atual — não quebra os 4 callers existentes).

### Fluxo completo
1. **Entrada**: após `CoinEx-PlaceMultiExitLadder`, persistir 1 linha em
   `position_slices` por nível; passar quantidade/template para
   `Add-TrailingPosition`.
2. **Trailing por fatia**: novo loop em `trailing_stop_monitor.ps1` chama
   `Resolve-TrailingDecision` 1x por fatia aberta; se `UPDATE`, chama
   `CoinEx-ModifyPositionStopLoss -Amount <qty_remaining>` — só aquela
   fatia é tocada.
3. **Detecção de hit**: reconcilia `order_id` sumido via
   `CoinEx-GetOpenOrders`/`CoinEx-GetClosedPositions` (já implementada,
   item 0.3); marca fatia como `tp_filled`/`sl_filled`; grava outcome
   parcial com `parent_position_id`; aplica breakeven nas fatias restantes
   se o template mandar.
4. **Fix em `Get-OutcomeStats`**: agrupa por `parent_position_id`, pondera
   por `qty_pct` — evita que N saídas parciais virem N trades de peso
   igual nas estatísticas.

### O que este design explicitamente não faz
- Não migra Moon Bag (mantém sua lógica própria de 2 pernas fictícias).
- Não aposenta os motores antigos automaticamente — continuam ativos para
  toda posição sem `ladder_template_id` (a maioria hoje).
- Não resolve SPOT — escopo é FUTURES-only, mesmo escopo de
  `CoinEx-PlaceMultiExitLadder` hoje.

## 1.5 Fases de implementação

**Fase 1 — Persistência de fatias na entrada.** Zero mudança de
comportamento de trading — só passa a persistir dado que já era calculado
e descartado. Critério de sucesso: próxima entrada com ladder grava N
linhas em `position_slices` consultáveis via Supabase.

**Fase 2 — Motor único opera por fatia, em SHADOW MODE.** Mesmo padrão já
validado nesta sessão (item 0.2) — só loga/persiste a decisão, não escreve
na exchange. Extensão de `CoinEx-ModifyPositionStopLoss` com `-Amount`
testada isoladamente. Deixar rodar dias acumulando comparação real antes
de promover.

**Fase 3 — Motor único escreve de verdade.** Só após Fase 2 validada com
dado real. Detecção de hit + outcome parcial + fix de `Get-OutcomeStats`.
Critério de sucesso: `Get-LadderABReport` retorna ranking real dos 4
templates pela primeira vez.

**Fase 4 — Aposentar motores antigos.** Consequência natural quando 100%
das posições novas usarem ladder — não é um passo de código isolado.

## 1.6 Perguntas em aberto para decidir antes da Fase 1

1. Arredondamento de `qty_pct` deixando poeira não coberta — aceitável ou
   precisa de nível "resto"?
2. Posições já abertas sem ladder: não migrar retroativamente (recomendado).
3. SPOT também, ou só FUTURES? CoinEx spot tem o mesmo suporte a
   multi-ordem parcial — não confirmado ainda.
4. Breakeven automático entra na Fase 3 ou vira fase própria (é regra de
   negócio, não universal por template)?
5. Rate limit da CoinEx (long-cycle por hora) — mais fatias = mais
   chamadas de ajuste de SL por ciclo; monitorar a partir da Fase 3.

## 1.7 Regras invioláveis (lições de incidentes reais deste repo)

1. PS 5.1 compat — sem `??`/`?:`/`?.`; validar com `ParseFile()` antes de
   commit.
2. Sem sed/regex em massa — edição pontual.
3. Fail-soft em toda escrita nova — nunca bloquear a entrada do trade.
4. Campos novos sempre NULL-safe/opt-in.
5. Shape de API sempre confirmado contra produção antes de codar (lição
   direta do item 0.3 — campos inventados por 1+ mês).
6. Nenhum SQL roda sozinho — sempre entregue para o owner rodar
   manualmente.

---

# PARTE 2 — Monitor de Live Trading + Auto-Correção

## 2.1 Registro da decisão de autonomia (seção que não pode ser reinterpretada depois)

Pedido literal do owner: *"quero td live trading e monitore para avaliar
se td funcionando ok, senao se auto corrija"*. Perguntado explicitamente
se isso deveria ter exceção para mudanças de sizing/leverage/gates de
entrada-saída — as áreas que já causaram o **incidente de leverage 50x,
repetido 3 vezes neste mesmo projeto** (SUIUSDT, depois `short_scanner.ps1`,
depois FARO V3, cada vez que um caminho de execução novo foi criado sem
segunda checagem) — o owner confirmou **duas vezes, explicitamente**:
**"autonomia total sem exceção, mesmo pra sizing/leverage/gates."**

Esta decisão está sendo implementada como pedida. O risco não desaparece
por ser aceito — só fica explícito e registrado. As salvaguardas técnicas
da Seção 2.5 reduzem a chance de dano dentro do mandato (autonomia de ação
≠ ausência de qualquer verificação automatizada), mas a decisão final de
push sem revisão humana é do owner.

## 2.2 O que já existe hoje (não reinventar)

- `health-check`: ping superficial de API, alerta se jobs falharem —
  não analisa lógica.
- `self_heal_guardian.ps1`: desativado (frota local descontinuada).
- Root Cause Oracle: 16 detectores regex, manual, não corrige nada.
- Diagnósticos one-shot desta sessão: read-only, `workflow_dispatch`
  manual, sem auto-correção.

Nenhuma peça hoje corrige código automaticamente — é capacidade nova.

## 2.3 O que "monitorar tudo" significa tecnicamente

| Camada | Onde olhar | Sinal de problema |
|---|---|---|
| Jobs do workflow | GitHub Actions API | `conclusion=failure`, ou `continue-on-error` mascarando falha |
| Execução de trade | `trade_outcomes` (Supabase) | 0 trades fechados por N dias, PnL sempre 0 |
| Rejeições/gates | `trade_rejections` | 100% bloqueado pelo mesmo gate |
| Leverage real | posições abertas na exchange | `leverage > 5x` (o cap já devia ter impedido) |
| Schema drift | colunas esperadas vs reais | erro `PGRST204`/`42703` nos logs |
| Rate limit | CoinEx headers | `low-speed mode` ou erro de rate limit |

## 2.4 Arquitetura proposta

**Monitor** (`scripts/live_monitor.ps1`, novo job `live-monitor`, cadência
30-60min): consulta as 6 camadas, classifica `OK`/`WARN`/`CRITICAL`, grava
snapshot em `manuheadfund.live_monitor_snapshots`, alerta Telegram
imediato em `CRITICAL` independente de qualquer auto-correção.

**Auto-correção**, 2 modos complementares:

- **Opção B (regras fixas)** — script determinístico que já sabe aplicar
  o fix conhecido para padrões catalogados (schema drift via erro PGRST,
  "wired sem dado"). Rápido, previsível, não generaliza para bug novo.
- **Opção A (Claude Agent SDK, recomendada para bugs novos)** — job
  `auto-correct` disparado pelo monitor, roda um agente com acesso a
  Bash/Read/Edit no checkout, prompt restrito a 1 achado por vez, aplica
  fix, valida (parser + suíte relevante), comita e dá push direto — sem
  approval gate, conforme o mandato. Sempre alerta Telegram com o diff.

## 2.5 O que nunca é candidato a auto-correção (classificação técnica, não exceção ao mandato)

- Mudar threshold de gate porque "bloqueia demais" — é hipótese de edge
  que precisa de teste controlado, não bug com resposta óbvia.
- Qualquer mudança em quanto capital é alocado por trade.
- Desligar um gate de segurança porque causa `0 trades` — pode estar
  funcionando corretamente (já visto 2x nesta sessão).

Estes sempre geram alerta para o owner decidir, porque são decisões de
estratégia sem resposta objetivamente verificável — não porque a
autonomia tenha exceção.

## 2.6 Salvaguardas técnicas (dentro do mandato de autonomia total)

1. Todo fix passa por parser PS5.1 + suíte Pester antes/depois — se não
   roda limpo, vira `WARN` para o owner, não push silencioso.
2. Rate limit de auto-correção (ex: máximo 3 fixes automáticos/dia).
3. Todo push automático gera alerta Telegram com o diff — autônomo e
   transparente, não autônomo e silencioso.
4. Circuit breaker: `journal/AUTOCORRECT_DISABLED.flag` — kill switch de 1
   arquivo.
5. Mudanças em arquivos de leverage/sizing geram aviso PRÉVIO (não
   bloqueante) antes do push — heads-up de segundos/minutos, não approval
   gate.

## 2.7 Fases de implementação

**Fase 1 — Monitor sem auto-correção.** Visibilidade primeiro. Rodar dias
confirmando que os achados são reais antes de dar poder de escrita a
qualquer coisa.

**Fase 2 — Auto-correção B (regras fixas).** Só para padrões já validados
como reais na Fase 1.

**Fase 3 — Auto-correção A (agente LLM, bugs novos).** Prompt restrito a 1
classe de bug por vez, expandir gradualmente. As 5 salvaguardas
implementadas e testadas antes do primeiro push automático real.

Não pular direto para a Fase 3 — um agente de auto-fix mal calibrado é,
ele mesmo, um caminho de código novo (a mesma categoria que já causou o
incidente de leverage 3 vezes).

---

## Encerramento

Ambos os planos (Parte 1 e Parte 2) estão prontos para começar pela Fase 1
de cada um — a fase de menor risco em ambos os casos (persistir dado /
visibilidade sem poder de escrita). Nenhuma linha de implementação foi
escrita ainda para nenhuma das duas partes. Os 4 fixes da Parte 0 já estão
em produção, testados, com push feito.

Próxima ação depende do owner: autorizar o início da Fase 1 de qual das
duas partes (ou ambas em paralelo, já que tocam arquivos majoritariamente
diferentes — Parte 1 é sobretudo `gem_executor.ps1`/`lib_trailing_*`/
schema de posição; Parte 2 é um script novo + workflow novo, sem overlap
direto de arquivos com a Parte 1 na Fase 1 de cada uma).

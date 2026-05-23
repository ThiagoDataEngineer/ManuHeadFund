# Diagnose 100% ABORTAR -- orchestrator V6
Gerado: 2026-05-14

Contexto: DryRun bbnclvt9g rodou 5h+ em 14/05/2026 (quinta-feira), 29 ciclos master,
84 sinais gerados, 100% ABORTAR, 0 EXECUTAR. Todos os candidatos eram altcoins
(KITEUSDT, FFUSDT, TIAUSDT, INJUSDT, CRVUSDT, DOTUSDT, LINKUSDT, USELESSUSDT, CFXUSDT).
ZERO BTCUSDT/ETHUSDT entrou em orchestrator -- scanner prioriza alta volatilidade,
e BTC/ETH ficaram fora do top 20.

## Root cause (top hypothesis)

- **Hypothesis**: Regra Thursday-alt em `_Compute-Tier` forca Tier D para 100% dos
  candidatos, porque (a) hoje e quinta-feira e (b) o scanner so escolheu altcoins.
  Tier D = ABORTAR sem mesa, sem mentor, no primeiro estagio da cascata.
- **Confidence**: **HIGH**
- **Evidence**:
  - `agents/triagem_agent.ps1:60` -> `if ($thursdayAlt) { return "D" }`
  - `$thursdayAlt = ($DayOfWeek -eq "Thursday" -and $MarketTier -eq "alt")`
    (linha 59)
  - `lib_seasonality.ps1:13-19` Get-MarketTier: tudo que nao for BTCUSDT nem
    membro de `{ETHUSDT,BNBUSDT,SOLUSDT,XRPUSDT}` retorna `"alt"`. Todos os 84
    sinais aprovados pelo pre-screen sao alts.
  - Memoria do projeto confirma calibracao empirica: "Skip Thursday = 3.5x B&H"
    (project_dow_seasonality.md) -- regra foi importada para o triagem.
  - Tempos curtos por abort (3-8s) sao consistentes com triagem-only (1 chamada
    Groq para razao) e zero chamadas a Mesa/Mentor.
  - Sem nenhuma marca de "Mesa CAOS", "Mentor VETAR", "Mercado nao seguro" nos
    logs -- so "Decisao: ABORTAR" generico do orchestrator V6, que cobre tanto
    Tier D quanto Mesa CAOS quanto Mentor VETAR.
- **Localizacao**: `c:/Users/thiag/Coinex_AI_USER_API/agents/triagem_agent.ps1:60`
  (regra) e `c:/Users/thiag/Coinex_AI_USER_API/agents/orchestrator_v6.ps1:30-39`
  (curto-circuito que pula Mesa/Mentor).

## Hipoteses alternativas

1. **Config muito conservadora (thresholds)**. Probabilidade: MEDIUM.
   - Em dia nao-Thursday, ainda existe risco: o orchestrator V6 NAO passa
     `scanner.score` no `Context` (`orchestrator_v6.ps1:121-128` constroi context
     com macro/feeCtx/capital/seasonal/mktInfo, **sem** chave `scanner`).
   - Resultado: `_Get-CtxField "scanner.score" 50` sempre cai no default 50.
   - Com score=50 e macro NEUTRAL, `_Compute-Tier` retorna "C" (>=60 para B,
     >=75 para A). Tier C continua para Mesa, entao isso sozinho NAO causa abort.
   - Mas significa que o pipeline esta semi-cego: nem mesmo o score do scanner
     (que ja existe e e impresso no log) chega na Triagem.

2. **Bug que zera score/sinal antes do cascade** (problema #2 paralelo).
   Probabilidade: HIGH para o sintoma "score= sinal=" mas NAO causa o ABORTAR.
   - `scan_master.ps1:300` loga `score=$($result.scorePonderado) sinal=$($result.sinalTech)`,
     porem `Invoke-OrchestratorV6` retorna `triagem/mesa/mentor/setup` -- nao tem
     campos `scorePonderado` ou `sinalTech`. Sao properties legacy do orchestrator
     antigo. O agente paralelo focado em logging vai cuidar disso.

3. **Mock/stub deixou de retornar dado**. Probabilidade: LOW.
   - `lib_esquadrao_mocks.ps1` e idempotente (so define se nao existe), e tanto
     triagem_agent.ps1 quanto mesa_agent.ps1 reais sao carregados antes em
     `scan_master.ps1:58-60`. Mock so atuaria se reais falhassem ao carregar,
     o que produziria erro de import, nao 84 aborts limpos.

4. **CoinEx API ou macro feed falhando silenciosamente**. Probabilidade: LOW.
   - Scanner imprime "237 futuros + 1534 spot" -- CoinEx esta respondendo.
   - Macro retorna momentScore variando (22/42/62/77) -- macro feed esta vivo.
   - Se CoinEx market info falhasse, log mostraria "Mercado nao seguro" no
     motivo (orchestrator_v6.ps1:99-104) e nao "Decisao: ABORTAR" generico.

## Fix proposto

**Fix curto (libera o pipeline hoje)**: relaxar a regra Thursday-alt para nao ser
um curto-circuito Tier D incondicional. Opcoes:

a) Mover a quinta-feira-alt para um **flag** que vira o score_predicted para
   baixo, mas deixa a Mesa/Mentor decidir (preserva a calibracao 14y como vies,
   nao como veto).

b) Aplicar Thursday-skip **somente** quando o setup for LONG (a calibracao foi
   construida para LONG B&H). Setups SHORT em quinta podem ate ter edge inverso.

c) Tornar a regra configuravel via `config.local.ps1` (parametro
   `$THURSDAY_ALT_VETO = $false` para destravar paper trade enquanto a calibracao
   por par e revalidada).

**Fix complementar (qualidade do sinal)**: preencher `scanner.score` no Context.
- `orchestrator_v6.ps1:121-128` precisa receber/montar um sub-objeto
  `scanner = @{ score = <score do scanner>, change, volume }`.
- Hoje a Triagem opera no escuro: score=50 default invariante.
- Sem isso, mesmo destravando Thursday, a Triagem nao consegue chegar em Tier A
  (precisa score >= 75) -- todo trade vai cair em Tier B/C, gastando Mesa.

**Arquivos a tocar**:
- `agents/triagem_agent.ps1` (regra de Tier D)
- `agents/orchestrator_v6.ps1` (propagar scanner.score para Context)
- `scripts/scan_master.ps1` (passar scanner result na chamada Invoke-OrchestratorV6,
  hoje so passa Market)
- `agents/config.ps1` ou `config.local.ps1` (flag opcional do Thursday veto)

**Complexidade**: BAIXA. Mudanca pontual em 3 arquivos, ~20-40 linhas no total.
Sem refactor estrutural.

## Risco do fix

- **LOW** para a remocao/parametrizacao do Thursday-veto: regra ja era um
  filtro pre-existente; transformar em peso (nao veto) reverte ao comportamento
  da Mesa, que e o desenho original. Pior caso: alguns trades ruins em quinta
  passam para Mesa e sao filtrados la (mesa CAOS, mentor VETAR).
- **LOW-MEDIUM** para propagar scanner.score: e adicao de campo, nao alteracao
  de logica existente. Triagem ja tem fallback (default 50). Side effect possivel:
  scores reais 80+ vao gerar muito mais Tier A (que pula Mesa) -- isso e
  desejado, mas aumenta custo Mentor (Tier A vai direto pro Mentor).
- **Side effects potenciais**:
  - Aumento de chamadas Groq na Mesa em quintas (3 drones por candidato em vez
    de 0). Custo continua $0 (Groq free tier), mas tempo do ciclo cresce.
  - Se a calibracao Thursday-skip estiver realmente certa estatisticamente,
    destravar pode permitir trades EV-negativos. Mitigacao: paper trade DryRun
    primeiro, validar 14 dias antes de live.

## Proximos passos para o agente Wave 2

1. Implementar fix do Thursday-veto:
   - Decidir entre opcao (a)/(b)/(c) acima. Sugestao: (c) com flag default = $false
     em config.local.ps1 -> destrava paper, preserva calibracao em prod.
   - Reescrever `_Compute-Tier` para que `thursdayAlt` adicione `-15` ao score em
     vez de retornar Tier D direto, OU consultar o flag.
2. Propagar `scanner` no Context do orchestrator V6:
   - Mudar assinatura `Invoke-OrchestratorV6` para aceitar `-ScannerResult`
     (PSCustomObject com market/score/change/volume), ou faze-lo recalcular o
     score do par via CoinEx tickers.
   - Em `scan_master.ps1:299`, passar o objeto do scanner (`$c` ja tem adx/rsi/vol,
     mas falta o score do scanner -- considerar guardar o score original).
3. Coordenar com o agente paralelo (problema #2): apos esses fixes, validar que
   o log `[TRADE]` em scan_master.ps1:300 mostra valores nao-vazios. O fix
   correto la e renomear `scorePonderado/sinalTech` para os campos reais
   retornados por V6 (`triagem.score_predicted` ou `mesa.score_avg`, e
   `mesa.sinal_consenso`).
4. Rodar DryRun de 30 min apos os fixes, num dia que NAO seja quinta, para
   confirmar que Mesa e Mentor agora sao acionados (procurar nos logs por
   "consensus", "APROVAR", "VETAR", "Tier C->Mesa"). Adicionar instrumentacao
   minima no orchestrator_v6.ps1 para imprimir `triagem.tier`, `mesa.consensus`,
   `mentor.decision` (sem PII, so as labels) para tornar visivel o estagio do
   abort em futuras rodadas.
5. Apos destravar, monitorar primeira sexta/sabado/domingo: a regra empirica
   Thursday tambem nao deveria virar Friday-alt-veto -- garantir que a remocao
   nao introduza novos vies por DoW.

# mentor_agent.ps1 — MentorAgent: veto final com sabedoria dos melhores traders
# Persona: sintese de Livermore, Tudor Jones, Druckenmiller, Seykota, Soros,
#          Dennis/Faith, Douglas, Schwartz, Darvas, Raschke, Hayes, Woo
# Ver: knowledge/MENTOR.md e knowledge/MENTOR_PROMPT.md

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "lib_claude.ps1")
# E2 Grounded v2 (2026-05-22): structured GATE STATUS block + forbidden phrases guard
if (Test-Path (Join-Path $PSScriptRoot "lib_mentor_gate_block.ps1")) {
    . (Join-Path $PSScriptRoot "lib_mentor_gate_block.ps1")
}
# E3 Decision Reflection (2026-05-22): PRIOR RESOLVED block injection
if (Test-Path (Join-Path $PSScriptRoot "lib_decision_reflection.ps1")) {
    . (Join-Path $PSScriptRoot "lib_decision_reflection.ps1")
}
# E1 Schema 5-tier wire (2026-05-23): Get-SizingTiltMultiplier integration
if (Test-Path (Join-Path $PSScriptRoot "lib_mentor_schema.ps1")) {
    . (Join-Path $PSScriptRoot "lib_mentor_schema.ps1")
}
# E1 HARD_VETO mechanism (2026-05-23): blacklist 24h on extreme red flag
if (Test-Path (Join-Path $PSScriptRoot "lib_market_blacklist.ps1")) {
    . (Join-Path $PSScriptRoot "lib_market_blacklist.ps1")
}
# A.6 wire (2026-05-26): time context (weekday/hour/session/weekend)
if (Test-Path (Join-Path $PSScriptRoot "lib_mentor_time_context.ps1")) {
    . (Join-Path $PSScriptRoot "lib_mentor_time_context.ps1")
}
# B.4 wire (2026-05-26): alpha_vs_btc historico per market
if (Test-Path (Join-Path $PSScriptRoot "lib_mentor_alpha_history.ps1")) {
    . (Join-Path $PSScriptRoot "lib_mentor_alpha_history.ps1")
}
# B.7 wire (2026-05-26): multi-shot examples canonical
if (Test-Path (Join-Path $PSScriptRoot "lib_mentor_examples.ps1")) {
    . (Join-Path $PSScriptRoot "lib_mentor_examples.ps1")
}
# C.8 wire (2026-05-26): self-consistency 2x para critical tiers
if (Test-Path (Join-Path $PSScriptRoot "lib_mentor_self_consistency.ps1")) {
    . (Join-Path $PSScriptRoot "lib_mentor_self_consistency.ps1")
}

$MENTOR_SYSTEM_PROMPT = @'
Voce e O Mentor - uma sintese das mentes mais brilhantes e experientes
que ja operaram mercados financeiros. Voce nao e um personagem ficticio.
Voce carrega dentro de si as licoes documentadas e verificaveis de:

JESSE LIVERMORE: o maior especulador individual da historia. Ganhou
$100 milhoes no crash de 1929 (equivalente a $1.5B hoje). Perdeu tudo
multiplas vezes por ego e excesso de confianca. Morreu falido em 1940.
Sua licao: "Nunca perdi dinheiro ficando parado. Perdi operando."

PAUL TUDOR JONES: perdeu 60-70% em um dia em 1979. Reconstruiu do zero.
Criou a regra dos 1-2% de risco maximo por trade que usa ate hoje.
Seu principio: "I'm always thinking about losing money, not making money."

STANLEY DRUCKENMILLER: o melhor track record de longo prazo da historia
(30 anos, zero ano negativo). Cometeu seu maior erro em 2000 comprando
$6B em tech no pico por FOMO. Perdeu $3B em semanas.

ED SEYKOTA: transformou $5.000 em $15 milhoes em 12 anos nos anos 70-80.
Sua verdade mais incomoda: "Everybody gets what they want out of the market."

GEORGE SOROS: quebrou o Banco da Inglaterra em 1992, ganhando $1B em um dia.
Sua regra de sobrevivencia: "It's not whether you're right or wrong.
It's how much you make when you're right and how much you lose when wrong."

RICHARD DENNIS E OS TURTLE TRADERS: provou que trading pode ser ensinado
em 2 semanas. O grupo gerou $175M em 5 anos. Mas a maioria parou de
seguir o sistema quando ficou dificil. Licao: saber o sistema e
executar o sistema sao habilidades completamente diferentes.

MARTY SCHWARTZ: passou 9 anos como fundamentalista perdendo dinheiro.
Aprendeu analise tecnica e transformou $100K em $20M em 10 anos.

MARK DOUGLAS: "The market doesn't punish you. Your losses are
the cost of doing business - not feedback about your worth as a person."

NICOLAS DARVAS: danciarino que transformou $36K em $2.25M em 18 meses.
Cada regra do seu sistema nasceu de uma perda real.

LINDA BRADFORD RASCHKE: "In trading, the one who loses the least wins."
Disciplina acima de brilhantismo.

ARTHUR HAYES: co-fundador da BitMEX. "In crypto, tail risk is not theoretical.
It's frequent. Stop loss is not optional. It's oxygen."

WILLY WOO: "The blockchain never lies. Price can be manipulated.
On-chain data cannot."

---

COMO VOCE AGE:

Voce nao e um professor paciente. Voce e um espelho honesto.
Quando alguem apresenta um trade, voce pergunta primeiro:
"Qual e o seu plano se voce estiver errado?"

Voce nao confirma vies sem questionar o lado oposto.
Voce nao da alvo sem stop calculado primeiro.
Voce nao minimiza erros - "foi azar" nao existe no seu vocabulario.
Voce nao motiva - voce confronta.

Quando detecta um dos padroes classicos de erro, voce o nomeia:
- FOMO: "Isso nao e um setup. E medo de ficar de fora com nome tecnico."
- Ego: "Voce esta protegendo sua analise, nao seu capital."
- Revenge trading: "Voce esta tentando recuperar. O mercado nao sabe disso."
- Stop movido: "Voce moveu o stop porque estava com medo, nao porque o setup mudou."
- Overtrading: "Livermore ficou rico parado. O que te faz pensar que operar mais te ajuda?"

---

FRAMEWORK DE ANALISE (sempre nesta ordem):

1. MACRO: o ambiente global favorece esse tipo de operacao agora?
2. CICLO: em qual fase Weinstein estamos? (1-4)
3. ON-CHAIN: o que as maos fortes estao fazendo? (nao o que estao dizendo)
4. TENDENCIA: HTF define a direcao - nunca operar contra o HTF sem razao clara
5. ESTRUTURA: suporte/resistencia com contexto de volume
6. ENTRADA: pullback, breakout ou reversao? Volume confirma?
7. RISCO: stop, alvo e tamanho calculados ANTES de pensar no lucro

---

REGRAS INVIOLAVEIS (Tudor Jones, Dalio, Druckenmiller, CLAUDE.md):

1. Stop loss antes de qualquer entrada. Sem stop = sem trade.
2. Risco maximo por trade: 1% do capital total.
3. R:R minimo: 1:5 (perder $1 para ganhar $5 minimo).
4. Confluencia de 3+ fatores antes de agir.
5. Aguardar e uma posicao. Sem setup claro = sem trade.
6. Nunca mover stop por emocao. Stop foi calculado quando voce estava racional.
7. 3 perdas seguidas no mesmo dia = parar.
8. BTC-core: altcoin precisa BATER BTC (alpha historico > 0) pra justificar exposicao.

REGRAS ANTI-HALLUCINATION (CRITICAS):
1. Se CONTEXTO contem "FQS=N/7 CATEGORY", o FQS ESTA DECLARADO -- cite o valor exato.
   NUNCA escreva "FQS indisponivel" se score presente.
2. Se "FQS=N/A_no_registry" ou "[FQS] ABSENT", entao usar "FQS indisponivel (sem entry)".
3. NUNCA invente razoes ausentes do contexto. Cite SO o que esta no payload.
4. Se faltar dado real, diga "X indisponivel" (qual X) -- nunca "todos faltam".

---

COMO INTERPRETAR "CONFLUENCIA 3+" (calibracao operacional V6):

A Mesa V6 ja sintetiza multiplos fatores em 3 drones (Termal=tendencia HTF,
Radar=macro/risco, Lidar=ATR/sizing). O consensus da Mesa expressa confluencia:

- consensus = FORTE_3  -> 3/3 drones direcionais alinhados = confluencia AAA
- consensus = MEDIO_2  -> 2/3 drones direcionais (1 neutro) = confluencia
  ACEITAVEL se Triagem >= tier B e score_predicted >= 65
- consensus = CAOS     -> drones discordantes = sem confluencia, abortar

NAO confunda "1 drone neutro" com "ausencia de fator". MEDIO_2 com score B+
ja contem 3+ fatores: T (tecnico Mesa), R (risco aprovado Lidar/Termal),
contexto Triagem (tier+score). Veto MEDIO_2 so se Tier <= C OU score < 60.

---

QUANDO VOCE DIZ "NAO OPERE" (condicoes de veto):

- Setup abaixo de B em qualidade (A = perfeito, B = bom, C = marginal)
- Noticia macro relevante nas proximas 2 horas
- Funding rate extremo contra a direcao do trade sem catalisador claro
- R:R menor que 1:3
- Mesa CAOS (drones discordantes)
- Mesa MEDIO_2 com Tier C/D OU score < 60
- ADX < 20 e tentando operar breakout
- Score ponderado dos agentes abaixo de 60/100
- Forca do sinal tecnico abaixo de 50/100
- Discordancia fundamental (macro bearish + tentando long sem catalisador)
- NUPL em euforia (>75) tentando long sem hedge

---

Voce responde APENAS com JSON valido conforme especificado.
'@

function Invoke-MentorAgent {
    param(
        [string]$Market     = "BTCUSDT",
        [object]$TechResult,
        [object]$FundResult,
        [object]$SentResult,
        [object]$ChainResult,
        [double]$ScorePonderado = 50,
        [double]$CapitalTotal   = $CAPITAL_FUTURES,
        [double]$RiscoMaxPct    = $RISCO_MAXIMO_PCT,
        $FeeContext = $null,    # PSCustomObject de CoinEx-GetFeeContext
        [string]$MacroContext = "",  # resumo de lib_macro (DXY/M2/yields, cache 24h)
        [switch]$Verbose
    )

    Write-Host "  [MentorAgent] Avaliando setup para veto: $Market..." -ForegroundColor Magenta

    # Monta resumo de cada agente
    $techSummary  = if ($TechResult) {
        "Sinal: $($TechResult.sinal) | Forca: $($TechResult.forca)/100 | Setup: $($TechResult.qualidade_setup)`n" +
        "Entrada: $($TechResult.preco_entrada) | Stop: $($TechResult.stop_loss) | Alvo1: $($TechResult.alvo1) | R:R: $($TechResult.rr_calculado)`n" +
        "Weinstein: $($TechResult.weinstein_fase) | Wyckoff: $($TechResult.wyckoff_contexto)`n" +
        "Confluencias: $($TechResult.confluencias -join '; ')`n" +
        "Riscos: $($TechResult.riscos -join '; ')`n" +
        "Justificativa: $($TechResult.justificativa)"
    } else { "TechAgent nao disponivel" }

    $fundSummary  = if ($FundResult) {
        "Score fundamental: $($FundResult.score_fundamental)/100 | Macro: $($FundResult.macro_outlook)`n" +
        "Ciclo: $($FundResult.fase_ciclo) | Horizonte: $($FundResult.horizonte_favoravel)`n" +
        "Catalysadores: $($FundResult.catalysadores_positivos -join '; ')`n" +
        "Riscos macro: $($FundResult.riscos_fundamentais -join '; ')`n" +
        "Recomendacao: $($FundResult.recomendacao)"
    } else { "FundAgent nao disponivel" }

    $sentSummary  = if ($SentResult) {
        "Sentimento: $($SentResult.sentimento) | Intensidade: $($SentResult.intensidade)/100`n" +
        "Funding: $($SentResult.funding_sinal) | Contrarian: $($SentResult.contrarian_signal)`n" +
        "Narrativa: $($SentResult.narrativa_dominante)`n" +
        "Alertas: $($SentResult.alertas -join '; ')`n" +
        "Recomendacao: $($SentResult.recomendacao_sentimento)"
    } else { "SentAgent nao disponivel" }

    $chainSummary = if ($ChainResult) {
        "Score chain: $($ChainResult.chain_score)/100 | Bias: $($ChainResult.chain_bias)`n" +
        "Whales: $($ChainResult.comportamento_whales) | Exchange flow: $($ChainResult.exchange_flow)`n" +
        "NUPL fase: $($ChainResult.nupl_fase) | OI sinal: $($ChainResult.oi_sinal)`n" +
        "Alertas chain: $($ChainResult.alertas_chain -join '; ')`n" +
        "Resumo: $($ChainResult.resumo)"
    } else { "ChainAgent nao disponivel" }

    $riscoUSD      = [math]::Round($CapitalTotal * $RiscoMaxPct, 2)
    $stopDistance  = if ($TechResult -and $TechResult.preco_entrada -gt 0 -and $TechResult.stop_loss -gt 0) {
        [math]::Abs($TechResult.preco_entrada - $TechResult.stop_loss)
    } else { 0 }
    $posicaoMax    = if ($stopDistance -gt 0) { [math]::Round($riscoUSD / $stopDistance, 4) } else { 0 }

    $feeSummary = if ($FeeContext) {
        "Maker=$($FeeContext.makerRate*100)% Taker=$($FeeContext.takerRate*100)% RoundTrip=$($FeeContext.roundTrip)% | " +
        "Funding8h=$($FeeContext.funding8h)% Funding24h=$($FeeContext.funding24h)% | " +
        "HoldCost24h=$($FeeContext.holdCost24h)% do valor | Fonte=$($FeeContext.source)"
    } else { "Taxas desconhecidas (fallback: 0.4% round-trip)" }

    $context = @"
=== REVISAO DE TRADE PELO MENTOR ===
PAR: $Market
TIMESTAMP: $(Get-Date -Format "yyyy-MM-dd HH:mm") UTC
SCORE PONDERADO DOS AGENTES: $ScorePonderado/100
CAPITAL TOTAL: $($CapitalTotal) USD | RISCO MAXIMO: $riscoUSD USD (1%)
TAMANHO MAXIMO POSICAO: $posicaoMax unidades (calculado pelo stop)

--- TAXAS REAIS DA CORRETORA ---
$feeSummary

--- ANALISE TECNICA ---
$techSummary

--- ANALISE FUNDAMENTAL ---
$fundSummary

--- SENTIMENTO DE MERCADO ---
$sentSummary

--- ON-CHAIN ---
$chainSummary

--- MACRO GLOBAL (FRED: DXY / M2 / Yields / Fed) ---
$(if ($MacroContext) { $MacroContext } else { "Dados macro nao disponíveis." })
"@

    if ($Verbose) { Write-Host $context -ForegroundColor DarkGray }

    $question = @"
$context

Como O Mentor - sintese dos melhores traders da historia - avalie este setup completo.
Aplique todas as suas regras inviolaveis. Seja implacavel com qualidade.

Responda em JSON:
{
  "veredicto": "EXECUTAR" | "REVISAR" | "ABORTAR",
  "confianca_mentor": 0-100,
  "risco_identificado": "BAIXO" | "MEDIO" | "ALTO" | "EXTREMO",
  "qualidade_final": "A" | "B+" | "B" | "C" | "D",
  "motivo_veto": "texto se ABORTAR ou REVISAR - seja especifico e direto",
  "o_que_falta": ["lista do que precisaria melhorar para ser EXECUTAR"],
  "ponto_mais_forte": "o que fala mais a favor deste setup",
  "ponto_mais_fraco": "o que mais preocupa o mentor",
  "tamanho_posicao_aprovado": numero (em unidades, baseado no 1% de risco),
  "stop_final": numero (confirmar ou ajustar o stop proposto),
  "alvo_final": numero (confirmar ou ajustar o alvo),
  "rr_final": numero,
  "rr_efetivo_com_taxas": numero (rr_final descontando round-trip de fees),
  "viavel_com_taxas": true | false,
  "licao_aplicada": "qual trader e qual licao se aplica diretamente a este setup",
  "mensagem_mentor": "2-3 frases diretas, no estilo do mentor - sem suavizar"
}
"@

    Write-Host "  [MentorAgent] Consultando Mentor (Anthropic->Groq->Gemini)..." -ForegroundColor Magenta
    # Cascade Mentor 2026-05-16: Anthropic primary -> Groq -> Gemini.
    # Mentor é decisão final, qualidade matters, mas com 2 fallbacks gratuitos.

    # 2026-07-05: Injetar consensus_gate dinâmico (Evolution Engine pode ter mudado)
    $mentorSystemPromptDynamic = Get-MentorSystemPromptDynamic
    $gateVal = if ($global:consensus_gate) { $global:consensus_gate } else { "MEDIO_2" }
    Write-Host "  [MentorGate] TIER_B_PAPER exige consensus: $gateVal (via config.local)" -ForegroundColor Cyan

    $result = $null
    if (Get-Command Invoke-MentorCascade -ErrorAction SilentlyContinue) {
        $raw = Invoke-MentorCascade -SystemPrompt $mentorSystemPromptDynamic -UserContent $question -Temperature 0.3 -MaxTokens 1500 -Agent "mentor"
        if ($raw) {
            try {
                $cleaned = $raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
                $result = $cleaned | ConvertFrom-Json
            } catch { $result = $null }
        }
    } else {
        $result = Invoke-ClaudeJson -SystemPrompt $mentorSystemPromptDynamic -UserContent $question -Temperature 0.3 -MaxTokens 1500 -Agent "mentor"
    }

    if (-not $result) {
        Write-Warning "  [MentorAgent] Falha na resposta - ABORTAR por seguranca"
        return [PSCustomObject]@{
            veredicto="ABORTAR"; confianca_mentor=0; risco_identificado="ALTO"
            qualidade_final="D"; motivo_veto="Mentor indisponivel - abortando por seguranca"
            mensagem_mentor="Sem resposta do mentor. Por Tudor Jones: quando ha duvida, nao opere."
            tamanho_posicao_aprovado=0; stop_final=0; alvo_final=0; rr_final=0
        }
    }

    $color = switch ($result.veredicto) {
        "EXECUTAR" { "Green" }
        "REVISAR"  { "Yellow" }
        "ABORTAR"  { "Red" }
        default    { "Gray" }
    }
    Write-Host "  [MentorAgent] VEREDITO: $($result.veredicto) | Confianca=$($result.confianca_mentor) | Qualidade=$($result.qualidade_final)" -ForegroundColor $color
    Write-Host "  [MentorAgent] Mentor: $($result.mensagem_mentor)" -ForegroundColor $color
    return $result
}

# =============================================================================
# Invoke-MentorDebate -- modo DEBATE para Esquadrao V6 (Triagem -> Mesa -> Mentor)
#   Prompt compacto (~300 tokens in, <=400 out). Cita knowledge especifica.
#   Contrato:
#     -Market           string
#     -TriagemResult    PSCustomObject { tier; score_predicted; razao; flags; knowledge_cited }
#     -MesaResult       PSCustomObject { termal; radar; lidar; consensus; sinal_consenso; score_avg }
#                       ou $null quando Tier A (Mesa pulada)
#     -Setup            PSCustomObject { entry; stop; target; rr }
#     -KnowledgeContext string opcional -- se vazio, tenta Get-RelevantKnowledge
#   Retorna:
#     [PSCustomObject]@{ decision="APROVAR"|"VETAR"; confianca=0-100;
#                        mentor_mensagem; knowledge_cited[] }
# =============================================================================

$MENTOR_DEBATE_SYSTEM = @'
Voce e O Mentor (sintese de Livermore, Tudor, Druckenmiller, Seykota, Soros, Douglas, Hayes).
MODO DEBATE: questione com autoridade historica. APROVE ou VETE.

ARQUITETURA (2026-05-20): pipeline ja validou ANTES de voce:
- DSR/PBO/walk-forward purged (Bailey-Lopez de Prado)
- FQS V1.6 (7 dim tokenomics: BLUE_CHIP 6-7 / QUALITY 4-5 / SPECULATIVE 2-3 / AVOID 0-1)
- Beta cap PHASE-AWARE (bull 1.6 / bear 1.4 / top/rec 1.2) -- use SEMPRE valor explicito do CONTEXTO/GATE STATUS, NUNCA assuma 1.2 hardcoded
- Asymmetric demote 3d FLAG, 15+ gates
- Mesa skip em TIER_A_LIVE eh BY DESIGN (asset ja passou todos gates) -- NAO eh atalho cognitivo.

REGRAS INVIOLAVEIS: stop antes entrada; risco 1%; R:R min 3; confluencia 3+;
3 perdas seguidas = parar; nao contra HTF sem catalisador.

DECISAO MODE-AWARE (4 modes ortogonais Triagem.tier × Whitelist.tier):
- TIER_A_LIVE  (triagem=A + wl=live):    FQS>=4 + DSR>=0.9 + n_trades>=30 + flag_streak<3 + beta<=cap_da_phase (NUNCA hardcode 1.2) = APROVAR (Mesa skip BY DESIGN)
- TIER_A_PAPER (triagem=A + wl=observe): mesmas regras do A_LIVE MAS regime atual limita pra paper. Mesa skip OK. APROVAR vira paperOnly automatico.
- TIER_B_PAPER (triagem=B + wl=observe): consensus auto-ajustavel (atual $global:consensus_gate). Se FORTE_3=APROVADO; se MEDIO_2=exige estrutura++; MEDIO_1=veto. Adaptativo por regime.
- GEM:         FQS>=2 + sizing<=0.5% + funding neutro = APROVAR (track record N/A by design)

NUNCA tratar TIER_A_PAPER como conflito -- eh estado legitimo (Tier A quality + regime defensivo).

VETE COM RAZAO ACIONAVEL (nao "Mesa pulou debate" -- isso eh design).

REGRAS ANTI-HALLUCINATION (CRITICAS, violar = decisao invalida):
1. Se CONTEXTO contem "FQS=N/7 CATEGORY" (ex: "FQS=4/7 QUALITY"), o FQS ESTA DECLARADO.
   NUNCA escreva "FQS indisponivel", "FQS nao declarado", "FQS missing", "FQS sem entry".
   Cite o valor exato no veto/aprovacao: "FQS=4/7 QUALITY supera threshold..."
2. Se CONTEXTO contem "FQS=N/A_no_registry", entao FQS realmente nao existe -- use essa
   frase exata: "FQS indisponivel (sem entry no registry)".
3. NUNCA invente razoes ausentes do contexto. Cite SO o que esta no payload.
4. Se faltar dado real, diga "X indisponivel" (e qual X) -- nunca "todos os dados faltam".
5. BETA MATEMATICO: compare o valor numerico exato. Se beta=1.38 e cap_block=1.4, entao
   1.38 < 1.4 = NAO viola BLOCK. NUNCA escreva "viola BLOCK" quando beta < cap_block.
   Isso e erro matematico = decisao invalida. Use: "beta=X abaixo do BLOCK Y (WARN acima de Z)".
5b. BETA DIRECIONAL (2026-07-03): o cap de beta protege LONG (beta alto = cai mais no dump).
   Para direction=SHORT em regime BEAR (BEAR_WEAK/BEAR_STRONG/TRANSITION_DOWN), beta alto
   AMPLIFICA o edge do short (ativo cai 2-3x mais que BTC = exatamente o que o short captura).
   NUNCA aborte um SHORT em bear por beta acima do cap. Frase correta:
   "beta=X favoravel para SHORT em bear (cap protege LONG, nao SHORT)".
   A excecao vale APENAS para SHORT em bear — LONG mantem o cap inviolavel.
5c. FQS DIRECIONAL (2026-07-03): FQS mede qualidade de tokenomics — protege LONG
   (nao comprar lixo). Para direction=SHORT a fisica INVERTE: FQS baixo (1-3 AVOID/
   SPECULATIVE) significa fundamentals fracos = ativo cai mais forte = A FAVOR do short.
   NUNCA use FQS baixo como razao de abortar um SHORT. FQS indisponivel em SHORT =
   neutro (nao bloqueia sozinho; julgue pelos demais gates: estrutura, regime, R:R).
   Frase correta: "FQS=X/7 fraco favorece o SHORT (qualidade baixa cai mais)".
   Para LONG, FQS mantem funcao integral de gate de qualidade.
6. [DSR_HISTORY] e INFORMATIVO, NAO e gate de bloqueio. n_trades=0 NAO impede trade.
   NUNCA use DSR como razao de ABORTAR. O sistema esta em fase de acumulo de historico.
   Se mencionar, use APENAS: "historico limitado -- monitorar evolucao".
   FRASES PROIBIDAS (violacao = decisao invalida, guard automatico detecta):
     "track record inexistente" | "track record zerado" | "zero track record"
     "sem track record" | "DSR n_trades=0" | "n_trades=0 elimina" | "n_trades=0 significa"

Cite knowledge (arquivo.md:tag). Responda APENAS JSON valido. SEJA CONCISO: use APENAS os campos do schema, sem campos extras. mentor_mensagem max 2 frases.
'@

function Build-MentorFullContext {
    # Monta PSCustomObject rich pro Mentor. Cada source eh try/catch -- se quebrar,
    # campo fica null e prompt skipa (graceful). Custo: ~6 leituras de json pequeno.
    # 2026-06-01: Supabase integration - reads from state_store (Supabase or local JSON fallback)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $Mode = "STANDARD",
        [string] $RegimeBias = ""
    )
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    $ctx = [PSCustomObject]@{
        mode = $Mode
        fqs = $null; beta = $null; historical = $null
        regime = $null; drawdown = $null; gates = $null
        time = $null  # A.6 2026-05-26
        alpha_history = $null  # B.4 2026-05-26
    }

    # A.6: time context (sempre disponivel, custo zero)
    if (Get-Command Get-TimeContext -ErrorAction SilentlyContinue) {
        try { $ctx.time = Get-TimeContext } catch {}
    }

    # B.4: alpha_vs_btc historico per market (read-only, cost zero)
    if (Get-Command Get-MarketAlphaSummary -ErrorAction SilentlyContinue) {
        try { $ctx.alpha_history = Get-MarketAlphaSummary -Market $Market } catch {}
    }

    # FQS -- 2026-06-01: Try Supabase first, fallback to JSON
    try {
        # Try Supabase state_store first
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $fqsRecords = @(Get-StateRecords -Table "fqs_registry" -Filter @{ market = $Market })
                if ($fqsRecords.Count -gt 0) {
                    $fqs = $fqsRecords[0]
                    $ctx.fqs = [PSCustomObject]@{ score = [int]$fqs.fqs; category = [string]$fqs.category }
                }
            } catch {}
        }
        
        # Fallback to JSON if Supabase failed
        if (-not $ctx.fqs -and (Get-Command Get-FundamentalScore -ErrorAction SilentlyContinue)) {
            $fqs = Get-FundamentalScore -Market $Market
            if ($fqs -and $fqs.reason -eq "market_not_in_registry") {
                try {
                    $queueFile = Join-Path $journalDir "fqs_enrichment_queue.jsonl"
                    @{ market = $Market; queued_at = (Get-Date).ToString('o'); source = "mentor_full_context" } |
                        ConvertTo-Json -Compress | Add-Content -Path $queueFile -Encoding utf8 -ErrorAction SilentlyContinue
                } catch {}
                $ctx.fqs = [PSCustomObject]@{ score = $null; category = "N/A_no_registry"; reason = "market_not_in_registry" }
            } elseif ($fqs) {
                $ctx.fqs = [PSCustomObject]@{ score = [int]$fqs.fqs; category = [string]$fqs.category }
            }
        }
    } catch {}

    # Beta + dynamic cap (2026-06-01: Supabase integration)
    try {
        # Try Supabase state_store first
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $betaRecords = @(Get-StateRecords -Table "beta_history" -Filter @{ market = $Market })
                if ($betaRecords.Count -gt 0) {
                    $beta = $betaRecords[0].beta
                    # Cap dinamico via phase atual
                    $currentCapBlock = 1.2; $currentCapWarn = 1.0; $capPhase = "default"
                    if (Get-Command Get-BetaCapForPhase -ErrorAction SilentlyContinue) {
                        try {
                            $regimeRecords = @(Get-StateRecords -Table "regime_state")
                            if ($regimeRecords.Count -gt 0) {
                                $regimeForCap = [string]$regimeRecords[0].phase
                                $capObj = Get-BetaCapForPhase -Phase $regimeForCap
                                $currentCapBlock = [double]$capObj.block
                                $currentCapWarn = [double]$capObj.warn
                                $capPhase = [string]$capObj.phase
                            }
                        } catch {}
                    }
                    $ctx.beta = [PSCustomObject]@{
                        asset = [double]$beta
                        portfolio_after = [double]$beta
                        current_cap_block = $currentCapBlock
                        current_cap_warn = $currentCapWarn
                        cap_phase = $capPhase
                    }
                }
            } catch {}
        }
        
        # Fallback to JSON if Supabase failed
        if (-not $ctx.beta) {
            $bPath = Join-Path $journalDir "beta_vs_btc.json"
            if (Test-Path $bPath) {
                $b = Get-Content $bPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($b.beta -and $b.beta.PSObject.Properties[$Market]) {
                    $currentCapBlock = 1.2; $currentCapWarn = 1.0; $capPhase = "default"
                    if (Get-Command Get-BetaCapForPhase -ErrorAction SilentlyContinue) {
                        try {
                            $regimePath = Join-Path $journalDir "regime_state.json"
                            $regimeForCap = ""
                            if (Test-Path $regimePath) {
                                $rs = Get-Content $regimePath -Raw -Encoding UTF8 | ConvertFrom-Json
                                if ($rs.current_regime) { $regimeForCap = [string]$rs.current_regime }
                                elseif ($rs.phase) { $regimeForCap = [string]$rs.phase }
                            }
                            $capObj = Get-BetaCapForPhase -Phase $regimeForCap
                            $currentCapBlock = [double]$capObj.block
                            $currentCapWarn = [double]$capObj.warn
                            $capPhase = [string]$capObj.phase
                        } catch {}
                    }
                    $ctx.beta = [PSCustomObject]@{
                        asset = [double]$b.beta.$Market
                        portfolio_after = [double]$b.beta.$Market
                        current_cap_block = $currentCapBlock
                        current_cap_warn = $currentCapWarn
                        cap_phase = $capPhase
                    }
                }
            }
        }
    } catch {}

    # Historical DSR + n_trades (2026-06-01: Supabase integration)
    try {
        # Try Supabase state_store first
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $drsRecords = @(Get-StateRecords -Table "dsr_global" -Filter @{ market = $Market })
                if ($drsRecords.Count -gt 0) {
                    $dsr = $drsRecords[0]
                    $ctx.historical = [PSCustomObject]@{
                        dsr = [double]$dsr.dsr
                        n_trades = [int]$dsr.n_trades
                        sharpe_30d = if ($dsr.PSObject.Properties['sharpe_30d']) { [double]$dsr.sharpe_30d } else { 0 }
                    }
                }
            } catch {}
        }
        
        # Fallback to JSON if Supabase failed
        if (-not $ctx.historical) {
            $dsrPath = Join-Path $journalDir "dsr_global.json"
            if (Test-Path $dsrPath) {
                $d = Get-Content $dsrPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $perMarket = if ($d.per_market -and $d.per_market.PSObject.Properties[$Market]) { $d.per_market.$Market } else { $null }
                if ($perMarket) {
                    $ctx.historical = [PSCustomObject]@{
                        dsr = [double]$perMarket.dsr
                        n_trades = [int]$perMarket.n_trials
                        sharpe_30d = if ($perMarket.PSObject.Properties['sharpe_30d']) { [double]$perMarket.sharpe_30d } else { 0 }
                    }
                }
            }
        }
    } catch {}

    # Regime (2026-06-01: Supabase integration)
    try {
        # Try Supabase state_store first
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $regimeRecords = @(Get-StateRecords -Table "regime_state")
                if ($regimeRecords.Count -gt 0) {
                    $regime = $regimeRecords[0]
                    $phase = [string]$regime.phase
                    if ($phase) {
                        $ctx.regime = [PSCustomObject]@{ phase = $phase; bias = $RegimeBias }
                    }
                }
            } catch {}
        }
        
        # Fallback to JSON if Supabase failed
        if (-not $ctx.regime) {
            $rPath = Join-Path $journalDir "regime_state.json"
            $phase = ""
            if (Test-Path $rPath) {
                $r = Get-Content $rPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($r.phase) { $phase = [string]$r.phase }
            }
            if ($phase -or $RegimeBias) {
                $ctx.regime = [PSCustomObject]@{ phase = $phase; bias = $RegimeBias }
            }
        }
    } catch {}

    # Drawdown (2026-06-01: Supabase integration)
    try {
        # Try Supabase state_store first
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $ddRecords = @(Get-StateRecords -Table "drawdown_history" -Filter @{ market = $Market })
                if ($ddRecords.Count -gt 0) {
                    $dd = $ddRecords[0]
                    $ctx.drawdown = [PSCustomObject]@{
                        vs_peak_pct = [double]$dd.vs_peak_pct
                        flag_streak = if ($dd.PSObject.Properties['flag_streak']) { [int]$dd.flag_streak } else { 0 }
                        level = [string]$dd.level
                    }
                }
            } catch {}
        }
        
        # Fallback to JSON if Supabase failed
        if (-not $ctx.drawdown) {
            $ddFile = Get-ChildItem -Path $journalDir -Filter "tier_a_drawdown_*.json" -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($ddFile) {
                $dd = Get-Content $ddFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $entry = $null
                if ($dd.drawdowns) {
                    $entry = @($dd.drawdowns | Where-Object { $_.market -eq $Market }) | Select-Object -First 1
                }
                if ($entry) {
                    $ctx.drawdown = [PSCustomObject]@{
                        vs_peak_pct = [double]$entry.vs_peak_pct
                        flag_streak = if ($entry.PSObject.Properties['flag_streak']) { [int]$entry.flag_streak } else { 0 }
                        level = [string]$entry.level
                    }
                }
            }
        }
    } catch {}

    # Gates: deferred -- caller passa via -GatesResult quando tiver. Default null.

    # Tori proximity (2026-06-01: Supabase integration - anticipatory layer)
    # Le snapshot escrito por CoinExToriProximity cron 15min. Fail-safe -- se stale/missing,
    # field=null e Mentor prompt skipa. Field rico: side (LONG/SHORT/NONE), proximity_pct,
    # action_line, ripening. Mentor decide se trade eh "setup zone" ou "chase".
    try {
        # Try Supabase state_store first
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $toriRecords = @(Get-StateRecords -Table "tori_proximity" -Filter @{ market = $Market })
                if ($toriRecords.Count -gt 0) {
                    $tp = $toriRecords[0]
                    $ctx | Add-Member -MemberType NoteProperty -Name tori_proximity -Value ([PSCustomObject]@{
                        valid          = [bool]$tp.valid
                        side           = "$($tp.side)"
                        proximity_pct  = [double]$tp.proximity_pct
                        action_line    = [double]$tp.action_line
                        touches        = [int]$tp.touches
                        slope_deg      = [double]$tp.slope_deg
                        rsi            = [double]$tp.rsi
                        vol_drying     = [bool]$tp.vol_drying
                        setup_ripening = [bool]$tp.setup_ripening
                    }) -Force
                }
            } catch {}
        }
        
        # Fallback to JSON if Supabase failed
        if (-not ($ctx.PSObject.Properties['tori_proximity'])) {
            if (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue) {
                $statePath = Join-Path $journalDir "tori_proximity_state.json"
                $tp = Get-ToriProximityForMarket -Market $Market -StatePath $statePath -MaxAgeMinutes 30
                if ($tp) {
                    $ctx | Add-Member -MemberType NoteProperty -Name tori_proximity -Value ([PSCustomObject]@{
                        valid          = [bool]$tp.valid
                        side           = "$($tp.side)"
                        proximity_pct  = $tp.proximity_pct
                        action_line    = $tp.action_line
                        touches        = $tp.touches
                        slope_deg      = $tp.slope_deg
                        rsi            = $tp.rsi
                        vol_drying     = $tp.vol_drying
                        setup_ripening = [bool]$tp.setup_ripening
                    }) -Force
                }
            }
        }
    } catch {}

    return $ctx
}


function Get-MentorSystemPromptDynamic {
    <#
    .SYNOPSIS
    Retorna o MENTOR_SYSTEM_PROMPT com consensus_gate injetado dinamicamente
    2026-07-05: Fix para Evolution Engine que muda consensus_gate em config.local
    #>
    $gate = if ($global:consensus_gate) { $global:consensus_gate } else { "MEDIO_2" }
    return $MENTOR_SYSTEM_PROMPT -replace 'TIER_B_PAPER \(triagem=B \+ wl=observe\): consensus auto-ajustavel.*', "TIER_B_PAPER (triagem=B + wl=observe): exige Mesa consensus $gate (auto-ajustado no ciclo anterior)"
}

function Get-MentorDebateSystemDynamic {
    <#
    .SYNOPSIS
    Retorna o MENTOR_DEBATE_SYSTEM com consensus_gate injetado dinamicamente
    #>
    $gate = if ($global:consensus_gate) { $global:consensus_gate } else { "MEDIO_2" }
    return $MENTOR_DEBATE_SYSTEM -replace 'TIER_B_PAPER \(triagem=B \+ wl=observe\): consensus auto-ajustavel.*', "TIER_B_PAPER (triagem=B + wl=observe): exige Mesa consensus $gate (auto-ajustado)"
}

function Invoke-MentorDebate {
    param(
        [string]$Market,
        [PSCustomObject]$TriagemResult,
        [PSCustomObject]$MesaResult,
        [PSCustomObject]$Setup,
        [string]$KnowledgeContext = "",
        [PSCustomObject]$FullContext = $null,   # Fase 1A 2026-05-20: rich context (FQS/beta/dsr/regime/dd/gates/mode)
        # Tier 2 Block 2 B.1 (2026-05-23): direction context pra SHORT support
        # Backward compat: vazio/null = LONG default (atual comportamento)
        [ValidateSet("LONG","SHORT","")] [string] $Direction = ""
    )
    # Resolve direction: explicit > Mesa(consenso) > Triagem(bidirecional) > LONG.
    # 2026-06-08: usa lib central + fallback Triagem (fecha "LONG default cego" em bear).
    if (-not (Get-Command Resolve-MentorDirection -ErrorAction SilentlyContinue)) {
        $__bidirLib = Join-Path $PSScriptRoot "lib_bidirectional_direction.ps1"
        if (Test-Path $__bidirLib) { . $__bidirLib }
    }
    $mesaSig = if ($MesaResult -and $MesaResult.sinal_consenso) { [string]$MesaResult.sinal_consenso } else { "" }
    $triagemDir = if ($TriagemResult -and $TriagemResult.direction) { [string]$TriagemResult.direction } else { "" }
    if (Get-Command Resolve-MentorDirection -ErrorAction SilentlyContinue) {
        $effectiveDirection = Resolve-MentorDirection -ExplicitDirection ([string]$Direction) -MesaSignal $mesaSig -TriagemDirection $triagemDir
    } else {
        # Fallback legado (lib indisponivel)
        $effectiveDirection = if ($Direction) { $Direction }
                              elseif ($mesaSig -in @("LONG","SHORT")) { $mesaSig }
                              elseif ($triagemDir -in @("LONG","SHORT")) { $triagemDir }
                              else { "LONG" }
    }

    # RAG opcional -- so executa se Get-RelevantKnowledge (Parte A) estiver disponivel
    if (-not $KnowledgeContext -and (Get-Command Get-RelevantKnowledge -ErrorAction SilentlyContinue)) {
        try {
            $sinalQ  = if ($MesaResult) { $MesaResult.sinal_consenso } else { "" }
            $consQ   = if ($MesaResult) { $MesaResult.consensus }      else { "TierA" }
            $query   = "$Market $consQ $sinalQ tier=$($TriagemResult.tier)"
            $chunks  = Get-RelevantKnowledge -Query $query -MaxChunks 3
            if ($chunks) {
                $KnowledgeContext = (@($chunks) | ForEach-Object { "$($_.source): $($_.text)" }) -join "`n"
            }
        } catch { $KnowledgeContext = "" }
    }

    $mesaLine = if ($MesaResult) {
        # 2026-05-20 fix: agregar confluencias dos 3 drones. Antes nao passava
        # -> Mentor vetava por "confluencia 3+ ausente" mesmo Mesa fornecendo.
        # 2026-05-20 PM refino (TIPO C hallucination): linguagem neutra quando vazio
        # (era "[ALERTA: Mesa nao documentou]" -> LLM vetava por trigger word).
        $allConfluencias = @()
        foreach ($d in @($MesaResult.termal, $MesaResult.radar, $MesaResult.lidar)) {
            if ($d -and $d.confluencias) { $allConfluencias += @($d.confluencias) }
        }
        $confluText = if ($allConfluencias.Count -gt 0) {
            " | confluencias($($allConfluencias.Count))=" + (($allConfluencias | Select-Object -First 8) -join ',')
        } else {
            " | confluencias=N/A (drone silent, peso reduzido)"
        }
        # 2026-05-20 PM: Mesa.degraded=true significa 1+ drone falhou no cascade -- info parcial.
        # Antes Mentor decidia cego. Agora prompt sinaliza pra ele ajustar confianca.
        $degradedText = if ($MesaResult.PSObject.Properties['degraded'] -and $MesaResult.degraded -eq $true) {
            " | [DEGRADED: 1+ drone falhou, info parcial]"
        } else { "" }
        "Mesa: $($MesaResult.consensus) sinal=$($MesaResult.sinal_consenso) avg=$($MesaResult.score_avg) | " +
        "T:$($MesaResult.termal.sinal)/$($MesaResult.termal.forca) " +
        "R:$($MesaResult.radar.sinal)/$($MesaResult.radar.forca) " +
        "L:$($MesaResult.lidar.sinal)/$($MesaResult.lidar.forca)" + $confluText + $degradedText
    } else {
        # 2026-05-20 PM refino (TIPO A hallucination): remover trigger word 'pulada/pulou'
        # do prompt. Antes era "Mesa: pulada (Tier A direto)" -> LLM ecoava 54% das
        # VETARs com frase "Mesa pulou o debate" mesmo prompt proibindo explicitamente.
        "Mesa: NAO_APLICAVEL (Tier A pre-validado por 8+ gates upstream -- skip eh by design)"
    }

    # 2026-06-15 FIX: Detecta e corrige target invertido para SHORT
    # Bug: SHORT com target > entry (deveria ser target < entry).
    # Deteccao: se direction=SHORT e target > entry, inverte target/stop.
    if ($Setup -and $Direction -eq "SHORT" -and [double]$Setup.target -gt [double]$Setup.entry) {
        $correctedTarget = $Setup.entry - ([double]$Setup.entry - [double]$Setup.stop) * $Setup.rr
        $correctedStop = $Setup.stop  # stop nao muda, ja esta correto
        Write-Host "  [MENTOR] SHORT target invertido detectado: $($Setup.target) > $($Setup.entry). Corrigindo para $([math]::Round($correctedTarget, 4))" -ForegroundColor DarkYellow
        $Setup.target = $correctedTarget
    }

    $setupLine = if ($Setup) {
        "Setup: entry=$($Setup.entry) stop=$($Setup.stop) target=$($Setup.target) rr=$($Setup.rr)"
    } else { "Setup: nao definido" }

    # Fase 1A: FullContext compacto (cost-aware). Cada linha so se field existe.
    $ctxLines = @()
    if ($FullContext) {
        if ($FullContext.PSObject.Properties['mode']) {
            $ctxLines += "mode=$($FullContext.mode)"
        }
        if ($FullContext.PSObject.Properties['fqs'] -and $FullContext.fqs) {
            # 2026-05-20 PM2: linha PROEMINENTE (uppercase FQS=) + handle no_registry case
            if ($null -eq $FullContext.fqs.score) {
                $ctxLines += "FQS=N/A_no_registry (market sem entry -- enrich agendado)"
            } else {
                $ctxLines += "FQS=$($FullContext.fqs.score)/7 $($FullContext.fqs.category)"
            }
        }
        if ($FullContext.PSObject.Properties['beta'] -and $FullContext.beta) {
            # 2026-05-22 PM fix: passa cap dinamico explicit pra evitar Mentor inventar 1.2
            $capStr = if ($FullContext.beta.PSObject.Properties['current_cap_block']) {
                " | cap_phase=$($FullContext.beta.cap_phase) cap_block=$($FullContext.beta.current_cap_block) cap_warn=$($FullContext.beta.current_cap_warn)"
            } else { "" }
            $ctxLines += "beta=$($FullContext.beta.asset) portfolio_after=$($FullContext.beta.portfolio_after)$capStr"
        }
        if ($FullContext.PSObject.Properties['historical'] -and $FullContext.historical) {
            $h = $FullContext.historical
            $ctxLines += "hist dsr=$($h.dsr) n_trades=$($h.n_trades) sharpe30d=$($h.sharpe_30d)"
        }
        if ($FullContext.PSObject.Properties['regime'] -and $FullContext.regime) {
            $ctxLines += "regime $($FullContext.regime.phase) bias=$($FullContext.regime.bias)"
        }
        if ($FullContext.PSObject.Properties['drawdown'] -and $FullContext.drawdown) {
            $d = $FullContext.drawdown
            $ctxLines += "dd vs_peak=$($d.vs_peak_pct)% streak=$($d.flag_streak) level=$($d.level)"
        }
        if ($FullContext.PSObject.Properties['gates'] -and $FullContext.gates) {
            $ctxLines += "gates $($FullContext.gates.passed)/$($FullContext.gates.total)"
        }
        # Tori proximity (2026-05-21 PM7) -- anticipatory trendline signal.
        # Mentor usa pra distinguir "setup zone" (perto da action_line, baixo chase risk)
        # de "chase" (preco ja extendido). Side LONG/SHORT informa qual setup esta amadurecendo.
        if ($FullContext.PSObject.Properties['tori_proximity'] -and $FullContext.tori_proximity -and $FullContext.tori_proximity.valid) {
            $tp = $FullContext.tori_proximity
            $ripeningTag = if ($tp.setup_ripening) { "RIPENING" } else { "watch" }
            $ctxLines += "tori_proximity side=$($tp.side) prox=$($tp.proximity_pct)% line=$($tp.action_line) touches=$($tp.touches) slope=$($tp.slope_deg)deg rsi=$($tp.rsi) vol_dry=$($tp.vol_drying) -> $ripeningTag"
        }
    }
    # E2 Grounded v2: prefer GATE STATUS block (structured, ABSENT explicit) over free-form CONTEXTO.
    # Free-form fallback se lib_mentor_gate_block nao loaded.
    $ctxBlock = if ($FullContext -and (Get-Command Build-GateStatusBlock -ErrorAction SilentlyContinue)) {
        (Build-GateStatusBlock -FullContext $FullContext) + "`n"
    } elseif ($ctxLines.Count -gt 0) {
        "CONTEXTO:`n" + ($ctxLines -join "`n") + "`n"
    } else {
        ""
    }

    # E3 Reflection loop: inject PRIOR RESOLVED block (last 5 resolved decisions este market).
    # Fail-soft: se lib nao loaded ou nao houver reflections, block fica vazio.
    $priorBlock = ""
    if ((Get-Command Get-PriorReflectionsForMarket -ErrorAction SilentlyContinue) -and `
        (Get-Command Format-PriorReflectionsBlock -ErrorAction SilentlyContinue)) {
        try {
            $priorReflections = Get-PriorReflectionsForMarket -Market $Market -MaxN 5
            if (@($priorReflections).Count -gt 0) {
                $priorBlock = (Format-PriorReflectionsBlock -Reflections $priorReflections) + "`n"
            }
        } catch {}
    }
    $ctxBlock = $ctxBlock + $priorBlock

    # 2026-07-04 AUTO-APRENDIZADO: placar de acerto gradeado (grade_llm_decisions)
    # injetado por bolso direction|regime. Fail-soft (mesmo padrao do reflection).
    if (Get-Command Get-LlmCalibrationBlock -ErrorAction SilentlyContinue) {
        try {
            $calDir = if ($FullContext -and $FullContext.PSObject.Properties['direction'] -and $FullContext.direction) { [string]$FullContext.direction } else { "LONG" }
            $calReg = if ($FullContext -and $FullContext.PSObject.Properties['regime'] -and $FullContext.regime) { [string]$FullContext.regime } elseif ($global:CURRENT_REGIME) { [string]$global:CURRENT_REGIME } else { "" }
            if ($calReg) {
                $calBlock = Get-LlmCalibrationBlock -Direction $calDir -Regime $calReg
                if ($calBlock) { $ctxBlock = $ctxBlock + $calBlock + "`n" }
            }
        } catch {}
    }

    # 2026-07-04 API RESEARCH: sinal de crowding (funding) com evidencia n=5133.
    # Informativo/confluencia — nunca standalone. Fail-soft.
    if (Get-Command Get-CrowdingBlock -ErrorAction SilentlyContinue) {
        try {
            $crBlock = Get-CrowdingBlock -Market $Market
            if ($crBlock) { $ctxBlock = $ctxBlock + $crBlock + "`n" }
        } catch {}
    }

    # 2026-05-20 PM refino (TIPO B hallucination): skip header KNOWLEDGE: quando vazio.
    # Antes prompt tinha "KNOWLEDGE:\n\n" -> LLM defaultava "ausencia de knowledge" como veto.
    $knowledgeBlock = if ($KnowledgeContext -and $KnowledgeContext.Trim().Length -gt 0) {
        "KNOWLEDGE:`n$KnowledgeContext`n"
    } else { "" }

    # E1 5-tier additive: prompt agora pede AMBOS legacy decision (compat) + optional 5-tier veredicto.
    # Sizing path usa 5-tier se presente (com cap STRONG <30 outcomes), senao 1.0x.
    # B.1 wire: direction explicit no prompt. Mentor avalia setup contextualmente
    # pra direcao especifica (LONG amplifica gains em bull, SHORT amplifica em bear).
    $directionLine = if ($effectiveDirection -eq "SHORT") {
        "DIRECTION: SHORT (vendendo top, expects decline). Avalie: setup eh capitulacao topo verdadeira ou pullback breve em uptrend? Risk: loss UNLIMITED em SHORT, stop ACIMA entry obrigatorio."
    } else {
        "DIRECTION: LONG (comprando fundo, expects bounce). Avalie: setup eh capitulacao fundo verdadeira ou continuation em downtrend?"
    }

    # B.7 (2026-05-26): multi-shot examples (1 APROVAR + 1 VETAR canonicos).
    # Cost: ~250 tokens extra/call. Beneficio: hallucination reduce 30-50% empirico.
    $examplesBlock = ""
    if (Get-Command Get-MentorExamplesBlock -ErrorAction SilentlyContinue) {
        try { $examplesBlock = (Get-MentorExamplesBlock) + "`n`n" } catch {}
    }

    $userPrompt = @"
$Market | Direction=$effectiveDirection | Triagem tier=$($TriagemResult.tier) score_pred=$($TriagemResult.score_predicted)
$mesaLine
$setupLine
$ctxBlock$knowledgeBlock$examplesBlock
$directionLine

APROVAR ou VETAR? Use CONTEXTO acima (FQS/beta/historical/regime/dd/gates/time/alpha_hist) pra decisao informada.

CLASSIFIQUE OBRIGATORIAMENTE em 5-tier:
  STRONG_EXECUTAR = high-confidence layup (rare, sizing 1.5x cap)
  EXECUTAR        = normal aprovar (sizing 1.0x)
  REVISAR         = doubt (sizing 0.5x paper-only) -- mapeia pra decision APROVAR ou VETAR
  ABORTAR         = skip (decision=VETAR)
  HARD_VETO       = extreme red flag (skip + blacklist 24h, decision=VETAR)

Coerencia: STRONG_EXECUTAR/EXECUTAR -> decision=APROVAR. ABORTAR/HARD_VETO -> decision=VETAR.

JSON: { "decision":"APROVAR"|"VETAR", "confianca":0-100, "mentor_mensagem":"2-3 frases", "knowledge_cited":["arquivo.md:tag"], "veredicto_5tier":"STRONG_EXECUTAR|EXECUTAR|REVISAR|ABORTAR|HARD_VETO" }
"@

    # Cascade Mentor 2026-05-16: Anthropic primary -> Groq -> Gemini.
    # 2026-07-05: Injetar consensus_gate dinâmico via função
    $mentorDebateSystemDynamic = Get-MentorDebateSystemDynamic

    $result = $null
    if (Get-Command Invoke-MentorCascade -ErrorAction SilentlyContinue) {
        $raw = Invoke-MentorCascade -SystemPrompt $mentorDebateSystemDynamic -UserContent $userPrompt -Temperature 0.3 -MaxTokens 1200 -Agent "mentor"
        if ($raw) {
            try {
                $cleaned = $raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
                $result = $cleaned | ConvertFrom-Json
            } catch { $result = $null }
        }
    } else {
        $result = Invoke-ClaudeJson -SystemPrompt $mentorDebateSystemDynamic -UserContent $userPrompt `
            -Temperature 0.3 -MaxTokens 1200 -Agent "mentor"
    }

    # 2026-05-20 PM: provider trace -- captura qual LLM respondeu (anthropic_sonnet/groq_llama70b/...)
    $providerUsed = if ($script:LAST_CASCADE_PROVIDER) { $script:LAST_CASCADE_PROVIDER } else { "none" }

    if (-not $result) {
        Write-Host "  [MentorDebate] Mentor indisponivel - VETO por seguranca" -ForegroundColor Yellow
        return [PSCustomObject]@{
            decision        = "VETAR"
            confianca       = 0
            mentor_mensagem = "Mentor indisponivel - VETO por seguranca. Tudor Jones: na duvida, fora do mercado."
            knowledge_cited = @()
            provider_used   = "none"
        }
    }

    $knowList = if ($result.knowledge_cited) { [object[]]@($result.knowledge_cited) } else { [object[]]@() }
    $msg = if ($result.mentor_mensagem) { $result.mentor_mensagem } else { "(sem mensagem)" }

    # B.2 (2026-05-26): schema V2 -- veredicto_5tier MANDATORY + coerencia.
    # Se falhar, NAO bloqueia (fail-soft), mas marca veredicto_5tier=null + log.
    if (Get-Command Test-MentorOutputV2 -ErrorAction SilentlyContinue) {
        try {
            $schemaCheck = Test-MentorOutputV2 -Response $result
            if (-not $schemaCheck.valid) {
                Write-Warning "  [MentorDebate] Schema V2 violations: $($schemaCheck.violations -join '; ')"
            }
        } catch {}
    }

    # E2 Grounded v2: forbidden phrases guard pos-LLM.
    # Smart detection: phrase "FQS indisponivel" eh hallucination apenas se GATE STATUS
    # nao tem [FQS] ABSENT (justified). Senao flagada como hallucination + logged.
    try {
        if (Get-Command Test-PromptForbiddenPhrases -ErrorAction SilentlyContinue) {
            $gateBlock = if ($FullContext -and (Get-Command Build-GateStatusBlock -ErrorAction SilentlyContinue)) {
                Build-GateStatusBlock -FullContext $FullContext
            } else { "" }
            $guardResult = Test-PromptForbiddenPhrases -Text $msg -GateStatusBlock $gateBlock
            if ($guardResult.has_forbidden) {
                Write-Warning "  [MentorDebate] FORBIDDEN_PHRASE in response: $($guardResult.found -join ', ')"
                if (Get-Command Add-HallucinationEvent -ErrorAction SilentlyContinue) {
                    $hpath = Join-Path $global:JOURNAL_DIR "mentor_hallucinations.jsonl"
                    Add-HallucinationEvent -Path $hpath -Market $Market -Type "forbidden_phrase" -MentorReason $msg -ContextValue ($guardResult.found -join ';')
                }
            }
        }
    } catch {}

    $color = if ($result.decision -eq "APROVAR") { "Green" } else { "Red" }
    Write-Host "  [MentorDebate] $($result.decision) conf=$($result.confianca) [$providerUsed] | $msg" -ForegroundColor $color

    # 2026-05-21 PM6+870min: post-LLM hallucination detector (P0b/P1).
    # Mentor as vezes invoca "FQS indisponivel" apesar de FullContext ter FQS valido.
    # Loga em journal/mentor_hallucinations.jsonl pra audit + metricas merit-only.
    # NAO bloqueia (Mentor ja VETOU) — apenas marca pra futura skill reforco.
    try {
        if ((Get-Command Test-MentorFqsHallucination -ErrorAction SilentlyContinue) -and $FullContext) {
            $fqsScore = $null
            $fqsCat   = ""
            if ($FullContext.PSObject.Properties['fqs'] -and $FullContext.fqs) {
                if ($null -ne $FullContext.fqs.score) {
                    $fqsScore = [int]$FullContext.fqs.score
                    $fqsCat   = [string]$FullContext.fqs.category
                }
            }
            $halluc = Test-MentorFqsHallucination -MentorReason $msg -FullContextFqsScore $fqsScore -FullContextFqsCategory $fqsCat
            if ($halluc.is_hallucination) {
                Write-Warning "  [MentorDebate] HALLUCINATION detected: $($halluc.evidence) (context tinha $($halluc.context_value))"
                if (Get-Command Add-HallucinationEvent -ErrorAction SilentlyContinue) {
                    $hpath = Join-Path $global:JOURNAL_DIR "mentor_hallucinations.jsonl"
                    Add-HallucinationEvent -Path $hpath -Market $Market -Type "fqs_missing" -MentorReason $msg -ContextValue $halluc.context_value
                }
            }
        }
    } catch {}

    # C.8 (2026-05-26): self-consistency 2x para critical tiers (STRONG/HARD_VETO).
    # ~5-10% das decisoes empirico = custo extra controlado. Anti-overconfidence.
    if ($result.PSObject.Properties['veredicto_5tier'] -and $result.veredicto_5tier `
        -and (Get-Command Test-SelfConsistencyRequired -ErrorAction SilentlyContinue) `
        -and (Test-SelfConsistencyRequired -Veredicto5tier ([string]$result.veredicto_5tier))) {
        try {
            Write-Host "  [MentorDebate] Critical tier '$($result.veredicto_5tier)' - chamando 2nd opinion" -ForegroundColor Magenta
            $raw2 = $null
            if (Get-Command Invoke-MentorCascade -ErrorAction SilentlyContinue) {
                $raw2 = Invoke-MentorCascade -SystemPrompt $mentorDebateSystemDynamic -UserContent $userPrompt -Temperature 0.4 -MaxTokens 1200 -Agent "mentor"
            }
            if ($raw2) {
                $cleaned2 = $raw2 -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
                $result2 = $cleaned2 | ConvertFrom-Json -ErrorAction Stop
                if ($result2.PSObject.Properties['veredicto_5tier']) {
                    $resolved = Resolve-SelfConsistency -First $result -Second $result2
                    if (-not $resolved.consistent) {
                        Write-Warning "  [MentorDebate] Self-consistency DIVERGE: $($resolved.reason)"
                        # Merge: substitui campos chave preservando knowledge_cited do First
                        foreach ($prop in @("decision","veredicto_5tier","confianca","mentor_mensagem")) {
                            if ($resolved.final.PSObject.Properties[$prop]) {
                                $result | Add-Member -MemberType NoteProperty -Name $prop -Value $resolved.final.$prop -Force
                            }
                        }
                        $msg = $result.mentor_mensagem
                    }
                }
            }
        } catch {
            Write-Host "  [MentorDebate] Self-consistency 2nd call falhou (nao bloqueia): $_" -ForegroundColor DarkYellow
        }
    }

    # E1 5-tier wire: extract optional veredicto_5tier + compute sizing multiplier.
    # Backward compat: campos legacy (decision/confianca) preservados; 5-tier eh additive.
    $veredicto5tier = $null
    $sizingMultiplier = 1.0
    if ($result.PSObject.Properties['veredicto_5tier'] -and $result.veredicto_5tier) {
        $veredicto5tier = [string]$result.veredicto_5tier
        if (Get-Command Get-SizingTiltMultiplier -ErrorAction SilentlyContinue) {
            try {
                $sizingMultiplier = Get-SizingTiltMultiplier -Veredicto $veredicto5tier
            } catch {}
        }
        # E1 HARD_VETO hook: auto-blacklist 24h se Mentor flagged extremo
        if ($veredicto5tier -eq "HARD_VETO" -and (Get-Command Add-MarketBlacklist -ErrorAction SilentlyContinue)) {
            try {
                Add-MarketBlacklist -Market $Market -TtlHours 24 -Reason "HARD_VETO: $($msg.Substring(0,[Math]::Min(120,$msg.Length)))"
                Write-Host "  [MentorDebate] HARD_VETO -> $Market blacklisted 24h" -ForegroundColor Magenta
            } catch {}
        }
    }

    return [PSCustomObject]@{
        decision           = $result.decision
        confianca          = [int]$result.confianca
        mentor_mensagem    = $msg
        veredicto_5tier    = $veredicto5tier        # NEW (null se LLM nao retornou)
        sizing_multiplier  = $sizingMultiplier      # NEW (default 1.0 = legacy behavior)
        direction          = $effectiveDirection    # B.1 wire (LONG default)
        knowledge_cited    = ,$knowList
        provider_used   = $providerUsed   # 2026-05-20 PM
    }
}

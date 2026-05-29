# lib_mentor_rules.ps1 -- C.3 wire 2026-05-26
# Single source of truth para regras compartilhadas entre MENTOR_SYSTEM_PROMPT
# (legado, debate full) e MENTOR_DEBATE_SYSTEM (V6 compact). Antes divergiam:
# legacy diz R:R 1:3, novo diz 1:5; legacy sem anti-hallucination rules.

function Get-MentorAntiHallucinationRules {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return @'
REGRAS ANTI-HALLUCINATION (CRITICAS, violar = decisao invalida):
1. Se CONTEXTO tem "FQS=N/7 CATEGORY" (ex "FQS=4/7 QUALITY"), o FQS ESTA DECLARADO.
   NUNCA escreva "FQS indisponivel", "FQS missing", "FQS nao declarado".
   Cite o valor exato: "FQS=4/7 QUALITY supera threshold...".
2. Se CONTEXTO tem "FQS=N/A_no_registry" ou "[FQS] ABSENT", entao FQS realmente
   nao existe -- use "FQS indisponivel (sem entry no registry)".
3. NUNCA invente razoes ausentes do contexto. Cite SO o que esta no payload.
4. Se faltar dado real, diga "X indisponivel" (qual X) -- nunca "todos os dados faltam".
5. [DSR_HISTORY] e INFORMATIVO, NAO e gate de bloqueio. n_trades=0 NAO impede trade.
   NUNCA use DSR_HISTORY como razao de ABORTAR. O sistema esta em fase de acumulo.
   Se quiser mencionar, diga "historico limitado -- monitorar evolucao".
   FRASES PROIBIDAS (violacao = decisao invalida):
     - "track record inexistente", "track record zerado", "zero track record"
     - "sem track record", "DSR n_trades=0", "n_trades=0 elimina/significa/e"
   Essas frases transformam dado informativo em veto -- comportamento incorreto.
6. BETA: compare NUMERICAMENTE o valor exato do payload vs o cap_block exato do payload.
   Se beta=1.38 e cap_block=1.4, entao 1.38 < 1.4 = NAO viola BLOCK (e WARN se acima de cap_warn).
   NUNCA escreva "viola BLOCK" quando beta < cap_block. Isso e erro matematico = decisao invalida.
   Formato correto: "beta=1.38 abaixo do BLOCK 1.4 (WARN acima de 1.1) -- monitorar exposicao".
'@
}

function Get-MentorInviolableRules {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return @'
REGRAS INVIOLAVEIS (Tudor Jones, Dalio, Druckenmiller, CLAUDE.md):
1. Stop loss antes de qualquer entrada. Sem stop = sem trade.
2. Risco maximo por trade: 1% do capital total.
3. R:R minimo: 1:5 (perder $1 para ganhar $5 minimo).
4. Confluencia de 3+ fatores antes de agir.
5. Aguardar e uma posicao. Sem setup claro = sem trade.
6. Nunca mover stop por emocao. Stop foi calculado quando voce estava racional.
7. 3 perdas seguidas no mesmo dia = parar.
8. BTC-core: altcoin precisa BATER BTC (alpha_vs_btc > 0 historico) pra justificar
   exposicao. Sem edge alpha demonstrada, holdar BTC e dominante.
'@
}

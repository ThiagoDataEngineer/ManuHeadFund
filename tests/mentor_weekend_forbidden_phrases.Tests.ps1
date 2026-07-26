# mentor_weekend_forbidden_phrases.Tests.ps1 -- 2026-07-26
#
# Owner reportou zero trades novos aos domingos; investigacao encontrou que
# o Mentor LLM (Sonnet real, funcional desde 2026-07-25) usava
# "WEEKEND_LOW_LIQUIDITY"/"fim de semana" como um dos "3+ filtros" de veto,
# mesmo o operador rodando 24/7 (cripto nao fecha fim de semana). [TIME] no
# contexto e so informativo (mesmo padrao ja resolvido pra [DSR_HISTORY] em
# 2026-05-28, ver dsr_forbidden_phrases.Tests.ps1) -- nunca deveria ser gate
# de bloqueio isolado.
#
# Fix: regra 7 explicita em MENTOR_DEBATE_SYSTEM (mentor_agent.ps1) +
# frases adicionadas ao guard pos-resposta (MENTOR_FORBIDDEN_PHRASES).
#
# Pester 3.x. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_mentor_gate_block.ps1")

Describe "Weekend/TIME frases proibidas detectadas pelo guard" {

    It "'fim de semana' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "regime BEAR_WEAK + fim de semana com baixa liquidez = setup arriscado"
        $r.has_forbidden | Should Be $true
        $r.found -contains "fim de semana" | Should Be $true
    }

    It "'WEEKEND_LOW_LIQUIDITY' (case do log real) e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "regime TRANSITION_UP mas setup em LONG de fundo em ASIA WEEKEND_LOW_LIQUIDITY = risco assimetrico"
        $r.has_forbidden | Should Be $true
        ($r.found -contains "weekend_low_liquidity" -or $r.found -contains "ASIA WEEKEND") | Should Be $true
    }

    It "'ASIA WEEKEND' isolado e detectado" {
        $r = Test-PromptForbiddenPhrases -Text "baixa liquidez (ASIA WEEKEND) amplificam risco"
        $r.has_forbidden | Should Be $true
        $r.found -contains "ASIA WEEKEND" | Should Be $true
    }

    It "'baixa liquidez de sabado' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "setup fraco em baixa liquidez de sabado"
        $r.has_forbidden | Should Be $true
    }

    It "'baixa liquidez de domingo' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "regime hostil + baixa liquidez de domingo"
        $r.has_forbidden | Should Be $true
    }

    It "razao real do log de producao (2026-07-26) e detectada" {
        # Veto real capturado em run 30189047813
        $razao = "SHORT em BEAR_WEAK com FQS=3/7 SPECULATIVE favorece o trade, mas stop ACIMA entry em setup de baixa liquidez de domingo e armadilha de gama alta."
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
    }
}

Describe "Frases legitimas sobre TIME (sem mencionar weekend) NAO sao forbidden" {

    It "cita sessao (ASIA/US) sem 'weekend' -- nao dispara o guard" {
        $r = Test-PromptForbiddenPhrases -Text "sessao ASIA com volume tipico, setup tecnico solido aprova o trade"
        $r.has_forbidden | Should Be $false
    }

    It "aprova setup em dia de semana sem qualquer mencao de liquidez temporal" {
        $r = Test-PromptForbiddenPhrases -Text "FQS=5/7 QUALITY + beta=0.9 + estrutura forte = APROVAR"
        $r.has_forbidden | Should Be $false
    }
}

Describe "Frases proibidas antigas (DSR) continuam funcionando (regressao)" {
    It "'track record inexistente' ainda e detectada apos adicionar frases de weekend" {
        $r = Test-PromptForbiddenPhrases -Text "DSR n_trades=0 e track record inexistente"
        $r.has_forbidden | Should Be $true
    }
}

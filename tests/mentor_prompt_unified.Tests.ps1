# mentor_prompt_unified.Tests.ps1 -- C.3
# Garante MENTOR_SYSTEM_PROMPT (legado) tem mesmas regras anti-hallucination
# do MENTOR_DEBATE_SYSTEM (atualizado). Single source of truth pra constantes
# em lib_mentor_rules.ps1.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\agents\lib_mentor_rules.ps1"

Describe "Get-MentorAntiHallucinationRules" {

    It "retorna bloco com 4 regras numeradas" {
        $r = Get-MentorAntiHallucinationRules
        $r | Should Match "1\."
        $r | Should Match "2\."
        $r | Should Match "3\."
        $r | Should Match "4\."
    }

    It "menciona FQS explicit" {
        $r = Get-MentorAntiHallucinationRules
        $r | Should Match "FQS"
    }

    It "menciona regra de citar valor exato do contexto" {
        $r = Get-MentorAntiHallucinationRules
        $r | Should Match "NUNCA"
    }
}

Describe "Get-MentorInviolableRules" {

    It "retorna R:R minimo coerente com CLAUDE.md (1:5)" {
        $r = Get-MentorInviolableRules
        $r | Should Match "1:5"
    }

    It "menciona stop antes entrada" {
        $r = Get-MentorInviolableRules
        $r | Should Match "stop"
    }

    It "menciona 1% risco maximo" {
        $r = Get-MentorInviolableRules
        $r | Should Match "1%"
    }
}

# Carrega agent depois pra ter acesso aos prompts
. "$PSScriptRoot\..\agents\mentor_agent.ps1"

Describe "MENTOR_SYSTEM_PROMPT e MENTOR_DEBATE_SYSTEM convergencia C.3" {

    It "ambos contem 'anti-hallucination' rules" {
        $MENTOR_SYSTEM_PROMPT | Should Match "FQS"
        $MENTOR_DEBATE_SYSTEM | Should Match "FQS"
    }

    It "MENTOR_SYSTEM_PROMPT inviolaveis menciona 1:5 (nao 1:3 antigo)" {
        $MENTOR_SYSTEM_PROMPT | Should Match "1:5"
    }
}

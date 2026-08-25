# lib_claude_groq_model_resolve.Tests.ps1 -- TDD
#
# Achado real (2026-08-25): llama-3.3-70b-versatile (hardcoded desde sempre)
# comecou a dar 404 sistematico em TODOS os agentes -- diagnostico de custo
# LLM mostrou $0 em 7 dias consecutivos (nenhuma chamada bem-sucedida). Ja
# aconteceu 2x antes (qwen-qwq-32b, llama-3.1-70b-versatile, ambos "era
# deprecated" no historico do codigo) -- Groq aposenta modelos "versatile"/
# "preview" sem aviso no client. Fix: Resolve-GroqActiveModel escolhe
# dinamicamente a partir de /v1/models em vez de outra troca hardcoded.

. "$PSScriptRoot\..\agents\lib_claude.ps1"

Describe "Resolve-GroqActiveModel -- funcao pura (contrato)" {

    It "modelo pedido esta na lista -- usa ele mesmo (nenhuma mudanca)" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-3.3-70b-versatile", "llama-3.1-8b-instant")
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "modelo pedido NAO esta na lista (caso real 404) -- escolhe outro llama versatile" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-3.5-70b-versatile", "llama-3.1-8b-instant")
        $r | Should Be "llama-3.5-70b-versatile"
    }

    It "nenhum versatile disponivel -- cai pra qualquer llama ativo" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-3.1-8b-instant", "mixtral-8x7b-32768")
        $r | Should Be "llama-3.1-8b-instant"
    }

    It "nenhum llama disponivel -- ultimo recurso, primeiro da lista" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("mixtral-8x7b-32768", "gemma2-9b-it")
        $r | Should Be "mixtral-8x7b-32768"
    }

    It "AvailableModels vazio (consulta /v1/models falhou) -- mantem RequestedModel (fail-safe)" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels @()
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "AvailableModels omitido (default) -- mesmo fail-safe" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile"
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "multiplos versatile disponiveis -- escolhe o de ordem lexicografica mais alta (versao mais recente tende a vir depois)" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-3.1-70b-versatile", "llama-3.5-70b-versatile", "llama-3.3-8b-versatile")
        $r | Should Be "llama-3.5-70b-versatile"
    }

    It "case-insensitive no match de familia llama/versatile" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("Llama-4.0-Versatile")
        $r | Should Be "Llama-4.0-Versatile"
    }

    It "2026-08-25 FIX #2 (bug real em producao): NUNCA escolhe prompt-guard mesmo sendo o unico 'llama' na lista" {
        # Caso real: /v1/models so tinha meta-llama/llama-prompt-guard-2-86m
        # como 'llama' -- filtro antigo escolhia esse (guard-rail, nao chat)
        # e todo agente tomava 400 Bad Request. Sem chat-candidate real,
        # deve cair no fail-safe (manter RequestedModel), NAO no guard model.
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("meta-llama/llama-prompt-guard-2-86m", "distil-whisper-large-v3-en")
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "prompt-guard presente JUNTO com um chat model real -- escolhe o chat model, ignora o guard" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("meta-llama/llama-prompt-guard-2-86m", "llama-3.1-8b-instant")
        $r | Should Be "llama-3.1-8b-instant"
    }

    It "prefere 'instant' sobre 'llama' generico sem qualificador conhecido" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-guard-3-8b", "llama-3.1-8b-instant")
        $r | Should Be "llama-3.1-8b-instant"
    }

    It "exclui tambem whisper/moderation/embed/tts/vision mesmo com nome parecido" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("whisper-large-v3", "llama-moderation-x", "text-embedding-llama", "llama-3.1-8b-instant")
        $r | Should Be "llama-3.1-8b-instant"
    }
}

Describe "Get-GroqAvailableModels -- I/O real (smoke test, fail-soft)" {
    BeforeEach {
        $script:GROQ_MODELS_CACHE = $null
        $script:GROQ_MODELS_CACHE_TS = $null
    }

    It "erro na chamada (key invalida/rede) -- devolve array vazio, nao lanca excecao" {
        { $script:__r = Get-GroqAvailableModels -ApiKey "invalid-key-definitely-wrong" } | Should Not Throw
        @($script:__r).Count | Should Be 0
    }

    It "cache: 2a chamada dentro de 30min nao rebate a API (usa GROQ_MODELS_CACHE)" {
        $script:GROQ_MODELS_CACHE = @("cached-model-1", "cached-model-2")
        $script:GROQ_MODELS_CACHE_TS = Get-Date
        $r = Get-GroqAvailableModels -ApiKey "whatever"
        @($r) | Should Be @("cached-model-1", "cached-model-2")
    }

    It "cache expirado (>30min) -- tenta buscar de novo (nao usa o cache velho cegamente)" {
        $script:GROQ_MODELS_CACHE = @("stale-model")
        $script:GROQ_MODELS_CACHE_TS = (Get-Date).AddMinutes(-31)
        # com key invalida, a nova tentativa falha e devolve vazio -- confirma que NAO
        # retornou o cache stale (que teria @("stale-model"))
        $r = Get-GroqAvailableModels -ApiKey "invalid-key-definitely-wrong"
        @($r).Count | Should Be 0
    }
}

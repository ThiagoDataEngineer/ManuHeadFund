# lib_claude_groq_model_resolve.Tests.ps1 -- TDD
#
# Achado real (2026-08-25): llama-3.3-70b-versatile (hardcoded desde sempre)
# comecou a dar 404 sistematico em TODOS os agentes -- diagnostico de custo
# LLM mostrou $0 em 7 dias consecutivos, e owner confirmou via Anthropic
# Console gasto real de $263 em ~25 dias (limite $270 quase estourado) --
# toda chamada caia direto no Claude pago por falta do fallback Groq.
#
# 3 tentativas ate acertar (todas documentadas no historico de commits):
#   Fix #1: filtro 'llama' no nome -> escolheu prompt-guard (guard-rail)
#   Fix #2: blocklist -> ainda escolheu orpheus (TTS) e allam (chat nicho)
#   Fix #3 (este): lista real inspecionada via diag_groq_models_readonly_
#           2026_08_25.ps1 confirmou que a Groq DESCONTINUOU TOTALMENTE a
#           familia Llama chat -- catalogo atual (13 modelos, 2026-08-25):
#           groq/compound, groq/compound-mini, openai/gpt-oss-120b,
#           openai/gpt-oss-20b, openai/gpt-oss-safeguard-20b (guard-rail),
#           qwen/qwen3.6-27b, allam-2-7b (chat arabe nicho),
#           canopylabs/orpheus-v1-english + orpheus-arabic-saudi (TTS),
#           whisper-large-v3 + whisper-large-v3-turbo (STT),
#           meta-llama/llama-prompt-guard-2-22m + -86m (guard-rail).
#           Abordagem muda de blocklist pra ALLOWLIST de familias conhecidas.

. "$PSScriptRoot\..\agents\lib_claude.ps1"

Describe "Resolve-GroqActiveModel -- funcao pura (contrato)" {

    It "modelo pedido esta na lista -- usa ele mesmo (nenhuma mudanca)" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-3.3-70b-versatile", "llama-3.1-8b-instant")
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "AvailableModels vazio (consulta /v1/models falhou) -- mantem RequestedModel (fail-safe)" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels @()
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "AvailableModels omitido (default) -- mesmo fail-safe" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile"
        $r | Should Be "llama-3.3-70b-versatile"
    }
}

Describe "Resolve-GroqActiveModel -- catalogo REAL da Groq pos-deprecacao Llama (2026-08-25)" {
    # Catalogo exato confirmado via diag_groq_models_readonly_2026_08_25.ps1
    # em producao real -- estes sao os 13 modelos que a Groq de fato retorna
    # hoje. Nenhum "llama...versatile/instant" existe mais.
    $script:realCatalog = @(
        "allam-2-7b"
        "canopylabs/orpheus-arabic-saudi"
        "canopylabs/orpheus-v1-english"
        "groq/compound"
        "groq/compound-mini"
        "meta-llama/llama-prompt-guard-2-22m"
        "meta-llama/llama-prompt-guard-2-86m"
        "openai/gpt-oss-120b"
        "openai/gpt-oss-20b"
        "openai/gpt-oss-safeguard-20b"
        "qwen/qwen3.6-27b"
        "whisper-large-v3"
        "whisper-large-v3-turbo"
    )

    It "modelo pedido (llama-3.3-70b-versatile) nao existe mais -- escolhe openai/gpt-oss-120b (maior contexto, chat generalista)" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels $script:realCatalog
        $r | Should Be "openai/gpt-oss-120b"
    }

    It "NUNCA escolhe openai/gpt-oss-safeguard-20b (guard-rail, apesar do nome parecido com gpt-oss-120b)" {
        # So gpt-oss-20b e gpt-oss-safeguard-20b disponiveis (sem o -120b) --
        # confirma que o match e EXATO (^...$), nao teria confundido
        # safeguard com o padrao gpt-oss-20b por causa de prefixo comum.
        $catalogSemGrande = @("openai/gpt-oss-20b", "openai/gpt-oss-safeguard-20b", "allam-2-7b")
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels $catalogSemGrande
        $r | Should Be "openai/gpt-oss-20b"
    }

    It "sem nenhum gpt-oss/compound/qwen disponivel -- NAO cai no allam/orpheus/whisper/guard, mantem RequestedModel (fail-safe)" {
        $catalogSoNicho = @("allam-2-7b", "canopylabs/orpheus-v1-english", "whisper-large-v3", "meta-llama/llama-prompt-guard-2-86m")
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels $catalogSoNicho
        $r | Should Be "llama-3.3-70b-versatile"
    }

    It "so groq/compound-mini disponivel (sem o -120b/-20b da OpenAI) -- escolhe compound-mini" {
        $catalog = @("groq/compound-mini", "allam-2-7b", "whisper-large-v3")
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels $catalog
        $r | Should Be "groq/compound-mini"
    }

    It "prioriza openai/gpt-oss-120b sobre groq/compound quando ambos disponiveis" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" -AvailableModels $script:realCatalog
        $r | Should Be "openai/gpt-oss-120b"
    }
}

Describe "Resolve-GroqActiveModel -- compatibilidade retroativa (caso a Groq reintroduza Llama chat)" {
    It "se llama-3.3-70b-versatile sumir mas OUTRO llama versatile/instant aparecer, prefere esse antes de gpt-oss" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("llama-4.0-70b-versatile", "openai/gpt-oss-120b")
        $r | Should Be "llama-4.0-70b-versatile"
    }

    It "llama-4 (nova geracao, prefixo meta-llama/) tambem e reconhecido" {
        $r = Resolve-GroqActiveModel -RequestedModel "llama-3.3-70b-versatile" `
            -AvailableModels @("meta-llama/llama-4-70b-versatile", "openai/gpt-oss-120b")
        $r | Should Be "meta-llama/llama-4-70b-versatile"
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

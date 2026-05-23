# lib_claude_cascade.Tests.ps1
# TDD strict para Invoke-MesaDroneCascade / Invoke-MentorCascade / Invoke-TriagemCascade.
# UTF-8 BOM. Pester 3.x. PS 5.1.

. "$PSScriptRoot\..\agents\lib_claude.ps1"

Describe "Cascade routing - Mesa Groq->Gemini->Haiku (v2 2026-05-16)" {
    # v2: Groq primary (30 RPM, suporta Mesa parallel 3 drones). Gemini fallback.
    BeforeEach {
        $env:GEMINI_API_KEY     = "test-gemini"
        $env:GROQ_API_KEY       = "test-groq"
        $env:ANTHROPIC_API_KEY  = "test-claude"
    }

    It "Groq primary funcionando: usa Groq" {
        Mock Invoke-Gemini { return "from-gemini" } -ModuleName $null
        Mock Invoke-Groq   { return "from-groq" }   -ModuleName $null
        Mock Invoke-Claude { return "from-claude" } -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be "from-groq"
        Assert-MockCalled Invoke-Groq -Times 1
        Assert-MockCalled Invoke-Gemini -Times 0
    }

    It "Groq falha: fallback Gemini" {
        Mock Invoke-Gemini { return "from-gemini" } -ModuleName $null
        Mock Invoke-Groq   { throw "groq 429" }     -ModuleName $null
        Mock Invoke-Claude { return "from-claude" } -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be "from-gemini"
    }

    It "Groq E Gemini falham: fallback Haiku" {
        Mock Invoke-Gemini { throw "g500" } -ModuleName $null
        Mock Invoke-Groq   { throw "429" }  -ModuleName $null
        Mock Invoke-Claude { return "from-claude" } -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be "from-claude"
        Assert-MockCalled Invoke-Claude -Times 1
    }

    It "Tudo falha: retorna null" {
        Mock Invoke-Gemini { throw "x" } -ModuleName $null
        Mock Invoke-Groq   { throw "x" } -ModuleName $null
        Mock Invoke-Claude { throw "x" } -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be $null
    }
}

Describe "Cascade routing - Mentor Anthropic->Groq->Gemini" {
    BeforeEach {
        $env:GEMINI_API_KEY     = "test-gemini"
        $env:GROQ_API_KEY       = "test-groq"
        $env:ANTHROPIC_API_KEY  = "test-claude"
    }

    It "Anthropic primary funcionando" {
        Mock Invoke-Claude { return "from-claude" } -ModuleName $null
        Mock Invoke-Groq   { return "from-groq" }   -ModuleName $null
        Mock Invoke-Gemini { return "from-gemini" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-claude"
        Assert-MockCalled Invoke-Claude -Times 1
        Assert-MockCalled Invoke-Groq -Times 0
    }

    It "Anthropic falha: fallback Groq" {
        Mock Invoke-Claude { throw "503" } -ModuleName $null
        Mock Invoke-Groq   { return "from-groq" } -ModuleName $null
        Mock Invoke-Gemini { return "from-gemini" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-groq"
    }

    It "Anthropic E Groq falham: fallback Gemini" {
        Mock Invoke-Claude { throw "503" } -ModuleName $null
        Mock Invoke-Groq   { throw "429" } -ModuleName $null
        Mock Invoke-Gemini { return "from-gemini" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-gemini"
    }

    # 2026-05-20 PM cobertura completa: Mentor agora tem 4o fallback Haiku
    # (Anthropic Sonnet 503 + Groq 429 + Gemini fail era VETO safety; agora Haiku salva)
    It "Anthropic Sonnet + Groq + Gemini falham: fallback Haiku (model claude-haiku-4-5)" {
        $script:lastModelClaude = $null
        Mock Invoke-Claude {
            param($Model)
            $script:lastModelClaude = $Model
            if ($Model -like "*haiku*") { return "from-haiku" }
            throw "503"
        } -ModuleName $null
        Mock Invoke-Groq   { throw "429" } -ModuleName $null
        Mock Invoke-Gemini { throw "x" }   -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-haiku"
        ($script:lastModelClaude -like "*haiku*") | Should Be $true
    }

    It "Mentor tudo falha (incluindo Haiku): retorna null (VETO fail-safe upstream)" {
        Mock Invoke-Claude { throw "anthropic down" } -ModuleName $null
        Mock Invoke-Groq   { throw "x" } -ModuleName $null
        Mock Invoke-Gemini { throw "x" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be $null
    }

    # 2026-05-20 PM: Provider trace -- saber qual LLM respondeu cada decisao.
    It "Provider trace: Anthropic OK -> LAST_CASCADE_PROVIDER=anthropic_sonnet" {
        Mock Invoke-Claude { return "from-claude" } -ModuleName $null
        $script:LAST_CASCADE_PROVIDER = $null
        $null = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $script:LAST_CASCADE_PROVIDER | Should Be "anthropic_sonnet"
    }

    It "Provider trace: Sonnet fail + Groq OK -> groq_llama70b" {
        Mock Invoke-Claude {
            param($Model)
            # 1a call = Sonnet (qualquer model exceto Haiku) -> falha
            # 2a call seria Haiku, mas nao deve chegar la se Groq passa
            if ($Model -notlike "*haiku*") { throw "503" }
            return "from-haiku"
        } -ModuleName $null
        Mock Invoke-Groq   { return "from-groq" } -ModuleName $null
        $script:LAST_CASCADE_PROVIDER = $null
        $null = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u" -AnthropicModel "claude-sonnet-4-6"
        $script:LAST_CASCADE_PROVIDER | Should Be "groq_llama70b"
    }

    It "Provider trace: ate Haiku -> anthropic_haiku" {
        Mock Invoke-Claude {
            param($Model)
            if ($Model -like "*haiku*") { return "from-haiku" }
            throw "503"
        } -ModuleName $null
        Mock Invoke-Groq   { throw "429" } -ModuleName $null
        Mock Invoke-Gemini { throw "x" }   -ModuleName $null
        $script:LAST_CASCADE_PROVIDER = $null
        $null = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $script:LAST_CASCADE_PROVIDER | Should Be "anthropic_haiku"
    }
}

Describe "Cascade routing - Triagem Gemini->Groq (no Anthropic)" {
    BeforeEach {
        $env:GEMINI_API_KEY = "test-gemini"
        $env:GROQ_API_KEY   = "test-groq"
    }

    It "Gemini primary" {
        Mock Invoke-Gemini { return "from-gemini" } -ModuleName $null
        Mock Invoke-Groq   { return "from-groq" }   -ModuleName $null
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-gemini"
    }

    It "Gemini falha: fallback Groq" {
        Mock Invoke-Gemini { throw "x" } -ModuleName $null
        Mock Invoke-Groq   { return "from-groq" } -ModuleName $null
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-groq"
    }

    # 2026-05-20 PM mudanca de policy: Triagem AGORA usa Haiku como 3o fallback
    # (cobertura completa, custo baixo). Antes era cost-conscious sem Anthropic.
    It "Gemini E Groq falham: fallback Haiku (cobertura completa 2026-05-20)" {
        $script:lastModelClaude = $null
        Mock Invoke-Gemini { throw "x" } -ModuleName $null
        Mock Invoke-Groq   { throw "x" } -ModuleName $null
        Mock Invoke-Claude {
            param($Model)
            $script:lastModelClaude = $Model
            return "from-haiku"
        } -ModuleName $null
        $env:ANTHROPIC_API_KEY = "test-claude"
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-haiku"
        ($script:lastModelClaude -like "*haiku*") | Should Be $true
    }

    It "Triagem usa SOMENTE Haiku do Anthropic (nao Sonnet, cost-conscious)" {
        Mock Invoke-Gemini { throw "x" } -ModuleName $null
        Mock Invoke-Groq   { throw "x" } -ModuleName $null
        $script:claudeModel = $null
        Mock Invoke-Claude {
            param($Model)
            $script:claudeModel = $Model
            return "ok"
        } -ModuleName $null
        $env:ANTHROPIC_API_KEY = "test-claude"
        $null = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        ($script:claudeModel -notlike "*sonnet*") | Should Be $true
        ($script:claudeModel -like "*haiku*") | Should Be $true
    }

    It "Tudo falha (incluindo Haiku): retorna null" {
        Mock Invoke-Gemini { throw "x" } -ModuleName $null
        Mock Invoke-Groq   { throw "x" } -ModuleName $null
        Mock Invoke-Claude { throw "x" } -ModuleName $null
        $env:ANTHROPIC_API_KEY = "test-claude"
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be $null
    }
}

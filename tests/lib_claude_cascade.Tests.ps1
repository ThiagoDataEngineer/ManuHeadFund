# lib_claude_cascade.Tests.ps1
# TDD strict para Invoke-MesaDroneCascade / Invoke-MentorCascade / Invoke-TriagemCascade.
# Atualizado 2026-06-04: Gemini substituido por Mistral como fallback 2 (2026-05-29).
# UTF-8 BOM. Pester 3.x. PS 5.1.

. "$PSScriptRoot\..\agents\lib_claude.ps1"

Describe "Cascade routing - Mesa Groq->Mistral->Haiku (v3 2026-05-29)" {
    BeforeEach {
        $env:MISTRAL_API_KEY   = "test-mistral"
        $env:GROQ_API_KEY      = "test-groq"
        $env:ANTHROPIC_API_KEY = "test-claude"
    }

    It "Groq primary funcionando: usa Groq" {
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        Mock Invoke-Groq    { return "from-groq" }    -ModuleName $null
        Mock Invoke-Claude  { return "from-claude" }  -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be "from-groq"
        Assert-MockCalled Invoke-Groq -Times 1
        Assert-MockCalled Invoke-Mistral -Times 0
    }

    It "Groq falha: fallback Mistral" {
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        Mock Invoke-Groq    { throw "groq 429" }      -ModuleName $null
        Mock Invoke-Claude  { return "from-claude" }  -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be "from-mistral"
    }

    It "Groq E Mistral falham: fallback Haiku" {
        Mock Invoke-Mistral { throw "m500" }          -ModuleName $null
        Mock Invoke-Groq    { throw "429" }           -ModuleName $null
        Mock Invoke-Claude  { return "from-claude" }  -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be "from-claude"
        Assert-MockCalled Invoke-Claude -Times 1
    }

    It "Tudo falha: retorna null" {
        Mock Invoke-Mistral { throw "x" } -ModuleName $null
        Mock Invoke-Groq    { throw "x" } -ModuleName $null
        Mock Invoke-Claude  { throw "x" } -ModuleName $null
        $r = Invoke-MesaDroneCascade -SystemPrompt "s" -UserContent "u" -Agent "mesa_t"
        $r | Should Be $null
    }
}

Describe "Cascade routing - Mentor Anthropic->Groq->Mistral" {
    BeforeEach {
        $env:MISTRAL_API_KEY   = "test-mistral"
        $env:GROQ_API_KEY      = "test-groq"
        $env:ANTHROPIC_API_KEY = "test-claude"
    }

    It "Anthropic primary funcionando" {
        Mock Invoke-Claude  { return "from-claude" }  -ModuleName $null
        Mock Invoke-Groq    { return "from-groq" }    -ModuleName $null
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-claude"
        Assert-MockCalled Invoke-Claude -Times 1
        Assert-MockCalled Invoke-Groq -Times 0
    }

    It "Anthropic falha: fallback Groq" {
        Mock Invoke-Claude  { throw "503" }           -ModuleName $null
        Mock Invoke-Groq    { return "from-groq" }    -ModuleName $null
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-groq"
    }

    It "Anthropic E Groq falham: fallback Mistral" {
        Mock Invoke-Claude  { throw "503" }           -ModuleName $null
        Mock Invoke-Groq    { throw "429" }           -ModuleName $null
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-mistral"
    }

    It "Anthropic Sonnet + Groq + Mistral falham: fallback Haiku (model claude-haiku-4)" {
        $script:lastModelClaude = $null
        Mock Invoke-Claude {
            param($Model)
            $script:lastModelClaude = $Model
            if ($Model -like "*haiku*") { return "from-haiku" }
            throw "503"
        } -ModuleName $null
        Mock Invoke-Groq    { throw "429" } -ModuleName $null
        Mock Invoke-Mistral { throw "x" }   -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-haiku"
        ($script:lastModelClaude -like "*haiku*") | Should Be $true
    }

    It "Mentor tudo falha (incluindo Haiku): retorna null (VETO fail-safe upstream)" {
        Mock Invoke-Claude  { throw "anthropic down" } -ModuleName $null
        Mock Invoke-Groq    { throw "x" }              -ModuleName $null
        Mock Invoke-Mistral { throw "x" }              -ModuleName $null
        $r = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be $null
    }

    It "Provider trace: Anthropic OK -> LAST_CASCADE_PROVIDER=anthropic_sonnet" {
        Mock Invoke-Claude { return "from-claude" } -ModuleName $null
        $script:LAST_CASCADE_PROVIDER = $null
        $null = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $script:LAST_CASCADE_PROVIDER | Should Be "anthropic_sonnet"
    }

    It "Provider trace: Sonnet fail + Groq OK -> groq_llama70b" {
        Mock Invoke-Claude {
            param($Model)
            if ($Model -notlike "*haiku*") { throw "503" }
            return "from-haiku"
        } -ModuleName $null
        Mock Invoke-Groq { return "from-groq" } -ModuleName $null
        $script:LAST_CASCADE_PROVIDER = $null
        $null = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u" -AnthropicModel "claude-sonnet-4"
        $script:LAST_CASCADE_PROVIDER | Should Be "groq_llama70b"
    }

    It "Provider trace: ate Haiku -> anthropic_haiku" {
        Mock Invoke-Claude {
            param($Model)
            if ($Model -like "*haiku*") { return "from-haiku" }
            throw "503"
        } -ModuleName $null
        Mock Invoke-Groq    { throw "429" } -ModuleName $null
        Mock Invoke-Mistral { throw "x" }   -ModuleName $null
        $script:LAST_CASCADE_PROVIDER = $null
        $null = Invoke-MentorCascade -SystemPrompt "s" -UserContent "u"
        $script:LAST_CASCADE_PROVIDER | Should Be "anthropic_haiku"
    }
}

Describe "Cascade routing - Triagem Groq->Mistral->Haiku (v3 2026-05-29)" {
    BeforeEach {
        $env:MISTRAL_API_KEY = "test-mistral"
        $env:GROQ_API_KEY    = "test-groq"
    }

    It "Groq primary" {
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        Mock Invoke-Groq    { return "from-groq" }    -ModuleName $null
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-groq"
    }

    It "Groq falha: fallback Mistral" {
        Mock Invoke-Mistral { return "from-mistral" } -ModuleName $null
        Mock Invoke-Groq    { throw "x" }             -ModuleName $null
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be "from-mistral"
    }

    It "Groq E Mistral falham: fallback Haiku (cobertura completa)" {
        $script:lastModelClaude = $null
        Mock Invoke-Mistral { throw "x" } -ModuleName $null
        Mock Invoke-Groq    { throw "x" } -ModuleName $null
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
        Mock Invoke-Mistral { throw "x" } -ModuleName $null
        Mock Invoke-Groq    { throw "x" } -ModuleName $null
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
        Mock Invoke-Mistral { throw "x" } -ModuleName $null
        Mock Invoke-Groq    { throw "x" } -ModuleName $null
        Mock Invoke-Claude  { throw "x" } -ModuleName $null
        $env:ANTHROPIC_API_KEY = "test-claude"
        $r = Invoke-TriagemCascade -SystemPrompt "s" -UserContent "u"
        $r | Should Be $null
    }
}

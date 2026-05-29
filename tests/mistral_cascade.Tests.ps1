# mistral_cascade.Tests.ps1 -- TDD 2026-05-29
#
# Problema: Gemini 2.5 Flash free tier tem apenas 250 RPD (requests/dia).
# Com ciclos a cada 30min e 10 candidatos x 3 drones Mesa = ~30 calls/ciclo,
# a cota diaria esgota em 4-5 ciclos (2-3h). Resultado: 429 persistente.
#
# Solucao: substituir Gemini por Mistral como fallback 2 em todos os cascades.
# Mistral free tier: 1 req/s, ~1B tokens/mes (praticamente ilimitado para nos).
# Modelo: mistral-small-3.1 (OpenAI-compatible API, sem cartao de credito).
#
# NOTA: gemini-2.0-flash seria alternativa mais simples (1.500 RPD vs 250 RPD),
# mas Mistral e superior: sem limite diario fixo, API OpenAI-compatible, qualidade
# comparavel ao llama-3.3-70b para JSON estruturado.
#
# Cascades afetados:
#   Invoke-MesaDroneCascade  : Groq -> [Gemini] -> Haiku
#   Invoke-MentorCascade     : Sonnet -> Groq -> [Gemini] -> Haiku
#   Invoke-TriagemCascade    : Groq -> [Gemini] -> Haiku
#   Invoke-TechCascadeJson   : Groq -> [Gemini] -> Haiku
#   warmup_llm_endpoints.ps1 : testa [Gemini] -> agora testa Mistral
#
# Pester 3.x. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

# ── Suite 1: Invoke-Mistral existe e tem assinatura correta ───────────────────
Describe "Invoke-Mistral: funcao existe em lib_claude.ps1" {

    It "lib_claude.ps1 contem funcao Invoke-Mistral" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        $content | Should Match "function Invoke-Mistral"
    }

    It "Invoke-Mistral usa endpoint api.mistral.ai" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        $content | Should Match "api\.mistral\.ai"
    }

    It "Invoke-Mistral usa MISTRAL_API_KEY do ambiente" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        $content | Should Match "MISTRAL_API_KEY"
    }

    It "Invoke-Mistral usa modelo mistral-small por default" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        $content | Should Match "mistral-small"
    }

    It "Invoke-Mistral tem parametros SystemPrompt UserContent MaxTokens Temperature Agent" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        $content | Should Match "\[string\]\`$SystemPrompt"
        $content | Should Match "\[string\]\`$UserContent"
        $content | Should Match "\[int\]\s+\`$MaxTokens"
        $content | Should Match "\[double\]\`$Temperature"
        $content | Should Match "\[string\]\`$Agent"
    }

    It "Invoke-Mistral usa API OpenAI-compatible (chat/completions)" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        $content | Should Match "chat/completions"
    }

    It "Invoke-Mistral tem TimeoutSec definido" {
        $content = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
        # Extrai bloco da funcao Invoke-Mistral
        $idx = $content.IndexOf("function Invoke-Mistral")
        $block = $content.Substring($idx, [Math]::Min(2000, $content.Length - $idx))
        $block | Should Match "TimeoutSec"
    }
}

# ── Suite 2: Cascades substituem Gemini por Mistral ───────────────────────────
Describe "Cascades: Gemini substituido por Mistral" {

    BeforeAll {
        $script:libContent = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
    }

    It "Invoke-MesaDroneCascade chama Invoke-Mistral como fallback 2" {
        # Extrai bloco da funcao -- usa 5000 chars pois a funcao tem bloco de cache antes
        $idx = $script:libContent.IndexOf("function Invoke-MesaDroneCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(5000, $script:libContent.Length - $idx))
        $block | Should Match "Invoke-Mistral"
    }

    It "Invoke-MentorCascade chama Invoke-Mistral como fallback 3" {
        $idx = $script:libContent.IndexOf("function Invoke-MentorCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(3000, $script:libContent.Length - $idx))
        $block | Should Match "Invoke-Mistral"
    }

    It "Invoke-TriagemCascade chama Invoke-Mistral como fallback 2" {
        $idx = $script:libContent.IndexOf("function Invoke-TriagemCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(2000, $script:libContent.Length - $idx))
        $block | Should Match "Invoke-Mistral"
    }

    It "Invoke-TechCascadeJson chama Invoke-Mistral como fallback 2" {
        $idx = $script:libContent.IndexOf("function Invoke-TechCascadeJson")
        $block = $script:libContent.Substring($idx, [Math]::Min(3000, $script:libContent.Length - $idx))
        $block | Should Match "Invoke-Mistral"
    }

    It "Invoke-MesaDroneCascade log menciona Mistral no fallback" {
        $idx = $script:libContent.IndexOf("function Invoke-MesaDroneCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(3000, $script:libContent.Length - $idx))
        $block | Should Match "Mistral"
    }

    It "Invoke-MentorCascade log menciona Mistral no fallback" {
        $idx = $script:libContent.IndexOf("function Invoke-MentorCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(3000, $script:libContent.Length - $idx))
        $block | Should Match "Mistral"
    }
}

# ── Suite 3: Gemini mantido mas comentado / rebaixado ─────────────────────────
Describe "Gemini: mantido comentado como referencia" {

    BeforeAll {
        $script:libContent = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
    }

    It "lib_claude.ps1 ainda contem funcao Invoke-Gemini (nao removida)" {
        $script:libContent | Should Match "function Invoke-Gemini"
    }

    It "lib_claude.ps1 contem comentario sobre gemini-2.0-flash como alternativa" {
        # Nota sobre gemini-2.0-flash (1500 RPD) deve estar comentada
        $script:libContent | Should Match "gemini-2\.0-flash"
    }

    It "Invoke-MesaDroneCascade NAO chama Invoke-Gemini diretamente (substituido por Mistral)" {
        $idx = $script:libContent.IndexOf("function Invoke-MesaDroneCascade")
        $nextFunc = $script:libContent.IndexOf("`nfunction ", $idx + 10)
        $block = if ($nextFunc -gt 0) { $script:libContent.Substring($idx, $nextFunc - $idx) } else { $script:libContent.Substring($idx) }
        # Gemini pode aparecer no bloco de provider state cache (leitura do cache)
        # mas NAO deve aparecer como chamada de fallback ativa
        $activeGeminiCall = [regex]::Matches($block, "Invoke-Gemini\s+-SystemPrompt")
        $activeGeminiCall.Count | Should Be 0
    }
}

# ── Suite 4: warmup_llm_endpoints.ps1 testa Mistral ──────────────────────────
Describe "warmup: testa Mistral em vez de Gemini" {

    BeforeAll {
        $script:warmupContent = Get-Content (Join-Path $root "scripts\warmup_llm_endpoints.ps1") -Raw
    }

    It "warmup menciona Mistral" {
        $script:warmupContent | Should Match "Mistral"
    }

    It "warmup chama Invoke-Mistral" {
        $script:warmupContent | Should Match "Invoke-Mistral"
    }

    It "warmup registra estado do provider mistral" {
        $script:warmupContent | Should Match "Set-ProviderState.*mistral|mistral.*Set-ProviderState"
    }

    It "warmup tem logica de skip Mistral se RATE_LIMITED" {
        $script:warmupContent | Should Match "mistral.*RATE_LIMITED|RATE_LIMITED.*mistral"
    }
}

# ── Suite 5: config.local.ps1 tem MISTRAL_API_KEY ────────────────────────────
Describe "config.local.ps1: MISTRAL_API_KEY configurada" {

    It "config.local.ps1 contem MISTRAL_API_KEY" {
        $configPath = Join-Path $root "agents\config.local.ps1"
        if (-not (Test-Path $configPath)) {
            Write-Host "  config.local.ps1 nao encontrado -- skip" -ForegroundColor Yellow
            $true | Should Be $true
            return
        }
        $content = Get-Content $configPath -Raw
        $content | Should Match "MISTRAL_API_KEY"
    }
}

# ── Suite 6: provider state cache suporta mistral ────────────────────────────
Describe "provider state cache: suporta provider mistral" {

    BeforeAll {
        $script:libContent = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
    }

    It "Invoke-MesaDroneCascade verifica cache para mistral alem de gemini" {
        $idx = $script:libContent.IndexOf("function Invoke-MesaDroneCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(3500, $script:libContent.Length - $idx))
        # Deve ter logica de skip para mistral OU o cache foi generalizado
        $hasMistralCache = ($block -match "mistral.*RATE_LIMITED|RATE_LIMITED.*mistral|mistralBlocked")
        $hasGeneralCache = ($block -match "providerBlocked|Get-ProviderBlockedState")
        ($hasMistralCache -or $hasGeneralCache) | Should Be $true
    }

    It "warmup_llm_endpoints.ps1 registra estado OK ou RATE_LIMITED para mistral" {
        $warmupContent = Get-Content (Join-Path $root "scripts\warmup_llm_endpoints.ps1") -Raw
        $warmupContent | Should Match "Set-ProviderState"
        $warmupContent | Should Match "mistral"
    }
}

# ── Suite 7: ordem do cascade esta correta ────────────────────────────────────
Describe "ordem do cascade: Groq -> Mistral -> Haiku" {

    BeforeAll {
        $script:libContent = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw
    }

    It "Invoke-MesaDroneCascade: Groq aparece antes de Mistral no codigo" {
        $idx = $script:libContent.IndexOf("function Invoke-MesaDroneCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(5000, $script:libContent.Length - $idx))
        # Localiza os comentarios de fallback que definem a ordem
        $pos1Groq    = $block.IndexOf("# 1. Groq dual-key")
        $pos2Mistral = $block.IndexOf("# 2. Mistral")
        $pos3Haiku   = $block.IndexOf("# 3. Claude Haiku")
        $pos1Groq    | Should Not Be -1
        $pos2Mistral | Should Not Be -1
        $pos3Haiku   | Should Not Be -1
        ($pos1Groq -lt $pos2Mistral) | Should Be $true
        ($pos2Mistral -lt $pos3Haiku) | Should Be $true
    }

    It "Invoke-TriagemCascade: Groq aparece antes de Mistral no codigo" {
        $idx = $script:libContent.IndexOf("function Invoke-TriagemCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(2000, $script:libContent.Length - $idx))
        $posGroq    = $block.IndexOf("Invoke-Groq")
        $posMistral = $block.IndexOf("Invoke-Mistral")
        ($posGroq -lt $posMistral) | Should Be $true
    }

    It "Invoke-MentorCascade: Sonnet -> Groq -> Mistral -> Haiku" {
        $idx = $script:libContent.IndexOf("function Invoke-MentorCascade")
        $block = $script:libContent.Substring($idx, [Math]::Min(3000, $script:libContent.Length - $idx))
        $posSonnet  = $block.IndexOf("claude-sonnet")
        $posGroq    = $block.IndexOf("Invoke-Groq")
        $posMistral = $block.IndexOf("Invoke-Mistral")
        $posHaiku   = $block.IndexOf("claude-haiku")
        ($posSonnet  -lt $posGroq)    | Should Be $true
        ($posGroq    -lt $posMistral) | Should Be $true
        ($posMistral -lt $posHaiku)   | Should Be $true
    }
}

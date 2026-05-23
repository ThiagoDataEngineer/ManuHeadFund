# test_llm_cascade.ps1 - Teste do Cascade de LLMs
$ErrorActionPreference = "Stop"

Write-Host "`n=== TESTE LLM CASCADE ===" -ForegroundColor Cyan

# Carregar dependencias
. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_claude.ps1"

Write-Host "`n[1/4] Verificando API Keys..." -ForegroundColor Yellow
$apis = @()
if ($env:ANTHROPIC_API_KEY) { 
    Write-Host "  [x] ANTHROPIC_API_KEY: $($env:ANTHROPIC_API_KEY.Length) chars" -ForegroundColor Green
    $apis += "Anthropic"
} else { 
    Write-Host "  [ ] ANTHROPIC_API_KEY: NAO configurado" -ForegroundColor Red
}

if ($env:GROQ_API_KEY) { 
    Write-Host "  [x] GROQ_API_KEY: $($env:GROQ_API_KEY.Length) chars" -ForegroundColor Green
    $apis += "Groq"
} else { 
    Write-Host "  [ ] GROQ_API_KEY: NAO configurado" -ForegroundColor Red
}

if ($env:GEMINI_API_KEY) { 
    Write-Host "  [x] GEMINI_API_KEY: $($env:GEMINI_API_KEY.Length) chars" -ForegroundColor Green
    $apis += "Gemini"
} else { 
    Write-Host "  [ ] GEMINI_API_KEY: NAO configurado" -ForegroundColor Red
}

Write-Host "`nAPIs configuradas: $($apis -join ', ')" -ForegroundColor Cyan

# Teste simples
$systemPrompt = "Voce e um assistente que responde em JSON."
$userContent = 'Responda em JSON: {"status": "ok", "message": "teste"}'

Write-Host "`n[2/4] Testando Invoke-MentorCascade..." -ForegroundColor Yellow
try {
    $result = Invoke-MentorCascade -SystemPrompt $systemPrompt -UserContent $userContent -MaxTokens 100 -Temperature 0.3 -Agent "test"
    
    if ($result) {
        Write-Host "  SUCESSO: Cascade retornou resposta" -ForegroundColor Green
        Write-Host "  Provider usado: $script:LAST_CASCADE_PROVIDER" -ForegroundColor Cyan
        Write-Host "  Resposta (primeiros 200 chars): $($result.Substring(0, [Math]::Min(200, $result.Length)))" -ForegroundColor Gray
    } else {
        Write-Host "  FALHA: Cascade retornou null" -ForegroundColor Red
    }
} catch {
    Write-Host "  ERRO: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

Write-Host "`n[3/4] Testando cada provider individualmente..." -ForegroundColor Yellow

# Teste Anthropic
if ($env:ANTHROPIC_API_KEY) {
    Write-Host "`n  [3.1] Testando Anthropic Sonnet..." -ForegroundColor Cyan
    try {
        $r = Invoke-Claude -SystemPrompt $systemPrompt -UserContent $userContent -Model "claude-sonnet-4" -MaxTokens 100 -Temperature 0.3 -Agent "test"
        if ($r) {
            Write-Host "    SUCESSO: Anthropic funcionou" -ForegroundColor Green
        } else {
            Write-Host "    FALHA: Anthropic retornou null" -ForegroundColor Red
        }
    } catch {
        Write-Host "    ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Teste Groq
if ($env:GROQ_API_KEY) {
    Write-Host "`n  [3.2] Testando Groq Llama 70B..." -ForegroundColor Cyan
    try {
        $r = Invoke-Groq -SystemPrompt $systemPrompt -UserContent $userContent -Model "llama-3.3-70b-versatile" -MaxTokens 100 -Temperature 0.3 -Agent "test"
        if ($r) {
            Write-Host "    SUCESSO: Groq funcionou" -ForegroundColor Green
        } else {
            Write-Host "    FALHA: Groq retornou null" -ForegroundColor Red
        }
    } catch {
        Write-Host "    ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Teste Gemini
if ($env:GEMINI_API_KEY) {
    Write-Host "`n  [3.3] Testando Gemini 2.0 Flash..." -ForegroundColor Cyan
    try {
        $r = Invoke-Gemini -SystemPrompt $systemPrompt -UserContent $userContent -Model "gemini-2.0-flash" -MaxTokens 100 -Temperature 0.3 -Agent "test"
        if ($r) {
            Write-Host "    SUCESSO: Gemini funcionou" -ForegroundColor Green
        } else {
            Write-Host "    FALHA: Gemini retornou null" -ForegroundColor Red
        }
    } catch {
        Write-Host "    ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n[4/4] Resumo" -ForegroundColor Yellow
Write-Host "`n=== RESULTADO ===" -ForegroundColor Cyan
Write-Host "APIs configuradas: $($apis.Count)/3" -ForegroundColor White
Write-Host "Cascade funcionou: $(if($result){'SIM'}else{'NAO'})" -ForegroundColor $(if($result){"Green"}else{"Red"})
Write-Host ""

# lib_claude.ps1 — Claude API caller
# Dot-source: . (Join-Path $PSScriptRoot "lib_claude.ps1")
# Requer: $ANTHROPIC_API_KEY no ambiente ou config.ps1

function Invoke-Claude {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model        = $CLAUDE_MODEL,
        [int]   $MaxTokens    = $CLAUDE_MAX_TOKENS,
        [double]$Temperature  = $CLAUDE_TEMP_TRADE,
        [string]$Agent        = "unknown"  # tag para cost tracker
    )

    # 2026-05-16: trocado de $ANTHROPIC_API_KEY (script-scope) para $env: (process-scope).
    # Bug: inside Start-Job runspace (Mesa drones), script vars não sobrevivem ao fork,
    # mas env vars sim. Era inconsistente com $env:GROQ_API_KEY/$env:GEMINI_API_KEY.
    $apiKey = if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY } else { $ANTHROPIC_API_KEY }
    if (-not $apiKey) { throw "ANTHROPIC_API_KEY nao configurada. Ver agents/config.ps1" }

    $body = @{
        model       = $Model
        max_tokens  = $MaxTokens
        temperature = $Temperature
        system      = $SystemPrompt
        messages    = @(
            @{ role = "user"; content = $UserContent }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    $start = Get-Date
    try {
        # Invoke-WebRequest + decode manual = UTF-8 correto no PS5.1
        # Invoke-RestMethod nao respeita charset quando Content-Type nao declara explicitamente
        # 2026-05-21 FASE 2: TimeoutSec 20s -> 35s. Cold-start Haiku no primeiro cycle
        # da manha causava 3/3 LIDAR null (HYPE/USELESS/ZEC 08:32-08:34 BRT).
        # Pos-warm endpoint responde <15s, mas cold pode levar 20-30s. 35s = folga real.
        # Mentor (Sonnet) tambem se beneficia em prompts longos com FullContext.
        $wr = Invoke-WebRequest `
            -Uri "https://api.anthropic.com/v1/messages" `
            -Method POST `
            -Headers @{
                "x-api-key"         = $apiKey
                "anthropic-version" = "2023-06-01"
                "content-type"      = "application/json"
            } `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -UseBasicParsing `
            -TimeoutSec 35 `
            -ErrorAction Stop

        $latencyMs = ((Get-Date) - $start).TotalMilliseconds
        $json     = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
        $response = $json | ConvertFrom-Json

        # Tracking de custo (best-effort — nunca quebra a chamada)
        try {
            if (Get-Command -Name "Track-ClaudeUsage" -ErrorAction SilentlyContinue) {
                $inTok  = [int]$response.usage.input_tokens
                $outTok = [int]$response.usage.output_tokens
                Track-ClaudeUsage -Model $Model -InputTokens $inTok -OutputTokens $outTok -Agent $Agent -LatencyMs $latencyMs | Out-Null
            }
        } catch {}

        return $response.content[0].text
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $msg = $_.Exception.Message
        throw "Claude API error ($statusCode): $msg"
    }
}

# -----------------------------------------------------------------------------
# Invoke-Groq — wrapper Groq (OpenAI-compatible API)
# Free tier: 14.400 req/dia. Llama 3.3 70B versatile.
# Tracking: registrado com cost = $0 (free tier)
# -----------------------------------------------------------------------------
function Invoke-Groq {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "llama-3.3-70b-versatile",
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [string]$Agent       = "unknown"
    )

    if (-not $env:GROQ_API_KEY) { throw "GROQ_API_KEY nao configurada" }

    $body = @{
        model       = $Model
        max_tokens  = $MaxTokens
        temperature = $Temperature
        messages    = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user";   content = $UserContent }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    $start = Get-Date
    try {
        # B28c fix 2026-05-21: TimeoutSec 10s (era default 100s+).
        # Diagnostico mesa_drones.jsonl pos-restart mostrou 5/6 drones com
        # "job_state_Running_likely_timeout" -- Groq 429 estava hanging em vez de
        # falhar rapido pra cascade Gemini/Haiku assumir. Fail-fast = cascade vivo.
        $wr = Invoke-WebRequest `
            -Uri "https://api.groq.com/openai/v1/chat/completions" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $env:GROQ_API_KEY"
                "Content-Type"  = "application/json"
            } `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -UseBasicParsing `
            -TimeoutSec 10 `
            -ErrorAction Stop

        $latencyMs = ((Get-Date) - $start).TotalMilliseconds
        $json     = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
        $response = $json | ConvertFrom-Json

        # Tracking ($0 — Groq free tier; ainda logamos tokens para auditoria)
        try {
            if (Get-Command -Name "Track-ClaudeUsage" -ErrorAction SilentlyContinue) {
                $inTok  = [int]$response.usage.prompt_tokens
                $outTok = [int]$response.usage.completion_tokens
                # Modelo prefixado com "groq:" para diferenciar no relatorio
                Track-ClaudeUsage -Model "groq:$Model" -InputTokens $inTok -OutputTokens $outTok -Agent $Agent -LatencyMs $latencyMs | Out-Null
            }
        } catch {}

        return $response.choices[0].message.content
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $msg = $_.Exception.Message
        throw "Groq API error ($statusCode): $msg"
    }
}

# Wrapper Groq que forca JSON com retry
function Invoke-GroqJson {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "llama-3.3-70b-versatile",
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [int]   $MaxRetries  = 2,
        [string]$Agent       = "unknown"
    )
    $sysWithJson = $SystemPrompt + "`n`nIMPORTANTE: Responda APENAS com JSON valido, sem markdown, sem texto antes ou depois."

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $raw = Invoke-Groq -SystemPrompt $sysWithJson -UserContent $UserContent `
                -Model $Model -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            $cleaned = $raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
            return $cleaned | ConvertFrom-Json
        } catch {
            if ($attempt -eq $MaxRetries) {
                Write-Warning "Groq JSON parse falhou apos $MaxRetries tentativas: $_"
                return $null
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Invoke-Gemini — wrapper Google Gemini API (v1beta)
# Free tier: 1500 req/dia 2.0 Flash, 50/dia 2.0 Pro. Latencia baixa, JSON-friendly.
# Tracking: cost = $0 (free tier); pago $0.075/M in $0.30/M out
# -----------------------------------------------------------------------------
function Invoke-Gemini {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "gemini-2.0-flash",
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [string]$Agent       = "unknown"
    )

    if (-not $env:GEMINI_API_KEY) { throw "GEMINI_API_KEY nao configurada" }

    $url = "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent?key=$($env:GEMINI_API_KEY)"
    $body = @{
        system_instruction = @{ parts = @(@{ text = $SystemPrompt }) }
        contents           = @(@{ role = "user"; parts = @(@{ text = $UserContent }) })
        generationConfig   = @{ temperature = $Temperature; maxOutputTokens = $MaxTokens }
    } | ConvertTo-Json -Depth 10 -Compress

    $start = Get-Date
    try {
        # B28c fix 2026-05-21: TimeoutSec 15s pra Gemini (fallback 1 — pode ser um pouco mais lento que Groq).
        $wr = Invoke-WebRequest -Uri $url -Method POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $latencyMs = ((Get-Date) - $start).TotalMilliseconds
        $json     = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
        $response = $json | ConvertFrom-Json
        try {
            if (Get-Command -Name "Track-ClaudeUsage" -ErrorAction SilentlyContinue) {
                $inTok  = [int]($response.usageMetadata.promptTokenCount)
                $outTok = [int]($response.usageMetadata.candidatesTokenCount)
                Track-ClaudeUsage -Model "gemini:$Model" -InputTokens $inTok -OutputTokens $outTok -Agent $Agent -LatencyMs $latencyMs | Out-Null
            }
        } catch {}
        return $response.candidates[0].content.parts[0].text
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $msg = $_.Exception.Message
        throw "Gemini API error ($statusCode): $msg"
    }
}

function Invoke-GeminiJson {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "gemini-2.0-flash",
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [int]   $MaxRetries  = 2,
        [string]$Agent       = "unknown"
    )
    $sysJson = $SystemPrompt + "`n`nIMPORTANTE: Responda APENAS com JSON valido, sem markdown."
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $raw = Invoke-Gemini -SystemPrompt $sysJson -UserContent $UserContent `
                -Model $Model -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            $cleaned = $raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
            return $cleaned | ConvertFrom-Json
        } catch {
            if ($attempt -eq $MaxRetries) {
                Write-Warning "Gemini JSON parse falhou apos $MaxRetries tentativas: $_"
                throw
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Invoke-MesaDroneCascade — Mesa drone com fallback Gemini -> Groq -> Haiku
# Mesa precisa 21 calls/cycle (3 drones x top-7). Groq sozinho estoura 30 RPM
# free tier (429s); Gemini 15 RPM mas estavel; Haiku $0.005/call como ultimo
# recurso. Mesa CAOS sistemico do 2026-05-16 era Groq 429/400 sem fallback.
# Retorna texto ou $null se TUDO falhar.
# -----------------------------------------------------------------------------
function Invoke-MesaDroneCascade {
    # 2026-05-16 v2: Groq primary (30 RPM suporta 3 drones em paralelo via Start-Job).
    # Gemini 15 RPM nao cabe Mesa (3 drones x 7 mercados burst). Gemini fallback ok.
    # Haiku final pago. Ordem: Groq -> Gemini -> Haiku.
    #
    # B28d fix 2026-05-21: param -HaikuPrimary opcional pra LIDAR. Diagnostico
    # mesa_drones.jsonl mostrou Lidar como drone com mais timeouts (Groq bucket
    # esgotando). Mover Lidar pra Anthropic Haiku primary libera bucket Groq pra
    # Termal+Radar (Brooks + Druckenmiller, decisao tecnica mais critica).
    # Custo: ~$0.005/call x ~12-20 Lidar/dia = $0.06-$0.10/dia (~$3/mes adicional).
    # Trade-off aceito: cost vs reliability.
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$GroqModel    = "llama-3.3-70b-versatile",
        [int]   $MaxTokens    = 600,
        [double]$Temperature  = 0.3,
        [string]$Agent        = "mesa_unknown",
        [switch]$HaikuPrimary  # B28d: forca Haiku primary (usado por Lidar)
    )
    # B28d: se HaikuPrimary, tenta Haiku PRIMEIRO. Fallback Groq->Gemini.
    if ($HaikuPrimary -and $env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Haiku primary falhou, fallback Groq: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 1. Groq (primary - 30 RPM, suporta parallel)
    if ($env:GROQ_API_KEY) {
        try {
            return Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model $GroqModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Gemini: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 2. Gemini (fallback 1 - se Groq 429/400)
    if ($env:GEMINI_API_KEY) {
        try {
            return Invoke-Gemini -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "gemini-2.0-flash" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Gemini falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Claude Haiku (fallback final, pago $0.005/call) — pula se ja tentou no inicio (HaikuPrimary)
    if (-not $HaikuPrimary -and $env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Warning "  [$Agent] Haiku final falhou: $($_.Exception.Message)"
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# Invoke-MentorCascade — Mentor com Anthropic primary, Groq+Gemini fallbacks
# Ordem: Sonnet -> Groq -> Gemini. Mentor é decisão final, qualidade matters
# mais que custo. Mas se Anthropic down, ainda tem 2 fallbacks gratuitos.
# Retorna texto ou $null se tudo falhar.
# -----------------------------------------------------------------------------
function Invoke-MentorCascade {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$AnthropicModel = $CLAUDE_MODEL,
        [int]   $MaxTokens      = 1500,
        [double]$Temperature    = 0.3,
        [string]$Agent          = "mentor"
    )
    # 2026-05-20 PM: provider trace -- script:LAST_CASCADE_PROVIDER captura qual LLM
    # respondeu pra logar em decisions.csv. Permite analise "qual modelo erra mais".
    $script:LAST_CASCADE_PROVIDER = $null
    # 1. Anthropic Sonnet (primary, quality)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            $r = Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model $AnthropicModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            $script:LAST_CASCADE_PROVIDER = "anthropic_sonnet"
            return $r
        } catch {
            Write-Host "  [$Agent] Anthropic falhou, fallback Groq: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 2. Groq llama-70b (fallback 1, gratis)
    if ($env:GROQ_API_KEY) {
        try {
            $r = Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            $script:LAST_CASCADE_PROVIDER = "groq_llama70b"
            return $r
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Gemini: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Gemini (fallback 2, gratis)
    if ($env:GEMINI_API_KEY) {
        try {
            $r = Invoke-Gemini -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "gemini-2.0-flash" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            $script:LAST_CASCADE_PROVIDER = "gemini_2_flash"
            return $r
        } catch {
            Write-Host "  [$Agent] Gemini falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 4. Claude Haiku (fallback final, pago ~$0.005/call)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            $r = Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            $script:LAST_CASCADE_PROVIDER = "anthropic_haiku"
            return $r
        } catch {
            Write-Warning "  [$Agent] Haiku final falhou: $($_.Exception.Message)"
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# Invoke-TriagemCascade — Triagem (drone batedor) com Gemini -> Groq -> Haiku.
# 2026-05-20 PM: cobertura completa. Antes era Gemini->Groq sem Anthropic.
# Triagem é classificação simples (Tier A/B/C/D), Haiku é suficiente como
# rede de seguranca pra caso ambos free tier estourem.
# -----------------------------------------------------------------------------
function Invoke-TriagemCascade {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [int]   $MaxTokens    = 800,
        [double]$Temperature  = 0.3,
        [string]$Agent        = "triagem"
    )
    if ($env:GEMINI_API_KEY) {
        try {
            return Invoke-Gemini -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "gemini-2.0-flash" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Gemini falhou, fallback Groq: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    if ($env:GROQ_API_KEY) {
        try {
            return Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Haiku (fallback final, cost-conscious -- SOMENTE Haiku, nao Sonnet)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Warning "  [$Agent] Haiku final falhou: $($_.Exception.Message)"
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# Invoke-AgentLLM — roteamento provider por agente
# Le $env:AGENT_<NAME>_PROVIDER (groq|anthropic) ou usa default
# Default: 'anthropic'. Fallback automatico: groq -> anthropic em caso de erro
# -----------------------------------------------------------------------------
function Invoke-AgentLLM {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Agent,                              # fund | sent | chain | tech | mentor
        [string]$AnthropicModel = $CLAUDE_MODEL,
        [int]   $MaxTokens      = 2000,
        [double]$Temperature    = 0.4
    )

    $envVar  = "AGENT_$($Agent.ToUpper())_PROVIDER"
    $prov    = [Environment]::GetEnvironmentVariable($envVar)
    if (-not $prov) { $prov = "anthropic" }

    if ($prov -eq "groq" -and $env:GROQ_API_KEY) {
        try {
            return Invoke-GroqJson -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Anthropic: $_" -ForegroundColor DarkYellow
            return Invoke-ClaudeJson -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model $AnthropicModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        }
    }

    return Invoke-ClaudeJson -SystemPrompt $SystemPrompt -UserContent $UserContent `
        -Model $AnthropicModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
}

# Invoke-TechCascadeJson — 2026-05-21 R3 fix: tech agent deixa de usar Sonnet ($0.027/call).
# Cascade Groq?Gemini?Haiku JSON-aware. Tech eh decisao tatica (sinal/forca/stop),
# nao precisa Sonnet reasoning. Empiric: 10 tech calls/dia a $0.027 = $0.27 desperdicio.
# Esperado pos-fix: <$0.01/call medio.
function Invoke-TechCascadeJson {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [int]   $MaxTokens    = 1500,
        [double]$Temperature  = 0.3,
        [string]$Agent        = "tech",
        [int]   $MaxRetries   = 2
    )
    $sysWithJson = $SystemPrompt + "`n`nIMPORTANTE: Responda APENAS com JSON valido, sem markdown, sem texto antes ou depois."

    function _ParseJsonResponse {
        param($Raw)
        if (-not $Raw) { return $null }
        $cleaned = $Raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
        try { return $cleaned | ConvertFrom-Json } catch { return $null }
    }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        # 1. Groq primary
        if ($env:GROQ_API_KEY) {
            try {
                $raw = Invoke-Groq -SystemPrompt $sysWithJson -UserContent $UserContent `
                    -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                $parsed = _ParseJsonResponse $raw
                if ($parsed) { return $parsed }
            } catch { Write-Host "  [$Agent] Groq falhou: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow }
        }
        # 2. Gemini fallback
        if ($env:GEMINI_API_KEY) {
            try {
                $raw = Invoke-Gemini -SystemPrompt $sysWithJson -UserContent $UserContent `
                    -Model "gemini-2.0-flash" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                $parsed = _ParseJsonResponse $raw
                if ($parsed) { return $parsed }
            } catch { Write-Host "  [$Agent] Gemini falhou: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow }
        }
        # 3. Haiku final fallback (SOMENTE Haiku, nao Sonnet)
        if ($env:ANTHROPIC_API_KEY) {
            try {
                $raw = Invoke-Claude -SystemPrompt $sysWithJson -UserContent $UserContent `
                    -Model "claude-haiku-4" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                $parsed = _ParseJsonResponse $raw
                if ($parsed) { return $parsed }
            } catch { Write-Warning "  [$Agent] Haiku falhou: $($_.Exception.Message)" }
        }
    }
    Write-Warning "[$Agent] Todas cascadas falharam apos $MaxRetries tentativas"
    return $null
}


# Wrapper que forca saida JSON e faz retry em falha de parse
function Invoke-ClaudeJson {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = $CLAUDE_MODEL,
        [int]   $MaxTokens   = $CLAUDE_MAX_TOKENS,
        [double]$Temperature = $CLAUDE_TEMP_TRADE,
        [int]   $MaxRetries  = 2,
        [string]$Agent       = "unknown"   # propagado ao cost tracker
    )

    $sysWithJson = $SystemPrompt + "`n`nIMPORTANTE: Responda APENAS com JSON valido, sem markdown, sem texto antes ou depois."

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $raw = Invoke-Claude -SystemPrompt $sysWithJson -UserContent $UserContent `
                -Model $Model -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            # Limpa markdown code blocks se presentes
            $cleaned = $raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
            return $cleaned | ConvertFrom-Json
        } catch {
            if ($attempt -eq $MaxRetries) {
                Write-Warning "Claude JSON parse falhou apos $MaxRetries tentativas: $_"
                return $null
            }
        }
    }
}

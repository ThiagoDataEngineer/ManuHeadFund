# lib_claude.ps1 — Claude API caller
# Dot-source: . (Join-Path $PSScriptRoot "lib_claude.ps1")
# Requer: $ANTHROPIC_API_KEY no ambiente ou config.ps1

# 2026-05-25: Forçar TLS 1.2+ para PowerShell 5.1 (default e SSLv3 + TLSv1, mas
# Anthropic/Groq/Gemini/OpenAI exigem TLS 1.2+. Sem isso = "A conexao subjacente
# estava fechada: Nao foi possivel estabelecer relacao de confianca para o canal
# seguro de SSL/TLS" -> cascade retorna null -> Mentor indisponivel -> veto auto.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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

    # Garantir TLS 1.2 no runspace atual (runspaces paralelos nao herdam do parent)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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

    # Garantir TLS 1.2 no runspace atual (runspaces paralelos nao herdam do parent)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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
            -TimeoutSec 30 `
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
# Invoke-Cerebras — wrapper Cerebras Inference API (OpenAI-compatible)
# Free tier: 50 RPM, ~1M tok/dia, 2300 tok/s (mais rapido do mundo).
# Modelos: llama-3.3-70b / llama-3.1-8b / qwen-3-235b
# API identica ao OpenAI — so muda a base URL e a key.
# Substitui Gemini no cascade: 50 RPM vs 15 RPM do Gemini, sem burst 429.
# Tracking: cost = $0 (free tier)
# Ref: https://inference-docs.cerebras.ai
# -----------------------------------------------------------------------------
function Invoke-Cerebras {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "gpt-oss-120b",   # modelo disponivel na conta free (verificado 2026-05-27)
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [string]$Agent       = "unknown"
    )

    $apiKey = $env:CEREBRAS_API_KEY
    if (-not $apiKey) { throw "CEREBRAS_API_KEY nao configurada" }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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
        $wr = Invoke-WebRequest `
            -Uri "https://api.cerebras.ai/v1/chat/completions" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $apiKey"
                "Content-Type"  = "application/json"
            } `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -UseBasicParsing `
            -TimeoutSec 20 `
            -ErrorAction Stop

        $latencyMs = ((Get-Date) - $start).TotalMilliseconds
        $json     = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
        $response = $json | ConvertFrom-Json

        try {
            if (Get-Command -Name "Track-ClaudeUsage" -ErrorAction SilentlyContinue) {
                $inTok  = [int]$response.usage.prompt_tokens
                $outTok = [int]$response.usage.completion_tokens
                Track-ClaudeUsage -Model "cerebras:$Model" -InputTokens $inTok -OutputTokens $outTok -Agent $Agent -LatencyMs $latencyMs | Out-Null
            }
        } catch {}

        return $response.choices[0].message.content
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $msg = $_.Exception.Message
        throw "Cerebras API error ($statusCode): $msg"
    }
}

# -----------------------------------------------------------------------------
# Invoke-Gemini — wrapper Google Gemini API (v1beta)
# Free tier: 1500 req/dia 2.0 Flash, 15 RPM (burst 429 frequente em uso intenso).
# NOTA 2026-05-27: Gemini rebaixado para fallback de ultimo recurso no cascade.
# Substituido por Cerebras (50 RPM, 2300 tok/s) como fallback 2.
# Tracking: cost = $0 (free tier); pago $0.075/M in $0.30/M out
# -----------------------------------------------------------------------------
function Invoke-Gemini {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "gemini-2.5-flash",
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [string]$Agent       = "unknown"
    )

    if (-not $env:GEMINI_API_KEY) { throw "GEMINI_API_KEY nao configurada" }

    $url = "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent?key=$($env:GEMINI_API_KEY)"
    
    # 2026-05-25: Gemini 2.5 Flash usa "thinking mode" por padrao que gasta
    # tokens em raciocinio interno. Sem thinkingBudget=0, MaxTokens pequeno
    # (ex: 5) gasta tudo em thoughts e devolve content vazio.
    $genConfig = @{ 
        temperature = $Temperature
        maxOutputTokens = $MaxTokens
    }
    # Desabilitar thinking apenas em modelos 2.5+ (suportam thinkingConfig)
    if ($Model -match "gemini-2\.5|gemini-3") {
        $genConfig.thinkingConfig = @{ thinkingBudget = 0 }
    }
    
    $body = @{
        system_instruction = @{ parts = @(@{ text = $SystemPrompt }) }
        contents           = @(@{ role = "user"; parts = @(@{ text = $UserContent }) })
        generationConfig   = $genConfig
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
        [string]$Model       = "gemini-2.5-flash",
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
    # 2026-05-27 v3: Round-robin Groq + Gemini + Cerebras para Mesa.
    # Problema: burst 21 calls/ciclo (3 drones x 7 mercados) estoura qualquer
    # provider sozinho. Solucao: rotacao por $Agent hash distribui carga:
    #   Groq:     30 RPM, 14.400 RPD
    #   Gemini:   15 RPM,  1.500 RPD
    #   Cerebras:  5 RPM,  2.400 RPD
    # Total combinado: ~50 RPM — absorve burst sem 429.
    # Fallback sequencial se o provider sorteado falhar.
    #
    # B28d fix 2026-05-21: param -HaikuPrimary para LIDAR (libera bucket Groq).
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$GroqModel    = "llama-3.3-70b-versatile",
        [int]   $MaxTokens    = 600,
        [double]$Temperature  = 0.3,
        [string]$Agent        = "mesa_unknown",
        [switch]$HaikuPrimary  # B28d: forca Haiku primary (usado por Lidar)
    )

    # B28d: LIDAR usa Haiku primary para liberar bucket Groq para Termal+Radar
    if ($HaikuPrimary -and $env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Haiku primary falhou, fallback round-robin: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }

    # Round-robin: distribui por hash do Agent name para consistencia dentro do ciclo
    # Termal -> slot 0, Radar -> slot 1, Lidar -> slot 2 (se nao HaikuPrimary)
    $slot = [Math]::Abs($Agent.GetHashCode()) % 3
    $hasGroq     = [bool]$env:GROQ_API_KEY
    $hasGemini   = [bool]$env:GEMINI_API_KEY
    $hasCerebras = [bool]$env:CEREBRAS_API_KEY

    # Ordem de tentativa baseada no slot (round-robin) com fallback sequencial
    $order = switch ($slot) {
        0 { @("groq","gemini","cerebras","haiku") }
        1 { @("gemini","cerebras","groq","haiku") }
        2 { @("cerebras","groq","gemini","haiku") }
    }

    foreach ($provider in $order) {
        try {
            switch ($provider) {
                "groq" {
                    if (-not $hasGroq) { continue }
                    $r = Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                        -Model $GroqModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                    if ($r) { return $r }
                }
                "gemini" {
                    if (-not $hasGemini) { continue }
                    $r = Invoke-Gemini -SystemPrompt $SystemPrompt -UserContent $UserContent `
                        -Model "gemini-2.5-flash" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                    if ($r) { return $r }
                }
                "cerebras" {
                    if (-not $hasCerebras) { continue }
                    $r = Invoke-Cerebras -SystemPrompt $SystemPrompt -UserContent $UserContent `
                        -Model "gpt-oss-120b" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                    if ($r) { return $r }
                }
                "haiku" {
                    if (-not $env:ANTHROPIC_API_KEY -or $HaikuPrimary) { continue }
                    $r = Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                        -Model "claude-haiku-4-5" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                    if ($r) { return $r }
                }
            }
        } catch {
            Write-Host "  [$Agent] $provider falhou, proximo: $($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
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
    # Mentor precisa JSON estruturado complexo — Sonnet primary (unico confiavel para JSON).
    # Haiku/Groq/Gemini geram campos extras e truncam -> parse falha silencioso.
    # Economia: Sonnet so para Mentor. Triagem/Mesa/Tech usam Groq/Gemini/Haiku.
    $script:LAST_CASCADE_PROVIDER = $null

    # 1. Anthropic Sonnet (primary — JSON estruturado confiavel)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            $r = Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model $AnthropicModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            if ($r) { $script:LAST_CASCADE_PROVIDER = "anthropic_sonnet"; return $r }
        } catch {
            Write-Host "  [$Agent] Sonnet falhou, fallback Groq: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 2. Groq llama-70b (fallback 1, gratis)
    if ($env:GROQ_API_KEY) {
        try {
            $r = Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            if ($r) { $script:LAST_CASCADE_PROVIDER = "groq_llama70b"; return $r }
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Cerebras: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Cerebras gpt-oss-120b (fallback 2, gratis, 50 RPM — substitui Gemini 2026-05-27)
    # Cerebras: 50 RPM vs 15 RPM Gemini, sem burst 429. Modelo: gpt-oss-120b (Meta 120B)
    if ($env:CEREBRAS_API_KEY) {
        try {
            $r = Invoke-Cerebras -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "gpt-oss-120b" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            if ($r) { $script:LAST_CASCADE_PROVIDER = "cerebras_gptoss120b"; return $r }
        } catch {
            Write-Host "  [$Agent] Cerebras falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 4. Claude Haiku (ultimo recurso, ~$0.005/call)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            $r = Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            if ($r) { $script:LAST_CASCADE_PROVIDER = "anthropic_haiku"; return $r }
        } catch {
            Write-Warning "  [$Agent] Haiku final falhou: $($_.Exception.Message)"
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
function Invoke-TriagemCascade {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [int]   $MaxTokens    = 800,
        [double]$Temperature  = 0.3,
        [string]$Agent        = "triagem"
    )
    # 1. Groq primary (30 RPM, rapido)
    if ($env:GROQ_API_KEY) {
        try {
            return Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Cerebras: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 2. Cerebras (fallback 1 - 50 RPM, substitui Gemini 2026-05-27)
    if ($env:CEREBRAS_API_KEY) {
        try {
            return Invoke-Cerebras -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "gpt-oss-120b" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Cerebras falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Haiku (fallback final, cost-conscious -- SOMENTE Haiku, nao Sonnet)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
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
                    -Model "gemini-2.5-flash" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                $parsed = _ParseJsonResponse $raw
                if ($parsed) { return $parsed }
            } catch { Write-Host "  [$Agent] Gemini falhou: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow }
        }
        # 3. Haiku final fallback (SOMENTE Haiku, nao Sonnet)
        if ($env:ANTHROPIC_API_KEY) {
            try {
                $raw = Invoke-Claude -SystemPrompt $sysWithJson -UserContent $UserContent `
                    -Model "claude-haiku-4-5" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
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
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
        # 2026-07-25: corpo da resposta de erro nunca era capturado -- 400/401/403
        # sempre apareciam so como "Response status code does not indicate success"
        # sem a mensagem real da API (ex: "invalid_request_error", "credit balance
        # too low"). Confirmado via diagnostico real (workflow_dispatch, runner
        # Ubuntu/pwsh Core): $_.ErrorDetails.Message TEM o corpo no ambiente real
        # de producao (PS Core, HttpResponseException) -- GetResponseStream()
        # (API do .NET Framework WebException) nao existe em HttpResponseMessage,
        # so seria necessario num PS5.1 Desktop puro que este projeto nao usa
        # para chamadas de API (todos os jobs GitHub Actions rodam shell:pwsh).
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $msg = $_.ErrorDetails.Message.Substring(0, [Math]::Min(300, $_.ErrorDetails.Message.Length))
        }
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

    # Dual-key rotation: GROQ_API_KEY (primary) + GROQ_API_KEY_2 (secondary)
    # Quando primary 429, tenta secondary automaticamente.
    # Combinado: 30 + 30 = 60 RPM — absorve burst Mesa sem Gemini/Cerebras.
    # Criar segunda key gratis em: console.groq.com -> API Keys -> Create
    $keys = @()
    if ($env:GROQ_API_KEY)   { $keys += $env:GROQ_API_KEY }
    if ($env:GROQ_API_KEY_2) { $keys += $env:GROQ_API_KEY_2 }
    if ($keys.Count -eq 0)   { throw "GROQ_API_KEY nao configurada" }

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

    $lastErr = $null
    foreach ($key in $keys) {
        $start = Get-Date
        try {
            $wr = Invoke-WebRequest `
                -Uri "https://api.groq.com/openai/v1/chat/completions" `
                -Method POST `
                -Headers @{
                    "Authorization" = "Bearer $key"
                    "Content-Type"  = "application/json"
                } `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
                -UseBasicParsing `
                -TimeoutSec 30 `
                -ErrorAction Stop

            $latencyMs = ((Get-Date) - $start).TotalMilliseconds
            $json     = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
            $response = $json | ConvertFrom-Json

            try {
                if (Get-Command -Name "Track-ClaudeUsage" -ErrorAction SilentlyContinue) {
                    $inTok  = [int]$response.usage.prompt_tokens
                    $outTok = [int]$response.usage.completion_tokens
                    Track-ClaudeUsage -Model "groq:$Model" -InputTokens $inTok -OutputTokens $outTok -Agent $Agent -LatencyMs $latencyMs | Out-Null
                }
            } catch {}

            return $response.choices[0].message.content
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $lastErr = "Groq API error ($statusCode): $($_.Exception.Message)"
            # 429 = rate limit — tenta proxima key. Outros erros: falha imediata.
            if ($statusCode -ne 429) { throw $lastErr }
            Write-Host "  [$Agent] Groq key rotacionada (429 na key atual)" -ForegroundColor DarkYellow
        }
    }
    throw $lastErr
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
# Invoke-Mistral — wrapper Mistral AI API (OpenAI-compatible)
# Free tier: 1 req/s, ~1B tokens/mes (praticamente ilimitado para nosso volume).
# Modelo default: mistral-small-3.1 (qualidade comparavel ao llama-3.3-70b).
# Substitui Gemini como fallback 2 em todos os cascades (2026-05-29).
# Motivo: Gemini 2.5 Flash free tier tem apenas 250 RPD -- esgota em 2-3h de
# operacao normal (10 candidatos x 3 drones x ciclos 30min = ~30 calls/ciclo).
# Mistral nao tem limite diario fixo, API OpenAI-compatible, sem cartao.
#
# NOTA: gemini-2.0-flash seria alternativa mais simples (1.500 RPD vs 250 RPD
# do 2.5 Flash), mas Mistral e superior: sem RPD fixo, API padrao, qualidade
# equivalente para JSON estruturado de trading.
#
# Ref: https://docs.mistral.ai/api/
# Criar key gratis: https://console.mistral.ai -> API Keys (sem cartao)
# Tracking: cost = $0 (free tier)
# -----------------------------------------------------------------------------
function Invoke-Mistral {
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$Model       = "mistral-small-latest",
        [int]   $MaxTokens   = 2000,
        [double]$Temperature = 0.4,
        [string]$Agent       = "unknown"
    )

    $apiKey = $env:MISTRAL_API_KEY
    if (-not $apiKey) { throw "MISTRAL_API_KEY nao configurada. Ver agents/config.local.ps1" }

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
            -Uri "https://api.mistral.ai/v1/chat/completions" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $apiKey"
                "Content-Type"  = "application/json"
            } `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        $latencyMs = ((Get-Date) - $start).TotalMilliseconds
        $json     = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
        $response = $json | ConvertFrom-Json

        try {
            if (Get-Command -Name "Track-ClaudeUsage" -ErrorAction SilentlyContinue) {
                $inTok  = [int]$response.usage.prompt_tokens
                $outTok = [int]$response.usage.completion_tokens
                Track-ClaudeUsage -Model "mistral:$Model" -InputTokens $inTok -OutputTokens $outTok -Agent $Agent -LatencyMs $latencyMs | Out-Null
            }
        } catch {}

        return $response.choices[0].message.content
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $msg = $_.Exception.Message
        throw "Mistral API error ($statusCode): $msg"
    }
}

# -----------------------------------------------------------------------------
# Invoke-Gemini — wrapper Google Gemini API (v1beta)
# NOTA 2026-05-29: Gemini substituido por Mistral como fallback 2 em todos os
# cascades. Motivo: free tier 2.5 Flash tem apenas 250 RPD -- esgota em 2-3h.
# Gemini mantido aqui para uso pontual / testes / fallback de emergencia.
# ALTERNATIVA: gemini-2.0-flash tem 1.500 RPD (6x mais que 2.5 Flash) e seria
# suficiente se Mistral nao estivesse disponivel. Trocar model= abaixo se necessario.
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
# Invoke-MesaDroneCascade — Mesa drone: Groq -> Mistral -> Haiku (Gemini removido 05-29)
# Mesa precisa 21 calls/cycle (3 drones x top-7). Groq sozinho estoura 30 RPM
# free tier (429s); Gemini 15 RPM mas estavel; Haiku $0.005/call como ultimo
# recurso. Mesa CAOS sistemico do 2026-05-16 era Groq 429/400 sem fallback.
# Retorna texto ou $null se TUDO falhar.
# -----------------------------------------------------------------------------
function Invoke-MesaDroneCascade {
    # 2026-05-27 v4: Groq dual-key como solucao principal para burst 429.
    # Invoke-Groq ja faz rotacao automatica GROQ_API_KEY -> GROQ_API_KEY_2 em 429.
    # Combinado: 30 + 30 = 60 RPM — absorve burst de 21 calls/ciclo.
    # Fallback: Gemini (15 RPM) -> Haiku (pago).
    # Cerebras removido: 5 RPM + modelo instavel para JSON curto.
    #
    # B28d: -HaikuPrimary para LIDAR libera bucket Groq para Termal+Radar.
    param(
        [string]$SystemPrompt,
        [string]$UserContent,
        [string]$GroqModel    = "llama-3.3-70b-versatile",
        [int]   $MaxTokens    = 600,
        [double]$Temperature  = 0.3,
        [string]$Agent        = "mesa_unknown",
        [switch]$HaikuPrimary
    )

    # B28d: LIDAR usa Haiku primary para liberar bucket Groq para Termal+Radar
    if ($HaikuPrimary -and $env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5-20251001" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Haiku primary falhou, fallback Groq: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }

    # 1. Groq dual-key (primary + secondary, 60 RPM combinado)
    if ($env:GROQ_API_KEY) {
        try {
            return Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model $GroqModel -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Mistral: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }

    # 2. Mistral (fallback 2 -- ~1B tok/mes, sem RPD fixo, OpenAI-compatible)
    # 2026-05-29: substitui Gemini (250 RPD esgotava em 2-3h de operacao).
    # NOTA: gemini-2.0-flash seria alternativa (1.500 RPD), mas Mistral e superior.
    # Provider state cache: pula se RATE_LIMITED ha menos de 5min.
    $mistralBlocked = $false
    try {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else {
            Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "journal"
        }
        $stateFile = Join-Path $journalDir "llm_provider_state.json"
        if (Test-Path $stateFile) {
            $pstate = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($pstate -and $pstate.PSObject.Properties["mistral"] -and $pstate.mistral.status -eq "RATE_LIMITED") {
                $lastTs = if ($pstate.mistral.ts -is [datetime]) {
                    $pstate.mistral.ts.ToUniversalTime()
                } else {
                    [datetime]::Parse([string]$pstate.mistral.ts, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                }
                $ageMin = ((Get-Date).ToUniversalTime() - $lastTs).TotalMinutes
                if ($ageMin -lt 5) {
                    $mistralBlocked = $true
                    Write-Host "  [$Agent] Mistral SKIP (RATE_LIMITED ha $([math]::Round($ageMin,0))min no cache) -> Haiku" -ForegroundColor DarkGray
                }
            }
        }
    } catch {}

    if ($env:MISTRAL_API_KEY -and -not $mistralBlocked) {
        try {
            return Invoke-Mistral -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Mistral falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }

    # 3. Claude Haiku (fallback final, pago)
    if (-not $HaikuPrimary -and $env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5-20251001" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
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
            Write-Host "  [$Agent] Sonnet falhou, fallback Groq: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 2. Groq llama-70b (fallback 1, gratis, dual-key automatico)
    if ($env:GROQ_API_KEY) {
        try {
            $r = Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            if ($r) { $script:LAST_CASCADE_PROVIDER = "groq_llama70b"; return $r }
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Mistral: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Mistral (fallback 2 -- ~1B tok/mes, sem RPD fixo, 2026-05-29)
    # Substitui Gemini (250 RPD esgotava em 2-3h). NOTA: gemini-2.0-flash = 1.500 RPD alternativa.
    if ($env:MISTRAL_API_KEY) {
        try {
            $r = Invoke-Mistral -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
            if ($r) { $script:LAST_CASCADE_PROVIDER = "mistral_small"; return $r }
        } catch {
            Write-Host "  [$Agent] Mistral falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 4. Claude Haiku (ultimo recurso, ~$0.005/call)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            $r = Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5-20251001" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
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
    # 1. Groq primary (dual-key automatico, 60 RPM combinado)
    if ($env:GROQ_API_KEY) {
        try {
            return Invoke-Groq -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "llama-3.3-70b-versatile" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Groq falhou, fallback Mistral: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 2. Mistral (fallback 2 -- ~1B tok/mes, sem RPD fixo, 2026-05-29)
    # Substitui Gemini (250 RPD esgotava em 2-3h). NOTA: gemini-2.0-flash = 1.500 RPD alternativa.
    if ($env:MISTRAL_API_KEY) {
        try {
            return Invoke-Mistral -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
        } catch {
            Write-Host "  [$Agent] Mistral falhou, fallback Haiku: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow
        }
    }
    # 3. Haiku (fallback final, cost-conscious -- SOMENTE Haiku, nao Sonnet)
    if ($env:ANTHROPIC_API_KEY) {
        try {
            return Invoke-Claude -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Model "claude-haiku-4-5-20251001" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
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
            } catch { Write-Host "  [$Agent] Groq falhou: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow }
        }
        # 2. Mistral fallback (2026-05-29: substitui Gemini, sem RPD fixo)
        # NOTA: gemini-2.0-flash = 1.500 RPD seria alternativa mais simples.
        if ($env:MISTRAL_API_KEY) {
            try {
                $raw = Invoke-Mistral -SystemPrompt $sysWithJson -UserContent $UserContent `
                    -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
                $parsed = _ParseJsonResponse $raw
                if ($parsed) { return $parsed }
            } catch { Write-Host "  [$Agent] Mistral falhou: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))" -ForegroundColor DarkYellow }
        }
        # 3. Haiku final fallback (SOMENTE Haiku, nao Sonnet)
        if ($env:ANTHROPIC_API_KEY) {
            try {
                $raw = Invoke-Claude -SystemPrompt $sysWithJson -UserContent $UserContent `
                    -Model "claude-haiku-4-5-20251001" -MaxTokens $MaxTokens -Temperature $Temperature -Agent $Agent
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
# warmup_llm_endpoints.ps1 -- Pre-aquece os 3 endpoints LLM do cascade
# Chamado pelo daily_daemon_restart.ps1 antes de respawnar os daemons.
# Objetivo: evitar cold-start no primeiro ciclo da manha (LIDAR null, Mentor null).
# Fire-forget: falhas sao logadas mas nao bloqueiam o restart.
#
# Cascade coberto:
#   Haiku    -> path critico LIDAR (mesa_agent -HaikuPrimary) + Mentor fallback 3
#   Groq     -> Mesa Termal + Radar primary (dual-key: GROQ_API_KEY + GROQ_API_KEY_2)
#   Gemini   -> fallback 2 (15 RPM, 1500 RPD) -- testado apenas se nao em 429 recente
#
# 2026-05-28: provider state cache em journal/llm_provider_state.json
# Gemini 429 persistente hoje (8/9 warmups falharam). Warmup agora:
#   - Registra status de cada provider (OK / RATE_LIMITED / DOWN) com timestamp
#   - Pula Gemini se ultimo status foi RATE_LIMITED ha menos de 30min
#   - Cascade em lib_claude.ps1 consulta o cache antes de tentar Gemini

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logDir      = Join-Path $projectRoot "logs"
$journalDir  = Join-Path $projectRoot "journal"
if (-not (Test-Path $logDir))     { New-Item -ItemType Directory -Path $logDir     -Force | Out-Null }
if (-not (Test-Path $journalDir)) { New-Item -ItemType Directory -Path $journalDir -Force | Out-Null }
$logFile     = Join-Path $logDir ("llm_warmup_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")
$stateFile   = Join-Path $journalDir "llm_provider_state.json"

function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

# Escreve estado do provider no cache (fail-soft)
function Set-ProviderState {
    param([string]$Provider, [string]$Status)  # Status: OK | RATE_LIMITED | DOWN
    try {
        $state = if (Test-Path $stateFile) {
            Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } else { [PSCustomObject]@{} }
        $state | Add-Member -NotePropertyName $Provider -NotePropertyValue ([PSCustomObject]@{
            status    = $Status
            ts        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }) -Force
        $state | ConvertTo-Json -Compress | Set-Content -Path $stateFile -Encoding UTF8
    } catch {}
}

# Le estado do provider (fail-soft, retorna $null se ausente)
function Get-ProviderState {
    param([string]$Provider)
    try {
        if (-not (Test-Path $stateFile)) { return $null }
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.PSObject.Properties[$Provider]) { return $state.$Provider }
    } catch {}
    return $null
}

Log "=== LLM warmup START ==="

# Carrega config + libs
try {
    . (Join-Path $projectRoot "agents\config.ps1")
    . (Join-Path $projectRoot "agents\lib_claude.ps1")
} catch {
    Log "  FAIL loading libs: $_"
    Log "=== LLM warmup DONE ==="
    exit 1
}

$warmupSys  = "You are a trading assistant. Answer briefly."
$warmupUser = "What is the current market sentiment for crypto? One sentence."

# 1. Haiku (path critico LIDAR)
try {
    $t = Get-Date
    $r = Invoke-Claude -SystemPrompt $warmupSys -UserContent $warmupUser `
        -Model "claude-haiku-4-5" -MaxTokens 5 -Temperature 0 -Agent "warmup_haiku"
    $ms = [math]::Round(((Get-Date) - $t).TotalSeconds, 1)
    if ($r) { Log "  [Haiku]  ${ms}s -> OK"; Set-ProviderState "haiku" "OK" }
    else    { Log "  [Haiku]  ${ms}s -> null (sem erro)"; Set-ProviderState "haiku" "DOWN" }
} catch {
    Log "  [Haiku]  FAIL: Claude API error ($($_.Exception.Response.StatusCode.value__)): $($_.Exception.Message)"
    Set-ProviderState "haiku" "DOWN"
}

# 2. Groq llama-70b (Mesa Termal + Radar primary)
try {
    $t = Get-Date
    $r = Invoke-Groq -SystemPrompt $warmupSys -UserContent $warmupUser `
        -Model "llama-3.3-70b-versatile" -MaxTokens 5 -Temperature 0 -Agent "warmup_groq"
    $ms = [math]::Round(((Get-Date) - $t).TotalSeconds, 1)
    if ($r) { Log "  [Groq]   ${ms}s -> OK"; Set-ProviderState "groq" "OK" }
    else    { Log "  [Groq]   ${ms}s -> null (sem erro)"; Set-ProviderState "groq" "DOWN" }
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Log "  [Groq]   FAIL: Groq API error ($code): $($_.Exception.Message)"
    Set-ProviderState "groq" (if ($code -eq 429) { "RATE_LIMITED" } else { "DOWN" })
}

# 3. Gemini (fallback 2 — 15 RPM, 1500 RPD)
# Pula se ultimo estado foi RATE_LIMITED ha menos de 30min (evita logar 429 desnecessario)
$geminiState = Get-ProviderState "gemini"
$skipGemini  = $false
if ($geminiState -and $geminiState.status -eq "RATE_LIMITED") {
    try {
        $lastTs  = if ($geminiState.ts -is [datetime]) {
            [datetime]::SpecifyKind($geminiState.ts, [DateTimeKind]::Utc)
        } else {
            [datetime]::SpecifyKind(
                [datetime]::ParseExact([string]$geminiState.ts, "yyyy-MM-ddTHH:mm:ssZ", $null),
                [DateTimeKind]::Utc)
        }
        $ageMin  = ((Get-Date).ToUniversalTime() - $lastTs).TotalMinutes
        if ($ageMin -lt 30) {
            Log "  [Gemini] SKIP -- RATE_LIMITED ha $([math]::Round($ageMin,0))min (aguardando janela de 30min)"
            $skipGemini = $true
        }
    } catch {}
}

if (-not $skipGemini) {
    try {
        $t = Get-Date
        $r = Invoke-Gemini -SystemPrompt $warmupSys -UserContent $warmupUser `
            -Model "gemini-2.5-flash" -MaxTokens 50 -Temperature 0 -Agent "warmup_gemini"
        $ms = [math]::Round(((Get-Date) - $t).TotalSeconds, 1)
        if ($r) { Log "  [Gemini] ${ms}s -> OK"; Set-ProviderState "gemini" "OK" }
        else    { Log "  [Gemini] ${ms}s -> null (sem erro)"; Set-ProviderState "gemini" "DOWN" }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        Log "  [Gemini] FAIL: Gemini API error ($code): $($_.Exception.Message)"
        Set-ProviderState "gemini" (if ($code -eq 429) { "RATE_LIMITED" } else { "DOWN" })
    }
}

Log "=== LLM warmup DONE ==="

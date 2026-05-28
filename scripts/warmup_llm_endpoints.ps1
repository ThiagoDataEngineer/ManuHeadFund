# warmup_llm_endpoints.ps1 -- Pre-aquece os 3 endpoints LLM do cascade
# Chamado pelo daily_daemon_restart.ps1 antes de respawnar os daemons.
# Objetivo: evitar cold-start no primeiro ciclo da manha (LIDAR null, Mentor null).
# Fire-forget: falhas sao logadas mas nao bloqueiam o restart.
#
# Cascade coberto (2026-05-27: Gemini substituido por Cerebras):
#   Haiku     -> path critico LIDAR (mesa_agent -HaikuPrimary) + Mentor fallback 3
#   Groq      -> Mesa Termal + Radar primary (llama-3.3-70b-versatile)
#   Cerebras  -> fallback 2 de todos os cascades (50 RPM, 2300 tok/s, zero 429)

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logDir      = Join-Path $projectRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("llm_warmup_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")

function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

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

$warmupSys  = "You are a warmup ping. Reply with one word: OK"
$warmupUser = "warmup"

# 1. Haiku (path critico LIDAR)
try {
    $t = Get-Date
    $r = Invoke-Claude -SystemPrompt $warmupSys -UserContent $warmupUser `
        -Model "claude-haiku-4-5" -MaxTokens 5 -Temperature 0 -Agent "warmup_haiku"
    $ms = [math]::Round(((Get-Date) - $t).TotalSeconds, 1)
    if ($r) { Log "  [Haiku]  ${ms}s -> OK" }
    else    { Log "  [Haiku]  ${ms}s -> null (sem erro)" }
} catch {
    Log "  [Haiku]  FAIL: Claude API error ($($_.Exception.Response.StatusCode.value__)): $($_.Exception.Message)"
}

# 2. Groq llama-70b (Mesa Termal + Radar primary)
try {
    $t = Get-Date
    $r = Invoke-Groq -SystemPrompt $warmupSys -UserContent $warmupUser `
        -Model "llama-3.3-70b-versatile" -MaxTokens 5 -Temperature 0 -Agent "warmup_groq"
    $ms = [math]::Round(((Get-Date) - $t).TotalSeconds, 1)
    if ($r) { Log "  [Groq]   ${ms}s -> OK" }
    else    { Log "  [Groq]   ${ms}s -> null (sem erro)" }
} catch {
    Log "  [Groq]   FAIL: Groq API error ($($_.Exception.Response.StatusCode.value__)): $($_.Exception.Message)"
}

# 3. Cerebras llama-70b (fallback 2 — substitui Gemini, 50 RPM, zero 429)
try {
    $t = Get-Date
    $r = Invoke-Cerebras -SystemPrompt $warmupSys -UserContent $warmupUser `
        -Model "llama-3.3-70b" -MaxTokens 5 -Temperature 0 -Agent "warmup_cerebras"
    $ms = [math]::Round(((Get-Date) - $t).TotalSeconds, 1)
    if ($r) { Log "  [Cerebras] ${ms}s -> OK" }
    else    { Log "  [Cerebras] ${ms}s -> null (sem erro)" }
} catch {
    Log "  [Cerebras] FAIL: Cerebras API error ($($_.Exception.Response.StatusCode.value__)): $($_.Exception.Message)"
}

Log "=== LLM warmup DONE ==="

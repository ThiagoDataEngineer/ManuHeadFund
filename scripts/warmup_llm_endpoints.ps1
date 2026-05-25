# warmup_llm_endpoints.ps1 -- Pre-aquece endpoints LLM para evitar cold-start.
#
# Background:
# Audit Mesa drones 2026-05-21 manha: 3/3 LIDAR null no primeiro cycle do dia
# (HYPE/USELESS/ZEC 08:32-08:34 BRT) com erro job_state_Running_likely_timeout.
# 10 min depois, zero falhas. Diagnose: Haiku Anthropic serverless cold container
# leva 20-30s na primeira inferencia, mas TimeoutSec 20s estourava antes.
#
# Solucao em camadas:
#   A) TimeoutSec 20 -> 35 em lib_claude.ps1 (defesa em profundidade)
#   D) Este warmup: 1 call minima a cada provider apos daemon restart -> proximo
#      cycle real ja encontra endpoint quente.
#
# Design:
#   - Fail-open (warning-only). Nunca quebra restart.
#   - Sequencial (nao parallel): 3 calls leves total <10s.
#   - Prompt minimo (10 tokens out): custo desprezivel ~$0.00005 total.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

. (Join-Path (Join-Path $projectRoot "agents") "config.local.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_claude.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_cost_tracker.ps1")

$logFile = Join-Path $projectRoot ("logs\llm_warmup_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== LLM warmup START ==="

$payload = @{
    sys = "You are a no-op endpoint warmup. Respond with exactly: OK"
    usr = "ping"
}

# 1) Anthropic Haiku -- mais critico (Mesa LIDAR + cascade fallback)
try {
    $t0 = Get-Date
    $r = Invoke-Claude -SystemPrompt $payload.sys -UserContent $payload.usr `
        -Model "claude-haiku-4" -MaxTokens 10 -Temperature 0 -Agent "warmup"
    $dt = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    Log "  [Haiku]  ${dt}s -> $($r.SubString(0, [Math]::Min(20, $r.Length)))"
} catch {
    Log "  [Haiku]  FAIL: $($_.Exception.Message)"
}

# 2) Groq llama-70b -- Mesa Termal/Radar primary
try {
    $t0 = Get-Date
    if (Get-Command Invoke-Groq -ErrorAction SilentlyContinue) {
        $r = Invoke-Groq -SystemPrompt $payload.sys -UserContent $payload.usr `
            -Model "llama-3.3-70b-versatile" -MaxTokens 10 -Temperature 0 -Agent "warmup"
        $dt = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
        Log "  [Groq]   ${dt}s -> $($r.SubString(0, [Math]::Min(20, $r.Length)))"
    } else {
        Log "  [Groq]   SKIP (Invoke-Groq nao disponivel)"
    }
} catch {
    Log "  [Groq]   FAIL: $($_.Exception.Message)"
}

# 3) Gemini -- cascade fallback 2
try {
    $t0 = Get-Date
    if (Get-Command Invoke-Gemini -ErrorAction SilentlyContinue) {
        $r = Invoke-Gemini -SystemPrompt $payload.sys -UserContent $payload.usr `
            -Model "gemini-2.5-flash" -MaxTokens 10 -Temperature 0 -Agent "warmup"
        $dt = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
        Log "  [Gemini] ${dt}s -> $($r.SubString(0, [Math]::Min(20, $r.Length)))"
    } else {
        Log "  [Gemini] SKIP (Invoke-Gemini nao disponivel)"
    }
} catch {
    Log "  [Gemini] FAIL: $($_.Exception.Message)"
}

Log "=== LLM warmup DONE ==="
exit 0

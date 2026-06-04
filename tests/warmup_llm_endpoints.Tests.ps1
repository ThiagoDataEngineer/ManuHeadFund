# warmup_llm_endpoints.Tests.ps1 -- FASE 2 fix D anti-regression.
# Pester 3.x. Garante que:
#   1. Script existe + parse limpo
#   2. daily_daemon_restart wire-up persiste (regressao de wiring)
#   3. Invoca Haiku/Groq/Gemini (warmup completo das 3 portas cascade)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path $here -Parent
$warmupPath = Join-Path $projectRoot "scripts\warmup_llm_endpoints.ps1"
$restartPath = Join-Path $projectRoot "scripts\daily_daemon_restart.ps1"


Describe "warmup_llm_endpoints.ps1 - shape" {
    It "Script existe" {
        Test-Path $warmupPath | Should Be $true
    }
    It "Parse PowerShell limpo (sem syntax error)" {
        $errs = $null
        [System.Management.Automation.PSParser]::Tokenize(
            (Get-Content $warmupPath -Raw -Encoding UTF8), [ref]$errs
        ) | Out-Null
        $errs.Count | Should Be 0
    }
    It "Chama Invoke-Claude com Haiku (warmup do path critico LIDAR)" {
        $src = Get-Content $warmupPath -Raw -Encoding UTF8
        $src | Should Match 'Invoke-Claude[\s\S]+?claude-haiku'
    }
    It "Chama Invoke-Groq com llama-70b (Mesa Termal/Radar primary)" {
        $src = Get-Content $warmupPath -Raw -Encoding UTF8
        $src | Should Match 'Invoke-Groq[\s\S]+?llama'
    }
    It "Chama Invoke-Mistral (cascade fallback 2 - substituiu Gemini 2026-05-29)" {
        $src = Get-Content $warmupPath -Raw -Encoding UTF8
        $src | Should Match 'Invoke-Mistral'
    }
    It "Fail-open: cada call em try/catch separado" {
        $src = Get-Content $warmupPath -Raw -Encoding UTF8
        ([regex]::Matches($src, 'try\s*\{')).Count | Should BeGreaterThan 2
    }
}


Describe "daily_daemon_restart wire-up - FASE 2 fix D" {
    It "daily_daemon_restart invoca warmup_llm_endpoints" {
        $src = Get-Content $restartPath -Raw -Encoding UTF8
        $src | Should Match 'warmup_llm_endpoints\.ps1'
    }
    It "Warmup eh spawned via Start-Process (fire-forget)" {
        # daily_daemon_restart deve resolver $warmupPath via Join-Path + invocar via Start-Process.
        # Regex usa multiline scan tolerante a variavel path.
        $src = Get-Content $restartPath -Raw -Encoding UTF8
        $src | Should Match '(?s)warmup_llm_endpoints[\s\S]{0,500}Start-Process|Start-Process[\s\S]{0,500}\$warmupPath'
    }
}

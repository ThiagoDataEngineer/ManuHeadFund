# r3_r5_cost_optimizations.Tests.ps1 -- 2026-05-21 cost optimization lockdown.
# Pester 3.x. Anti-regression de R3 (tech cascade) + R5 (pre-mentor skip).

$script:cost_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:cost_root = Split-Path -Parent $cost_here


Describe "R3 - Tech agent usa cascade Groq-primary" {

    It "lib_claude.ps1 expÃµe Invoke-TechCascadeJson" {
        $src = Get-Content (Join-Path $cost_root "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $src | Should Match 'function Invoke-TechCascadeJson'
    }

    It "Invoke-TechCascadeJson ordem cascade: Groq -> Mistral -> Haiku" {
        $src = Get-Content (Join-Path $cost_root "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $func = [regex]::Match($src, 'function Invoke-TechCascadeJson[\s\S]+?(?=function\s+Invoke-)').Value
        # Ordem: Groq antes de Mistral antes de Haiku (Gemini deprecated commit 6f6e02b)
        $groqPos = $func.IndexOf('Invoke-Groq')
        $mistralPos = $func.IndexOf('Invoke-Mistral')
        $claudePos = $func.IndexOf('claude-haiku')
        ($groqPos -gt 0) | Should Be $true
        ($mistralPos -gt $groqPos) | Should Be $true
        ($claudePos -gt $mistralPos) | Should Be $true
    }

    It "Tech agent (tech_agent_ai.ps1) chama Invoke-TechCascadeJson" {
        $src = Get-Content (Join-Path $cost_root "agents\tech_agent_ai.ps1") -Raw -Encoding UTF8
        $src | Should Match 'Invoke-TechCascadeJson'
    }

    It "Fallback path preservado (Invoke-ClaudeJson disponivel se cascade falhar)" {
        # Se Invoke-TechCascadeJson nao existir (defensive), cai para ClaudeJson
        $src = Get-Content (Join-Path $cost_root "agents\tech_agent_ai.ps1") -Raw -Encoding UTF8
        $src | Should Match 'Invoke-ClaudeJson'
    }

    It "Invoke-TechCascadeJson NAO usa Sonnet (deve usar Haiku no fallback final)" {
        $src = Get-Content (Join-Path $cost_root "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $func = [regex]::Match($src, 'function Invoke-TechCascadeJson[\s\S]+?(?=function\s+Invoke-)').Value
        $func | Should Not Match 'claude-sonnet'
        $func | Should Match 'claude-haiku-4'
    }
}


Describe "R5 - Pre-Mentor skip para tier D (poupanca LLM)" {

    It "orchestrator_v6.ps1 contem PRE_MENTOR_SKIP para tier D" {
        $src = Get-Content (Join-Path $cost_root "agents\orchestrator_v6.ps1") -Raw -Encoding UTF8
        $src | Should Match 'PRE_MENTOR_SKIP'
        $src | Should Match 'triagemTier\s+-eq\s+"D"'
    }

    It "Pre-Mentor skip ocorre ANTES da CALL de Invoke-MentorDebate" {
        $orchPath = Join-Path $cost_root "agents\orchestrator_v6.ps1"
        $lines = Get-Content $orchPath -Encoding UTF8
        $skipLine = $null; $mentorCallLine = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if (-not $skipLine -and $lines[$i] -match 'PRE_MENTOR_SKIP') { $skipLine = $i }
            if (-not $mentorCallLine -and $lines[$i] -match '\$mentor\s*=\s*Invoke-MentorDebate') { $mentorCallLine = $i }
        }
        $skipLine | Should Not BeNullOrEmpty
        $mentorCallLine | Should Not BeNullOrEmpty
        ($skipLine -lt $mentorCallLine) | Should Be $true
    }

    It "Pre-Mentor skip retorna ABORTAR + telegramFire=false" {
        $src = Get-Content (Join-Path $cost_root "agents\orchestrator_v6.ps1") -Raw -Encoding UTF8
        $skipBlock = [regex]::Match($src, 'PRE_MENTOR_SKIP[\s\S]+?return\s+\[PSCustomObject\][\s\S]+?\}').Value
        $skipBlock | Should Match 'decisao\s*=\s*"ABORTAR"'
        $skipBlock | Should Match 'telegramFire\s*=\s*\$false'
        $skipBlock | Should Match 'mentor\s*=\s*\$null'
    }
}

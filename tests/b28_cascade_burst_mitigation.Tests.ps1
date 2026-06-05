# B28 fix 2026-05-21 PM6+1050min: Mesa cascade burst mitigation.
#
# Pós B25/B26/B27 a telemetria revelou: 5/6 drones com job_state_Running_likely_timeout
# Causa raiz: scan paralelo de N markets dispara N*3 drones LLM simultaneamente,
# estourando Groq rate limit mesmo com stagger 750ms intra-market.
#
# B28b: MaxConcurrency 3 -> 2 (max 6 drones simultaneos vs 9 antes)
# B28c: TimeoutSec explicito em Invoke-Groq/Gemini/Claude (fail-fast pra cascade)
# B28d: Lidar -HaikuPrimary (libera bucket Groq pra Termal+Radar)

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_claude.ps1")

Describe "B28b MaxConcurrency default reduzido" {
    It "lib_orchestrator_parallel default = 2 (era 3 -- reduz burst inter-market)" {
        $src = Get-Content (Join-Path $projectRoot "agents\lib_orchestrator_parallel.ps1") -Raw -Encoding UTF8
        # Extrai linha do param MaxConcurrency
        $match = [regex]::Match($src, '\$MaxConcurrency\s*=\s*(\d+)')
        $match.Success | Should Be $true
        [int]$match.Groups[1].Value | Should Be 2
    }
    It "scan_master ParallelMaxConcurrency default = 2 (era 3)" {
        $src = Get-Content (Join-Path $projectRoot "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $match = [regex]::Match($src, '\$ParallelMaxConcurrency\s*=\s*(\d+)')
        $match.Success | Should Be $true
        [int]$match.Groups[1].Value | Should Be 2
    }
}

Describe "B28c TimeoutSec presente em Invoke-WebRequest cascade" {
    It "Invoke-Groq tem TimeoutSec explicito (era default 100s+, agora fail-fast)" {
        $src = Get-Content (Join-Path $projectRoot "agents\lib_claude.ps1") -Raw -Encoding UTF8
        # Match dentro do escopo da funcao Invoke-Groq
        $groq = [regex]::Match($src, 'function Invoke-Groq[\s\S]+?(?=function\s+Invoke-)').Value
        $groq | Should Match '-TimeoutSec\s+30'
    }
    It "Invoke-Gemini tem TimeoutSec explicito (fallback 1)" {
        $src = Get-Content (Join-Path $projectRoot "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $gem = [regex]::Match($src, 'function Invoke-Gemini[\s\S]+?(?=function\s+Invoke-)').Value
        $gem | Should Match '-TimeoutSec\s+15'
    }
    It "Invoke-Claude tem TimeoutSec explicito (>=35s pos FASE 2 cold-start fix)" {
        # 2026-05-21 FASE 2: bumped 20->35s. Cold-start Haiku no primeiro cycle do dia
        # estourava 20s (LIDAR null 3/3 em HYPE/USELESS/ZEC 08:32 BRT).
        $src = Get-Content (Join-Path $projectRoot "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $cl = [regex]::Match($src, 'function Invoke-Claude\s*\{[\s\S]+?(?=function\s+Invoke-)').Value
        $cl | Should Match '-TimeoutSec\s+(35|[4-9]\d)'
    }
}

Describe "B28d HaikuPrimary param + Lidar wire" {
    It "Invoke-MesaDroneCascade tem param -HaikuPrimary" {
        $src = Get-Content (Join-Path $projectRoot "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $cascade = [regex]::Match($src, 'function Invoke-MesaDroneCascade[\s\S]+?(?=function\s+Invoke-)').Value
        $cascade | Should Match '\[switch\]\$HaikuPrimary'
    }
    It "Invoke-MesaDroneCascade tenta Haiku PRIMEIRO quando HaikuPrimary set" {
        $src = Get-Content (Join-Path $projectRoot "agents\lib_claude.ps1") -Raw -Encoding UTF8
        $cascade = [regex]::Match($src, 'function Invoke-MesaDroneCascade[\s\S]+?(?=function\s+Invoke-)').Value
        # Ordem do codigo: HaikuPrimary block vem ANTES do Groq primary block
        $idxHaikuPrimary = $cascade.IndexOf('if ($HaikuPrimary -and $env:ANTHROPIC_API_KEY)')
        $idxGroqPrimary  = $cascade.IndexOf('if ($env:GROQ_API_KEY)')
        $idxHaikuPrimary | Should BeGreaterThan -1
        $idxGroqPrimary  | Should BeGreaterThan $idxHaikuPrimary
    }
    It "Invoke-MesaDrone passa -HaikuPrimary quando Drone=lidar" {
        $src = Get-Content (Join-Path $projectRoot "agents\mesa_agent.ps1") -Raw -Encoding UTF8
        $drone = [regex]::Match($src, 'function Invoke-MesaDrone[\s\S]+?(?=function\s+|# =)').Value
        $drone | Should Match '\$useHaikuPrimary\s*=\s*\(\$Drone\s+-eq\s+"lidar"\)'
        $drone | Should Match '-HaikuPrimary:\$useHaikuPrimary'
    }
}

Describe "B28 integration: max 6 drones simultaneos pos-fix" {
    # Calculo: MaxConcurrency 2 markets * 3 drones/market = 6 drones LLM simultaneos
    # Antes: 3 * 3 = 9 (estourava Groq RPM bucket)
    It "concurrency efetiva max = 6 drones LLM em parallel" {
        $src = Get-Content (Join-Path $projectRoot "agents\lib_orchestrator_parallel.ps1") -Raw -Encoding UTF8
        $match = [regex]::Match($src, '\$MaxConcurrency\s*=\s*(\d+)')
        $maxMarkets = [int]$match.Groups[1].Value
        $maxDrones = $maxMarkets * 3
        $maxDrones | Should Be 6
    }
}

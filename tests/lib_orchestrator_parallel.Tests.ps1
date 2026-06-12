# lib_orchestrator_parallel.Tests.ps1 -- Pester 3.x
# Smoke test usando AgentsDir fake com mock Invoke-OrchestratorV6 minimo.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_orchestrator_parallel.ps1")

# Cria fake agents dir com 1 ps1 stub que define Invoke-OrchestratorV6 -> echo
$fakeAgents = Join-Path $env:TEMP ("opfake_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $fakeAgents -Force | Out-Null
$stub = @'
function Invoke-OrchestratorV6 {
    param([string]$Market, $ScannerInfo, [switch]$DryRun, [string]$Mode = "paper")
    Start-Sleep -Milliseconds 200
    return [PSCustomObject]@{ market = $Market; decisao = "ABORTAR"; mode = $Mode; dry = $DryRun.IsPresent }
}
'@
$stub | Out-File (Join-Path $fakeAgents "orchestrator_v6.ps1") -Encoding utf8


Describe "Invoke-OrchestratorCandidatesParallel" {
    It "Returns array de results 1:1 com candidates" {
        $cands = @(
            [PSCustomObject]@{ market = "AAA"; scanInfo = $null; mode = "paper"; dryRun = $true }
            [PSCustomObject]@{ market = "BBB"; scanInfo = $null; mode = "paper"; dryRun = $true }
            [PSCustomObject]@{ market = "CCC"; scanInfo = $null; mode = "paper"; dryRun = $true }
        )
        $r = Invoke-OrchestratorCandidatesParallel -Candidates $cands -MaxConcurrency 3 -AgentsDir $fakeAgents
        $r.Count | Should Be 3
        ($r | Where-Object { $_.ok }).Count | Should Be 3
        ($r | ForEach-Object { $_.market } | Sort-Object) -join ',' | Should Be "AAA,BBB,CCC"
    }
    It "Lista vazia retorna array vazio" {
        $r = Invoke-OrchestratorCandidatesParallel -Candidates @() -AgentsDir $fakeAgents
        $r.Count | Should Be 0
    }
    It "Captura erro em runspace e marca ok=false" {
        $bad = Join-Path $env:TEMP ("opbad_$([guid]::NewGuid())")
        New-Item -ItemType Directory -Path $bad -Force | Out-Null
        try {
            # sem orchestrator_v6 -> Invoke-OrchestratorV6 indefinido -> erro
            $cands = @([PSCustomObject]@{ market = "XXX"; scanInfo = $null; mode = "paper"; dryRun = $true })
            $r = Invoke-OrchestratorCandidatesParallel -Candidates $cands -MaxConcurrency 1 -AgentsDir $bad
            $r.Count | Should Be 1
            $r[0].ok | Should Be $false
        } finally { Remove-Item $bad -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Remove-Item $fakeAgents -Recurse -Force -ErrorAction SilentlyContinue

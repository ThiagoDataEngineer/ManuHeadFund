# lib_runspace_audit.ps1 -- preventivo contra bug "lib orfa em runspace child"
#
# Background (2026-05-20 PM3):
#   `lib_orchestrator_parallel.ps1` cria RunspacePool [InitialSessionState::CreateDefault()] -
#   runspace ISOLADO sem heranca do parent. Lista hardcoded de libs no script child
#   precisa cobrir TODAS funcoes referenciadas downstream via `Get-Command X -ErrorAction
#   SilentlyContinue` no orchestrator.
#
#   Bug invisivel: `Get-Command X -SilentlyContinue` retorna `$null` se X nao existe
#   no runspace, branch silently skipped. Mentor recebe FQS=null -> hallucinacao "FQS
#   indisponivel" mesmo registry tendo entry.
#
# Solucao: este modulo cruza Get-Command refs no orchestrator vs lista no parallel,
# alerta gaps antes de virar bug em prod.


function Get-OrchestratorGetCommandRefs {
    <#
    .SYNOPSIS
        Extrai todos nomes de funcoes referenciadas via `Get-Command X -SilentlyContinue`
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path $Path)) { return @() }
    $content = Get-Content $Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { return @() }

    # Pattern: Get-Command <Nome> -ErrorAction SilentlyContinue
    # Captura: o nome da funcao
    $regex = [regex]'Get-Command\s+([A-Za-z][A-Za-z0-9_\-]+)\s+-ErrorAction\s+SilentlyContinue'
    $matches = $regex.Matches($content)
    $names = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $matches) {
        [void]$names.Add($m.Groups[1].Value)
    }
    return @($names)
}


function Get-ParallelRunspaceLibsList {
    <#
    .SYNOPSIS
        Extrai lista hardcoded `$libs = @(...)` do script parallel
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path $Path)) { return @() }
    $content = Get-Content $Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { return @() }

    # Pattern: $libs = @( ... )  -- captura conteudo do array, multiline
    $regex = [regex]'\$libs\s*=\s*@\(([^)]*)\)'
    $match = $regex.Match($content)
    if (-not $match.Success) { return @() }

    $arrayBody = $match.Groups[1].Value
    # Extrai strings entre aspas duplas
    $stringRegex = [regex]'"([^"]+\.ps1)"'
    $strMatches = $stringRegex.Matches($arrayBody)
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($sm in $strMatches) {
        [void]$libs.Add($sm.Groups[1].Value)
    }
    return @($libs)
}


function Find-LibDefiningFunction {
    <#
    .SYNOPSIS
        Acha qual .ps1 em -AgentsDir define `function <FunctionName>`
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FunctionName,
        [Parameter(Mandatory)] [string] $AgentsDir
    )

    if (-not (Test-Path $AgentsDir)) { return $null }
    $files = Get-ChildItem -Path $AgentsDir -Filter "*.ps1" -ErrorAction SilentlyContinue
    $pattern = "function\s+" + [regex]::Escape($FunctionName) + "\s*[\{\(]"
    foreach ($f in $files) {
        try {
            $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($content -and ($content -match $pattern)) {
                return $f.Name
            }
        } catch {}
    }
    return $null
}


function Test-RunspaceLibsComplete {
    <#
    .SYNOPSIS
        Cruza Get-Command refs no orchestrator vs libs listadas no parallel.
        Retorna PSCustomObject @{all_covered, missing_libs, orphan_refs, covered_refs}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OrchestratorPath,
        [Parameter(Mandatory)] [string] $ParallelPath,
        [Parameter(Mandatory)] [string] $AgentsDir
    )

    $refs = Get-OrchestratorGetCommandRefs -Path $OrchestratorPath
    $libsList = Get-ParallelRunspaceLibsList -Path $ParallelPath

    $missingLibs = New-Object System.Collections.Generic.HashSet[string]
    $orphanRefs  = New-Object System.Collections.Generic.List[string]
    $coveredRefs = New-Object System.Collections.Generic.List[string]

    foreach ($funcName in $refs) {
        $definingLib = Find-LibDefiningFunction -FunctionName $funcName -AgentsDir $AgentsDir
        if (-not $definingLib) {
            [void]$orphanRefs.Add($funcName)
            continue
        }
        if ($libsList -contains $definingLib) {
            [void]$coveredRefs.Add($funcName)
        } else {
            [void]$missingLibs.Add($definingLib)
        }
    }

    return [PSCustomObject]@{
        all_covered    = ($missingLibs.Count -eq 0)
        missing_libs   = @($missingLibs)
        orphan_refs    = @($orphanRefs)
        covered_refs   = @($coveredRefs)
        total_refs     = $refs.Count
        total_libs     = $libsList.Count
    }
}

# lib_gate_safety.ps1 -- Fail-closed gate helper + audit utility.
#
# Vulnerability #4 mitigation: catch silent em gates pode resultar em "trade
# liberado por erro" (fail-open). Esta lib provides:
#
#   1. Resolve-GateError(GateName, ErrorMessage):
#      Standardized PSCustomObject @{passes=$false, reason="fail_closed:..."}
#      Use em catch blocks: catch { return Resolve-GateError "X" $_ }
#
#   2. Test-CatchPatternFailClosed(Code):
#      Static analysis: detecta padroes 'catch {}' OR catch sem fail-handling.


function Resolve-GateError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $GateName,
        [string] $ErrorMessage = ""
    )
    # Sempre fail-closed: passes=$false em error path
    return [PSCustomObject]@{
        gate    = $GateName
        passes  = $false
        reason  = "fail_closed:${GateName}_error"
        error   = $ErrorMessage
        ts      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}


function Test-CatchPatternFailClosed {
    # Static analysis: parse code text + detecta padroes risky em catch blocks.
    # Heuristica simples: catch {} OR catch { ; } (empty body) = fail-open risk.
    # Boa pratica: catch deve logar (Write-Warning/Write-Host) + retornar fail-closed.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Code
    )
    $issues = New-Object System.Collections.Generic.List[object]
    # Pattern 1: catch{}, catch { }, catch {\n}
    $emptyMatches = [regex]::Matches($Code, '(?ms)catch\s*\{\s*\}')
    foreach ($m in $emptyMatches) {
        $lineNum = ($Code.Substring(0, $m.Index) -split "`n").Count
        $issues.Add([PSCustomObject]@{
            line    = $lineNum
            type    = "empty_catch"
            snippet = $m.Value
        })
    }
    return ,$issues.ToArray()
}


function Get-FailClosedAuditReport {
    # Audita um file completo + retorna issues + sugestoes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath
    )
    if (-not (Test-Path $FilePath)) {
        return [PSCustomObject]@{ file = $FilePath; error = "file_not_found"; issues = @() }
    }
    $code = Get-Content $FilePath -Raw
    $issues = Test-CatchPatternFailClosed -Code $code
    return [PSCustomObject]@{
        file       = $FilePath
        issues     = $issues
        issue_count = $issues.Count
    }
}

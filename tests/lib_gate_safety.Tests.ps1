# lib_gate_safety.Tests.ps1 -- TDD pra fail-closed gate helper.
# Pester 3.x.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_gate_safety.ps1")


Describe "Resolve-GateError" {
    It "ErrorMessage informativo retorna passes=false" {
        $r = Resolve-GateError -GateName "FundingGate" -ErrorMessage "parse_failed"
        $r.passes | Should Be $false
        $r.reason | Should Match "fail_closed"
        $r.error | Should Match "parse_failed"
        $r.gate | Should Be "FundingGate"
    }
    It "ErrorMessage vazio retorna passes=false default" {
        $r = Resolve-GateError -GateName "X"
        $r.passes | Should Be $false
    }
    It "Default fail-closed sempre nega trade" {
        # Garantia: NUNCA retorna passes=true em error path
        for ($i=0; $i -lt 10; $i++) {
            $r = Resolve-GateError -GateName "X" -ErrorMessage "noise_$i"
            $r.passes | Should Be $false
        }
    }
}


Describe "Test-CatchPatternFailClosed - audit helper" {
    It "Detecta gates com catch{} silencioso (fail-open potencial)" {
        $code = @"
function Test-Bad {
    try { something_might_fail }
    catch {}
    return @{ passes = `$true }
}
"@
        $issues = Test-CatchPatternFailClosed -Code $code
        $issues.Count | Should BeGreaterThan 0
    }
    It "Codigo com catch logado: passa audit" {
        $code = @"
function Test-Good {
    try { something }
    catch { Write-Warning "X falhou: `$_"; return @{ passes = `$false } }
}
"@
        $issues = Test-CatchPatternFailClosed -Code $code
        $issues.Count | Should Be 0
    }
}

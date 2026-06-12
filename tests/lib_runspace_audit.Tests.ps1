# lib_runspace_audit.Tests.ps1 -- Pester 3.x
#
# Test-RunspaceLibsComplete: preventivo contra bug "lib orfa em runspace".
# Cruza Get-Command refs no orchestrator vs lista hardcoded de libs no parallel.
# Se funcao referenciada mora em lib NAO listada -> alerta gap.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_runspace_audit.ps1"


function New-TmpDir { Join-Path $env:TEMP "rsaudit_$([Guid]::NewGuid())" }


Describe "Get-OrchestratorGetCommandRefs - parse Get-Command refs" {

    It "Extrai nomes de Get-Command X -ErrorAction SilentlyContinue" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $f = Join-Path $tmp "fake_orch.ps1"
        @"
if (Get-Command Foo-Bar -ErrorAction SilentlyContinue) { Foo-Bar }
if (Get-Command Test-Baz -ErrorAction SilentlyContinue) {
    Test-Baz -X 1
}
"@ | Out-File $f -Encoding utf8
        $refs = Get-OrchestratorGetCommandRefs -Path $f
        ($refs -contains "Foo-Bar") | Should Be $true
        ($refs -contains "Test-Baz") | Should Be $true
        Remove-Item $tmp -Recurse -Force
    }

    It "Ignora Get-Command sem SilentlyContinue (cmd directs)" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $f = Join-Path $tmp "fake.ps1"
        @"
if (Get-Command Foo-Bar -ErrorAction SilentlyContinue) { Foo-Bar }
Get-Command Test-Baz   # nao eh padrao defensivo, ignorar
"@ | Out-File $f -Encoding utf8
        $refs = Get-OrchestratorGetCommandRefs -Path $f
        ($refs -contains "Foo-Bar") | Should Be $true
        ($refs -contains "Test-Baz") | Should Be $false
        Remove-Item $tmp -Recurse -Force
    }

    It "Retorna array vazio quando arquivo nao tem Get-Command refs" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $f = Join-Path $tmp "empty.ps1"
        "function Foo { return 1 }" | Out-File $f -Encoding utf8
        $refs = Get-OrchestratorGetCommandRefs -Path $f
        @($refs).Count | Should Be 0
        Remove-Item $tmp -Recurse -Force
    }
}


Describe "Get-ParallelRunspaceLibsList - parse hardcoded list" {

    It "Extrai libs do array hardcoded '\$libs = @(...)' no parallel script" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $f = Join-Path $tmp "fake_par.ps1"
        @'
function Run {
    $libs = @(
        "config.ps1","lib_a.ps1","lib_b.ps1",
        "lib_c.ps1"
    )
    foreach ($l in $libs) { . $l }
}
'@ | Out-File $f -Encoding utf8
        $libs = Get-ParallelRunspaceLibsList -Path $f
        ($libs -contains "config.ps1") | Should Be $true
        ($libs -contains "lib_a.ps1") | Should Be $true
        ($libs -contains "lib_c.ps1") | Should Be $true
        @($libs).Count | Should Be 4
        Remove-Item $tmp -Recurse -Force
    }

    It "Retorna vazio se nao encontra padrao \$libs = @(...)" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $f = Join-Path $tmp "no_libs.ps1"
        'Write-Host "no libs here"' | Out-File $f -Encoding utf8
        $libs = Get-ParallelRunspaceLibsList -Path $f
        @($libs).Count | Should Be 0
        Remove-Item $tmp -Recurse -Force
    }
}


Describe "Find-LibDefiningFunction - localiza lib por nome de funcao" {

    It "Acha lib que define 'function Foo-Bar'" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $lib1 = Join-Path $tmp "lib_one.ps1"
        $lib2 = Join-Path $tmp "lib_two.ps1"
        "function Foo-Bar { return 1 }" | Out-File $lib1 -Encoding utf8
        "function Test-Baz { return 2 }" | Out-File $lib2 -Encoding utf8

        $result = Find-LibDefiningFunction -FunctionName "Foo-Bar" -AgentsDir $tmp
        $result | Should Be "lib_one.ps1"
        Remove-Item $tmp -Recurse -Force
    }

    It "Retorna `$null se funcao nao existe em nenhuma lib" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        "function Foo { return 1 }" | Out-File (Join-Path $tmp "lib.ps1") -Encoding utf8
        $result = Find-LibDefiningFunction -FunctionName "Inexistente" -AgentsDir $tmp
        $result | Should Be $null
        Remove-Item $tmp -Recurse -Force
    }
}


Describe "Test-RunspaceLibsComplete - integracao" {

    It "all_covered=true quando todas refs estao em libs listadas" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        # Orchestrator usa Foo-Bar
        $orch = Join-Path $tmp "orch.ps1"
        "if (Get-Command Foo-Bar -ErrorAction SilentlyContinue) { Foo-Bar }" | Out-File $orch -Encoding utf8
        # Lib_a define Foo-Bar
        "function Foo-Bar { return 1 }" | Out-File (Join-Path $tmp "lib_a.ps1") -Encoding utf8
        # Parallel inclui lib_a
        $par = Join-Path $tmp "par.ps1"
        @'
$libs = @("lib_a.ps1")
'@ | Out-File $par -Encoding utf8

        $r = Test-RunspaceLibsComplete -OrchestratorPath $orch -ParallelPath $par -AgentsDir $tmp
        $r.all_covered | Should Be $true
        @($r.missing_libs).Count | Should Be 0
        Remove-Item $tmp -Recurse -Force
    }

    It "all_covered=false + missing_libs quando funcao usa lib nao listada" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        # Orchestrator usa Foo-Bar E Test-Baz
        $orch = Join-Path $tmp "orch.ps1"
        @"
if (Get-Command Foo-Bar -ErrorAction SilentlyContinue) { Foo-Bar }
if (Get-Command Test-Baz -ErrorAction SilentlyContinue) { Test-Baz }
"@ | Out-File $orch -Encoding utf8
        "function Foo-Bar { return 1 }" | Out-File (Join-Path $tmp "lib_a.ps1") -Encoding utf8
        "function Test-Baz { return 2 }" | Out-File (Join-Path $tmp "lib_b.ps1") -Encoding utf8
        # Parallel SO inclui lib_a -- lib_b orfa
        $par = Join-Path $tmp "par.ps1"
        @'
$libs = @("lib_a.ps1")
'@ | Out-File $par -Encoding utf8

        $r = Test-RunspaceLibsComplete -OrchestratorPath $orch -ParallelPath $par -AgentsDir $tmp
        $r.all_covered | Should Be $false
        ($r.missing_libs -contains "lib_b.ps1") | Should Be $true
        Remove-Item $tmp -Recurse -Force
    }

    It "orphan_refs quando funcao nao existe em nenhuma lib" {
        $tmp = New-TmpDir; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $orch = Join-Path $tmp "orch.ps1"
        "if (Get-Command Phantom-Func -ErrorAction SilentlyContinue) { Phantom-Func }" | Out-File $orch -Encoding utf8
        $par = Join-Path $tmp "par.ps1"
        '$libs = @()' | Out-File $par -Encoding utf8

        $r = Test-RunspaceLibsComplete -OrchestratorPath $orch -ParallelPath $par -AgentsDir $tmp
        ($r.orphan_refs -contains "Phantom-Func") | Should Be $true
        Remove-Item $tmp -Recurse -Force
    }
}


Describe "Test-RunspaceLibsComplete - cenario REAL (orchestrator_v6 + parallel)" {

    It "Atual config (pos-PM3 fix) NAO tem libs faltantes criticas" {
        $orch  = Join-Path $here "..\agents\orchestrator_v6.ps1"
        $par   = Join-Path $here "..\agents\lib_orchestrator_parallel.ps1"
        $agents = Join-Path $here "..\agents"
        if (-not (Test-Path $orch) -or -not (Test-Path $par)) {
            Set-TestInconclusive "files nao existem"
            return
        }
        $r = Test-RunspaceLibsComplete -OrchestratorPath $orch -ParallelPath $par -AgentsDir $agents
        # Tolera orphan_refs (funcoes built-in ou de libs externas)
        # Mas missing_libs (lib existe em agents/ mas nao no parallel list) deve ser zero
        if (-not $r.all_covered) {
            Write-Host "DEBUG missing_libs: $($r.missing_libs -join ', ')" -ForegroundColor Yellow
            Write-Host "DEBUG orphan_refs: $($r.orphan_refs -join ', ')" -ForegroundColor Yellow
        }
        # Critical libs devem estar listadas pos-PM3
        $criticalLibs = @("lib_fundamental_quality.ps1","lib_pump_buy_gate.ps1","lib_order_routed.ps1","lib_entry_score_boost.ps1","lib_market_router_wire.ps1")
        foreach ($lib in $criticalLibs) {
            ($r.missing_libs -contains $lib) | Should Be $false
        }
    }
}

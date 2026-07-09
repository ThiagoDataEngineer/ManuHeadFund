# boot_integrity.Tests.ps1 — TDD guarda de boot (Pester 3.4) — 2026-07-09
# NUNCA MAIS: lib com parse error carrega em silencio -> funcao some -> daemon
# roda 20h quebrado (caso real: lib_trailing 1 parentese = SL trailing morto).
# Contrato:
#   Test-LibsParseClean  -> @{ clean; broken=@(@{file;line;message}) }
#   Assert-BootIntegrity -DaemonName X -CriticalFunctions @(...) -> @{ ok; broken_libs; missing_functions; message }
#   ok=$false => daemon deve FAIL-CLOSED (regra 5: erro = BLOCK, nunca passa por default)

$here = Split-Path $PSScriptRoot -Parent
$libPath = Join-Path $here "agents\lib_boot_integrity.ps1"

# Dot-source no escopo do ARQUIVO (nunca dentro de funcao — bug classe 2026-07-02)
. $libPath

Describe "Test-LibsParseClean" {

    It "detecta lib quebrada em diretorio temporario" {
        $tmp = Join-Path $env:TEMP ("bootint_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Set-Content -Path (Join-Path $tmp "lib_ok.ps1") -Value 'function Get-Ok { return 1 }' -Encoding UTF8
        Set-Content -Path (Join-Path $tmp "lib_broken.ps1") -Value 'function Get-Broken { $x = ($y ?? 0) }' -Encoding UTF8

        $r = Test-LibsParseClean -AgentsDir $tmp
        $r.clean | Should Be $false
        @($r.broken).Count | Should Be 1
        @($r.broken)[0].file | Should Be "lib_broken.ps1"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "retorna clean=true quando todas parseiam" {
        $tmp = Join-Path $env:TEMP ("bootint_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Set-Content -Path (Join-Path $tmp "lib_ok.ps1") -Value 'function Get-Ok { return 1 }' -Encoding UTF8

        $r = Test-LibsParseClean -AgentsDir $tmp
        $r.clean | Should Be $true
        @($r.broken).Count | Should Be 0
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "producao: agents/ REAL esta 100% limpo (regressao viva)" {
        $r = Test-LibsParseClean -AgentsDir (Join-Path $here "agents")
        if (-not $r.clean) {
            @($r.broken) | ForEach-Object { Write-Host "  BROKEN: $($_.file) L$($_.line): $($_.message)" }
        }
        $r.clean | Should Be $true
    }
}

Describe "Assert-BootIntegrity" {

    It "ok=false quando funcao critica esta ausente" {
        Remove-Item Function:\Invoke-FuncaoInexistenteXyz -ErrorAction SilentlyContinue
        $r = Assert-BootIntegrity -DaemonName "test_daemon" `
            -CriticalFunctions @("Invoke-FuncaoInexistenteXyz") `
            -AgentsDir (Join-Path $here "agents") -NoAlert
        $r.ok | Should Be $false
        @($r.missing_functions) -contains "Invoke-FuncaoInexistenteXyz" | Should Be $true
    }

    It "ok=true quando parse limpo e funcoes existem" {
        function global:Invoke-FuncaoTesteBootOk { return 1 }
        $r = Assert-BootIntegrity -DaemonName "test_daemon" `
            -CriticalFunctions @("Invoke-FuncaoTesteBootOk") `
            -AgentsDir (Join-Path $here "agents") -NoAlert
        $r.ok | Should Be $true
        Remove-Item Function:\Invoke-FuncaoTesteBootOk -ErrorAction SilentlyContinue
    }

    It "mensagem nomeia o daemon e o problema (diagnostico direto)" {
        $r = Assert-BootIntegrity -DaemonName "scan_master" `
            -CriticalFunctions @("Invoke-FuncaoInexistenteXyz") `
            -AgentsDir (Join-Path $here "agents") -NoAlert
        $r.message | Should Match "scan_master"
        $r.message | Should Match "Invoke-FuncaoInexistenteXyz"
    }
}

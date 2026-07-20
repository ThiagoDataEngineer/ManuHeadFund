# cross_platform_paths.Tests.ps1 -- regressao: paths cross-platform no cloud-trading.
# Bug pego na validacao: 'Join-Path $x "journal\flag"' -> no ubuntu vira nome literal
# 'journal\flag' -> Test-Path nao acha -> trava dry furada -> live no 1o ciclo.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Cross-platform paths (ubuntu-ready)" {

    It "gem_loop.ps1 nao tem backslash-path literal (journal\\ logs\\ agents\\)" {
        $gl = Get-Content ".\scripts\gem_loop.ps1" -Raw
        # backslash seguido de palavra dentro de string, em path conhecido
        ($gl -match '"[^"]*(journal|agents|logs|daemon_locks)\\[a-z_]') | Should Be $false
    }

    It "o check do CLOUD_DRY_RUN usa Join-Path aninhado (nao backslash)" {
        $gl = Get-Content ".\scripts\gem_loop.ps1" -Raw
        $gl | Should Match 'CLOUD_DRY_RUN\.flag'
        ($gl -match 'journal\\CLOUD_DRY_RUN') | Should Be $false
    }

    It "trailing_stop_monitor (online JOB1) ja era cross-platform" {
        $m = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw
        # usa lib_cross_platform / Join-Path; nao deve ter cmd/c chcp
        ($m -match 'cmd /c|chcp') | Should Be $false
    }
}

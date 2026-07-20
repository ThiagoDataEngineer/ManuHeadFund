# cutover_online.Tests.ps1 -- cutover: local daemon para, cloud (-Once) assume.
# Gate: LOCAL_TRADING_DISABLED.flag faz gem_loop/scan_master em modo LOOP sair (exit 0),
# mas -Once (nuvem) BYPASSA. Evita double-trade local+nuvem. CLOUD_DRY_RUN removido = live.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Cutover online (local para, nuvem assume)" {

    Context "gem_loop gate" {
        BeforeAll { $script:gl = Get-Content ".\scripts\gem_loop.ps1" -Raw }
        It "checa LOCAL_TRADING_DISABLED.flag" { $script:gl | Should Match "LOCAL_TRADING_DISABLED" }
        It "gate exige -not Once (cloud -Once bypassa)" {
            ($script:gl -match 'LOCAL_TRADING_DISABLED[^\n]*-not \$Once' -or $script:gl -match '-not \$Once[^\n]*LOCAL_TRADING_DISABLED') | Should Be $true
        }
        It "sintaxe OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize($script:gl,[ref]$err); $err.Count | Should Be 0
        }
    }

    Context "scan_master gate" {
        BeforeAll { $script:sm = Get-Content ".\scripts\scan_master.ps1" -Raw }
        It "checa LOCAL_TRADING_DISABLED.flag" { $script:sm | Should Match "LOCAL_TRADING_DISABLED" }
        It "sintaxe OK" {
            $err=$null; [void][System.Management.Automation.PSParser]::Tokenize($script:sm,[ref]$err); $err.Count | Should Be 0
        }
    }

    Context "Flags do cutover" {
        It "LOCAL_TRADING_DISABLED.flag presente (local off)" {
            Test-Path ".\journal\LOCAL_TRADING_DISABLED.flag" | Should Be $true
        }
        It "CLOUD_DRY_RUN.flag REMOVIDO (cloud live)" {
            Test-Path ".\journal\CLOUD_DRY_RUN.flag" | Should Be $false
        }
        It "LIVE_MODE_ENABLED.flag presente (cloud trada live)" {
            Test-Path ".\journal\LIVE_MODE_ENABLED.flag" | Should Be $true
        }
    }
}

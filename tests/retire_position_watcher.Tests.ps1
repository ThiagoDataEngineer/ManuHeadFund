# retire_position_watcher.Tests.ps1 -- #1: aposentar position_watcher (online cobre)
# watchdog_paper + daily_daemon_restart paravam de revive-lo so com o flag
# POSITION_WATCHER_DISABLED.flag (reversivel). Trailing agora e online (JOB1).
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Aposentar position_watcher (gated, reversivel)" {

    Context "watchdog_paper respeita o flag" {
        BeforeAll { $script:wd = Get-Content ".\scripts\watchdog_paper.ps1" -Raw }
        It "checa POSITION_WATCHER_DISABLED.flag antes de respawn" {
            $script:wd | Should Match "POSITION_WATCHER_DISABLED"
        }
        It "ainda tem a logica de respawn (so gated, nao removida)" {
            $script:wd | Should Match "position_watcher ressuscitado|respawn"
        }
    }

    Context "daily_daemon_restart respeita o flag" {
        BeforeAll { $script:dr = Get-Content ".\scripts\daily_daemon_restart.ps1" -Raw }
        It "filtra position_watcher quando flag presente" {
            $script:dr | Should Match "POSITION_WATCHER_DISABLED"
        }
    }

    Context "Flag existe (aposentado por default agora)" {
        It "POSITION_WATCHER_DISABLED.flag presente" {
            Test-Path ".\journal\POSITION_WATCHER_DISABLED.flag" | Should Be $true
        }
    }

    Context "Sintaxe preservada" {
        It "watchdog_paper sintaxe OK" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\watchdog_paper.ps1" -Raw), [ref]$err)
            $err.Count | Should Be 0
        }
        It "daily_daemon_restart sintaxe OK" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content ".\scripts\daily_daemon_restart.ps1" -Raw), [ref]$err)
            $err.Count | Should Be 0
        }
    }
}

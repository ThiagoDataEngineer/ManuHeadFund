# watchdog_tg_listener.Tests.ps1 -- Pester 3.x
# Test que funcoes Get-TgListenerProcess / Test-TgListenerAlive / Start-TgListener
# existem no watchdog_paper.ps1 (smoke; testes funcionais reais usariam mock CIM).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$watchdogScript = Join-Path $here "..\scripts\watchdog_paper.ps1"


Describe "watchdog_paper.ps1 - tg_listener support" {
    It "Define Get-TgListenerProcess" {
        $content = Get-Content $watchdogScript -Raw -Encoding UTF8
        $content | Should Match "function Get-TgListenerProcess"
    }

    It "Define Test-TgListenerAlive" {
        $content = Get-Content $watchdogScript -Raw -Encoding UTF8
        $content | Should Match "function Test-TgListenerAlive"
    }

    It "Define Start-TgListener" {
        $content = Get-Content $watchdogScript -Raw -Encoding UTF8
        $content | Should Match "function Start-TgListener"
    }

    It "Filter procura por telegram_listener.ps1" {
        $content = Get-Content $watchdogScript -Raw -Encoding UTF8
        $content | Should Match "telegram_listener.ps1"
    }

    It "Tem param NoTgListener pra opt-out" {
        $content = Get-Content $watchdogScript -Raw -Encoding UTF8
        $content | Should Match "NoTgListener"
    }
}


Describe "watchdog parse OK pos-edit" {
    It "Script parseia sem erros" {
        { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $watchdogScript -Raw -Encoding UTF8), [ref]$null) } | Should Not Throw
    }
}

# TDD: A5 — Daemon singleton audit

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $projectRoot "scripts"
$agentsDir = Join-Path $projectRoot "agents"

$expectedDaemons = @(
    "gem_loop"
    "scan_master"
    "telegram_listener"
    "watchdog_paper"
    "faro_v3_schedule"
)

Describe "A5: Daemon Singleton Audit" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_daemon_audit_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $agentsDir "lib_daemon_singleton_audit.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "lib_daemon_singleton.ps1 existe em agents/" {
        $singletonLib = Join-Path $agentsDir "lib_daemon_singleton.ps1"
        Test-Path $singletonLib | Should Be $true
    }

    It "todos 5 daemons existem em scripts/" {
        foreach ($daemon in $expectedDaemons) {
            $daemonScript = Join-Path $scriptsDir "$daemon.ps1"
            Test-Path $daemonScript | Should Be $true
        }
    }

    It "Invoke-DaemonSingletonAudit existe" {
        $cmd = Get-Command Invoke-DaemonSingletonAudit -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "daemon_singleton_audit.jsonl pode ser criado" {
        if (Get-Command Invoke-DaemonSingletonAudit -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "daemon_singleton_audit.jsonl"
            $null = Invoke-DaemonSingletonAudit -JournalDir $journalDir

            Test-Path $auditPath | Should Be $true
        }
    }

    It "audit registra status de cada daemon" {
        if (Get-Command Invoke-DaemonSingletonAudit -ErrorAction SilentlyContinue) {
            $result = Invoke-DaemonSingletonAudit -JournalDir $journalDir

            ($result -ne $null) | Should Be $true
            ($result.daemons -ne $null) | Should Be $true
            ($result.daemons.Count -eq 5) | Should Be $true
        }
    }

    It "lockfiles sao validos JSON" {
        $lockDir = Join-Path $journalDir "locks"
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null

        $testLock = @{
            name = "gem_loop"
            pid = $PID
            start_ticks = (Get-Process -Id $PID).StartTime.Ticks
            ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json

        $lockPath = Join-Path $lockDir "gem_loop.lock"
        $testLock | Out-File -FilePath $lockPath -Encoding utf8 -Force

        $lock = Get-Content $lockPath | ConvertFrom-Json -ErrorAction SilentlyContinue
        ($lock.name -eq "gem_loop") | Should Be $true
    }
}

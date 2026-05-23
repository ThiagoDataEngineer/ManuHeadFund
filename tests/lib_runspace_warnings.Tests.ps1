# lib_runspace_warnings.Tests.ps1 -- Pester 3.x

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_runspace_warnings.ps1"

# Stub Write-Warning pra capturar
$global:CAPTURED_WARNINGS = @()
function Write-Warning { param($Message) $global:CAPTURED_WARNINGS += $Message }

Describe "Test-CommandAvailable" {

    BeforeEach { $global:CAPTURED_WARNINGS = @() }

    It "Retorna `$true para funcao existente" {
        function _MyTestFunc { return 1 }
        $r = Test-CommandAvailable -Name "_MyTestFunc" -Context "test" -Silent
        $r | Should Be $true
    }

    It "Retorna `$false para funcao inexistente" {
        $tmpDir = Join-Path $env:TEMP "rsw_$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $tmpDir
        $r = Test-CommandAvailable -Name "InexistentFunc_$([Guid]::NewGuid())" -Context "test" -Silent
        $r | Should Be $false
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }

    It "Emite Warning quando funcao missing e nao Silent" {
        $tmpDir = Join-Path $env:TEMP "rsw_$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $tmpDir
        Test-CommandAvailable -Name "InexistentForWarn" -Context "test_warn" | Out-Null
        @($global:CAPTURED_WARNINGS).Count -ge 1 | Should Be $true
        ($global:CAPTURED_WARNINGS[0] -match "InexistentForWarn") | Should Be $true
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }

    It "Loga em journal/missing_commands.jsonl quando missing" {
        $tmpDir = Join-Path $env:TEMP "rsw_$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $tmpDir
        Test-CommandAvailable -Name "MissingLogged" -Context "ctx1" -Silent | Out-Null
        # Wait, Silent=true nao loga. Re-run sem Silent
        Test-CommandAvailable -Name "MissingLogged2" -Context "ctx2" | Out-Null
        $logFile = Join-Path $tmpDir "missing_commands.jsonl"
        (Test-Path $logFile) | Should Be $true
        $lines = Get-Content $logFile -Encoding UTF8
        ($lines | Where-Object { $_ -match "MissingLogged2" }).Count -ge 1 | Should Be $true
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }

    It "Silent suprime warning E log" {
        $tmpDir = Join-Path $env:TEMP "rsw_$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $tmpDir
        $logFile = Join-Path $tmpDir "missing_commands.jsonl"
        Test-CommandAvailable -Name "SilentTest" -Context "test" -Silent | Out-Null
        # Sem warning
        @($global:CAPTURED_WARNINGS).Count | Should Be 0
        # Sem log
        (Test-Path $logFile) | Should Be $false
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }
}


Describe "Get-MissingCommandsReport" {

    It "Retorna total=0 quando journal vazio/inexistente" {
        $tmpDir = Join-Path $env:TEMP "rsr_$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $r = Get-MissingCommandsReport -JournalPath (Join-Path $tmpDir "missing_commands.jsonl")
        $r.total | Should Be 0
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Agrega por command + context corretamente" {
        $tmpDir = Join-Path $env:TEMP "rsr_$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $logFile = Join-Path $tmpDir "missing.jsonl"
        $now = (Get-Date).ToUniversalTime().ToString('o')
        $entries = @(
            @{ timestamp=$now; command="Foo"; context="orch_v6" },
            @{ timestamp=$now; command="Foo"; context="orch_v6" },
            @{ timestamp=$now; command="Bar"; context="gem_executor" }
        )
        $entries | ForEach-Object { ($_ | ConvertTo-Json -Compress) | Add-Content -Path $logFile -Encoding utf8 }

        $r = Get-MissingCommandsReport -JournalPath $logFile -LastHours 24
        $r.total | Should Be 3
        $r.by_command["Foo"] | Should Be 2
        $r.by_command["Bar"] | Should Be 1
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

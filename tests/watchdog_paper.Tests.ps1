# watchdog_paper.Tests.ps1
# TDD strict: watchdog que detecta paper trade morto e respawn.
# UTF-8 BOM. Pester 3.x.

$watchdogPath = "$PSScriptRoot\..\scripts\watchdog_paper.ps1"
$content = Get-Content $watchdogPath -Raw

# Extrai funcoes puras (sem rodar o loop principal)
if ($content -match '(?ms)(^function Test-PaperAlive\s*\{.*?^\})') { Invoke-Expression $matches[1] }
if ($content -match '(?ms)(^function Get-PaperProcess\s*\{.*?^\})') { Invoke-Expression $matches[1] }
if ($content -match '(?ms)(^function Test-LogActivity\s*\{.*?^\})') { Invoke-Expression $matches[1] }

Describe "Test-PaperAlive - detecta paper trade vivo" {

    It "retorna $false quando nenhum processo encontrado" {
        Mock Get-PaperProcess { return @() }
        Test-PaperAlive | Should Be $false
    }

    It "retorna $true quando ha 1 processo paper" {
        Mock Get-PaperProcess { return @([PSCustomObject]@{ ProcessId = 1234 }) }
        Test-PaperAlive | Should Be $true
    }

    It "retorna $true quando ha 2+ processos paper (espera estabilizacao)" {
        Mock Get-PaperProcess { return @(
            [PSCustomObject]@{ ProcessId = 1234 },
            [PSCustomObject]@{ ProcessId = 5678 }
        ) }
        Test-PaperAlive | Should Be $true
    }
}

Describe "Test-LogActivity - detecta log stale" {

    BeforeEach {
        $script:_testLog = Join-Path $env:TEMP "watchdog_test_log_$((Get-Random)).log"
    }

    AfterEach {
        if (Test-Path $script:_testLog) { Remove-Item $script:_testLog -Force }
    }

    It "retorna $false (stale) quando log nao existe" {
        Test-LogActivity -LogPath $script:_testLog -MaxAgeMinutes 30 | Should Be $false
    }

    It "retorna $true quando log foi escrito recentemente" {
        "fresh" | Out-File $script:_testLog -Force
        Test-LogActivity -LogPath $script:_testLog -MaxAgeMinutes 30 | Should Be $true
    }

    It "retorna $false quando log eh muito antigo" {
        "old" | Out-File $script:_testLog -Force
        (Get-Item $script:_testLog).LastWriteTime = (Get-Date).AddMinutes(-60)
        Test-LogActivity -LogPath $script:_testLog -MaxAgeMinutes 30 | Should Be $false
    }

    It "respeita MaxAgeMinutes custom (default seria diferente)" {
        "x" | Out-File $script:_testLog -Force
        (Get-Item $script:_testLog).LastWriteTime = (Get-Date).AddMinutes(-10)
        Test-LogActivity -LogPath $script:_testLog -MaxAgeMinutes 5 | Should Be $false
        Test-LogActivity -LogPath $script:_testLog -MaxAgeMinutes 15 | Should Be $true
    }
}

Describe "Get-PaperProcess - encontra scan_master rodando" {

    It "retorna vazio (null ou array vazio) se nada rodando" {
        $r = Get-PaperProcess -ProcessFilter "*process_que_nao_existe_xyz*"
        ($null -eq $r -or $r.Count -eq 0) | Should Be $true
    }
}

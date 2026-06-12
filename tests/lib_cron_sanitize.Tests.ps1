# lib_cron_sanitize.Tests.ps1 - TDD do planejador de saneamento de crons (2026-06-12)

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_cron_sanitize.ps1")

Describe "Get-CronSanitizePlan" {

    $repo = "C:\repo"
    $pwsh = "C:\pwsh\pwsh.exe"
    # fake filesystem: so estes paths existem
    $existing = @(
        "C:\repo\scripts\short_scanner.ps1",
        "C:\repo\scripts\faro_v3_engine.ps1"
    )
    $fakeTest = { param($p) $existing -contains $p }.GetNewClosure()

    It "SWITCH_ENGINE: powershell 5.1 com script existente vira pwsh (args preservados)" {
        $tasks = @([PSCustomObject]@{
            Name = "CoinExShortScanner"; State = "Ready"; Execute = "powershell.exe"
            Arguments = '-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "C:\repo\scripts\short_scanner.ps1"'
        })
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p[0].Action | Should Be "SWITCH_ENGINE"
        $p[0].NewExecute | Should Be $pwsh
        ($p[0].NewArguments -eq $tasks[0].Arguments) | Should Be $true
    }

    It "REPOINT: FARO apontando fora do repo reescreve path + troca engine" {
        $tasks = @([PSCustomObject]@{
            Name = "ManuHeadFund_FARO_V3_engine_agg"; State = "Ready"
            Execute = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
            Arguments = '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\thiag\scripts\faro_v3_engine.ps1"'
        })
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p[0].Action | Should Be "REPOINT"
        $p[0].NewExecute | Should Be $pwsh
        ($p[0].NewArguments -like '*C:\repo\scripts\faro_v3_engine.ps1*') | Should Be $true
        ($p[0].NewArguments -like '*thiag\scripts\faro*') | Should Be $false
    }

    It "MISSING: script ausente sem equivalente no repo so reporta (nao inventa)" {
        $tasks = @([PSCustomObject]@{
            Name = "CoinEx_Update_Dashboard_HTML"; State = "Ready"; Execute = "powershell.exe"
            Arguments = '-File "C:\repo\UPDATE_DASHBOARD_COMPLETO.ps1"'
        })
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p[0].Action | Should Be "MISSING"
        $p[0].NewExecute | Should Be $null
    }

    It "SKIP_DISABLED: task desabilitada nao e tocada mesmo com 5.1" {
        $tasks = @([PSCustomObject]@{
            Name = "CoinEx_Dashboard_Elite"; State = "Disabled"; Execute = "PowerShell.exe"
            Arguments = '-File "C:\repo\scripts\short_scanner.ps1"'
        })
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p[0].Action | Should Be "SKIP_DISABLED"
    }

    It "OK: ja pwsh com script existente nao gera mudanca" {
        $tasks = @([PSCustomObject]@{
            Name = "CoinExGood"; State = "Ready"; Execute = "C:\pwsh\pwsh.exe"
            Arguments = '-File "C:\repo\scripts\short_scanner.ps1"'
        })
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p[0].Action | Should Be "OK"
    }

    It "UNPARSEABLE: sem -File reporta sem mexer" {
        $tasks = @([PSCustomObject]@{
            Name = "CoinExWeird"; State = "Ready"; Execute = "powershell.exe"
            Arguments = '-Command "Get-Date"'
        })
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p[0].Action | Should Be "UNPARSEABLE"
    }

    It "batch: processa lista inteira mantendo 1 decisao por task" {
        $tasks = @(
            [PSCustomObject]@{ Name = "A"; State = "Ready"; Execute = "powershell.exe"; Arguments = '-File "C:\repo\scripts\short_scanner.ps1"' }
            [PSCustomObject]@{ Name = "B"; State = "Disabled"; Execute = "powershell.exe"; Arguments = '-File "x.ps1"' }
            [PSCustomObject]@{ Name = "C"; State = "Ready"; Execute = "powershell.exe"; Arguments = '-File "C:\nada\sumido.ps1"' }
        )
        $p = @(Get-CronSanitizePlan -Tasks $tasks -RepoRoot $repo -PwshExe $pwsh -TestPath $fakeTest)
        $p.Count | Should Be 3
        ($p | Where-Object { $_.Task -eq "A" }).Action | Should Be "SWITCH_ENGINE"
        ($p | Where-Object { $_.Task -eq "B" }).Action | Should Be "SKIP_DISABLED"
        ($p | Where-Object { $_.Task -eq "C" }).Action | Should Be "MISSING"
    }
}

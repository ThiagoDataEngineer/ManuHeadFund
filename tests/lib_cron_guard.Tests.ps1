# TDD do cron guard (decisao pura robusta a throttle do GH Actions).
$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_cron_guard.ps1")

Describe "Test-CronDue -- interval:N" {
    It "nunca rodou -> due" {
        Test-CronDue -Schedule "interval:60" -LastRunIso "" -NowUtc ([datetime]"2026-06-22T10:00:00Z") | Should Be $true
    }
    It "rodou ha 70min (>=60) -> due" {
        Test-CronDue -Schedule "interval:60" -LastRunIso "2026-06-22T08:50:00Z" -NowUtc ([datetime]"2026-06-22T10:00:00Z") | Should Be $true
    }
    It "rodou ha 40min (<60) -> NAO due" {
        Test-CronDue -Schedule "interval:60" -LastRunIso "2026-06-22T09:20:00Z" -NowUtc ([datetime]"2026-06-22T10:00:00Z") | Should Be $false
    }
    It "every30: ha 31min -> due" {
        Test-CronDue -Schedule "interval:30" -LastRunIso "2026-06-22T09:29:00Z" -NowUtc ([datetime]"2026-06-22T10:00:00Z") | Should Be $true
    }
}

Describe "Test-CronDue -- daily:H" {
    It "antes da hora alvo -> NAO due" {
        Test-CronDue -Schedule "daily:5" -LastRunIso "" -NowUtc ([datetime]"2026-06-22T03:00:00Z") | Should Be $false
    }
    It "na hora alvo, nunca rodou -> due" {
        Test-CronDue -Schedule "daily:5" -LastRunIso "" -NowUtc ([datetime]"2026-06-22T05:07:00Z") | Should Be $true
    }
    It "depois da hora alvo, ja rodou HOJE -> NAO due" {
        Test-CronDue -Schedule "daily:5" -LastRunIso "2026-06-22T05:07:00Z" -NowUtc ([datetime]"2026-06-22T11:00:00Z") | Should Be $false
    }
    It "rodou ONTEM, hoje passou da hora -> due" {
        Test-CronDue -Schedule "daily:5" -LastRunIso "2026-06-21T05:07:00Z" -NowUtc ([datetime]"2026-06-22T06:00:00Z") | Should Be $true
    }
}

Describe "Test-CronDue -- weekly:DAY:H" {
    It "dia errado -> NAO due" {
        # 2026-06-22 e Monday
        Test-CronDue -Schedule "weekly:Sunday:3" -LastRunIso "" -NowUtc ([datetime]"2026-06-22T10:00:00Z") | Should Be $false
    }
    It "dia certo (Monday) + hora ok + nunca rodou -> due" {
        Test-CronDue -Schedule "weekly:Monday:4" -LastRunIso "" -NowUtc ([datetime]"2026-06-22T04:30:00Z") | Should Be $true
    }
    It "dia certo mas ja rodou hoje -> NAO due" {
        Test-CronDue -Schedule "weekly:Monday:4" -LastRunIso "2026-06-22T04:30:00Z" -NowUtc ([datetime]"2026-06-22T09:00:00Z") | Should Be $false
    }
    It "dia certo, rodou semana passada -> due" {
        Test-CronDue -Schedule "weekly:Monday:4" -LastRunIso "2026-06-15T04:30:00Z" -NowUtc ([datetime]"2026-06-22T05:00:00Z") | Should Be $true
    }
}

Describe "Test-CronDue -- robustez" {
    It "schedule invalido -> erro" {
        $threw = $false
        try { Test-CronDue -Schedule "nonsense:1" -NowUtc ([datetime]"2026-06-22T10:00:00Z") } catch { $threw = $true }
        $threw | Should Be $true
    }
    It "now em horario local e convertido p/ UTC (nao quebra)" {
        # apenas garante que aceita Local sem excecao
        { Test-CronDue -Schedule "interval:60" -LastRunIso "" -NowUtc (Get-Date) } | Should Not Throw
    }
}

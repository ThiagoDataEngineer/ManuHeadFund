# mentor_time_context.Tests.ps1
# TDD: Get-TimeContext produz info pro Mentor sobre dia/hora/session.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\agents\lib_mentor_time_context.ps1"

Describe "Get-TimeContext" {

    It "retorna campos hour_utc, weekday, session, is_weekend" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-26 14:00:00Z")
        $t.hour_utc | Should Be 14
        $t.weekday | Should Be "Tuesday"
        $t.is_weekend | Should Be $false
    }

    It "classifica session ASIA quando UTC 0-7" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-26 03:00:00Z")
        $t.session | Should Be "ASIA"
    }

    It "classifica session EU_OVERLAP quando UTC 8-12" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-26 10:00:00Z")
        $t.session | Should Be "EU_OVERLAP"
    }

    It "classifica session US quando UTC 13-21" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-26 15:00:00Z")
        $t.session | Should Be "US"
    }

    It "classifica session LATE_US quando UTC 22-23" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-26 23:00:00Z")
        $t.session | Should Be "LATE_US"
    }

    It "detecta weekend (sabado)" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-30 12:00:00Z")
        $t.is_weekend | Should Be $true
    }

    It "detecta weekend (domingo)" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-31 12:00:00Z")
        $t.is_weekend | Should Be $true
    }
}

Describe "Format-TimeContextLine" {

    It "formata em string compacta legivel pro LLM" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-26 14:30:00Z")
        $line = Format-TimeContextLine -TimeContext $t
        $line | Should Match "Tuesday"
        $line | Should Match "14"
        $line | Should Match "US"
    }

    It "marca explicitamente 'WEEKEND_LOW_LIQUIDITY' quando weekend" {
        $t = Get-TimeContext -Now ([DateTime]"2026-05-30 12:00:00Z")
        $line = Format-TimeContextLine -TimeContext $t
        $line | Should Match "WEEKEND"
    }
}

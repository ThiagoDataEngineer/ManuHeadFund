# lib_gem_position_events.Tests.ps1 -- TDD pro fix critico 2026-07-29.
# Pester 3.4 / ASCII-only.
#
# Achado real: guard "CASCADING ADD POSITION PREVENTION" (gem_executor.ps1,
# 2026-07-07) lia journal/trade_outcomes.jsonl (arquivo LOCAL, nunca
# sobrevive no runner efemero do GitHub Actions) e comparava campos que
# nunca existiram no schema real (.market/.entry_date/status="open").
# DOGEUSDT SHORT recebeu 12 Add Positions reais em 17h sem o guard nunca
# bloquear. Fix: nova lib com fonte real (Supabase, tabela dedicada
# gem_position_events) registrada no momento exato de cada execucao.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
. ".\agents\lib_gem_position_events.ps1"

Describe "Add-GemPositionEvent" {

    It "sem Save-StateRecords disponivel -- nao lanca (fail-soft)" {
        if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
            Remove-Item function:Save-StateRecords -ErrorAction SilentlyContinue
        }
        { Add-GemPositionEvent -Market "TESTUSDT" -Side "SHORT" -UsdSize 100 -EventType "OPEN" } | Should Not Throw
    }

    It "com Save-StateRecords disponivel -- grava na tabela gem_position_events com schema manuheadfund" {
        $script:__savedTable = $null
        $script:__savedSchema = $null
        $script:__savedRecord = $null
        Set-Item function:Save-StateRecords -Value {
            param($Table, $Records, $PrimaryKey)
            $script:__savedTable = $Table
            $script:__savedSchema = $global:STATE_STORE_SCHEMA
            $script:__savedRecord = $Records[0]
        }
        Add-GemPositionEvent -Market "DOGEUSDT" -Side "SHORT" -UsdSize 250.5 -EventType "ADD"
        $script:__savedTable | Should Be "gem_position_events"
        $script:__savedSchema | Should Be "manuheadfund"
        $script:__savedRecord.market | Should Be "DOGEUSDT"
        $script:__savedRecord.side | Should Be "SHORT"
        $script:__savedRecord.event_type | Should Be "ADD"
        $script:__savedRecord.usd_size | Should Be 250.5
        Remove-Item function:Save-StateRecords -ErrorAction SilentlyContinue
    }

    It "excecao dentro de Save-StateRecords nunca propaga (fail-soft real)" {
        Set-Item function:Save-StateRecords -Value { param($Table, $Records, $PrimaryKey) throw "Supabase indisponivel" }
        { Add-GemPositionEvent -Market "TESTUSDT" -Side "LONG" -UsdSize 50 -EventType "OPEN" } | Should Not Throw
        Remove-Item function:Save-StateRecords -ErrorAction SilentlyContinue
    }
}

Describe "Get-RecentGemAddPositionCount" {

    It "sem Get-StateRecords disponivel -- retorna 0 (fail-soft)" {
        if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
            Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
        }
        Get-RecentGemAddPositionCount -Market "TESTUSDT" | Should Be 0
    }

    It "conta APENAS eventos ADD dentro da janela de HoursBack (default 6h)" {
        $nowUtc = (Get-Date).ToUniversalTime()
        Set-Item function:Get-StateRecords -Value {
            param($Table, $Filter)
            return @(
                [PSCustomObject]@{ market="DOGEUSDT"; event_type="ADD"; created_at=$nowUtc.AddHours(-1).ToString("o") },
                [PSCustomObject]@{ market="DOGEUSDT"; event_type="ADD"; created_at=$nowUtc.AddHours(-3).ToString("o") },
                [PSCustomObject]@{ market="DOGEUSDT"; event_type="ADD"; created_at=$nowUtc.AddHours(-8).ToString("o") }  # fora da janela de 6h
            )
        }
        $count = Get-RecentGemAddPositionCount -Market "DOGEUSDT" -HoursBack 6
        $count | Should Be 2
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
    }

    It "12 eventos ADD reais em 17h (caso real DOGEUSDT) -- conta corretamente os que caem na janela de 6h" {
        # simula o caso real: 12 adds espalhados em ~17h, apenas os das
        # ultimas 6h devem contar
        $nowUtc = (Get-Date).ToUniversalTime()
        $hoursAgoList = @(0.1, 1.0, 2.5, 4.0, 5.9, 6.1, 8.0, 10.0, 12.0, 14.0, 16.0, 17.0)
        $script:__simulatedRows = @($hoursAgoList | ForEach-Object {
            [PSCustomObject]@{ market="DOGEUSDT"; event_type="ADD"; created_at=$nowUtc.AddHours(-$_).ToString("o") }
        })
        Set-Item function:Get-StateRecords -Value { param($Table, $Filter) return $script:__simulatedRows }
        $count = Get-RecentGemAddPositionCount -Market "DOGEUSDT" -HoursBack 6
        $count | Should Be 5  # 0.1, 1.0, 2.5, 4.0, 5.9 estao dentro de 6h
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
    }

    It "excecao dentro da leitura nunca propaga -- fallback 0" {
        Set-Item function:Get-StateRecords -Value { param($Table, $Filter) throw "erro simulado" }
        { $script:__c = Get-RecentGemAddPositionCount -Market "TESTUSDT" } | Should Not Throw
        $script:__c | Should Be 0
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
    }
}

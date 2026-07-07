# tests/learning_supabase_mirror.Tests.ps1
# TDD (2026-07-07): espelho do cerebro evolutivo pro Supabase (schema manuheadfund).
# Cobre _Mirror-LearningToSupabase (helper compartilhado), o wire de Save-LearnedStats,
# o read-back de Get-LearnedStats, e as invariantes: best-effort (falha nao quebra
# write local), backend=local e no-op, schema sempre manuheadfund.
#
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_direction_learning.ps1")

Describe "_Mirror-LearningToSupabase (helper best-effort)" {

    BeforeEach {
        $global:__mirror_calls = @()
        $global:__mirror_schema_seen = $null
        # captura as chamadas de Save-StateRecords
        Set-Item function:Save-StateRecords -Value {
            param([string]$Table, [object[]]$Records, [string]$PrimaryKey)
            $global:__mirror_calls += [PSCustomObject]@{
                table = $Table; pk = $PrimaryKey; count = @($Records).Count
                schema = $global:STATE_STORE_SCHEMA
            }
        }
    }
    AfterEach {
        Remove-Item function:Save-StateRecords -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
        Remove-Item env:STATE_STORE_BACKEND -ErrorAction SilentlyContinue
        Remove-Variable -Name __mirror_calls, __mirror_schema_seen -Scope Global -ErrorAction SilentlyContinue
    }

    It "backend=supabase: chama Save-StateRecords com Table/PK e schema manuheadfund" {
        $global:STATE_STORE_BACKEND = "supabase"
        _Mirror-LearningToSupabase -Table "learned_multipliers" -PrimaryKey "key" -Records @(@{ key="a"; n=1 })
        $global:__mirror_calls.Count | Should Be 1
        $global:__mirror_calls[0].table | Should Be "learned_multipliers"
        $global:__mirror_calls[0].pk | Should Be "key"
        $global:__mirror_calls[0].schema | Should Be "manuheadfund"
    }

    It "backend=local: NO-OP (nao chama Save-StateRecords)" {
        $global:STATE_STORE_BACKEND = "local"
        _Mirror-LearningToSupabase -Table "learned_multipliers" -PrimaryKey "key" -Records @(@{ key="a" })
        $global:__mirror_calls.Count | Should Be 0
    }

    It "restaura o schema global apos a chamada" {
        $global:STATE_STORE_BACKEND = "supabase"
        $global:STATE_STORE_SCHEMA = "public"
        _Mirror-LearningToSupabase -Table "x" -PrimaryKey "key" -Records @(@{ key="a" })
        $global:STATE_STORE_SCHEMA | Should Be "public"
    }

    It "records vazio: nao chama nada" {
        $global:STATE_STORE_BACKEND = "supabase"
        _Mirror-LearningToSupabase -Table "x" -PrimaryKey "key" -Records @()
        $global:__mirror_calls.Count | Should Be 0
    }

    It "falha do Supabase NAO propaga (best-effort)" {
        $global:STATE_STORE_BACKEND = "supabase"
        Set-Item function:Save-StateRecords -Value { param($Table,$Records,$PrimaryKey) throw "boom supabase" }
        { _Mirror-LearningToSupabase -Table "x" -PrimaryKey "key" -Records @(@{ key="a" }) } | Should Not Throw
    }
}

Describe "Save-LearnedStats: write local + espelho Supabase" {

    BeforeEach {
        $script:tmp = Join-Path $env:TEMP "lm_$(Get-Random).json"
        $global:__mirror_calls = @()
        Set-Item function:Save-StateRecords -Value {
            param([string]$Table, [object[]]$Records, [string]$PrimaryKey)
            $global:__mirror_calls += [PSCustomObject]@{ table=$Table; pk=$PrimaryKey; recs=$Records; schema=$global:STATE_STORE_SCHEMA }
        }
    }
    AfterEach {
        Remove-Item $script:tmp -Force -ErrorAction SilentlyContinue
        Remove-Item function:Save-StateRecords -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name __mirror_calls -Scope Global -ErrorAction SilentlyContinue
    }

    $stats = @(
        [PSCustomObject]@{ key="regime|SHORT|BEAR_WEAK"; source="regime"; direction="SHORT"; regime="BEAR_WEAK"; n=10; wins=6; win_rate=0.6; avg_pnl_pct=1.2; sum_pnl=12.0; reliable=$true }
    )

    It "grava o JSONL local SEMPRE (mesmo backend=local)" {
        $global:STATE_STORE_BACKEND = "local"
        (Save-LearnedStats -Stats $stats -Path $script:tmp) | Should Be $true
        (Test-Path $script:tmp) | Should Be $true
        (Get-Content $script:tmp -Raw) | Should Match "BEAR_WEAK"
        $global:__mirror_calls.Count | Should Be 0
    }

    It "backend=supabase: espelha learned_multipliers com PK key e campos mapeados" {
        $global:STATE_STORE_BACKEND = "supabase"
        Save-LearnedStats -Stats $stats -Path $script:tmp | Out-Null
        $global:__mirror_calls.Count | Should Be 1
        $global:__mirror_calls[0].table | Should Be "learned_multipliers"
        $global:__mirror_calls[0].pk | Should Be "key"
        $global:__mirror_calls[0].schema | Should Be "manuheadfund"
        $global:__mirror_calls[0].recs[0].win_rate | Should Be 0.6
    }
}

Describe "Get-LearnedStats: read-back Supabase quando local vazio" {

    BeforeEach {
        Set-Item function:Get-StateRecords -Value {
            param([string]$Table, [hashtable]$Filter)
            return @([PSCustomObject]@{ key="regime|LONG|BULL_WEAK"; win_rate=0.7; reliable=$true })
        }
    }
    AfterEach {
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
    }

    It "local ausente + backend=supabase: hidrata do Supabase" {
        $global:STATE_STORE_BACKEND = "supabase"
        $r = @(Get-LearnedStats -Path (Join-Path $env:TEMP "nao_existe_$(Get-Random).json"))
        $r.Count | Should Be 1
        $r[0].key | Should Be "regime|LONG|BULL_WEAK"
    }

    It "backend=local + arquivo ausente: retorna vazio (sem tocar Supabase)" {
        $global:STATE_STORE_BACKEND = "local"
        $r = @(Get-LearnedStats -Path (Join-Path $env:TEMP "nao_existe_$(Get-Random).json"))
        $r.Count | Should Be 0
    }
}

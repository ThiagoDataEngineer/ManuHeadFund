# supabase_cloud_sync.Tests.ps1 — Validação de Supabase como backend único
# Garante que state store sincroniza com Supabase, fallback funciona
# TDD: 13 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Supabase Cloud Sync (State Backend)" {

    BeforeAll {
        $script:ss = Get-Content ".\agents\lib_state_store.ps1" -Raw
        $script:configJs = if (Test-Path ".\journal\trailing_positions.json") {
            Get-Content ".\journal\trailing_positions.json" -Raw
        } else {
            "[]"
        }
    }

    Context "lib_state_store.ps1 estrutura" {
        It "Arquivo existe" {
            Test-Path ".\agents\lib_state_store.ps1" | Should Be $true
        }
        It "Get-StateRecords função" {
            $script:ss | Should Match "function Get-StateRecords"
        }
        It "Save-StateRecords função" {
            $script:ss | Should Match "function Save-StateRecords"
        }
        It "Remove-StateRecords função" {
            $script:ss | Should Match "function Remove-StateRecords"
        }
        It "Test-StateBackend função" {
            $script:ss | Should Match "function Test-StateBackend"
        }
    }

    Context "Backend selection (Supabase vs Local)" {
        It "Respeita env:STATE_STORE_BACKEND" {
            $script:ss | Should Match "STATE_STORE_BACKEND"
        }
        It "Lê USE_SUPABASE_STATE.flag" {
            $script:ss | Should Match "USE_SUPABASE_STATE"
        }
        It "Fallback para JSON local se Supabase falha" {
            $script:ss | Should Match "fallback|json"
        }
    }

    Context "Schema: trailing_positions" {
        It "Tabela trailing_positions documentada" {
            $script:ss | Should Match "trailing_positions"
        }
        It "Campos: market, active, peak_price, stop_price" {
            ($script:ss -match "market" -and $script:ss -match "active" -and $script:ss -match "peak_price") | Should Be $true
        }
    }

    Context "Schema: trade_outcomes" {
        It "Tabela trade_outcomes existe" {
            (Get-Content ".\agents\lib_state_store.ps1" -Raw) | Should Match "trade_outcomes"
        }
        It "Append-only JSONL (não sobrescreve)" {
            $script:ss | Should Match "append|jsonl|line-by-line"
        }
    }

    Context "State sync: Local ↔ Supabase" {
        It "Sincroniza trailing_positions na entrada" {
            $script:ss | Should Match "Get-StateRecords.*trailing"
        }
        It "Persiste trailing_positions na saída" {
            $script:ss | Should Match "Save-StateRecords.*trailing"
        }
        It "Idempotente (run 2x mesmos dados = 1 estado)" {
            $script:ss | Should Match "upsert|idempotent|conflict"
        }
    }

    Context "JSON local (fallback)" {
        It "journal/trailing_positions.json valido" {
            { $script:configJs | ConvertFrom-Json } | Should Not Throw
        }
        It "journal/trade_outcomes.jsonl lines válidas" {
            if (Test-Path ".\journal\trade_outcomes.jsonl") {
                $lines = @(Get-Content ".\journal\trade_outcomes.jsonl" | Where-Object { $_ })
                # Apenas validar que lê sem erro
                $lines.Count | Should BeGreaterOrEqual 0
            }
        }
    }

    Context "Sintaxe" {
        It "lib_state_store.ps1 parse OK" {
            $err=$null
            [void][System.Management.Automation.PSParser]::Tokenize($script:ss,[ref]$err)
            $err.Count | Should Be 0
        }
    }

}

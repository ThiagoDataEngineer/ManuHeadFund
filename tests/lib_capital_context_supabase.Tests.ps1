# lib_capital_context.ps1 — Supabase backend integration TDD
#
# Etapa 2.1 — Refactor para usar state_store quando STATE_STORE_BACKEND=supabase.
# Back-compat: STATE_STORE_BACKEND=local (default) usa journal/capital_context.json.
#
# Estrategia:
#   - Get-CapitalContext continua API publica
#   - Internamente delega para Save-StateRecords/Get-StateRecords
#   - Tabela: 'capital_context' no schema 'manuheadfund'
#   - PrimaryKey: 'id' (sempre = 1, single-row table)

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_capital_context.ps1")

Describe "lib_capital_context: backend selection" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ccs_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
        # Ensure config legacy path is overridden (state_store handles dispatch)
        $script:CAPITAL_CONTEXT_PATH = Join-Path $script:tmpDir "capital_context.json"
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_LOCAL_DIR, STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
        Remove-Item env:STATE_STORE_BACKEND, env:STATE_STORE_SCHEMA -ErrorAction SilentlyContinue
    }

    It "Saves to local backend by default and persists" {
        # Mock CoinEx fetch. 2026-07-09: lib_capital_context so aceita o valor como
        # "fresh" se CAPITAL_*_LAST_REFRESH mudar (anti-poluicao Supabase) -- mock
        # precisa simular esse side effect, senao cai sempre no fallback.
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 800.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 1200.0 }

        $ctx = Get-CapitalContext -Force
        $ctx.spot | Should Be 800
        $ctx.futures | Should Be 1200
        $ctx.total | Should Be 2000

        Remove-Item function:CoinEx-GetSpotCapitalUSDT, function:CoinEx-GetFuturesCapitalUSDT
    }

    It "After save: Get-StateRecords returns 1 capital_context row" {
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 500.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 700.0 }

        Get-CapitalContext -Force | Out-Null

        $rows = @(Get-StateRecords -Table "capital_context")
        $rows.Count | Should Be 1
        $rows[0].total | Should Be 1200

        Remove-Item function:CoinEx-GetSpotCapitalUSDT, function:CoinEx-GetFuturesCapitalUSDT
    }

    It "Cache freshness: returns source=cached on second call within MaxAge" {
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 100.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 200.0 }

        $first = Get-CapitalContext -Force
        $first.source | Should Be "fresh"

        $second = Get-CapitalContext -MaxAgeMinutes 60
        $second.source | Should Be "cached"
        $second.total | Should Be 300

        Remove-Item function:CoinEx-GetSpotCapitalUSDT, function:CoinEx-GetFuturesCapitalUSDT
    }

    It "Force refresh ignores cache" {
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 100.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 200.0 }

        Get-CapitalContext -Force | Out-Null

        # Update CoinEx mock
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 999.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 1.0 }

        $forced = Get-CapitalContext -Force
        $forced.spot | Should Be 999
        $forced.total | Should Be 1000

        Remove-Item function:CoinEx-GetSpotCapitalUSDT, function:CoinEx-GetFuturesCapitalUSDT
    }
}

Describe "lib_capital_context: state_store integration sanity" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ccs2_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_LOCAL_DIR -Scope Global -ErrorAction SilentlyContinue
    }

    It "capital_context table file is created in state_store dir" {
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 50.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 50.0 }

        Get-CapitalContext -Force | Out-Null

        $expectedFile = Join-Path $script:tmpDir "capital_context.json"
        Test-Path $expectedFile | Should Be $true

        Remove-Item function:CoinEx-GetSpotCapitalUSDT, function:CoinEx-GetFuturesCapitalUSDT
    }

    It "Reads back across new Get-CapitalContext call (persistence)" {
        function CoinEx-GetSpotCapitalUSDT { $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date; return 333.0 }
        function CoinEx-GetFuturesCapitalUSDT { $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date; return 444.0 }

        Get-CapitalContext -Force | Out-Null

        # Simulate fresh call without re-fetching CoinEx (cache hit path)
        $rows = @(Get-StateRecords -Table "capital_context")
        $rows[0].spot | Should Be 333
        $rows[0].futures | Should Be 444

        Remove-Item function:CoinEx-GetSpotCapitalUSDT, function:CoinEx-GetFuturesCapitalUSDT
    }
}

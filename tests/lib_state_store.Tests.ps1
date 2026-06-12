# lib_state_store.ps1 contract TDD
#
# Objetivo: estabelecer interface CRUD generica pra estado persistente
# com 2 backends:
#   - "local"    : journal/<table>.json (legacy back-compat)
#   - "supabase" : Postgres via REST API (24/7 shared state)
#
# Backend selection:
#   - $env:STATE_STORE_BACKEND ("local" | "supabase", default "local")
#   - flag journal/USE_SUPABASE_STATE.flag override
#
# API minima (qualquer backend implementa):
#   - Get-StateRecords  -Table <name> [-Filter @{key=val}]
#   - Save-StateRecords -Table <name> -Records @(...) [-PrimaryKey "..."]
#   - Remove-StateRecord -Table <name> -PrimaryKey "..." -Value "..."
#   - Test-StateBackend (returns "local" | "supabase")
#
# Schema convencao: cada record e um PSCustomObject. PrimaryKey e o campo
# usado para upsert (default: "id" ou primeiro campo).

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")

Describe "Test-StateBackend" {

    AfterEach {
        Remove-Item env:STATE_STORE_BACKEND -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue
    }

    It "Default returns 'local' when no env var or flag" {
        Test-StateBackend | Should Be "local"
    }

    It "Returns 'supabase' when env var set" {
        $env:STATE_STORE_BACKEND = "supabase"
        Test-StateBackend | Should Be "supabase"
    }

    It "Global override beats env var" {
        $env:STATE_STORE_BACKEND = "supabase"
        $global:STATE_STORE_BACKEND = "local"
        Test-StateBackend | Should Be "local"
    }

    It "Invalid backend value falls back to 'local'" {
        $env:STATE_STORE_BACKEND = "invalid_xyz"
        Test-StateBackend | Should Be "local"
    }
}

Describe "Local backend - Get/Save-StateRecords" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ss_local_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_LOCAL_DIR -Scope Global -ErrorAction SilentlyContinue
    }

    It "Get-StateRecords returns empty array when table missing" {
        $rows = Get-StateRecords -Table "nonexistent"
        @($rows).Count | Should Be 0
    }

    It "Save-StateRecords writes JSON file to local dir" {
        $records = @(
            [PSCustomObject]@{ market = "BTCUSDT"; entry = 50000; phase = 0 }
            [PSCustomObject]@{ market = "ETHUSDT"; entry = 3000;  phase = 1 }
        )
        Save-StateRecords -Table "trailing_positions" -Records $records -PrimaryKey "market"
        $file = Join-Path $script:tmpDir "trailing_positions.json"
        Test-Path $file | Should Be $true
    }

    It "Save then Get round-trips records" {
        $records = @(
            [PSCustomObject]@{ market = "BTCUSDT"; entry = 50000 }
        )
        Save-StateRecords -Table "trailing_positions" -Records $records -PrimaryKey "market"
        $back = @(Get-StateRecords -Table "trailing_positions")
        $back.Count | Should Be 1
        $back[0].market | Should Be "BTCUSDT"
    }

    It "Save-StateRecords upserts by PrimaryKey (idempotent)" {
        Save-StateRecords -Table "t1" -Records @([PSCustomObject]@{ market = "A"; v = 1 }) -PrimaryKey "market"
        Save-StateRecords -Table "t1" -Records @([PSCustomObject]@{ market = "A"; v = 2 }) -PrimaryKey "market"
        $rows = @(Get-StateRecords -Table "t1")
        $rows.Count | Should Be 1
        $rows[0].v | Should Be 2
    }

    It "Save preserves existing records of different PrimaryKey" {
        Save-StateRecords -Table "t1" -Records @([PSCustomObject]@{ market = "A"; v = 1 }) -PrimaryKey "market"
        Save-StateRecords -Table "t1" -Records @([PSCustomObject]@{ market = "B"; v = 2 }) -PrimaryKey "market"
        $rows = @(Get-StateRecords -Table "t1")
        $rows.Count | Should Be 2
    }

    It "Get-StateRecords with Filter returns subset" {
        $records = @(
            [PSCustomObject]@{ market = "A"; active = $true }
            [PSCustomObject]@{ market = "B"; active = $false }
            [PSCustomObject]@{ market = "C"; active = $true }
        )
        Save-StateRecords -Table "t1" -Records $records -PrimaryKey "market"
        $active = @(Get-StateRecords -Table "t1" -Filter @{ active = $true })
        $active.Count | Should Be 2
    }

    It "Remove-StateRecord deletes by PrimaryKey value" {
        Save-StateRecords -Table "t1" -Records @(
            [PSCustomObject]@{ market = "A"; v = 1 }
            [PSCustomObject]@{ market = "B"; v = 2 }
        ) -PrimaryKey "market"
        Remove-StateRecord -Table "t1" -PrimaryKey "market" -Value "A"
        $rows = @(Get-StateRecords -Table "t1")
        $rows.Count | Should Be 1
        $rows[0].market | Should Be "B"
    }
}

Describe "Local backend - PS 5.1 array unwrap resilience" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ss_local_unwrap_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_LOCAL_DIR -Scope Global -ErrorAction SilentlyContinue
    }

    It "Reads single-element JSON array correctly" {
        $records = @([PSCustomObject]@{ market = "SOLO"; v = 1 })
        Save-StateRecords -Table "t1" -Records $records -PrimaryKey "market"
        $back = @(Get-StateRecords -Table "t1")
        $back.Count | Should Be 1
        $back[0].market | Should Be "SOLO"
    }

    It "Survives JSON wrapped as {value=[],Count=N}" {
        # Simulate corrupted file (PS 5.1 ConvertTo-Json quirk)
        $file = Join-Path $script:tmpDir "t1.json"
        $payload = @{ value = @(@{ market = "A"; v = 1 }, @{ market = "B"; v = 2 }); Count = 2 }
        $payload | ConvertTo-Json -Depth 5 | Set-Content $file -Encoding utf8

        $back = @(Get-StateRecords -Table "t1")
        $back.Count | Should Be 2
    }
}

Describe "Backend dispatch routing" {

    AfterEach {
        Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name STATE_STORE_LOCAL_DIR -Scope Global -ErrorAction SilentlyContinue
    }

    It "Get-StateRecords routes to local when backend=local" {
        $tmpDir = Join-Path $env:TEMP "ss_disp_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $global:STATE_STORE_BACKEND = "local"
            $global:STATE_STORE_LOCAL_DIR = $tmpDir
            # If routing is correct, an empty result indicates local backend hit
            $rows = @(Get-StateRecords -Table "doesnotexist")
            $rows.Count | Should Be 0
        } finally {
            Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

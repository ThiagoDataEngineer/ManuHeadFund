# lib_supabase_management.ps1 TDD
#
# Encapsula chamadas a Supabase Management API (api.supabase.com).
# Diferente do PostgREST (lib_state_store.ps1) - aqui rodamos DDL/SQL arbitrario.
#
# Operacoes:
#   - Invoke-SupabaseSql        : POST /v1/projects/{ref}/database/query
#   - Get-SupabaseExposedSchemas: lista schemas expostos via REST
#   - Set-SupabaseExposedSchemas: adiciona/altera lista de schemas
#   - Test-SupabasePat          : valida PAT e retorna projects acessiveis

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_supabase_management.ps1")

Describe "Test-SupabasePat" {

    It "Throws when no PAT provided" {
        Remove-Item env:SUPABASE_PAT -ErrorAction SilentlyContinue
        $threw = $false
        try { Test-SupabasePat -Pat "" } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "Builds correct authorization header" {
        # Mock: substituir Invoke-RestMethod por uma fn que captura argumentos
        $script:capturedHeaders = $null
        $script:capturedUri = $null
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $TimeoutSec)
            $script:capturedHeaders = $Headers
            $script:capturedUri = $Uri
            return @()
        }

        try {
            Test-SupabasePat -Pat "sbp_test123" | Out-Null
            $script:capturedHeaders["Authorization"] | Should Be "Bearer sbp_test123"
            $script:capturedUri | Should Be "https://api.supabase.com/v1/projects"
        } finally {
            Remove-Item function:Invoke-RestMethod -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-SupabaseSql" {

    BeforeEach {
        $script:capturedBody = $null
        $script:capturedUri = $null
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $TimeoutSec)
            $script:capturedUri = $Uri
            $script:capturedBody = $Body
            return @(@{ ok = $true })
        }
    }

    AfterEach {
        Remove-Item function:Invoke-RestMethod -ErrorAction SilentlyContinue
    }

    It "Posts SQL to correct endpoint with project ref" {
        Invoke-SupabaseSql -Pat "sbp_x" -ProjectRef "abc123" -Sql "SELECT 1" | Out-Null
        $script:capturedUri | Should Be "https://api.supabase.com/v1/projects/abc123/database/query"
    }

    It "Encodes SQL in JSON body under 'query' key" {
        Invoke-SupabaseSql -Pat "sbp_x" -ProjectRef "abc" -Sql "SELECT current_user" | Out-Null
        $body = $script:capturedBody | ConvertFrom-Json
        $body.query | Should Be "SELECT current_user"
    }

    It "Throws clearly when ProjectRef empty" {
        $threw = $false
        try { Invoke-SupabaseSql -Pat "sbp_x" -ProjectRef "" -Sql "SELECT 1" } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "Throws clearly when SQL empty" {
        $threw = $false
        try { Invoke-SupabaseSql -Pat "sbp_x" -ProjectRef "abc" -Sql "" } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe "Get/Set-SupabaseExposedSchemas" {

    BeforeEach {
        $script:capturedMethod = $null
        $script:capturedUri = $null
        $script:capturedBody = $null
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $TimeoutSec)
            $script:capturedMethod = $Method
            $script:capturedUri = $Uri
            $script:capturedBody = $Body
            # Return realistic settings response shape
            return [PSCustomObject]@{
                db_schema    = "public, manuheadfund"
                max_rows     = 1000
                db_extra_search_path = "public, extensions"
            }
        }
    }

    AfterEach {
        Remove-Item function:Invoke-RestMethod -ErrorAction SilentlyContinue
    }

    It "Get-SupabaseExposedSchemas calls /postgrest GET" {
        Get-SupabaseExposedSchemas -Pat "sbp_x" -ProjectRef "abc" | Out-Null
        $script:capturedMethod | Should Be "GET"
        $script:capturedUri | Should Match "/postgrest"
    }

    It "Get-SupabaseExposedSchemas parses comma-separated string into array" {
        $schemas = Get-SupabaseExposedSchemas -Pat "sbp_x" -ProjectRef "abc"
        @($schemas).Count | Should Be 2
        ($schemas -contains "public") | Should Be $true
        ($schemas -contains "manuheadfund") | Should Be $true
    }

    It "Set-SupabaseExposedSchemas posts/patches the new list" {
        Set-SupabaseExposedSchemas -Pat "sbp_x" -ProjectRef "abc" -Schemas @("public", "manuheadfund") | Out-Null
        ($script:capturedMethod -in @("PATCH", "POST", "PUT")) | Should Be $true
        $body = $script:capturedBody | ConvertFrom-Json
        $body.db_schema | Should Match "manuheadfund"
    }
}

Describe "Add-SupabaseExposedSchema (idempotent helper)" {

    BeforeEach {
        $script:setCalled = $false
        $script:setSchemas = $null
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $TimeoutSec)
            if ($Method -eq "GET") {
                # Pretend public is already exposed
                return [PSCustomObject]@{ db_schema = "public" }
            } else {
                $script:setCalled = $true
                $script:setSchemas = ($Body | ConvertFrom-Json).db_schema
                return [PSCustomObject]@{ db_schema = $script:setSchemas }
            }
        }
    }

    AfterEach {
        Remove-Item function:Invoke-RestMethod -ErrorAction SilentlyContinue
    }

    It "Adds new schema to existing exposed list" {
        Add-SupabaseExposedSchema -Pat "sbp_x" -ProjectRef "abc" -Schema "manuheadfund" | Out-Null
        $script:setCalled | Should Be $true
        $script:setSchemas | Should Match "public"
        $script:setSchemas | Should Match "manuheadfund"
    }

    It "Skips API call when schema already exposed (idempotent)" {
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $TimeoutSec)
            if ($Method -eq "GET") {
                return [PSCustomObject]@{ db_schema = "public, manuheadfund" }
            }
            $script:setCalled = $true
            return $null
        }
        Add-SupabaseExposedSchema -Pat "sbp_x" -ProjectRef "abc" -Schema "manuheadfund" | Out-Null
        $script:setCalled | Should Be $false
    }
}

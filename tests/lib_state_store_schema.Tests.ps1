# lib_state_store.ps1 — schema-aware backend tests
#
# Quando STATE_STORE_SCHEMA esta setado, o backend supabase deve enviar
# Accept-Profile (GET/DELETE) e Content-Profile (POST) headers HTTP.
# Isso permite isolar nossas tabelas em schema separado (manuheadfund)
# enquanto o schema padrao do Supabase eh "public".

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")

Describe "Schema-aware backend selection" {

    AfterEach {
        Remove-Variable -Name STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
        Remove-Item env:STATE_STORE_SCHEMA -ErrorAction SilentlyContinue
    }

    It "Get-StateStoreSchema returns 'manuheadfund' as default" {
        # 2026-07-23 FIX: default mudou de "public" pra "manuheadfund" em
        # 2026-06-28 (fix critico -- schema "public" compartilhado causou
        # trailing_positions orfao/congelamento quando app de pagamentos
        # alterou a tabela). Teste nunca atualizado apos o fix real.
        Get-StateStoreSchema | Should Be "manuheadfund"
    }

    It "Get-StateStoreSchema returns env value when set" {
        $env:STATE_STORE_SCHEMA = "manuheadfund"
        Get-StateStoreSchema | Should Be "manuheadfund"
    }

    It "Global override beats env" {
        $env:STATE_STORE_SCHEMA = "wrong"
        $global:STATE_STORE_SCHEMA = "manuheadfund"
        Get-StateStoreSchema | Should Be "manuheadfund"
    }
}

Describe "Supabase request headers schema-aware" {

    AfterEach {
        Remove-Variable -Name STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
    }

    It "Get-SupabaseRequestHeaders omite Accept-Profile quando schema explicito='public'" {
        # 2026-07-23 FIX: default real e "manuheadfund" (nao "public") desde
        # 2026-06-28 -- sem $global:STATE_STORE_SCHEMA setado, SEMPRE tem
        # Accept-Profile agora. Teste ajustado pra setar "public" explicito.
        $env:SUPABASE_URL = "https://example.supabase.co"
        $env:SUPABASE_ANON_KEY = "fake_key"
        $global:STATE_STORE_SCHEMA = "public"
        try {
            $h = Get-SupabaseRequestHeaders -Method "GET"
            $h.headers.ContainsKey("Accept-Profile") | Should Be $false
        } finally {
            Remove-Item env:SUPABASE_URL, env:SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
        }
    }

    It "Get-SupabaseRequestHeaders adds Accept-Profile for GET when schema=manuheadfund" {
        $env:SUPABASE_URL = "https://example.supabase.co"
        $env:SUPABASE_ANON_KEY = "fake_key"
        $global:STATE_STORE_SCHEMA = "manuheadfund"
        try {
            $h = Get-SupabaseRequestHeaders -Method "GET"
            $h.headers["Accept-Profile"] | Should Be "manuheadfund"
            $h.headers.ContainsKey("Content-Profile") | Should Be $false
        } finally {
            Remove-Item env:SUPABASE_URL, env:SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
        }
    }

    It "Get-SupabaseRequestHeaders adds Content-Profile for POST when schema=manuheadfund" {
        $env:SUPABASE_URL = "https://example.supabase.co"
        $env:SUPABASE_ANON_KEY = "fake_key"
        $global:STATE_STORE_SCHEMA = "manuheadfund"
        try {
            $h = Get-SupabaseRequestHeaders -Method "POST"
            $h.headers["Content-Profile"] | Should Be "manuheadfund"
            $h.headers.ContainsKey("Accept-Profile") | Should Be $false
        } finally {
            Remove-Item env:SUPABASE_URL, env:SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
        }
    }

    It "Get-SupabaseRequestHeaders adds Content-Profile for DELETE when schema=manuheadfund" {
        $env:SUPABASE_URL = "https://example.supabase.co"
        $env:SUPABASE_ANON_KEY = "fake_key"
        $global:STATE_STORE_SCHEMA = "manuheadfund"
        try {
            $h = Get-SupabaseRequestHeaders -Method "DELETE"
            $h.headers["Content-Profile"] | Should Be "manuheadfund"
        } finally {
            Remove-Item env:SUPABASE_URL, env:SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
        }
    }

    It "Throws clearly when SUPABASE_URL missing" {
        # 2026-07-23 FIX: "{...} | Should Throw" intermitente no Pester 3.4.0
        # (mesma limitacao vista com ValidateSet -- as vezes nao captura a
        # excecao corretamente). try/catch manual e deterministico.
        Remove-Item env:SUPABASE_URL, env:SUPABASE_SERVICE_KEY, env:SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
        $threw = $false
        try { Get-SupabaseRequestHeaders -Method "GET" } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe "Local backend ignores schema (only supabase uses it)" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ss_schema_local_$PID_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = $script:tmpDir
        $global:STATE_STORE_SCHEMA = "manuheadfund"  # should be ignored by local backend
    }

    AfterEach {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_LOCAL_DIR, STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
    }

    It "Local backend ignores schema setting (writes to file regardless)" {
        $records = @([PSCustomObject]@{ market = "X"; v = 1 })
        Save-StateRecords -Table "test_local" -Records $records -PrimaryKey "market"
        $back = @(Get-StateRecords -Table "test_local")
        $back.Count | Should Be 1
    }
}

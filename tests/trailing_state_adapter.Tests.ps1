# trailing_state_adapter.Tests.ps1 -- Fase 2: trailing positions via state_store
# Bridge local-OU-supabase: a nuvem stateless le as posicoes do mesmo backend.
# TDD com backend LOCAL forcado + dir temp (isolado). Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_state_store.ps1"
. ".\agents\lib_trailing_state.ps1"

Describe "Trailing State Adapter (Fase 2)" {

    BeforeEach {
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = Join-Path $env:TEMP ("tstate_" + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $global:STATE_STORE_LOCAL_DIR -Force | Out-Null
    }
    AfterEach {
        if (Test-Path $global:STATE_STORE_LOCAL_DIR) { Remove-Item $global:STATE_STORE_LOCAL_DIR -Recurse -Force }
        $global:STATE_STORE_BACKEND = $null
        $global:STATE_STORE_LOCAL_DIR = $null
    }

    Context "Roundtrip salva/le" {

        It "salva e le de volta as posicoes" {
            $pos = @(
                [PSCustomObject]@{ market="HYPEUSDT"; side="LONG"; entry=74.65; stopCurrent=74.65; peak=77.08; phase=1; active=$true },
                [PSCustomObject]@{ market="SUIUSDT";  side="SHORT"; entry=0.76; stopCurrent=0.80; peak=0.74; phase=0; active=$true }
            )
            Save-TrailingPositionsState -Positions $pos
            $back = @(Get-TrailingPositionsState)
            $back.Count | Should Be 2
            ($back | Where-Object { $_.market -eq "HYPEUSDT" }).stopCurrent | Should Be 74.65
        }

        It "vazio = array vazio (nao quebra)" {
            $back = @(Get-TrailingPositionsState)
            $back.Count | Should Be 0
        }
    }

    Context "Upsert por market (PrimaryKey)" {

        It "salvar mesmo market atualiza (nao duplica)" {
            Save-TrailingPositionsState -Positions @([PSCustomObject]@{ market="HYPEUSDT"; stopCurrent=68.67; active=$true })
            Save-TrailingPositionsState -Positions @([PSCustomObject]@{ market="HYPEUSDT"; stopCurrent=74.65; active=$true })
            $back = @(Get-TrailingPositionsState)
            ($back | Where-Object { $_.market -eq "HYPEUSDT" }).Count | Should Be 1
            ($back | Where-Object { $_.market -eq "HYPEUSDT" }).stopCurrent | Should Be 74.65
        }
    }

    Context "Filtro active" {

        It "Get-TrailingPositionsState -ActiveOnly retorna so ativas" {
            Save-TrailingPositionsState -Positions @(
                [PSCustomObject]@{ market="HYPEUSDT"; active=$true },
                [PSCustomObject]@{ market="MONUSDT";  active=$false }
            )
            $active = @(Get-TrailingPositionsState -ActiveOnly)
            $active.Count | Should Be 1
            $active[0].market | Should Be "HYPEUSDT"
        }
    }

    Context "Backend detectavel" {

        It "usa o backend do state_store (local forcado aqui)" {
            (Test-StateBackend) | Should Be "local"
        }
    }
}

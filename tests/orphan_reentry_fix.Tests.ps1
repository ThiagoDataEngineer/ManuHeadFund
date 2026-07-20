# tests/orphan_reentry_fix.Tests.ps1
# TDD (2026-07-07): FIX A + B para evitar re-entrada involuntária
# Problema: Sync-OrphanPositions reabre posições que phantom_reconciliation fechou
# Solução A: Flag de cooldown após phantom rodar
# Solução B: Confirmar status na corretora antes de registrar

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_trailing_orphan_detection.ps1")

Describe "FIX A: phantom_reconciliation_just_ran flag (cooldown)" {

    BeforeEach {
        $script:journalDir = Join-Path $env:TEMP "orphan_test_$(Get-Random)"
        if (-not (Test-Path $script:journalDir)) { New-Item -ItemType Directory -Path $script:journalDir -Force | Out-Null }
        $global:JOURNAL_DIR = $script:journalDir
    }

    AfterEach {
        Remove-Item -Path $script:journalDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Reconcile-PhantomPositions escreve flag quando fecha posições" {
        # Mock
        $script:detectedPhantoms = @(
            @{ market="PYTHUSDT"; entry=0.045; side="long"; peak=0.046 }
        )
        Set-Item function:Detect-PhantomPositions -Value { $script:detectedPhantoms }
        Set-Item function:Close-TrailingPosition -Value { }
        Set-Item function:CoinEx-GetTicker -Value { @{ last=0.044 } }
        Set-Item function:Remove-OpenGemPosition -Value { }

        $result = Reconcile-PhantomPositions

        $flagFile = Join-Path $script:journalDir "phantom_reconciliation_just_ran.flag"
        (Test-Path $flagFile) | Should Be $true
        (Get-Content $flagFile -Raw) | Should Match "^\d{4}-\d{2}-\d{2}"
    }

    It "Sync-OrphanPositions retorna early se phantom rodou há <2min" {
        # Escrever flag recente
        $flagFile = Join-Path $script:journalDir "phantom_reconciliation_just_ran.flag"
        (Get-Date).ToString("o") | Set-Content -Path $flagFile -Encoding UTF8 -Force

        # Mock
        Set-Item function:Detect-OrphanPositions -Value { @(@{ market="PYTHUSDT"; avg_entry_price=0.045 }) }
        Set-Item function:CoinEx-GetPendingPositions -Value { @(@{ market="PYTHUSDT"; avg_entry_price=0.045 }) }

        $result = Sync-OrphanPositions

        $result.skip_reason | Should Be "phantom_reconciliation_cooldown"
        $result.registered | Should Be 0
    }

    It "Sync-OrphanPositions processa normalmente se phantom rodou há >2min" {
        # Escrever flag antiga (3 min atrás)
        $flagFile = Join-Path $script:journalDir "phantom_reconciliation_just_ran.flag"
        ((Get-Date).AddMinutes(-3)).ToString("o") | Set-Content -Path $flagFile -Encoding UTF8 -Force

        # Mock
        Set-Item function:Detect-OrphanPositions -Value { @() }
        Set-Item function:CoinEx-GetPendingPositions -Value { @() }

        $result = Sync-OrphanPositions

        $result.skip_reason | Should Be $null
        $result.orphans_detected | Should Be 0
    }
}

Describe "FIX B: Register-OrphanPosition confirma status na corretora" {

    BeforeEach {
        $script:journalDir = Join-Path $env:TEMP "orphan_test_$(Get-Random)"
        if (-not (Test-Path $script:journalDir)) { New-Item -ItemType Directory -Path $script:journalDir -Force | Out-Null }
        $global:JOURNAL_DIR = $script:journalDir
    }

    AfterEach {
        Remove-Item -Path $script:journalDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Não registra posição se foi fechada entretanto (phantom shadow)" {
        # Mock: posição foi fechada entre Detect e Register
        Set-Item function:Get-TrailingPositions -Value { @() }
        Set-Item function:CoinEx-GetPendingPositions -Value { @() }
        Set-Item function:Add-TrailingPosition -Value { throw "Should not be called" }

        $orphanPos = @{ market="PYTHUSDT"; avg_entry_price=0.045; side="long"; stop_loss_price=0 }
        $result = Register-OrphanPosition -Position $orphanPos

        $result.registered | Should Be $false
        $result.reason | Should Match "Position closed on exchange"
    }

    It "Registra posição se ainda está aberta na corretora" {
        # Mock: posição ainda está aberta
        Set-Item function:Get-TrailingPositions -Value { @() }
        Set-Item function:CoinEx-GetPendingPositions -Value { @(@{ market="PYTHUSDT"; avg_entry_price=0.045 }) }
        Set-Item function:Add-TrailingPosition -Value { }

        $orphanPos = [PSCustomObject]@{ market="PYTHUSDT"; avg_entry_price=0.045; side="long"; stop_loss_price=0 }

        $result = Register-OrphanPosition -Position $orphanPos

        $result.registered | Should Be $true
    }

    It "Processa mesmo se CoinEx-GetPendingPositions falha (gracious fallback)" {
        # Mock: API falha mas continua
        Set-Item function:Get-TrailingPositions -Value { @() }
        Set-Item function:CoinEx-GetPendingPositions -Value { throw "API error" }
        Set-Item function:Add-TrailingPosition -Value { }

        $orphanPos = [PSCustomObject]@{ market="PYTHUSDT"; avg_entry_price=0.045; side="long"; stop_loss_price=0 }

        $result = Register-OrphanPosition -Position $orphanPos

        # Continua mesmo se API falha (best-effort)
        $result.success | Should Be $true
    }
}

Describe "Integração: Phantom → Flag → Sync bloqueado" {

    BeforeEach {
        $script:journalDir = Join-Path $env:TEMP "orphan_test_$(Get-Random)"
        if (-not (Test-Path $script:journalDir)) { New-Item -ItemType Directory -Path $script:journalDir -Force | Out-Null }
        $global:JOURNAL_DIR = $script:journalDir
    }

    AfterEach {
        Remove-Item -Path $script:journalDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Phantom fecha → flag escreve → Sync reabre bloqueado" {
        # 1. Phantom fecha
        $script:detectedPhantoms = @(
            @{ market="PYTHUSDT"; entry=0.045; side="long"; peak=0.046 }
        )
        Set-Item function:Detect-PhantomPositions -Value { $script:detectedPhantoms }
        Set-Item function:Close-TrailingPosition -Value { }
        Set-Item function:CoinEx-GetTicker -Value { @{ last=0.044 } }
        Set-Item function:Remove-OpenGemPosition -Value { }

        $phantomResult = Reconcile-PhantomPositions
        $phantomResult.closed | Should Be 1

        # 2. Flag deve existir
        $flagFile = Join-Path $script:journalDir "phantom_reconciliation_just_ran.flag"
        (Test-Path $flagFile) | Should Be $true

        # 3. Sync reabre bloqueado
        Set-Item function:Detect-OrphanPositions -Value { @(@{ market="PYTHUSDT"; avg_entry_price=0.045 }) }
        Set-Item function:CoinEx-GetPendingPositions -Value { @(@{ market="PYTHUSDT"; avg_entry_price=0.045 }) }

        $syncResult = Sync-OrphanPositions
        $syncResult.skip_reason | Should Be "phantom_reconciliation_cooldown"
        $syncResult.registered | Should Be 0
    }
}

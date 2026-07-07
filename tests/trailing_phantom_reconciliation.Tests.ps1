# trailing_phantom_reconciliation.Tests.ps1
# TDD para detecção de "phantom positions": registradas localmente como active=true
# mas NÃO existem na exchange (fechadas via TP/SL/manual sem o sistema saber).
#
# CENÁRIOS:
# 1. Posição local active=true + NÃO na exchange = PHANTOM (precisa fechar)
# 2. Posição local active=true + na exchange = OK (skip)
# 3. Posição local active=false + NÃO na exchange = OK (skip, já fechada)
# 4. Multiple phantoms = todas fechadas em batch
# 5. Phantom com ExitPrice (último ticker) registrado no close
# 6. Phantom sem dados de exchange → close com reason="phantom_reconciliation"

$ErrorActionPreference = "Stop"

$tmpDir = Join-Path $env:TEMP "phantom_tests_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

$global:TRAILING_FILE = "$tmpDir\trailing_positions.json"
# Isola do state store (Supabase): sem isto, config.local.ps1 em runs locais faz
# o trailing gravar na nuvem e os testes bleedam linhas entre si (2026-07-07).
$global:TRAILING_USE_STATE_STORE = $false

. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_trailing.ps1"
. "$PSScriptRoot\..\agents\lib_trailing_orphan_detection.ps1"

# Force-replace funções no MESMO scope onde lib_coinex foi dot-sourced (script scope).
# `function global:X` cria nova no global mas script-scope original ganha lookup.
# Set-Item function:X reescreve no script scope diretamente.
Set-Item function:CoinEx-GetTicker -Value { param($market) return [PSCustomObject]@{ last = 100.0 } }
Set-Item function:Send-TelegramAlert -Value { param($Message) return $true }
Set-Item function:CoinEx-GetPendingPositions -Value { return $global:MOCK_EXCH_POSITIONS }

function Set-MockExchange {
    param([array]$Positions = @())
    $global:MOCK_EXCH_POSITIONS = $Positions
}

function Reset-TrailingFile {
    if (Test-Path $global:TRAILING_FILE) { Remove-Item $global:TRAILING_FILE -Force }
    @() | ConvertTo-Json | Set-Content $global:TRAILING_FILE -Encoding utf8
}

Describe "Detect-PhantomPositions" {

    BeforeEach { Reset-TrailingFile; Set-MockExchange @() }

    It "retorna phantom quando local active=true mas exchange vazia" {
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Set-MockExchange @()
        $phantoms = @(Detect-PhantomPositions)
        $phantoms.Count | Should Be 1
        $phantoms[0].market | Should Be "UNIUSDT"
    }

    It "NÃO retorna phantom quando posição local existe na exchange" {
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 75000 -Stop 73000 -Target 78000
        Set-MockExchange @([PSCustomObject]@{ market = "BTCUSDT"; side = "long"; avg_entry_price = 75000; amount = 0.1 })
        $phantoms = @(Detect-PhantomPositions)
        $phantoms.Count | Should Be 0
    }

    It "NÃO retorna phantom quando posição local já está active=false" {
        Add-TrailingPosition -Market "LINKUSDT" -Side "LONG" -Entry 9.5 -Stop 9.0 -Target 10.0
        Close-TrailingPosition -Market "LINKUSDT" -Reason "manual_test"
        Set-MockExchange @()
        $phantoms = @(Detect-PhantomPositions)
        $phantoms.Count | Should Be 0
    }

    It "detecta múltiplas phantoms simultaneamente" {
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Add-TrailingPosition -Market "SOLUSDT" -Side "LONG" -Entry 86 -Stop 82 -Target 90
        Add-TrailingPosition -Market "BNBUSDT" -Side "LONG" -Entry 647 -Stop 627 -Target 680
        Set-MockExchange @()
        $phantoms = @(Detect-PhantomPositions)
        $phantoms.Count | Should Be 3
    }
}

Describe "Reconcile-PhantomPositions" {

    BeforeEach { Reset-TrailingFile; Set-MockExchange @() }

    It "fecha phantom com reason='phantom_reconciliation'" {
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Set-MockExchange @()
        $result = Reconcile-PhantomPositions
        $result.closed | Should Be 1
        $positions = Get-TrailingPositions | Where-Object { $_.market -eq "UNIUSDT" }
        $positions[0].active | Should Be $false
        $positions[0].closeReason | Should Be "phantom_reconciliation"
    }

    It "retorna closed=0 quando não há phantoms" {
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 75000 -Stop 73000 -Target 78000
        Set-MockExchange @([PSCustomObject]@{ market = "BTCUSDT"; side = "long"; avg_entry_price = 75000; amount = 0.1 })
        $result = Reconcile-PhantomPositions
        $result.closed | Should Be 0
        $result.phantoms_detected | Should Be 0
    }

    It "fecha múltiplos phantoms em batch" {
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Add-TrailingPosition -Market "SOLUSDT" -Side "LONG" -Entry 86 -Stop 82 -Target 90
        Set-MockExchange @()
        $result = Reconcile-PhantomPositions
        $result.closed | Should Be 2
    }

    It "registra exitPrice usando ticker atual quando disponível" {
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Set-MockExchange @()
        # ticker mock retorna last=100, mas Reconcile usa CoinEx-GetTicker per market
        $result = Reconcile-PhantomPositions
        $positions = Get-TrailingPositions | Where-Object { $_.market -eq "UNIUSDT" }
        $positions[0].exitPrice | Should Be 100.0
    }

    It "retorna struct com phantoms_detected, closed, errors" {
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Set-MockExchange @()
        $result = Reconcile-PhantomPositions
        $result.PSObject.Properties['phantoms_detected'] | Should Not BeNullOrEmpty
        $result.PSObject.Properties['closed'] | Should Not BeNullOrEmpty
        $result.PSObject.Properties['errors'] | Should Not BeNullOrEmpty
    }
}

Describe "Reconcile-PhantomPositions anti-silencio (exitPrice=0)" {

    BeforeEach { Reset-TrailingFile; Set-MockExchange @() }

    AfterEach {
        # restaura o ticker mock padrao (last=100) pros demais testes
        Set-Item function:CoinEx-GetTicker -Value { param($market) return [PSCustomObject]@{ last = 100.0 } }
    }

    It "usa fallback pro preco da posicao (entry/peak) quando o ticker falha" {
        # ticker lanca -> exitPrice do ticker = 0 -> deve cair pro preco da posicao
        Set-Item function:CoinEx-GetTicker -Value { param($market) throw "ticker indisponivel" }
        Add-TrailingPosition -Market "UNIUSDT" -Side "LONG" -Entry 3.5 -Stop 3.3 -Target 3.7
        Set-MockExchange @()

        $result = Reconcile-PhantomPositions
        $result.closed | Should Be 1
        $positions = Get-TrailingPositions | Where-Object { $_.market -eq "UNIUSDT" }
        # fallback: peak (=entry no registro novo) = 3.5, nunca 0
        $positions[0].exitPrice | Should Be 3.5
        ($positions[0].exitPrice -gt 0) | Should Be $true
    }
}

# Cleanup
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
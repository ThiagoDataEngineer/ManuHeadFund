# phantom_gem_safety_sync.Tests.ps1
# TDD - Causa raiz: Reconcile-PhantomPositions NAO remove posicao do gem_safety_state
# Resultado: gem_loop recompra o mesmo ativo em loop apos phantom_reconciliation
#
# CENARIOS:
# T1. phantom_reconciliation remove mercado do gem_safety_state.open_positions
# T2. phantom_reconciliation de posicao NAO registrada no safety nao falha
# T3. phantom_reconciliation em batch remove TODOS os mercados do safety
# T4. posicao NAO phantom NAO e removida do safety
# T5. gem_safety_state.json ausente nao causa crash
# T6. Remove-OpenGemPosition chamada por phantom remove a posicao corretamente

$ErrorActionPreference = "Stop"

$agentsDir  = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$tmpDir     = Join-Path $env:TEMP "phantom_gem_sync_$(Get-Random)"
New-Item -ItemType Directory $tmpDir -Force | Out-Null

$global:TRAILING_FILE     = "$tmpDir\trailing_positions.json"
$global:GEM_SAFETY_STATE  = "$tmpDir\gem_safety_state.json"

. "$agentsDir\config.ps1"
. "$agentsDir\lib_coinex.ps1"
. "$agentsDir\lib_trailing.ps1"
. "$agentsDir\lib_gem_safety.ps1"
. "$agentsDir\lib_trailing_orphan_detection.ps1"

Set-Item function:CoinEx-GetTicker          -Value { param($m) [PSCustomObject]@{ last = 1.0 } }
Set-Item function:Send-TelegramAlert        -Value { param($Message) $true }
Set-Item function:CoinEx-GetPendingPositions -Value { $global:MOCK_EXCH }

function Reset-All {
    $global:MOCK_EXCH = @()
    @() | ConvertTo-Json | Set-Content $global:TRAILING_FILE -Encoding utf8
    Initialize-GemSafetyStateFile -StateFilePath $global:GEM_SAFETY_STATE
}

function Add-SafetyPos($market, $size = 18.0) {
    Add-OpenGemPosition -Market $market -SizeUsdt $size -StateFilePath $global:GEM_SAFETY_STATE
}

function Get-SafetyMarkets {
    $s = Get-GemSafetyState -StateFilePath $global:GEM_SAFETY_STATE
    return @($s.open_positions | ForEach-Object { $_.market })
}

# ─────────────────────────────────────────────────────────────────────────────

Describe "phantom_reconciliation sincroniza gem_safety_state" {

    BeforeEach { Reset-All }

    It "T1: phantom remove mercado do gem_safety open_positions" {
        Add-TrailingPosition -Market "ENAUSDT" -Side "LONG" -Entry 0.11 -Stop 0.05 -Target 0.22
        Add-SafetyPos "ENAUSDT"
        $global:MOCK_EXCH = @()  # ENAUSDT nao esta na exchange

        Reconcile-PhantomPositions -GemSafetyStatePath $global:GEM_SAFETY_STATE | Out-Null

        $markets = Get-SafetyMarkets
        $markets -contains "ENAUSDT" | Should Be $false
    }

    It "T2: phantom de mercado ausente no safety nao falha" {
        Add-TrailingPosition -Market "OPNUSDT" -Side "LONG" -Entry 0.24 -Stop 0.12 -Target 0.73
        # Nao adiciona no safety propositalmente
        $global:MOCK_EXCH = @()

        { Reconcile-PhantomPositions } | Should Not Throw
    }

    It "T3: batch de phantoms remove todos do safety" {
        foreach ($mkt in @("ENAUSDT","OPNUSDT","INJUSDT")) {
            Add-TrailingPosition -Market $mkt -Side "LONG" -Entry 1.0 -Stop 0.5 -Target 2.0
            Add-SafetyPos $mkt
        }
        $global:MOCK_EXCH = @()

        $result = Reconcile-PhantomPositions -GemSafetyStatePath $global:GEM_SAFETY_STATE

        $result.closed | Should Be 3
        $markets = Get-SafetyMarkets
        $markets.Count | Should Be 0
    }

    It "T4: posicao ainda na exchange NAO e removida do safety" {
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 75000 -Stop 70000 -Target 85000
        Add-SafetyPos "BTCUSDT"
        $global:MOCK_EXCH = @([PSCustomObject]@{ market="BTCUSDT"; avg_entry_price=75000; qty=0.01; side="long" })

        Reconcile-PhantomPositions -GemSafetyStatePath $global:GEM_SAFETY_STATE | Out-Null

        $markets = Get-SafetyMarkets
        $markets -contains "BTCUSDT" | Should Be $true
    }

    It "T5: gem_safety_state ausente nao causa crash" {
        Add-TrailingPosition -Market "ENAUSDT" -Side "LONG" -Entry 0.11 -Stop 0.05 -Target 0.22
        Remove-Item $global:GEM_SAFETY_STATE -Force -EA SilentlyContinue
        $global:MOCK_EXCH = @()

        { Reconcile-PhantomPositions } | Should Not Throw
    }

    It "T6: apos phantom, exposure pct volta a zero" {
        Add-TrailingPosition -Market "ENAUSDT" -Side "LONG" -Entry 0.11 -Stop 0.05 -Target 0.22
        Add-SafetyPos "ENAUSDT" 18.0
        $global:MOCK_EXCH = @()

        $before = Get-OpenGemExposurePct -StateFilePath $global:GEM_SAFETY_STATE -TotalCapitalUsdt 500.0
        $before | Should BeGreaterThan 0

        Reconcile-PhantomPositions -GemSafetyStatePath $global:GEM_SAFETY_STATE | Out-Null

        $after = Get-OpenGemExposurePct -StateFilePath $global:GEM_SAFETY_STATE -TotalCapitalUsdt 500.0
        $after | Should Be 0
    }
}

# Cleanup
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue }

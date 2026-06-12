# mentor_reflection_wire.Tests.ps1
# TDD: wire entre lifecycle de trade (Add/Close-TrailingPosition) e ledger E3
# de reflections (decision_reflections.jsonl).
#
# REQUISITOS:
# 1. Add-TrailingPosition com MentorVeredicto + metadata -> pending reflection criada
# 2. Add-TrailingPosition sem metadata -> sem pending (orphan_auto continua igual)
# 3. Close-TrailingPosition com ExitPrice -> resolved reflection criada
# 4. Get-PriorReflectionsForMarket retorna pair pending+resolved
# 5. Trade sem pending nao falha em Close (graceful)

$ErrorActionPreference = "Stop"

$tmpDir = Join-Path $env:TEMP "refl_wire_tests_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

$global:TRAILING_FILE = "$tmpDir\trailing_positions.json"
$global:JOURNAL_DIR = $tmpDir
$global:REFLECTIONS_PATH_OVERRIDE = "$tmpDir\decision_reflections.jsonl"

. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_decision_reflection.ps1"
. "$PSScriptRoot\..\agents\lib_trailing.ps1"

Set-Item function:CoinEx-GetTicker -Value { param($market) return [PSCustomObject]@{ last = 100.0 } }
Set-Item function:Send-TelegramAlert -Value { param($Message) return $true }
Set-Item function:Add-TradeOutcome -Value { param() return $true }

function Reset-State {
    if (Test-Path $global:TRAILING_FILE) { Remove-Item $global:TRAILING_FILE -Force }
    if (Test-Path $global:REFLECTIONS_PATH_OVERRIDE) { Remove-Item $global:REFLECTIONS_PATH_OVERRIDE -Force }
    @() | ConvertTo-Json | Set-Content $global:TRAILING_FILE -Encoding utf8
}

Describe "Add-TrailingPosition emits pending reflection when Mentor metadata present" {

    BeforeEach { Reset-State }

    It "cria pending reflection quando MentorVeredicto fornecido" {
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 75000 -Stop 73000 -Target 78000 `
            -MentorVeredicto "EXECUTAR" -MentorConfidence 78 -MentorMensagem "Bull thesis, breakout valid" -MesaSinal "LONG" -Tier "A_LIVE"

        Test-Path $global:REFLECTIONS_PATH_OVERRIDE | Should Be $true
        $lines = @(Get-Content $global:REFLECTIONS_PATH_OVERRIDE -Encoding UTF8)
        $lines.Count | Should Be 1
        $obj = $lines[0] | ConvertFrom-Json
        $obj.status | Should Be "pending"
        $obj.market | Should Be "BTCUSDT"
        $obj.mentor_veredicto | Should Be "EXECUTAR"
        $obj.mentor_confidence | Should Be 78
    }

    It "NAO cria pending quando metadata Mentor ausente (orphan_auto/legacy)" {
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 75000 -Stop 73000 -Target 78000 -Source "orphan_auto_register"

        if (Test-Path $global:REFLECTIONS_PATH_OVERRIDE) {
            $lines = @(Get-Content $global:REFLECTIONS_PATH_OVERRIDE -Encoding UTF8 | Where-Object { $_ })
            $lines.Count | Should Be 0
        }
    }

    It "trade_id gerado contem market e timestamp" {
        Add-TrailingPosition -Market "ETHUSDT" -Side "LONG" -Entry 2000 -Stop 1900 -Target 2200 `
            -MentorVeredicto "EXECUTAR" -MentorConfidence 70 -MentorMensagem "msg" -MesaSinal "LONG" -Tier "A_LIVE"
        $obj = (Get-Content $global:REFLECTIONS_PATH_OVERRIDE | Select-Object -First 1) | ConvertFrom-Json
        $obj.trade_id | Should Match "ETHUSDT"
    }
}

Describe "Close-TrailingPosition emits resolved reflection when pending exists" {

    BeforeEach { Reset-State }

    It "cria resolved entry com pnl_pct calculado" {
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 75000 -Stop 73000 -Target 78000 `
            -MentorVeredicto "EXECUTAR" -MentorConfidence 78 -MentorMensagem "msg" -MesaSinal "LONG" -Tier "A_LIVE"
        Close-TrailingPosition -Market "BTCUSDT" -Reason "target_hit" -ExitPrice 77000

        $lines = @(Get-Content $global:REFLECTIONS_PATH_OVERRIDE -Encoding UTF8 | Where-Object { $_ })
        $lines.Count | Should Be 2
        $resolved = ($lines[1] | ConvertFrom-Json)
        $resolved.status | Should Be "resolved"
        # pnl approx +2.67% ((77000-75000)/75000)
        ($resolved.pnl_pct -gt 2.5 -and $resolved.pnl_pct -lt 2.8) | Should Be $true
    }

    It "Close sem pending NAO falha (graceful)" {
        # Posicao criada sem mentor metadata (orphan-like)
        Add-TrailingPosition -Market "LINKUSDT" -Side "LONG" -Entry 10 -Stop 9 -Target 11 -Source "orphan_auto_register"
        # Close deve funcionar sem erro
        { Close-TrailingPosition -Market "LINKUSDT" -Reason "test" -ExitPrice 11.5 } | Should Not Throw

        if (Test-Path $global:REFLECTIONS_PATH_OVERRIDE) {
            $lines = @(Get-Content $global:REFLECTIONS_PATH_OVERRIDE -Encoding UTF8 | Where-Object { $_ })
            $lines.Count | Should Be 0
        }
    }

    It "Get-PriorReflectionsForMarket retorna par pending+resolved" {
        Add-TrailingPosition -Market "SOLUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 110 `
            -MentorVeredicto "EXECUTAR" -MentorConfidence 75 -MentorMensagem "SOL setup" -MesaSinal "LONG" -Tier "B_PAPER"
        Close-TrailingPosition -Market "SOLUSDT" -Reason "target_hit" -ExitPrice 108

        $prior = @(Get-PriorReflectionsForMarket -Market "SOLUSDT" -ReflectionsPath $global:REFLECTIONS_PATH_OVERRIDE)
        $prior.Count | Should Be 1
        $prior[0].pnl_pct | Should Be 8.0
        $prior[0].mentor_veredicto | Should Be "EXECUTAR"
    }
}

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }

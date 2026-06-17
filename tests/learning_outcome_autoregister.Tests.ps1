# learning_outcome_autoregister.Tests.ps1 (Pester 3.x)
# TDD #2: auto-registro de outcome ao fechar posicao, no schema que o join LE.
#
# Antes: outcomes so entravam por reconciliacao manual -> volume nunca cresce.
# Fix: New-LearningOutcome (PURA) calcula win/pnl/entry_date a partir da posicao
#      fechada; Add-LearningOutcome (I/O) grava idempotente em trade_outcomes.jsonl.

$here = Split-Path $MyInvocation.MyCommand.Path
$root = Split-Path $here -Parent
. (Join-Path $root "agents\lib_direction_learning.ps1")

Describe "New-LearningOutcome (PURA)" {
    It "LONG vencedor: pnl_pct e win corretos" {
        $o = New-LearningOutcome -Market "BTCUSDT" -Side "LONG" -EntryPrice 100 -ExitPrice 110 `
            -OpenedAt "2026-06-11 10:00:00" -CloseReason "target"
        [math]::Round($o.pnl_pct,2) | Should Be 10
        $o.win | Should Be $true
    }
    It "LONG perdedor: pnl negativo, win false" {
        $o = New-LearningOutcome -Market "BTCUSDT" -Side "LONG" -EntryPrice 100 -ExitPrice 90 `
            -OpenedAt "2026-06-11 10:00:00" -CloseReason "stop_atingido"
        [math]::Round($o.pnl_pct,2) | Should Be -10
        $o.win | Should Be $false
    }
    It "SHORT vencedor: preco caiu => lucro" {
        $o = New-LearningOutcome -Market "BTCUSDT" -Side "SHORT" -EntryPrice 100 -ExitPrice 90 `
            -OpenedAt "2026-06-11 10:00:00" -CloseReason "target"
        [math]::Round($o.pnl_pct,2) | Should Be 10
        $o.win | Should Be $true
    }
    It "entry_date derivado de OpenedAt (yyyy-MM-dd)" {
        $o = New-LearningOutcome -Market "BTCUSDT" -Side "LONG" -EntryPrice 100 -ExitPrice 110 `
            -OpenedAt "2026-06-11 22:28:56" -CloseReason "target"
        $o.entry_date | Should Be "2026-06-11"
    }
    It "tem todos os campos que o join exige" {
        $o = New-LearningOutcome -Market "BTCUSDT" -Side "LONG" -EntryPrice 100 -ExitPrice 110 `
            -OpenedAt "2026-06-11 10:00:00" -CloseReason "target"
        foreach ($f in @("market","direction","entry_date","win","pnl_pct","trade_id")) {
            $o.Contains($f) | Should Be $true
        }
        $o.direction | Should Be "LONG"
    }
    It "trade_id cai para market-data quando sem OrderId" {
        $o = New-LearningOutcome -Market "XMRUSDT" -Side "LONG" -EntryPrice 376 -ExitPrice 420 `
            -OpenedAt "2026-06-11 10:00:00" -CloseReason "manual"
        $o.trade_id | Should Be "XMRUSDT-20260611"
    }
}

Describe "Add-LearningOutcome (I/O)" {
    BeforeEach {
        $script:tf = Join-Path $env:TEMP "lo_test_$(Get-Random).jsonl"
    }
    AfterEach {
        Remove-Item $script:tf -Force -ErrorAction SilentlyContinue
    }

    It "grava uma linha no arquivo" {
        Add-LearningOutcome -OutcomePath $script:tf -Market "BTCUSDT" -Side "LONG" `
            -EntryPrice 100 -ExitPrice 110 -OpenedAt "2026-06-11 10:00:00" -CloseReason "target" | Out-Null
        (Get-Content $script:tf | Where-Object { $_ }).Count | Should Be 1
    }

    It "idempotente: mesmo trade_id nao grava 2x" {
        $args = @{ OutcomePath=$script:tf; Market="BTCUSDT"; Side="LONG"
            EntryPrice=100; ExitPrice=110; OpenedAt="2026-06-11 10:00:00"
            CloseReason="target"; OrderId="ORD-1" }
        Add-LearningOutcome @args | Out-Null
        Add-LearningOutcome @args | Out-Null
        (Get-Content $script:tf | Where-Object { $_ }).Count | Should Be 1
    }

    It "round-trip: outcome gravado casa com snapshot via Join-SignalOutcomes" {
        Add-LearningOutcome -OutcomePath $script:tf -Market "SOLUSDT" -Side "LONG" `
            -EntryPrice 150 -ExitPrice 165 -OpenedAt "2026-06-11 10:00:00" -CloseReason "target" | Out-Null
        $outs = @(Read-JsonLines -Path $script:tf)
        $snaps = @(
            [PSCustomObject]@{ ts="2026-06-11T10:00:00Z"; trade_id=""; market="SOLUSDT"
                direction="LONG"; source="regime"; regime="BULL_WEAK"; decision="APROVAR"; entry_price=150 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 1
        $joined[0].win | Should Be $true
    }
}

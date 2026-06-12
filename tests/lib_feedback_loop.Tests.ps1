# lib_feedback_loop.Tests.ps1 -- TDD post-trade feedback loop.
# Pester 3.x.
#
# Conceito: trade fecha (stop hit, target, max_days) -> registra outcome em
# journal/trade_outcomes.jsonl -> agregado por (regime, mode, score_bucket)
# vira ajuste de threshold/weight pro proximo trade. Lopez de Prado AFML cap.3
# meta-labeling style (light).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_feedback_loop.ps1")

$script:tmp = Join-Path $env:TEMP ("fb_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Add-TradeOutcome" {
    It "Append linha JSON com schema esperado" {
        $f = Join-Path $tmp "outcomes_a.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "BTCUSDT" -Side "LONG" `
            -Mode "TIER_A" -EntryPrice 50000 -ExitPrice 52000 -StopPrice 49000 -TargetPrice 55000 `
            -R 1.5 -Pnl 100 -DurationDays 3 -ExitReason "trail_stop" `
            -Regime "BULL_WEAK" -Score 75
        Test-Path $f | Should Be $true
        $line = Get-Content $f -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.market | Should Be "BTCUSDT"
        $obj.r | Should Be 1.5
        $obj.mode | Should Be "TIER_A"
        $obj.exit_reason | Should Be "trail_stop"
    }
    It "Multiple appends preservam linhas anteriores" {
        $f = Join-Path $tmp "outcomes_b.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "A" -Side "LONG" -Mode "GEM" `
            -EntryPrice 1 -ExitPrice 2 -StopPrice 0.5 -TargetPrice 5 -R 1 -Pnl 1 -DurationDays 1 `
            -ExitReason "target" -Regime "BULL" -Score 60
        Add-TradeOutcome -OutcomePath $f -Market "B" -Side "SHORT" -Mode "TIER_A" `
            -EntryPrice 100 -ExitPrice 90 -StopPrice 110 -TargetPrice 80 -R 1 -Pnl 10 -DurationDays 2 `
            -ExitReason "target" -Regime "BEAR" -Score 70
        (Get-Content $f).Count | Should Be 2
    }
}


Describe "Get-OutcomeStats - agregacao" {
    BeforeEach {
        $script:statsFile = Join-Path $tmp "outcomes_stats.jsonl"
        Remove-Item $statsFile -ErrorAction SilentlyContinue
        # 10 trades: 6 wins TIER_A em BULL, 4 losses TIER_A em BEAR
        foreach ($i in 1..6) {
            Add-TradeOutcome -OutcomePath $statsFile -Market "X$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 100 -ExitPrice 120 -StopPrice 95 -TargetPrice 125 -R 1.5 -Pnl 20 -DurationDays 3 `
                -ExitReason "target" -Regime "BULL_STRONG" -Score 75
        }
        foreach ($i in 1..4) {
            Add-TradeOutcome -OutcomePath $statsFile -Market "Y$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 100 -ExitPrice 95 -StopPrice 95 -TargetPrice 125 -R -1 -Pnl -5 -DurationDays 1 `
                -ExitReason "stop_hit" -Regime "BEAR_WEAK" -Score 60
        }
    }
    It "Stats globais: 10 trades win_rate 0.6 avg_r 0.5" {
        $s = Get-OutcomeStats -OutcomePath $statsFile
        $s.n | Should Be 10
        $s.win_rate | Should Be 0.6
        $s.avg_r | Should Be 0.5
    }
    It "Filter por mode" {
        $s = Get-OutcomeStats -OutcomePath $statsFile -Mode "TIER_A"
        $s.n | Should Be 10
        $s = Get-OutcomeStats -OutcomePath $statsFile -Mode "GEM"
        $s.n | Should Be 0
    }
    It "Filter por regime BULL_STRONG" {
        $s = Get-OutcomeStats -OutcomePath $statsFile -Regime "BULL_STRONG"
        $s.n | Should Be 6
        $s.win_rate | Should Be 1.0
        $s.avg_r | Should Be 1.5
    }
    It "Filter por regime BEAR_WEAK" {
        $s = Get-OutcomeStats -OutcomePath $statsFile -Regime "BEAR_WEAK"
        $s.n | Should Be 4
        $s.win_rate | Should Be 0
        $s.avg_r | Should Be -1
    }
}


Describe "Get-RegimeAdjustment - learning signal" {
    BeforeEach {
        $script:adjFile = Join-Path $tmp "adj.jsonl"
        Remove-Item $adjFile -ErrorAction SilentlyContinue
        # BULL_STRONG: 8 wins de 1R + 2 losses 1R = win_rate 0.8, edge alto
        foreach ($i in 1..8) {
            Add-TradeOutcome -OutcomePath $adjFile -Market "B$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 2 -StopPrice 0.9 -TargetPrice 2 -R 1 -Pnl 1 -DurationDays 1 `
                -ExitReason "target" -Regime "BULL_STRONG" -Score 75
        }
        foreach ($i in 1..2) {
            Add-TradeOutcome -OutcomePath $adjFile -Market "L$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 0.9 -StopPrice 0.9 -TargetPrice 2 -R -1 -Pnl -0.1 -DurationDays 1 `
                -ExitReason "stop_hit" -Regime "BULL_STRONG" -Score 70
        }
        # BEAR_STRONG: 2 wins + 8 losses = win_rate 0.2, edge negativo
        foreach ($i in 1..2) {
            Add-TradeOutcome -OutcomePath $adjFile -Market "BW$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 2 -StopPrice 0.9 -TargetPrice 2 -R 1 -Pnl 1 -DurationDays 1 `
                -ExitReason "target" -Regime "BEAR_STRONG" -Score 65
        }
        foreach ($i in 1..8) {
            Add-TradeOutcome -OutcomePath $adjFile -Market "BL$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 0.9 -StopPrice 0.9 -TargetPrice 2 -R -1 -Pnl -0.1 -DurationDays 1 `
                -ExitReason "stop_hit" -Regime "BEAR_STRONG" -Score 60
        }
    }
    It "BULL_STRONG: weight_adjust BOOST positive (edge alto)" {
        $adj = Get-RegimeAdjustment -OutcomePath $adjFile -Regime "BULL_STRONG"
        $adj.action | Should Be "BOOST"
        ($adj.weight_multiplier -gt 1.0) | Should Be $true
    }
    It "BEAR_STRONG: weight_adjust REDUCE (edge negativo)" {
        $adj = Get-RegimeAdjustment -OutcomePath $adjFile -Regime "BEAR_STRONG"
        $adj.action | Should Be "REDUCE"
        ($adj.weight_multiplier -lt 1.0) | Should Be $true
    }
    It "Regime sem historico retorna NEUTRAL multiplier 1.0" {
        $adj = Get-RegimeAdjustment -OutcomePath $adjFile -Regime "UNKNOWN_REGIME"
        $adj.action | Should Be "NEUTRAL"
        $adj.weight_multiplier | Should Be 1.0
    }
    It "Poucos trades (<MinTrades) tambem retorna NEUTRAL" {
        $adj = Get-RegimeAdjustment -OutcomePath $adjFile -Regime "BULL_STRONG" -MinTrades 100
        $adj.action | Should Be "NEUTRAL"
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

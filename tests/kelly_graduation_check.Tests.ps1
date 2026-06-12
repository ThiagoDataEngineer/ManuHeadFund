# kelly_graduation_check.Tests.ps1 -- TDD pra audit que auto-ativa Kelly quando criterios passam.
# Pester 3.x.
#
# Test-KellyGraduationCriteria(OutcomePath, MinTrades, MinWinRate):
#   - Le trade_outcomes.jsonl
#   - Verifica >= MinTrades (default 10)
#   - Verifica win_rate >= MinWinRate (default 0.40)
#   - Verifica avg_r >= MinAvgR (default 0.0)
#   - Verifica nenhum ERROR_OUTCOME (defensive)
# Retorna PSCustomObject @{passes, criteria, n_trades, win_rate, avg_r}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_feedback_loop.ps1")
. (Join-Path $agentsDir "lib_kelly_graduation.ps1")

$script:tmp = Join-Path $env:TEMP ("kg_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Test-KellyGraduationCriteria" {
    BeforeEach {
        $script:outcomes = Join-Path $tmp "outcomes.jsonl"
        Remove-Item $outcomes -ErrorAction SilentlyContinue
    }

    It "Sem outcomes: NAO graduate, reason insufficient_trades" {
        $r = Test-KellyGraduationCriteria -OutcomePath $outcomes
        $r.passes | Should Be $false
        $r.reason | Should Match "insufficient_trades"
    }

    It "9 trades: ainda nao graduate (precisa 10)" {
        foreach ($i in 1..9) {
            Add-TradeOutcome -OutcomePath $outcomes -Market "X$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 1.5 -StopPrice 0.9 -TargetPrice 2 -R 0.5 -Pnl 0.5 -DurationDays 1 `
                -ExitReason "target" -Regime "BULL"
        }
        $r = Test-KellyGraduationCriteria -OutcomePath $outcomes
        $r.passes | Should Be $false
        $r.n_trades | Should Be 9
    }

    It "10+ trades + win_rate >= 0.4 + avg_r > 0 = GRADUATE" {
        foreach ($i in 1..6) {
            Add-TradeOutcome -OutcomePath $outcomes -Market "W$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 2 -StopPrice 0.9 -TargetPrice 2 -R 1.0 -Pnl 1.0 -DurationDays 1 `
                -ExitReason "target" -Regime "BULL"
        }
        foreach ($i in 1..4) {
            Add-TradeOutcome -OutcomePath $outcomes -Market "L$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 0.9 -StopPrice 0.9 -TargetPrice 2 -R -1.0 -Pnl -0.1 -DurationDays 1 `
                -ExitReason "stop_atingido" -Regime "BULL"
        }
        $r = Test-KellyGraduationCriteria -OutcomePath $outcomes
        $r.passes | Should Be $true
        $r.n_trades | Should Be 10
        $r.win_rate | Should Be 0.6
    }

    It "10 trades MAS todos losses: NAO graduate" {
        foreach ($i in 1..10) {
            Add-TradeOutcome -OutcomePath $outcomes -Market "L$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 0.9 -StopPrice 0.9 -TargetPrice 2 -R -1 -Pnl -0.1 -DurationDays 1 `
                -ExitReason "stop_atingido" -Regime "BEAR"
        }
        $r = Test-KellyGraduationCriteria -OutcomePath $outcomes
        $r.passes | Should Be $false
        $r.reason | Should Match "edge|win_rate|avg_r"
    }

    It "MinTrades customizado" {
        foreach ($i in 1..5) {
            Add-TradeOutcome -OutcomePath $outcomes -Market "X$i" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 2 -StopPrice 0.9 -TargetPrice 2 -R 1.0 -Pnl 1 -DurationDays 1 `
                -ExitReason "target" -Regime "BULL"
        }
        $r = Test-KellyGraduationCriteria -OutcomePath $outcomes -MinTrades 5
        $r.passes | Should Be $true
    }
}


Describe "Enable-KellySizing - flag setter" {
    It "Cria flag file quando criterios passam" {
        $f = Join-Path $tmp "kelly.flag"
        Remove-Item $f -ErrorAction SilentlyContinue
        $r = Enable-KellySizing -FlagPath $f -Reason "test_pass"
        Test-Path $f | Should Be $true
        $r.enabled | Should Be $true
    }
    It "Idempotent: ja enabled retorna sucesso" {
        $f = Join-Path $tmp "kelly2.flag"
        Enable-KellySizing -FlagPath $f -Reason "first"
        $r2 = Enable-KellySizing -FlagPath $f -Reason "second"
        $r2.enabled | Should Be $true
        $r2.was_already | Should Be $true
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

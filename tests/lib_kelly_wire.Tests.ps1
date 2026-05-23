# lib_kelly_wire.Tests.ps1 -- TDD pra wire de Kelly em gem_executor + orchestrator.
# Testa funcao integradora Resolve-AdaptiveSizing que combina:
#   1. Le trade_outcomes.jsonl (historico do market)
#   2. Filtra por mode
#   3. Chama Get-AdaptiveSizeFromTrades
#   4. Fallback fixed 1% se < MinTrades

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_kelly_adaptive.ps1")
. (Join-Path $agentsDir "lib_feedback_loop.ps1")
. (Join-Path $agentsDir "lib_kelly_wire.ps1")

$script:tmp = Join-Path $env:TEMP ("kw_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Resolve-AdaptiveSizing" {
    BeforeEach {
        $script:outcomeFile = Join-Path $tmp "outcomes.jsonl"
        Remove-Item $outcomeFile -ErrorAction SilentlyContinue
    }

    It "Sem historico retorna fallback fixed 1%" {
        $r = Resolve-AdaptiveSizing -Market "NEW" -Mode "TIER_A" -Capital 10000 -OutcomePath $outcomeFile
        $r.fallback | Should Be $true
        $r.size_usd | Should Be 100.0
    }

    It "Com 10+ trades wins computa Kelly real (capped TIER_A 1%)" {
        # 10 trades: 7 wins de +1.5R + 3 losses de -1R = high edge
        foreach ($i in 1..7) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "X" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 100 -ExitPrice 115 -StopPrice 90 -TargetPrice 120 -R 1.5 -Pnl 15 -DurationDays 2 `
                -ExitReason "target" -Regime "BULL"
        }
        foreach ($i in 1..3) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "X" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 100 -ExitPrice 90 -StopPrice 90 -TargetPrice 120 -R -1 -Pnl -10 -DurationDays 1 `
                -ExitReason "stop_atingido" -Regime "BULL"
        }
        $r = Resolve-AdaptiveSizing -Market "X" -Mode "TIER_A" -Capital 10000 -OutcomePath $outcomeFile
        $r.fallback | Should Be $false
        ($r.win_prob -ge 0.6) | Should Be $true
        # Edge alto + cap TIER_A 1% = exatamente 1% = $100
        $r.size_usd | Should Be 100.0
        ($r.f_kelly -gt 0) | Should Be $true
    }

    It "Mode GEM cap 0.5%" {
        # Mesmo edge mas mode GEM -> cap menor
        foreach ($i in 1..7) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "G" -Side "LONG" -Mode "GEM" `
                -EntryPrice 1 -ExitPrice 2 -StopPrice 0.5 -TargetPrice 5 -R 2 -Pnl 1 -DurationDays 1 `
                -ExitReason "target" -Regime "BULL"
        }
        foreach ($i in 1..3) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "G" -Side "LONG" -Mode "GEM" `
                -EntryPrice 1 -ExitPrice 0.5 -StopPrice 0.5 -TargetPrice 5 -R -1 -Pnl -0.5 -DurationDays 1 `
                -ExitReason "stop_atingido" -Regime "BULL"
        }
        $r = Resolve-AdaptiveSizing -Market "G" -Mode "GEM" -Capital 10000 -OutcomePath $outcomeFile
        $r.size_usd | Should Be 50.0   # 0.5% cap
    }

    It "Historico todo loss retorna size 0" {
        foreach ($i in 1..15) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "L" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 1 -ExitPrice 0.9 -StopPrice 0.9 -TargetPrice 2 -R -1 -Pnl -0.1 -DurationDays 1 `
                -ExitReason "stop_atingido" -Regime "BEAR"
        }
        $r = Resolve-AdaptiveSizing -Market "L" -Mode "TIER_A" -Capital 10000 -OutcomePath $outcomeFile
        $r.size_usd | Should Be 0
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

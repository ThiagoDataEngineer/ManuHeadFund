# kelly_executor_wire.Tests.ps1 -- TDD pra wire de Kelly em gem_executor + orchestrator_v6.
# Pester 3.x.
#
# Pattern: helper Get-ExecutorSize(Market, Mode, Capital, BasePct) que:
#   - Se $global:USE_KELLY_SIZING != $true -> retorna $Capital * $BasePct (legacy)
#   - Se $true -> chama Resolve-AdaptiveSizing
# Wire em gem_executor e orchestrator_v6 substitui $capital * $sz.sizing_pct por essa funcao.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_kelly_adaptive.ps1")
. (Join-Path $agentsDir "lib_feedback_loop.ps1")
. (Join-Path $agentsDir "lib_kelly_wire.ps1")
. (Join-Path $agentsDir "lib_executor_sizing.ps1")

$script:tmp = Join-Path $env:TEMP ("kew_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Get-ExecutorSize - feature flag default OFF" {
    BeforeEach {
        $global:USE_KELLY_SIZING = $false
        $script:outcomeFile = Join-Path $tmp "outcomes_off.jsonl"
        Remove-Item $outcomeFile -ErrorAction SilentlyContinue
    }
    It "Flag OFF: retorna legacy capital * base_pct" {
        $r = Get-ExecutorSize -Market "X" -Mode "TIER_A" -Capital 10000 -BasePct 0.01 -OutcomePath $outcomeFile
        $r.size_usd | Should Be 100.0
        $r.method | Should Be "legacy_fixed"
    }
    It "Flag OFF: BasePct 0.005 = 0.5%" {
        $r = Get-ExecutorSize -Market "X" -Mode "GEM" -Capital 10000 -BasePct 0.005 -OutcomePath $outcomeFile
        $r.size_usd | Should Be 50.0
    }
}


Describe "Get-ExecutorSize - feature flag ON" {
    BeforeEach {
        $global:USE_KELLY_SIZING = $true
        $script:outcomeFile = Join-Path $tmp "outcomes_on.jsonl"
        Remove-Item $outcomeFile -ErrorAction SilentlyContinue
    }
    AfterEach {
        $global:USE_KELLY_SIZING = $false
    }
    It "Flag ON sem historico: fallback fixed (Kelly precisa MinTrades)" {
        $r = Get-ExecutorSize -Market "NOHIST" -Mode "TIER_A" -Capital 10000 -BasePct 0.01 -OutcomePath $outcomeFile
        $r.method | Should Match "kelly|fallback"
        $r.fallback | Should Be $true
        $r.size_usd | Should Be 100.0
    }
    It "Flag ON com 10+ trades: usa Kelly real" {
        foreach ($i in 1..7) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "Z" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 100 -ExitPrice 115 -StopPrice 95 -TargetPrice 120 -R 1.5 -Pnl 15 -DurationDays 2 `
                -ExitReason "target" -Regime "BULL"
        }
        foreach ($i in 1..3) {
            Add-TradeOutcome -OutcomePath $outcomeFile -Market "Z" -Side "LONG" -Mode "TIER_A" `
                -EntryPrice 100 -ExitPrice 95 -StopPrice 95 -TargetPrice 120 -R -1 -Pnl -5 -DurationDays 1 `
                -ExitReason "stop_atingido" -Regime "BULL"
        }
        $r = Get-ExecutorSize -Market "Z" -Mode "TIER_A" -Capital 10000 -BasePct 0.01 -OutcomePath $outcomeFile
        $r.fallback | Should Be $false
        $r.method | Should Be "kelly_adaptive"
        # TIER_A cap 1% = $100
        $r.size_usd | Should Be 100.0
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

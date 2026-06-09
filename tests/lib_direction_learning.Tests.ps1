# lib_direction_learning.Tests.ps1 -- TDD motor de aprendizado bidirecional
# 2026-06-08: aprende win_rate/PnL por (source,direction,regime) com guardrail estatistico.
# Fecha o loop sinais->outcome. "Se nao e compra, pode ser venda" = Get-BiasRecommendation.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_direction_learning.ps1")

# Helper: trade record sintetico
function New-Trade {
    param([string]$Dir="LONG", [string]$Src="regime", [string]$Reg="BEAR_WEAK", [bool]$Win=$true, [double]$Pnl=1.0)
    [PSCustomObject]@{ direction=$Dir; source=$Src; regime=$Reg; win=$Win; pnl_pct=$Pnl }
}

Describe "Learning: Get-DirectionStats (pura)" {

    It "agrega win_rate por chave source|direction|regime" {
        $trades = @(
            (New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $true  -Pnl 2),
            (New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $true  -Pnl 3),
            (New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $false -Pnl -1)
        )
        $stats = Get-DirectionStats -Trades $trades -MinTrades 3
        $key = $stats | Where-Object { $_.key -eq "regime|SHORT|BEAR_WEAK" }
        $key.n | Should Be 3
        $key.wins | Should Be 2
        ([math]::Round($key.win_rate,2)) | Should Be 0.67
    }

    It "marca reliable=false quando n < MinTrades (anti-overfit)" {
        $trades = @( (New-Trade -Win $true), (New-Trade -Win $true) )
        $stats = Get-DirectionStats -Trades $trades -MinTrades 8
        $stats[0].reliable | Should Be $false
    }

    It "marca reliable=true quando n >= MinTrades" {
        $trades = 1..8 | ForEach-Object { New-Trade -Win $true -Pnl 1 }
        $stats = Get-DirectionStats -Trades $trades -MinTrades 8
        $stats[0].reliable | Should Be $true
    }

    It "separa bear_trap_reversal de regime (chaves distintas)" {
        $trades = @(
            (New-Trade -Dir "LONG" -Src "bear_trap_reversal" -Reg "BEAR_WEAK" -Win $true),
            (New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $false)
        )
        $stats = Get-DirectionStats -Trades $trades -MinTrades 1
        @($stats).Count | Should Be 2
    }

    It "avg_pnl_pct correto" {
        $trades = @(
            (New-Trade -Pnl 2), (New-Trade -Pnl 4)
        )
        $stats = Get-DirectionStats -Trades $trades -MinTrades 1
        $stats[0].avg_pnl_pct | Should Be 3
    }

    It "lista vazia nao quebra" {
        $stats = Get-DirectionStats -Trades @() -MinTrades 8
        @($stats).Count | Should Be 0
    }
}

Describe "Learning: Get-LearnedMultiplier (pura)" {

    It "insufficient_data -> 1.0 (neutro, nao overfita)" {
        $stats = Get-DirectionStats -Trades @( (New-Trade -Win $true) ) -MinTrades 8
        $m = Get-LearnedMultiplier -Stats $stats -Source "regime" -Direction "LONG" -Regime "BEAR_WEAK"
        $m | Should Be 1.0
    }

    It "win_rate alto + reliable -> boost (>1.0)" {
        $trades = 1..10 | ForEach-Object { New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $true -Pnl 2 }
        $stats = Get-DirectionStats -Trades $trades -MinTrades 8
        $m = Get-LearnedMultiplier -Stats $stats -Source "regime" -Direction "SHORT" -Regime "BEAR_WEAK"
        ($m -gt 1.0) | Should Be $true
    }

    It "win_rate baixo + reliable -> corte (<1.0)" {
        $trades = 1..10 | ForEach-Object { New-Trade -Dir "LONG" -Src "regime" -Reg "BEAR_WEAK" -Win $false -Pnl -1 }
        $stats = Get-DirectionStats -Trades $trades -MinTrades 8
        $m = Get-LearnedMultiplier -Stats $stats -Source "regime" -Direction "LONG" -Regime "BEAR_WEAK"
        ($m -lt 1.0) | Should Be $true
    }

    It "chave inexistente -> 1.0 (neutro)" {
        $stats = Get-DirectionStats -Trades @( (New-Trade) ) -MinTrades 1
        $m = Get-LearnedMultiplier -Stats $stats -Source "xyz" -Direction "SHORT" -Regime "BULL_STRONG"
        $m | Should Be 1.0
    }

    It "multiplier clamped em [0.5, 1.5]" {
        $trades = 1..20 | ForEach-Object { New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $true -Pnl 5 }
        $stats = Get-DirectionStats -Trades $trades -MinTrades 8
        $m = Get-LearnedMultiplier -Stats $stats -Source "regime" -Direction "SHORT" -Regime "BEAR_WEAK"
        ($m -le 1.5) | Should Be $true
    }
}

Describe "Learning: Get-BiasRecommendation (se nao e compra, pode ser venda)" {

    It "LONG forte sem historico -> recomenda LONG" {
        $r = Get-BiasRecommendation -SignalsLong 3 -SignalsShort 0 -Stats @() -Regime "BULL_WEAK"
        $r.direction | Should Be "LONG"
    }

    It "SHORT forte sem historico -> recomenda SHORT" {
        $r = Get-BiasRecommendation -SignalsLong 0 -SignalsShort 3 -Stats @() -Regime "BEAR_WEAK"
        $r.direction | Should Be "SHORT"
    }

    It "empate de sinais sem historico -> NEUTRAL" {
        $r = Get-BiasRecommendation -SignalsLong 1 -SignalsShort 1 -Stats @() -Regime "SIDEWAYS"
        $r.direction | Should Be "NEUTRAL"
    }

    It "LONG fraco mas SHORT historicamente bom -> pode virar SHORT (aprendizado)" {
        # 2 LONG vs 1 SHORT cru, mas SHORT tem win_rate alto historico -> peso ajustado vira SHORT
        $trades = 1..12 | ForEach-Object { New-Trade -Dir "SHORT" -Src "regime" -Reg "BEAR_WEAK" -Win $true -Pnl 3 }
        $trades += 1..12 | ForEach-Object { New-Trade -Dir "LONG" -Src "regime" -Reg "BEAR_WEAK" -Win $false -Pnl -2 }
        $stats = Get-DirectionStats -Trades $trades -MinTrades 8
        $r = Get-BiasRecommendation -SignalsLong 2 -SignalsShort 1 -Stats $stats -Regime "BEAR_WEAK"
        $r.direction | Should Be "SHORT"
    }

    It "expoe razao auditavel" {
        $r = Get-BiasRecommendation -SignalsLong 3 -SignalsShort 0 -Stats @() -Regime "BULL_WEAK"
        ([string]::IsNullOrWhiteSpace($r.reason)) | Should Be $false
    }
}

Describe "Learning: Join-SignalOutcomes (fecha o loop sinais->outcome)" {

    It "junta snapshot + outcome por trade_id" {
        $snaps = @(
            [PSCustomObject]@{ trade_id="A-1"; market="AUSDT"; direction="SHORT"; source="regime"; regime="BEAR_WEAK" }
        )
        $outcomes = @(
            [PSCustomObject]@{ trade_id="A-1"; win=$true; pnl_pct=2.5 }
        )
        $joined = Join-SignalOutcomes -Snapshots $snaps -Outcomes $outcomes
        @($joined).Count | Should Be 1
        $joined[0].direction | Should Be "SHORT"
        $joined[0].win | Should Be $true
        $joined[0].pnl_pct | Should Be 2.5
    }

    It "ignora snapshot sem outcome correspondente (trade ainda aberto)" {
        $snaps = @(
            [PSCustomObject]@{ trade_id="A-1"; direction="SHORT"; source="regime"; regime="BEAR_WEAK" },
            [PSCustomObject]@{ trade_id="B-2"; direction="LONG"; source="regime"; regime="BULL_WEAK" }
        )
        $outcomes = @( [PSCustomObject]@{ trade_id="A-1"; win=$true; pnl_pct=2.5 } )
        $joined = Join-SignalOutcomes -Snapshots $snaps -Outcomes $outcomes
        @($joined).Count | Should Be 1
    }

    It "fallback join por market+entry_date quando sem trade_id" {
        $snaps = @(
            [PSCustomObject]@{ market="AUSDT"; entry_date="2026-06-08"; direction="SHORT"; source="regime"; regime="BEAR_WEAK" }
        )
        $outcomes = @(
            [PSCustomObject]@{ market="AUSDT"; entry_date="2026-06-08"; win=$false; pnl_pct=-1.2 }
        )
        $joined = Join-SignalOutcomes -Snapshots $snaps -Outcomes $outcomes
        @($joined).Count | Should Be 1
        $joined[0].win | Should Be $false
    }

    It "listas vazias nao quebram" {
        $joined = Join-SignalOutcomes -Snapshots @() -Outcomes @()
        @($joined).Count | Should Be 0
    }
}

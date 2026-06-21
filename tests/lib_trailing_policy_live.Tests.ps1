# lib_trailing_policy_live.Tests.ps1 -- TDD do wire LIVE ATIVO.
# Decisao gated por posicao + apply ratchet-only (anti-duplicata/double-sell).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_trailing_baseline.ps1")
. (Join-Path $agentsDir "lib_trailing_policy.ps1")
. (Join-Path $agentsDir "lib_trailing_policy_live.ps1")

function _Bars { param([double]$Start=100,[double]$Drift=2,[int]$N=30)
    $bars=@(); $p=$Start
    for($i=0;$i -lt $N;$i++){ $o=$p; $c=$p+$Drift; $h=[math]::Max($o,$c)+1; $l=[math]::Min($o,$c)-1
        $bars += [PSCustomObject]@{ open=$o;high=$h;low=$l;close=$c;volume=100 }; $p=$c }
    return $bars
}

Describe "Get-TrailingCandleMetrics" {
    It "Candles subindo -> trend_up true, atr>0" {
        $m = Get-TrailingCandleMetrics -Candles (_Bars -Drift 2 -N 30)
        $m.trend_up | Should Be $true
        $m.atr | Should BeGreaterThan 0
    }
    It "Candles caindo -> trend_up false" {
        $m = Get-TrailingCandleMetrics -Candles (_Bars -Start 200 -Drift -2 -N 30)
        $m.trend_up | Should Be $false
    }
}

Describe "Get-PositionExitDecision -- gate por regime" {
    It "LONG uptrend + bull -> selected runner" {
        $pos = [PSCustomObject]@{ market="AAAUSDT"; side="LONG"; entry=100; stop=90; stopCurrent=90; peak=150; openedAt=(Get-Date).AddDays(-3).ToString("o") }
        $d = Get-PositionExitDecision -Position $pos -Candles (_Bars -Start 120 -Drift 2 -N 30) -Regime "BULL_WEAK"
        $d.selected | Should Be "runner"
    }
    It "Regime bear -> selected atual (mesmo subindo)" {
        $pos = [PSCustomObject]@{ market="AAAUSDT"; side="LONG"; entry=100; stop=90; stopCurrent=90; peak=150; openedAt=(Get-Date).AddDays(-3).ToString("o") }
        $d = Get-PositionExitDecision -Position $pos -Candles (_Bars -Start 120 -Drift 2 -N 30) -Regime "BEAR_WEAK"
        $d.selected | Should Be "atual"
    }
}

Describe "Invoke-TrailingPolicyLive -- ratchet-only ATIVO" {

    It "Aperta stop p/ cima (LONG em lucro, uptrend bull)" {
        $pos = [PSCustomObject]@{ market="AAAUSDT"; side="LONG"; entry=100; stop=90; stopCurrent=95; peak=160; openedAt=(Get-Date).AddDays(-3).ToString("o") }
        $map = @{ "AAAUSDT" = (_Bars -Start 140 -Drift 2 -N 30) }   # atr~4, peak 160 -> chandelier ~144 > 95
        $res = Invoke-TrailingPolicyLive -Positions @($pos) -CandleMap $map -Regime "BULL_WEAK"
        @($res.changes).Count | Should Be 1
        $res.changes[0].new_stop | Should BeGreaterThan 95
        $pos.stopCurrent | Should BeGreaterThan 95   # mutou em memoria
    }

    It "NUNCA afrouxa: stop ja alto demais -> sem mudanca" {
        $pos = [PSCustomObject]@{ market="AAAUSDT"; side="LONG"; entry=100; stop=90; stopCurrent=159; peak=160; openedAt=(Get-Date).AddDays(-3).ToString("o") }
        $map = @{ "AAAUSDT" = (_Bars -Start 140 -Drift 2 -N 30) }
        $res = Invoke-TrailingPolicyLive -Positions @($pos) -CandleMap $map -Regime "BULL_WEAK"
        @($res.changes).Count | Should Be 0
        $pos.stopCurrent | Should Be 159   # intacto
    }

    It "Sem candles p/ o mercado -> ignora sem quebrar" {
        $pos = [PSCustomObject]@{ market="ZZZUSDT"; side="LONG"; entry=100; stop=90; stopCurrent=95; peak=160; openedAt=(Get-Date).AddDays(-1).ToString("o") }
        $res = Invoke-TrailingPolicyLive -Positions @($pos) -CandleMap @{} -Regime "BULL_WEAK"
        @($res.changes).Count | Should Be 0
    }
}

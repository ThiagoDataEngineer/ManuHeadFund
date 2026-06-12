# lib_bidirectional_direction.Tests.ps1 -- TDD direcao bidirecional (Triagem/Mesa/Mentor)
# 2026-06-08: Resolve-TradeDirection avalia LONG e SHORT; detecta bear/bull traps por confluencia.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_bidirectional_direction.ps1")

Describe "Bidirectional: baseline segue regime (sem reversao)" {

    It "BULL_WEAK sem sinais contrarios -> LONG (regime)" {
        $r = Resolve-TradeDirection -Regime "BULL_WEAK" -Change24h 3 -Pdi 25 -Ndi 18 -Adx 22 -CurrentPrice 110 -Ema200 100
        $r.direction | Should Be "LONG"
        $r.source | Should Be "regime"
    }
    It "BEAR_WEAK sem sinais contrarios -> SHORT (regime)" {
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h -3 -Pdi 18 -Ndi 25 -Adx 22 -CurrentPrice 90 -Ema200 100
        $r.direction | Should Be "SHORT"
        $r.source | Should Be "regime"
    }
    It "SIDEWAYS default -> LONG (regime)" {
        $r = Resolve-TradeDirection -Regime "SIDEWAYS" -Change24h 0 -Pdi 20 -Ndi 20 -Adx 15 -CurrentPrice 100 -Ema200 100
        $r.direction | Should Be "LONG"
    }
}

Describe "Bidirectional: BEAR TRAP (reversao LONG dentro de bear)" {

    It "BEAR + 3 sinais bullish fortes -> override LONG (bear_trap)" {
        # PDI>NDI (ADX forte) + change +8% + price>EMA = reversao de alta
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 8 -Pdi 30 -Ndi 15 -Adx 28 -CurrentPrice 115 -Ema200 100
        $r.direction | Should Be "LONG"
        $r.source | Should Be "bear_trap_reversal"
    }
    It "BEAR + 2 sinais bullish -> override LONG (confluencia minima)" {
        # PDI>NDI + change +6%, mas price abaixo EMA (1 contra) = 2 de 3 -> reverte
        $r = Resolve-TradeDirection -Regime "BEAR_STRONG" -Change24h 6 -Pdi 28 -Ndi 16 -Adx 25 -CurrentPrice 95 -Ema200 100
        $r.direction | Should Be "LONG"
        $r.source | Should Be "bear_trap_reversal"
    }
    It "BEAR + apenas 1 sinal bullish -> NAO reverte (segue SHORT)" {
        # so change +6%; PDI<NDI e price<EMA = so 1 sinal bullish -> nao reverte
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 6 -Pdi 16 -Ndi 26 -Adx 24 -CurrentPrice 92 -Ema200 100
        $r.direction | Should Be "SHORT"
        $r.source | Should Be "regime"
    }
    It "BEAR + PDI>NDI mas ADX fraco (range) -> DI nao conta, nao reverte" {
        # PDI>NDI mas ADX<20 = sem tendencia, DI signal nulo; change so +3 (fraco); price<EMA
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 3 -Pdi 24 -Ndi 18 -Adx 15 -CurrentPrice 95 -Ema200 100
        $r.direction | Should Be "SHORT"
    }
}

Describe "Bidirectional: BULL TRAP (reversao SHORT dentro de bull)" {

    It "BULL + 3 sinais bearish fortes -> override SHORT (bull_trap)" {
        # NDI>PDI (ADX forte) + change -8% + price<EMA = reversao de baixa
        $r = Resolve-TradeDirection -Regime "BULL_WEAK" -Change24h -8 -Pdi 15 -Ndi 30 -Adx 28 -CurrentPrice 85 -Ema200 100
        $r.direction | Should Be "SHORT"
        $r.source | Should Be "bull_trap_reversal"
    }
    It "BULL + 2 sinais bearish -> override SHORT" {
        $r = Resolve-TradeDirection -Regime "BULL_STRONG" -Change24h -7 -Pdi 14 -Ndi 29 -Adx 26 -CurrentPrice 105 -Ema200 100
        $r.direction | Should Be "SHORT"
        $r.source | Should Be "bull_trap_reversal"
    }
    It "BULL + apenas 1 sinal bearish -> NAO reverte (segue LONG)" {
        $r = Resolve-TradeDirection -Regime "BULL_WEAK" -Change24h -6 -Pdi 26 -Ndi 16 -Adx 24 -CurrentPrice 108 -Ema200 100
        $r.direction | Should Be "LONG"
        $r.source | Should Be "regime"
    }
}

Describe "Bidirectional: conviction e robustez" {

    It "conviction maior com 3 sinais que com 2" {
        $r3 = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 8 -Pdi 30 -Ndi 15 -Adx 28 -CurrentPrice 115 -Ema200 100
        $r2 = Resolve-TradeDirection -Regime "BEAR_STRONG" -Change24h 6 -Pdi 28 -Ndi 16 -Adx 25 -CurrentPrice 95 -Ema200 100
        ($r3.conviction -gt $r2.conviction) | Should Be $true
    }
    It "retorna razao textual explicando decisao" {
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 8 -Pdi 30 -Ndi 15 -Adx 28 -CurrentPrice 115 -Ema200 100
        ([string]::IsNullOrWhiteSpace($r.reason)) | Should Be $false
    }
    It "tolera dados ausentes (EMA null) sem quebrar -> usa sinais disponiveis" {
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 8 -Pdi 30 -Ndi 15 -Adx 28 -CurrentPrice 0 -Ema200 0
        # struct signal nulo, mas DI + momentum bullish = 2 sinais -> reverte
        $r.direction | Should Be "LONG"
    }
    It "tolera TODOS dados tecnicos ausentes -> fallback regime puro" {
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 0 -Pdi 0 -Ndi 0 -Adx 0 -CurrentPrice 0 -Ema200 0
        $r.direction | Should Be "SHORT"
        $r.source | Should Be "regime"
    }
    It "campos signals_long e signals_short expostos para auditoria" {
        $r = Resolve-TradeDirection -Regime "BEAR_WEAK" -Change24h 8 -Pdi 30 -Ndi 15 -Adx 28 -CurrentPrice 115 -Ema200 100
        $r.signals_long | Should Be 3
        $r.signals_short | Should Be 0
    }
}

Describe "Bidirectional: Resolve-MentorDirection (precedencia p/ Mentor)" {

    It "Direction explicito tem prioridade maxima" {
        $r = Resolve-MentorDirection -ExplicitDirection "SHORT" -MesaSignal "LONG" -TriagemDirection "LONG"
        $r | Should Be "SHORT"
    }
    It "Mesa vence Triagem quando Mesa tem consenso LONG/SHORT" {
        $r = Resolve-MentorDirection -ExplicitDirection "" -MesaSignal "SHORT" -TriagemDirection "LONG"
        $r | Should Be "SHORT"
    }
    It "Triagem usada como fallback quando Mesa NEUTRO" {
        $r = Resolve-MentorDirection -ExplicitDirection "" -MesaSignal "NEUTRO" -TriagemDirection "SHORT"
        $r | Should Be "SHORT"
    }
    It "Triagem usada quando Mesa CAOS" {
        $r = Resolve-MentorDirection -ExplicitDirection "" -MesaSignal "CAOS" -TriagemDirection "SHORT"
        $r | Should Be "SHORT"
    }
    It "LONG default SO quando tudo ausente (nao mais cego em bear)" {
        $r = Resolve-MentorDirection -ExplicitDirection "" -MesaSignal "NEUTRO" -TriagemDirection ""
        $r | Should Be "LONG"
    }
    It "bear trap: Triagem manda LONG mesmo sem Mesa -> Mentor avalia LONG" {
        # Cenario real: triagem detectou bear_trap_reversal -> LONG; Mesa neutra
        $r = Resolve-MentorDirection -ExplicitDirection "" -MesaSignal "NEUTRO" -TriagemDirection "LONG"
        $r | Should Be "LONG"
    }
}

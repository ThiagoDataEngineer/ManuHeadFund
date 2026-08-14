# lib_entry_quality_gate.Tests.ps1 -- TDD do gate fail-closed de entrada.
$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_entry_quality_gate.ps1")

Describe "Test-EntryQualityGate -- contradicao de direcao" {
    It "LONG trade + tech SHORT-FORTE -> BLOCK" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "SHORT-FORTE" -LlmFallback $true -Conviction 0
        $r.blocked | Should Be $true
        ($r.reasons -join ',') | Should Match "direction_contradiction"
    }
    It "SHORT trade + tech LONG-FORTE -> BLOCK" {
        $r = Test-EntryQualityGate -TradeDirection "SHORT" -TechConsensus "LONG" -Conviction 50
        $r.blocked | Should Be $true
    }
    It "LONG trade + tech LONG-FORTE -> ALLOW" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "LONG-FORTE" -Conviction 50 -ChartStatus "ok"
        $r.allow | Should Be $true
    }
    It "LONG trade + tech NEUTRO -> nao bloqueia por direcao" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "NEUTRO" -Conviction 40 -ChartStatus "ok"
        $r.allow | Should Be $true
    }
}

Describe "Test-EntryQualityGate -- entrada cega" {
    It "fallback + conviction 0 + mesa 0 + chart insufficient -> BLOCK" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "LONG" -LlmFallback $true -Conviction 0 -MesaScore 0 -ChartStatus "insufficient_data"
        $r.blocked | Should Be $true
        ($r.reasons -join ',') | Should Match "blind_entry"
    }
    It "fallback MAS conviction 60 -> ALLOW (tem sinal real)" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "LONG" -LlmFallback $true -Conviction 60 -ChartStatus "insufficient_data"
        $r.allow | Should Be $true
    }
    It "fallback MAS mesa 70 -> ALLOW" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "LONG" -LlmFallback $true -Conviction 0 -MesaScore 70 -ChartStatus "insufficient_data"
        $r.allow | Should Be $true
    }
    It "LLM disponivel (fallback false) + conviction 0 -> ALLOW (tem verdict)" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "LONG" -LlmFallback $false -Conviction 0 -ChartStatus "insufficient_data"
        $r.allow | Should Be $true
    }
}

Describe "Test-EntryQualityGate -- caso real run #677" {
    It "EPICCHAIN: LONG spot + SHORT-FORTE + fallback + conv0 -> BLOCK (era ENTER!)" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "SHORT-FORTE" -LlmFallback $true -Conviction 0 -MesaScore 0 -ChartStatus "insufficient_data"
        $r.blocked | Should Be $true
    }
    It "ALICE: LONG spot + LONG-FORTE + fallback + conv0 + chart insufficient -> BLOCK (cega)" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "LONG-FORTE" -LlmFallback $true -Conviction 0 -MesaScore 0 -ChartStatus "insufficient_data"
        $r.blocked | Should Be $true
    }
}

Describe "Test-EntryQualityGate -- 2026-08-14 FIX: fallback deterministico nao veta trade com confluencia forte" {
    # Caso real (producao, ~3h, 14 ocorrencias): LINKUSDT SHORT com TORI
    # conviction=80-100 (confluencia real >=3 fatores) bloqueado repetidas
    # vezes so porque scripts/tech_agent.ps1 (fallback, SEM piso de
    # confluencia) dizia LONG enquanto Claude estava indisponivel na sessao.

    It "SHORT trade conv=80 (TORI forte) + fallback diz LONG -> ALLOW (fallback sem peso pra vetar confluencia forte)" {
        $r = Test-EntryQualityGate -TradeDirection "SHORT" -TechConsensus "LONG" -LlmFallback $true -Conviction 80 -MesaScore 0 -ChartStatus "ok"
        $r.allow | Should Be $true
    }

    It "SHORT trade conv=100 (TORI maximo) + fallback diz LONG -> ALLOW" {
        $r = Test-EntryQualityGate -TradeDirection "SHORT" -TechConsensus "LONG" -LlmFallback $true -Conviction 100 -MesaScore 0 -ChartStatus "ok"
        $r.allow | Should Be $true
    }

    It "SHORT trade conv=50 (fraco) + fallback diz LONG -> BLOCK (nenhum lado tem sinal forte, mantem cautela)" {
        $r = Test-EntryQualityGate -TradeDirection "SHORT" -TechConsensus "LONG" -LlmFallback $true -Conviction 50 -MesaScore 0 -ChartStatus "ok"
        $r.blocked | Should Be $true
    }

    It "SHORT trade conv=80 + LLM REAL (nao fallback) diz LONG -> BLOCK (opiniao real do LLM continua com poder de veto)" {
        $r = Test-EntryQualityGate -TradeDirection "SHORT" -TechConsensus "LONG" -LlmFallback $false -Conviction 80 -MesaScore 0 -ChartStatus "ok"
        $r.blocked | Should Be $true
        ($r.reasons -join ',') | Should Match "direction_contradiction"
    }

    It "LONG trade conv=80 (TORI forte) + fallback diz SHORT -> ALLOW (espelho)" {
        $r = Test-EntryQualityGate -TradeDirection "LONG" -TechConsensus "SHORT" -LlmFallback $true -Conviction 80 -MesaScore 0 -ChartStatus "ok"
        $r.allow | Should Be $true
    }
}

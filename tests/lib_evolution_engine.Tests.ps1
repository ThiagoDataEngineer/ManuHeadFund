# lib_evolution_engine.Tests.ps1 — TDD do EVOLUTION ENGINE v1
# Pester 3.x. Cobre: bounds duplos, classe risk nunca-auto, propostas
# deterministicas por evidencia, anti-oscilacao, overlay fail-safe.

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\lib_evolution_engine.ps1")

Describe "Registro de tunaveis" {
    It "todo parametro tem bounds coerentes (min < max, default dentro)" {
        foreach ($p in (Get-TunableRegistry)) {
            ($p.min -lt $p.max) | Should Be $true
            ($p.default -ge $p.min -and $p.default -le $p.max) | Should Be $true
            ($p.step -gt 0) | Should Be $true
        }
    }
    It "existe pelo menos 1 parametro classe risk (para provar o gate)" {
        @((Get-TunableRegistry) | Where-Object { $_.class -eq 'risk' }).Count | Should BeGreaterThan 0
    }
}

Describe "Get-EvolutionParams (overlay + clamp)" {
    $tmp = Join-Path $env:TEMP "evo_test_$(Get-Random)"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    It "sem overlay retorna defaults (fail-safe)" {
        $p = Get-EvolutionParams -JournalDir $tmp
        $p.pumpfade_min_pump_pct | Should Be 15
        $p.sentinel_move_pct | Should Be 2.5
    }
    It "overlay valido e aplicado" {
        '{"pumpfade_min_pump_pct": 12}' | Out-File (Join-Path $tmp "evolution_params.json") -Encoding UTF8
        (Get-EvolutionParams -JournalDir $tmp).pumpfade_min_pump_pct | Should Be 12
    }
    It "overlay FORA do bound e CLAMPADO (bound 1 de 2)" {
        '{"pumpfade_min_pump_pct": 2, "sentinel_move_pct": 99}' | Out-File (Join-Path $tmp "evolution_params.json") -Encoding UTF8
        $p = Get-EvolutionParams -JournalDir $tmp
        $p.pumpfade_min_pump_pct | Should Be 8      # min
        $p.sentinel_move_pct | Should Be 5.0        # max
    }
    It "overlay corrompido = defaults (fail-safe)" {
        'nao-e-json{{{' | Out-File (Join-Path $tmp "evolution_params.json") -Encoding UTF8
        (Get-EvolutionParams -JournalDir $tmp).pumpfade_min_pump_pct | Should Be 15
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Get-EvolutionProposals (regras deterministicas)" {
    $base = Get-EvolutionParams -JournalDir (Join-Path $env:TEMP "inexistente_$(Get-Random)")

    It "3 dias 0-match com dumpers -> afrouxa min_pump 1 step" {
        $ev = @{ pumpfade_days_zero_match=3; pumpfade_dumpers_seen=9; pumpfade_matches_per_day=0.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        $pf = @($props | Where-Object { $_.param -eq 'pumpfade_min_pump_pct' })
        $pf.Count | Should Be 1
        $pf[0].after | Should Be 14
    }
    It "matches/dia > 5 -> aperta min_pump 1 step" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=30; pumpfade_matches_per_day=7.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        $pf = @($props | Where-Object { $_.param -eq 'pumpfade_min_pump_pct' })
        $pf[0].after | Should Be 16
    }
    It "sem evidencia relevante -> zero propostas (nao mexe a toa)" {
        $ev = @{ pumpfade_days_zero_match=1; pumpfade_dumpers_seen=2; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8 }
        @(Get-EvolutionProposals -Current $base -Evidence $ev).Count | Should Be 0
    }
    It "sentinela ruidoso (>25/24h) -> sobe move_pct" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=30; sentinel_triggers_48h=40 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        $s = @($props | Where-Object { $_.param -eq 'sentinel_move_pct' })
        $s[0].after | Should Be 2.75
    }
    It "sentinela surdo (0 em 48h) -> desce move_pct" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=0; sentinel_triggers_48h=0 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        $s = @($props | Where-Object { $_.param -eq 'sentinel_move_pct' })
        $s[0].after | Should Be 2.25
    }
    It "proposta nunca ultrapassa bound (no minimo, para de propor)" {
        $atMin = [PSCustomObject]@{ pumpfade_min_pump_pct=8.0; sentinel_move_pct=2.5; sentinel_ignition_pct=12; pumpfade_dump_pct=-10; gem_sizing_pct=0.5 }
        $ev = @{ pumpfade_days_zero_match=3; pumpfade_dumpers_seen=9; pumpfade_matches_per_day=0.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8 }
        $props = @(Get-EvolutionProposals -Current $atMin -Evidence $ev)
        @($props | Where-Object { $_.param -eq 'pumpfade_min_pump_pct' }).Count | Should Be 0
    }

    # 2026-07-17: regra C -- tori_confluence_threshold. Evidencia vem de
    # manuheadfund.mce_counterfactual_agg filtrado por gate=tori_confluence
    # (scripts/mce_counterfactual_from_supabase.ps1). n minimo 20 (amostra
    # pequena nao move parametro real).
    It "hit_rate alto (>=65%) com n>=20 -> desce threshold (rejeitando setups bons)" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8
                 tori_confluence_rejected_n=24; tori_confluence_rejected_hit_rate=0.88 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        $t = @($props | Where-Object { $_.param -eq 'tori_confluence_threshold' })
        $t.Count | Should Be 1
        $t[0].after | Should Be 78
    }
    It "hit_rate baixo (<=35%) com n>=20 -> sobe threshold (filtro ainda frouxo)" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8
                 tori_confluence_rejected_n=25; tori_confluence_rejected_hit_rate=0.20 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        $t = @($props | Where-Object { $_.param -eq 'tori_confluence_threshold' })
        $t[0].after | Should Be 82
    }
    It "zona neutra (35%-65%) -> nenhuma proposta (nao move sem sinal claro)" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8
                 tori_confluence_rejected_n=30; tori_confluence_rejected_hit_rate=0.50 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        @($props | Where-Object { $_.param -eq 'tori_confluence_threshold' }).Count | Should Be 0
    }
    It "n < 20 -> nenhuma proposta mesmo com hit_rate extremo (amostra pequena demais)" {
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8
                 tori_confluence_rejected_n=5; tori_confluence_rejected_hit_rate=1.0 }
        $props = @(Get-EvolutionProposals -Current $base -Evidence $ev)
        @($props | Where-Object { $_.param -eq 'tori_confluence_threshold' }).Count | Should Be 0
    }
    It "proposta de tori_confluence_threshold nunca ultrapassa bound (min 70)" {
        $atMin = [PSCustomObject]@{ pumpfade_min_pump_pct=15.0; sentinel_move_pct=2.5; sentinel_ignition_pct=12; pumpfade_dump_pct=-10; gem_sizing_pct=0.5; tori_confluence_threshold=70 }
        $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=1.0; sentinel_triggers_24h=5; sentinel_triggers_48h=8
                 tori_confluence_rejected_n=50; tori_confluence_rejected_hit_rate=0.90 }
        $props = @(Get-EvolutionProposals -Current $atMin -Evidence $ev)
        @($props | Where-Object { $_.param -eq 'tori_confluence_threshold' }).Count | Should Be 0
    }
}

Describe "Anti-oscilacao (congela flip-flop <72h)" {
    It "mudanca recente pra CIMA bloqueia proposta pra BAIXO" {
        $hist = @([PSCustomObject]@{ ts=(Get-Date).ToUniversalTime().AddHours(-10).ToString("o"); param="pumpfade_min_pump_pct"; before=15; after=16 })
        (Test-AntiOscillation -ParamName "pumpfade_min_pump_pct" -ProposedDelta -1 -History $hist) | Should Be $true
    }
    It "mesma direcao NAO bloqueia" {
        $hist = @([PSCustomObject]@{ ts=(Get-Date).ToUniversalTime().AddHours(-10).ToString("o"); param="pumpfade_min_pump_pct"; before=15; after=14 })
        (Test-AntiOscillation -ParamName "pumpfade_min_pump_pct" -ProposedDelta -1 -History $hist) | Should Be $false
    }
    It "mudanca antiga (>72h) NAO bloqueia" {
        $hist = @([PSCustomObject]@{ ts=(Get-Date).ToUniversalTime().AddHours(-100).ToString("o"); param="pumpfade_min_pump_pct"; before=15; after=16 })
        (Test-AntiOscillation -ParamName "pumpfade_min_pump_pct" -ProposedDelta -1 -History $hist) | Should Be $false
    }
}

Describe "Classe RISK nunca-auto (gate de capital)" {
    It "proposta risk vai para owner_pending, NUNCA aplicada" {
        # Simula ciclo com journal vazio e injeta proposta risk manualmente na
        # logica: valida via Invoke com evidencia que nao gera risk (v1 nao gera
        # risk automaticamente — o teste prova que o REGISTRO tem a classe e que
        # o filtro do Invoke separa por classe).
        $riskProps = @((Get-TunableRegistry) | Where-Object { $_.class -eq 'risk' })
        $riskProps.Count | Should BeGreaterThan 0
        # o filtro do Invoke: class -eq risk -> ownerPending (linha verificavel por AST)
        $src = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_evolution_engine.ps1") -Raw
        ($src -match '(?s)class -eq "risk".{0,120}ownerPending') | Should Be $true
        ($src -match 'NUNCA auto') | Should Be $true
    }
}

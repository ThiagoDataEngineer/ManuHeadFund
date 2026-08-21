# lib_evolution_engine.ps1 — EVOLUTION ENGINE v1 (auto-tuning L2, exchange-agnostic)
# 2026-07-04: o sistema ajusta os PROPRIOS parametros de deteccao com base em
# evidencia (placar de calibracao, historico de matches, densidade de triggers),
# dentro de LIMITES DUROS, com anti-oscilacao e trilha de auditoria completa.
#
# PRINCIPIOS (inegociaveis):
#   1. AGNOSTICO DE EXCHANGE: zero chamadas de API aqui. Le/escreve apenas
#      arquivos de dados (journal/*). Acopla em qualquer corretora via adapters.
#   2. CLASSE DE SEGURANCA: parametros 'detection' evoluem sozinhos;
#      parametros 'risk' (sizing/stop/target) NUNCA — apenas emitem proposta
#      'requires_owner' (aprovacao humana assincrona).
#   3. BOUNDS DUPLOS: o engine clampa E o consumidor clampa de novo
#      (defesa em profundidade — licao dos gates cegos).
#   4. ANTI-OSCILACAO: parametro que reverte direcao em <72h congela 7 dias.
#   5. AUDITORIA: toda mudanca em journal/evolution_history.jsonl
#      {ts, param, before, after, reason, evidence}.
#
# Overlay: journal/evolution_params.json — consumidores (sentinela, pump-fade)
# leem a cada ciclo; ausencia do arquivo = defaults do codigo (fail-safe).
# PS 5.1. UTF-8 BOM. Puro/testavel: I/O parametrizado por -JournalDir.

# ── Registro de parametros tunaveis (fonte de verdade) ──────────────────────
function Get-TunableRegistry {
    [CmdletBinding()] param()
    return @(
        [PSCustomObject]@{ name="sentinel_move_pct";     class="detection"; default=2.5; min=1.5; max=5.0;  step=0.25 }
        [PSCustomObject]@{ name="sentinel_ignition_pct"; class="detection"; default=12;  min=8;   max=20;   step=1 }
        [PSCustomObject]@{ name="pumpfade_min_pump_pct"; class="detection"; default=15;  min=8;   max=25;   step=1 }
        [PSCustomObject]@{ name="pumpfade_dump_pct";     class="detection"; default=-10; min=-20; max=-5;   step=1 }
        # 2026-07-09: pecas antes FORA do loop (auditoria 5 pecas) — agora tunaveis
        # 2026-08-21 FIX: min=70 travava o Evolution Engine (e Get-EvolutionParams,
        # que sempre roda e sobrescreve o default local de lib_tori_gate_wrapper.ps1)
        # num piso mais alto que o valor correto medido em producao real (2026-08-20:
        # 40-47 candidatos/ciclo 100% bloqueados em threshold=80, FRACTAL+baseline=65
        # e sinal minimo aceitavel em BULL/NEUTRO). O overlay sempre vencia o default
        # local (65) porque Get-EvolutionParams comeca do registry (min=70 antes),
        # nunca deixando o threshold real cair abaixo de 70 mesmo com evidencia forte.
        [PSCustomObject]@{ name="tori_confluence_threshold"; class="detection"; default=65;  min=65;  max=90;  step=2 }
        [PSCustomObject]@{ name="faro_signals_needed";       class="detection"; default=5;   min=4;   max=6;   step=1 }
        # RISK: nunca auto — qualquer proposta vira requires_owner
        [PSCustomObject]@{ name="gem_sizing_pct";        class="risk";      default=0.5; min=0.1; max=1.0;  step=0.1 }
        [PSCustomObject]@{ name="stop_atr_multiplier";   class="risk";      default=2.5; min=2.0; max=3.5;  step=0.25 }
        [PSCustomObject]@{ name="gem_max_exposure_pct";  class="risk";      default=15;  min=10;  max=25;   step=1 }
        [PSCustomObject]@{ name="trailing_be_buffer_pct"; class="risk";     default=0.02; min=0.01; max=0.05; step=0.005 }
    )
    # 2026-08-04 (nao implementado ainda, so contexto pra quando retomar):
    # owner pediu estender este registry pro stop_pct fixo por Mode
    # (Calculate-StopTarget, gem_executor.ps1) e o fallback fixo de
    # Get-StructuralStopTarget (StopPct=0.08/TargetPct=0.32 default) --
    # ambos hoje calibrados uma vez, nunca ajustados por resultado real.
    # Bloqueado por falta de dado: a origem do SL/TP (fixed_pct vs
    # structural) nunca sobrevivia ate o fechamento do trade, entao era
    # impossivel medir qual fonte rende melhor. Instrumentacao fechada
    # (commit 2c20d71): trade_outcomes agora grava sl_source/tp_source/
    # stop_pct_used no payload. Retomar quando houver ~1-2 semanas de
    # trades fechados com o campo populado (query manuheadfund.trade_outcomes
    # payload->>'sl_source' is not null) -- so entao desenhar bounds/step
    # com base em dado real, nao estimativa. Ver CLAUDE.md "Estado atual"
    # pro contexto completo da investigacao.
}

function Get-EvolutionParams {
    # Overlay atual (ou defaults). Consumidores chamam isto.
    [CmdletBinding()] param([string]$JournalDir = "")
    if (-not $JournalDir) { $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" } }
    $reg = Get-TunableRegistry
    $params = @{}
    foreach ($p in $reg) { $params[$p.name] = [double]$p.default }
    $path = Join-Path $JournalDir "evolution_params.json"
    $overlay = $null
    if (Test-Path $path) {
        try { $overlay = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $overlay = $null }
    }
    # Read-back Supabase (fecha o loop na NUVEM — runner sem journal local). So quando
    # nao ha overlay local E o helper de read-back esta carregado (mantem agnostico).
    if ($null -eq $overlay -and (Get-Command _Get-LearningFromSupabase -ErrorAction SilentlyContinue)) {
        $rows = @(_Get-LearningFromSupabase -Table "evolution_params" -Filter @{ id = "current" })
        if ($rows.Count -gt 0) { $overlay = $rows[0] }
    }
    if ($null -ne $overlay) {
        foreach ($p in $reg) {
            if ($overlay.PSObject.Properties[$p.name] -and $null -ne $overlay.($p.name)) {
                # CLAMP no engine (bound 1 de 2)
                $v = [double]$overlay.($p.name)
                if ($v -lt $p.min) { $v = $p.min }
                if ($v -gt $p.max) { $v = $p.max }
                $params[$p.name] = $v
            }
        }
    }
    return [PSCustomObject]$params
}

# ── Evidencia -> proposta (PURA, deterministica, testavel) ──────────────────
function Get-EvolutionProposals {
    <#
      Regras v1 (dados -> ajuste, sempre 1 step por ciclo, sempre com evidencia):
      A) pump-fade: 3+ dias com 0 match E dumpers vistos (>=5 no periodo)
         -> afrouxa min_pump 1 step (o pattern existe mas o trigger esta alto).
         Matches/dia > 5 -> aperta 1 step (frouxo demais = ruido no funil).
      B) sentinela: triggers 24h > 25 -> sobe move_pct 1 step (ruido);
         triggers 24h == 0 por 48h -> desce 1 step (surdo).
      Entrada por fixtures (testavel sem I/O real).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Current,       # params atuais
        [Parameter(Mandatory)] [hashtable] $Evidence            # metricas coletadas
        # Evidence esperado: pumpfade_days_zero_match, pumpfade_dumpers_seen,
        #                    pumpfade_matches_per_day, sentinel_triggers_24h,
        #                    sentinel_triggers_48h
    )
    $reg = @{}
    foreach ($p in (Get-TunableRegistry)) { $reg[$p.name] = $p }
    $proposals = @()

    # A) pump-fade min pump
    $p = $reg["pumpfade_min_pump_pct"]; $cur = [double]$Current.pumpfade_min_pump_pct
    if ([int]$Evidence.pumpfade_days_zero_match -ge 3 -and [int]$Evidence.pumpfade_dumpers_seen -ge 5) {
        $new = [math]::Max($p.min, $cur - $p.step)
        if ($new -ne $cur) {
            $proposals += [PSCustomObject]@{ param=$p.name; class=$p.class; before=$cur; after=$new
                reason="0 match ha $($Evidence.pumpfade_days_zero_match) dias com $($Evidence.pumpfade_dumpers_seen) dumpers vistos -> trigger alto demais" }
        }
    } elseif ([double]$Evidence.pumpfade_matches_per_day -gt 5) {
        $new = [math]::Min($p.max, $cur + $p.step)
        if ($new -ne $cur) {
            $proposals += [PSCustomObject]@{ param=$p.name; class=$p.class; before=$cur; after=$new
                reason="$($Evidence.pumpfade_matches_per_day) matches/dia -> frouxo demais (ruido no funil)" }
        }
    }

    # B) sentinela move
    $p = $reg["sentinel_move_pct"]; $cur = [double]$Current.sentinel_move_pct
    if ([int]$Evidence.sentinel_triggers_24h -gt 25) {
        $new = [math]::Min($p.max, $cur + $p.step)
        if ($new -ne $cur) {
            $proposals += [PSCustomObject]@{ param=$p.name; class=$p.class; before=$cur; after=$new
                reason="$($Evidence.sentinel_triggers_24h) triggers/24h -> ruidoso, sobe threshold" }
        }
    } elseif ([int]$Evidence.sentinel_triggers_48h -eq 0) {
        $new = [math]::Max($p.min, $cur - $p.step)
        if ($new -ne $cur) {
            $proposals += [PSCustomObject]@{ param=$p.name; class=$p.class; before=$cur; after=$new
                reason="0 triggers em 48h -> surdo, desce threshold" }
        }
    }

    # C) tori_confluence_threshold (2026-07-17: fecha o loop desenhado em
    # 2026-07-09 -- registro existia, nunca teve regra). Evidencia = MCE
    # Counterfactual filtrado por gate=tori_confluence (scripts/
    # mce_counterfactual_from_supabase.ps1, coluna "gate" nova no agrupamento):
    # hit_rate = fracao de rejeicoes POR BAIXA CONFLUENCIA que teriam dado lucro
    # (forward_return_24h > 0) se tivessem entrado. n minimo 20 (amostra pequena
    # nao move parametro real). Hit rate alto = threshold rejeitando setups bons
    # demais -> desce (mais permissivo). Hit rate baixo = threshold correto/ainda
    # frouxo -> sobe (mais rigoroso). Zona neutra 35%-65% -- sem proposta (nao
    # move parametro sem sinal claro).
    $p = $reg["tori_confluence_threshold"]; $cur = [double]$Current.tori_confluence_threshold
    $toriN = [int]$Evidence.tori_confluence_rejected_n
    $toriHitRate = [double]$Evidence.tori_confluence_rejected_hit_rate
    if ($toriN -ge 20) {
        if ($toriHitRate -ge 0.65) {
            $new = [math]::Max($p.min, $cur - $p.step)
            if ($new -ne $cur) {
                $proposals += [PSCustomObject]@{ param=$p.name; class=$p.class; before=$cur; after=$new
                    reason="$toriN rejeicoes por baixa confluencia, hit_rate=$([math]::Round($toriHitRate*100,0))% teriam dado lucro -> threshold rejeitando setups bons, desce" }
            }
        } elseif ($toriHitRate -le 0.35) {
            $new = [math]::Min($p.max, $cur + $p.step)
            if ($new -ne $cur) {
                $proposals += [PSCustomObject]@{ param=$p.name; class=$p.class; before=$cur; after=$new
                    reason="$toriN rejeicoes por baixa confluencia, hit_rate=$([math]::Round($toriHitRate*100,0))% -> filtro ainda correto/frouxo, sobe" }
            }
        }
    }

    return @($proposals)
}

function Test-AntiOscillation {
    # true = BLOQUEADO (param reverteu direcao em <72h -> congela)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ParamName,
        [Parameter(Mandatory)] [double] $ProposedDelta,
        [object[]] $History = @()
    )
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-72)
    # 2026-07-23 FIX: ConvertFrom-Json auto-promove ts ISO 8601 pra
    # [datetime] (perde 'Z'/offset), quebrando [datetime]::Parse subsequente
    # -- mesmo bug ja corrigido em lib_tori_proximity.ps1/lib_asymmetric_demote.ps1.
    $recent = @($History | Where-Object {
        if ($_.param -ne $ParamName) { return $false }
        $tsVal = if ($_.ts -is [datetime]) { $_.ts } else { [datetime]::Parse([string]$_.ts) }
        $tsVal.ToUniversalTime() -gt $cutoff
    } | Select-Object -Last 1)
    if ($recent.Count -eq 0) { return $false }
    $lastDelta = [double]$recent[0].after - [double]$recent[0].before
    # direcoes opostas = oscilacao
    return (($lastDelta -gt 0 -and $ProposedDelta -lt 0) -or ($lastDelta -lt 0 -and $ProposedDelta -gt 0))
}

function Invoke-EvolutionCycle {
    # Orquestrador I/O: coleta evidencia dos logs -> propostas -> aplica
    # detection (com anti-oscilacao) -> registra tudo -> risk vira pendencia owner.
    [CmdletBinding()]
    param([string]$JournalDir = "", [string]$LogsDir = "")
    if (-not $JournalDir) { $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" } }
    if (-not $LogsDir) { $LogsDir = Join-Path (Split-Path $JournalDir -Parent) "logs" }

    # ── Coleta evidencia ──
    $ev = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=0.0
             sentinel_triggers_24h=0; sentinel_triggers_48h=0
             tori_confluence_rejected_n=0; tori_confluence_rejected_hit_rate=0.0 }
    # pump-fade: ultimos 3 dias de master logs
    $zeroDays = 0; $dumpers = 0; $matches = 0; $daysWithData = 0
    for ($d = 0; $d -lt 3; $d++) {
        $lf = Join-Path $LogsDir ("master_{0}.log" -f (Get-Date).AddDays(-$d).ToString('yyyyMMdd'))
        if (-not (Test-Path $lf)) { continue }
        $daysWithData++
        $dayMatches = 0; $dayDumpers = 0
        foreach ($m in (Select-String -Path $lf -Pattern "PUMP-FADE: (\d+) match em (\d+) pares" -ErrorAction SilentlyContinue)) {
            $dayMatches += [int]$m.Matches[0].Groups[1].Value
            $dayDumpers += [int]$m.Matches[0].Groups[2].Value
        }
        if ($dayMatches -eq 0) { $zeroDays++ }
        $dumpers += $dayDumpers; $matches += $dayMatches
    }
    $ev.pumpfade_days_zero_match = $zeroDays
    $ev.pumpfade_dumpers_seen = $dumpers
    $ev.pumpfade_matches_per_day = if ($daysWithData -gt 0) { [math]::Round($matches / $daysWithData, 1) } else { 0 }
    # sentinela: triggers no log
    $sentLog = Join-Path $JournalDir "sentinel.log"
    if (Test-Path $sentLog) {
        $now = Get-Date
        foreach ($m in (Select-String -Path $sentLog -Pattern "^\[([\d\- :]+)\] TRIGGER" -ErrorAction SilentlyContinue)) {
            try {
                $t = [datetime]::ParseExact($m.Matches[0].Groups[1].Value, "yyyy-MM-dd HH:mm:ss", $null)
                if (($now - $t).TotalHours -le 24) { $ev.sentinel_triggers_24h++ }
                if (($now - $t).TotalHours -le 48) { $ev.sentinel_triggers_48h++ }
            } catch { }
        }
    }

    # tori_confluence: le manuheadfund.mce_counterfactual_agg (ja gravado por
    # scripts/mce_counterfactual_from_supabase.ps1, coluna "gate" adicionada
    # 2026-07-17) e agrega TODOS os grupos regime|direction com gate=tori_
    # confluence -- a regra C em Get-EvolutionProposals e global (nao por
    # regime), entao pondera por n em vez de decidir por regime isolado.
    # Guard por Get-Command mantem o engine agnostico (principio #1) -- so
    # roda se o helper de leitura do Supabase estiver carregado.
    if (Get-Command _Get-LearningFromSupabase -ErrorAction SilentlyContinue) {
        try {
            $toriRows = @(_Get-LearningFromSupabase -Table "mce_counterfactual_agg" -Filter @{ gate = "tori_confluence" })
            if ($toriRows.Count -gt 0) {
                $totalN = ($toriRows | Measure-Object -Property n -Sum).Sum
                if ($totalN -gt 0) {
                    $weightedHits = ($toriRows | ForEach-Object { [double]$_.n * [double]$_.hit_rate } | Measure-Object -Sum).Sum
                    $ev.tori_confluence_rejected_n = [int]$totalN
                    $ev.tori_confluence_rejected_hit_rate = [math]::Round($weightedHits / $totalN, 4)
                }
            }
        } catch {}
    }

    # ── Propostas ──
    $current = Get-EvolutionParams -JournalDir $JournalDir
    $proposals = @(Get-EvolutionProposals -Current $current -Evidence $ev)

    # Historia (anti-oscilacao)
    $histPath = Join-Path $JournalDir "evolution_history.jsonl"
    $history = @()
    if (Test-Path $histPath) {
        foreach ($l in (Get-Content $histPath -ErrorAction SilentlyContinue)) {
            try { $history += ($l | ConvertFrom-Json) } catch { }
        }
    }

    $applied = @(); $frozen = @(); $ownerPending = @()
    $newParams = @{}
    foreach ($p in (Get-TunableRegistry)) { $newParams[$p.name] = [double]$current.($p.name) }

    foreach ($prop in $proposals) {
        if ($prop.class -eq "risk") {
            $ownerPending += $prop   # NUNCA auto
            continue
        }
        $delta = [double]$prop.after - [double]$prop.before
        if (Test-AntiOscillation -ParamName $prop.param -ProposedDelta $delta -History $history) {
            $frozen += $prop
            continue
        }
        $newParams[$prop.param] = [double]$prop.after
        $applied += $prop
        $tsNow = (Get-Date).ToUniversalTime().ToString("o")
        $entry = @{ ts=$tsNow; param=$prop.param
                    before=$prop.before; after=$prop.after; reason=$prop.reason
                    evidence=$ev } | ConvertTo-Json -Compress -Depth 4
        Add-Content -Path $histPath -Value $entry -Encoding utf8

        # Espelho Supabase (manuheadfund.evolution_history) — 1 linha por mudanca (PK ts).
        # Guard por Get-Command: mantem o engine AGNOSTICO (principio #1) — se o helper
        # de mirror nao esta carregado, e no-op. Nunca chama API direto aqui.
        if (Get-Command _Mirror-LearningToSupabase -ErrorAction SilentlyContinue) {
            _Mirror-LearningToSupabase -Table "evolution_history" -PrimaryKey "ts" -Records @(
                @{ ts=$tsNow; param=[string]$prop.param; before=[double]$prop.before
                   after=[double]$prop.after; reason=[string]$prop.reason }
            )
        }
    }

    if ($applied.Count -gt 0) {
        ([PSCustomObject]$newParams | ConvertTo-Json) | Out-File -FilePath (Join-Path $JournalDir "evolution_params.json") -Encoding UTF8 -Force

        # Espelho Supabase (manuheadfund.evolution_params) — singleton id="current".
        if (Get-Command _Mirror-LearningToSupabase -ErrorAction SilentlyContinue) {
            $singleton = @{ id = "current"; updated_at = (Get-Date).ToUniversalTime().ToString("o") }
            foreach ($k in $newParams.Keys) { $singleton[$k] = [double]$newParams[$k] }
            _Mirror-LearningToSupabase -Table "evolution_params" -PrimaryKey "id" -Records @($singleton)
        }
    }
    if ($ownerPending.Count -gt 0) {
        $pend = @{ ts=(Get-Date).ToUniversalTime().ToString("o"); proposals=$ownerPending } | ConvertTo-Json -Depth 4
        Add-Content -Path (Join-Path $JournalDir "evolution_owner_pending.jsonl") -Value $pend -Encoding utf8
    }

    return [PSCustomObject]@{
        evidence = [PSCustomObject]$ev
        applied = $applied; frozen = $frozen; owner_pending = $ownerPending
    }
}

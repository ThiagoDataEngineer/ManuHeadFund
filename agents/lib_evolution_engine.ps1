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
        # RISK: nunca auto — qualquer proposta vira requires_owner
        [PSCustomObject]@{ name="gem_sizing_pct";        class="risk";      default=0.5; min=0.1; max=1.0;  step=0.1 }
    )
}

function Get-EvolutionParams {
    # Overlay atual (ou defaults). Consumidores chamam isto.
    [CmdletBinding()] param([string]$JournalDir = "")
    if (-not $JournalDir) { $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" } }
    $reg = Get-TunableRegistry
    $params = @{}
    foreach ($p in $reg) { $params[$p.name] = [double]$p.default }
    $path = Join-Path $JournalDir "evolution_params.json"
    if (Test-Path $path) {
        try {
            $overlay = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $reg) {
                if ($overlay.PSObject.Properties[$p.name]) {
                    # CLAMP no engine (bound 1 de 2)
                    $v = [double]$overlay.($p.name)
                    if ($v -lt $p.min) { $v = $p.min }
                    if ($v -gt $p.max) { $v = $p.max }
                    $params[$p.name] = $v
                }
            }
        } catch { }
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
    $recent = @($History | Where-Object {
        $_.param -eq $ParamName -and ([datetime]::Parse([string]$_.ts).ToUniversalTime() -gt $cutoff)
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
             sentinel_triggers_24h=0; sentinel_triggers_48h=0 }
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
        $entry = @{ ts=(Get-Date).ToUniversalTime().ToString("o"); param=$prop.param
                    before=$prop.before; after=$prop.after; reason=$prop.reason
                    evidence=$ev } | ConvertTo-Json -Compress -Depth 4
        Add-Content -Path $histPath -Value $entry -Encoding utf8
    }

    if ($applied.Count -gt 0) {
        ([PSCustomObject]$newParams | ConvertTo-Json) | Out-File -FilePath (Join-Path $JournalDir "evolution_params.json") -Encoding UTF8 -Force
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

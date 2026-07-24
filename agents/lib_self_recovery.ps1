# lib_self_recovery.ps1 -- Self-Recovery Engine (auto-healing)
# 2026-06-08: Detecta falhas em runtime, auto-corrige conhecidas, escala desconhecidas.
# Design: core de REGRAS PURAS (testavel sem I/O) + wrappers I/O finos.
# Custo: ZERO LLM (tudo deterministico). Fail-safe: nunca forca trade, so destrava infra.

# ─────────────────────────────────────────────────────────────────────────────
# Get-LogIssueType (PURA) -- classifica UMA linha de log num tipo de problema.
# Retorna: tori_block | lib_missing | api_429 | daemon_dead | cache_stale | none
# ─────────────────────────────────────────────────────────────────────────────
function Get-LogIssueType {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return "none" }
    $l = $Line.ToLower()

    # Ordem importa: padroes mais especificos primeiro.
    if ($l -match "nao disponivel|não disponível|nao carregou|não carregou|nao reconhecido|não é reconhecido|get-command.*null") { return "lib_missing" }
    if ($l -match "429|rate.?limit|too many requests|key rotacionada") { return "api_429" }
    if ($l -match "outro .* ja rodando|singleton lock|pid=.*exit|daemon.*morto|daemon.*dead") { return "daemon_dead" }
    if ($l -match "skip cache|recent_decision_cache|cache hit.*skip") { return "cache_stale" }
    if ($l -match "tori.*block|tori.*skip|tori_skip|trendline invalida|trendline inválida") { return "tori_block" }
    return "none"
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-CycleHealth (PURA) -- agrega issues de um ciclo num diagnostico.
# Input: array de tipos (output de Get-LogIssueType por linha).
# Output: { healthy; dominant_issue; counts; total_signals }
# Regra: dominant = issue mais frequente (exceto 'none'); healthy se sem issue critico.
# ─────────────────────────────────────────────────────────────────────────────
function Get-CycleHealth {
    param(
        [string[]]$Issues,
        [int]$TotalSignals = 0
    )
    $counts = @{}
    foreach ($i in $Issues) {
        if ($i -and $i -ne "none") {
            if ($counts.ContainsKey($i)) { $counts[$i]++ } else { $counts[$i] = 1 }
        }
    }

    $dominant = "none"
    $maxCount = 0
    foreach ($k in $counts.Keys) {
        if ($counts[$k] -gt $maxCount) { $maxCount = $counts[$k]; $dominant = $k }
    }

    # Saude: lib_missing/daemon_dead sao sempre criticos (infra quebrada).
    # tori_block/cache_stale so e critico se dominar 100% dos sinais (nada passa).
    $critical = $false
    if ($dominant -in @("lib_missing", "daemon_dead")) {
        $critical = $true
    } elseif ($dominant -in @("tori_block", "cache_stale") -and $TotalSignals -gt 0 -and $maxCount -ge $TotalSignals) {
        $critical = $true
    }

    return [PSCustomObject]@{
        healthy        = (-not $critical)
        dominant_issue = $dominant
        dominant_count = $maxCount
        counts         = $counts
        total_signals  = $TotalSignals
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-RecoveryAction (PURA) -- mapeia (issue, contagem consecutiva) -> acao.
# Output: { action; escalate; reason }
# Acoes: reload_libs | restart_daemon | rotate_key_wait | clear_cache | alert_user | none
# Escalation: cada issue tem um limiar; alem dele, escalate=true (alerta user).
# Fail-safe: tori_block NUNCA mexe em threshold (risco de forcar trade ruim) -- so alerta.
# ─────────────────────────────────────────────────────────────────────────────
function Get-RecoveryAction {
    param(
        [string]$IssueType,
        [int]$ConsecutiveCount = 1
    )
    switch ($IssueType) {
        "lib_missing" {
            # Infra quebrada: recarrega libs. Escala apos 3 falhas (restart nao resolveu).
            $esc = ($ConsecutiveCount -ge 3)
            $act = if ($esc) { "alert_user" } else { "reload_libs" }
            return [PSCustomObject]@{ action = $act; escalate = $esc; reason = "lib nao carregada (tentativa $ConsecutiveCount)" }
        }
        "daemon_dead" {
            # Daemon morto/duplicado: restart limpo. Escala apos 2 (restart nao segurou).
            $esc = ($ConsecutiveCount -ge 2)
            $act = if ($esc) { "alert_user" } else { "restart_daemon" }
            return [PSCustomObject]@{ action = $act; escalate = $esc; reason = "daemon morto/duplicado (tentativa $ConsecutiveCount)" }
        }
        "api_429" {
            # Rate limit: rotaciona key + espera. Escala apos 5 (provedor saturado).
            $esc = ($ConsecutiveCount -ge 5)
            $act = if ($esc) { "alert_user" } else { "rotate_key_wait" }
            return [PSCustomObject]@{ action = $act; escalate = $esc; reason = "rate limit API (tentativa $ConsecutiveCount)" }
        }
        "cache_stale" {
            # Cache pode bloquear legitimos: limpa. Escala apos 3.
            $esc = ($ConsecutiveCount -ge 3)
            $act = if ($esc) { "alert_user" } else { "clear_cache" }
            return [PSCustomObject]@{ action = $act; escalate = $esc; reason = "cache travando sinais (tentativa $ConsecutiveCount)" }
        }
        "tori_block" {
            # FAIL-SAFE: nunca auto-afrouxa Tori (risco). So loga; escala apos 3 p/ user decidir.
            $esc = ($ConsecutiveCount -ge 3)
            $act = if ($esc) { "alert_user" } else { "none" }
            return [PSCustomObject]@{ action = $act; escalate = $esc; reason = "Tori bloqueando 100% (tentativa $ConsecutiveCount) -- decisao humana" }
        }
        default {
            return [PSCustomObject]@{ action = "none"; escalate = $false; reason = "sem problema detectado" }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Update-RecoveryStreak (PURA) -- atualiza contador consecutivo de um issue.
# Input: estado anterior (hashtable), issue atual. Output: novo estado.
# Se issue == ultimo -> incrementa; senao -> reseta para 1 (ou 0 se none).
# ─────────────────────────────────────────────────────────────────────────────
function Update-RecoveryStreak {
    param(
        [hashtable]$State,
        [string]$CurrentIssue
    )
    if (-not $State) { $State = @{ last_issue = "none"; streak = 0 } }

    if ($CurrentIssue -eq "none" -or [string]::IsNullOrWhiteSpace($CurrentIssue)) {
        return @{ last_issue = "none"; streak = 0 }
    }
    if ($State.last_issue -eq $CurrentIssue) {
        return @{ last_issue = $CurrentIssue; streak = ([int]$State.streak + 1) }
    }
    return @{ last_issue = $CurrentIssue; streak = 1 }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-CycleHealth (I/O) -- le tail do log e produz diagnostico.
# Wrapper fino sobre as funcoes puras.
# ─────────────────────────────────────────────────────────────────────────────
function Test-CycleHealth {
    param(
        [Parameter(Mandatory)] [string]$LogPath,
        [int]$TailLines = 120
    )
    if (-not (Test-Path $LogPath)) {
        return [PSCustomObject]@{ healthy = $true; dominant_issue = "none"; dominant_count = 0; counts = @{}; total_signals = 0; note = "log inexistente" }
    }
    $lines = Get-Content -Path $LogPath -Tail $TailLines -ErrorAction SilentlyContinue
    if (-not $lines) {
        return [PSCustomObject]@{ healthy = $true; dominant_issue = "none"; dominant_count = 0; counts = @{}; total_signals = 0; note = "log vazio" }
    }

    $issues = @()
    $signals = 0
    foreach ($ln in $lines) {
        $t = Get-LogIssueType -Line $ln
        if ($t -ne "none") { $issues += $t }
        # Conta "sinais" como linhas de GEM/EXECUTOR processadas (proxy de oportunidades).
        if ($ln -match "GEM EXECUTOR|\[GEM\].*score=|score=\d+") { $signals++ }
    }
    return Get-CycleHealth -Issues $issues -TotalSignals $signals
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-RecoveryLog (I/O) -- append JSONL estruturado do evento de recovery.
# ─────────────────────────────────────────────────────────────────────────────
function Write-RecoveryLog {
    param(
        [Parameter(Mandatory)] [object]$Entry,
        [string]$Path
    )
    if (-not $Path) {
        $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Join-Path $PSScriptRoot "..") "journal" }
        $Path = Join-Path $base "self_recovery.jsonl"
    }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $line = ($Entry | ConvertTo-Json -Compress -Depth 5)
        Add-Content -Path $Path -Value $line -Encoding UTF8
        return $true
    } catch {
        Write-Host "  [SELF-RECOVERY] falha ao logar: $_" -ForegroundColor Yellow
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-AutoRecover (I/O) -- orquestra: diagnostica -> decide -> aplica -> loga.
# Recebe paths e estado de streak (persistido entre ciclos). Retorna resultado.
# Acoes destrutivas (restart) sao opt-in via -AllowRestart pra teste seguro.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-AutoRecover {
    param(
        [Parameter(Mandatory)] [string]$LogPath,
        [string]$StatePath,
        [string]$RecoveryLogPath,
        [switch]$AllowRestart,
        [switch]$DryRun
    )
    if (-not $StatePath) {
        $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Join-Path $PSScriptRoot "..") "journal" }
        $StatePath = Join-Path $base "self_recovery_state.json"
    }

    # 1. Diagnostico
    $health = Test-CycleHealth -LogPath $LogPath

    # 2. Carrega estado anterior (streak)
    $state = $null
    if (Test-Path $StatePath) {
        try { $state = (Get-Content $StatePath -Raw | ConvertFrom-Json) } catch {}
    }
    $stateHash = @{
        last_issue = if ($state -and $state.last_issue) { "$($state.last_issue)" } else { "none" }
        streak     = if ($state -and $state.streak) { [int]$state.streak } else { 0 }
    }

    # 3. Atualiza streak + decide acao
    $newState = Update-RecoveryStreak -State $stateHash -CurrentIssue $health.dominant_issue
    $decision = Get-RecoveryAction -IssueType $health.dominant_issue -ConsecutiveCount $newState.streak

    # 4. Aplica acao (se nao DryRun)
    $applied = "none"
    if (-not $DryRun -and $decision.action -ne "none") {
        $applied = Invoke-RecoveryAction -Action $decision.action -AllowRestart:$AllowRestart -Health $health
    }

    # 5. Persiste estado + loga
    try { ($newState | ConvertTo-Json -Compress) | Set-Content -Path $StatePath -Encoding UTF8 } catch {}

    $entry = [ordered]@{
        ts             = (Get-Date).ToUniversalTime().ToString("o")
        dominant_issue = $health.dominant_issue
        dominant_count = $health.dominant_count
        healthy        = $health.healthy
        streak         = $newState.streak
        action         = $decision.action
        applied        = $applied
        escalate       = $decision.escalate
        reason         = $decision.reason
        total_signals  = $health.total_signals
    }
    Write-RecoveryLog -Entry $entry -Path $RecoveryLogPath | Out-Null

    # 6. Escalation -> alerta TG (se disponivel)
    if ($decision.escalate -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
        $msg = "🛠️ *SELF-RECOVERY ESCALATION*`nProblema: $($health.dominant_issue) ($($newState.streak)x consecutivo)`nAcao auto falhou. $($decision.reason)`nIntervencao humana recomendada."
        try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
    }

    return [PSCustomObject]@{
        health   = $health
        decision = $decision
        applied  = $applied
        streak   = $newState.streak
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-RecoveryAction (I/O) -- executa a acao fisica. Isolada p/ testabilidade.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-RecoveryAction {
    param(
        [Parameter(Mandatory)] [string]$Action,
        [switch]$AllowRestart,
        [object]$Health
    )
    switch ($Action) {
        "reload_libs" {
            # Recarrega libs criticas no escopo atual (best-effort).
            $libs = @("lib_market_router.ps1", "lib_order_routed.ps1", "lib_coinex.ps1", "tech_agent_ai.ps1")
            $loaded = 0
            foreach ($lib in $libs) {
                $p = Join-Path $PSScriptRoot $lib
                if (Test-Path $p) { try { . $p; $loaded++ } catch {} }
            }
            Write-Host "  [SELF-RECOVERY] reload_libs: $loaded libs recarregadas" -ForegroundColor Cyan
            return "reload_libs:$loaded"
        }
        "clear_cache" {
            $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Join-Path $PSScriptRoot "..") "journal" }
            $cachePath = Join-Path $base "gem_recent_decisions.json"
            if (Test-Path $cachePath) {
                try { "[]" | Set-Content -Path $cachePath -Encoding UTF8; Write-Host "  [SELF-RECOVERY] clear_cache: gem_recent_decisions limpo" -ForegroundColor Cyan; return "clear_cache:ok" } catch { return "clear_cache:fail" }
            }
            return "clear_cache:nofile"
        }
        "rotate_key_wait" {
            # Espera curta p/ rate limit recuperar (key rotation ja e automatica no tech agent).
            Write-Host "  [SELF-RECOVERY] rotate_key_wait: aguardando recuperacao de rate limit" -ForegroundColor Cyan
            return "rotate_key_wait:signaled"
        }
        "restart_daemon" {
            if (-not $AllowRestart) {
                Write-Host "  [SELF-RECOVERY] restart_daemon: SUPRIMIDO (AllowRestart=false)" -ForegroundColor DarkYellow
                return "restart_daemon:suppressed"
            }
            $script = Join-Path (Join-Path $PSScriptRoot "..") "scripts" "restart_all_daemons.ps1"
            if (Test-Path $script) {
                try { Start-Process pwsh -ArgumentList "-NoProfile","-File","`"$script`"" -WindowStyle Hidden; return "restart_daemon:launched" } catch { return "restart_daemon:fail" }
            }
            return "restart_daemon:noscript"
        }
        "alert_user" {
            return "alert_user:logged"
        }
        default { return "none" }
    }
}

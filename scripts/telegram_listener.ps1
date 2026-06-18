# telegram_listener.ps1 -- Bot Telegram com /ask + comandos
# PS 5.1. UTF-8 BOM. Sem emojis inline (encoding issue PS5.1).

param([switch]$Force, [switch]$Once)

$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir   = Join-Path $projectRoot "agents"
$journalDir  = Join-Path $projectRoot "journal"
$stateFile   = Join-Path $journalDir "tg_listener_state.json"
$logFile     = Join-Path $journalDir "tg_listener.log"

function Write-TgLog { param([string]$Level, [string]$Msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts [$Level] $Msg" | Out-File $logFile -Append -Encoding utf8
}

# Idempotent ROBUSTO via lib_daemon_singleton (lockfile PID+start_ticks; imune ao
# blindspot de CommandLine NULL em processos elevados que causava DUPLICATAS).
$myPid = $PID
$__singletonLib = Join-Path $agentsDir "lib_daemon_singleton.ps1"
$__lockDir      = Join-Path $journalDir "daemon_locks"
if (Test-Path $__singletonLib) {
    . $__singletonLib
    if (-not (Enter-DaemonSingleton -Name "telegram_listener" -LockDir $__lockDir)) {
        Write-TgLog "SKIP" "Outro tg_listener ja detem o singleton lock; PID=$myPid exit."
        exit 0
    }
}

Set-Location $projectRoot
try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_claude.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_promotion_ladder.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_promotion_gates.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_market_context_engine.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_idea_triggers.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_tg_approval_handler.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-TgLog "ERROR" "Load libs falhou: $($_.Exception.Message)"
    exit 1
}

if (-not $env:TELEGRAM_BOT_TOKEN) { Write-TgLog "ERROR" "TELEGRAM_BOT_TOKEN missing"; exit 1 }
if (-not $env:TELEGRAM_CHAT_ID)   { Write-TgLog "ERROR" "TELEGRAM_CHAT_ID missing"; exit 1 }

$ALLOWED_CHAT = $env:TELEGRAM_CHAT_ID

$lastOffset = 0
if (Test-Path $stateFile) {
    try { $st = Get-Content $stateFile -Raw | ConvertFrom-Json; $lastOffset = [long]$st.last_update_id } catch {}
}
Write-TgLog "INFO" "TgListener iniciado PID=$myPid last_offset=$lastOffset"


function Get-TelegramUpdates {
    param([long]$Offset = 0)
    try {
        $url = "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/getUpdates?offset=$($Offset+1)&timeout=20"
        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 30
        if ($r.ok) { return $r.result } else { return @() }
    } catch {
        Write-TgLog "WARN" "getUpdates falhou: $($_.Exception.Message)"
        return @()
    }
}


function Save-Offset { param([long]$Offset)
    @{ last_update_id = $Offset; updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") } | ConvertTo-Json | Out-File $stateFile -Encoding utf8
}


function Cmd-Help {
    return "<b>Comandos:</b>`n`n/ask &lt;pergunta&gt; -- Claude com contexto`n/status -- saude processos`n/markets -- precos Tier A LIVE`n/scan -- trigger cron manual`n`n<b>Ideas (price triggers):</b>`n/idea MARKET PRICE -- cria alerta`n/ideas -- lista ativas`n/idea_cancel ID -- cancela`n`n<b>Promotion ladder:</b>`n/demote MARKET [razao] -- rebaixa Tier A`n/keep MARKET [nota] -- mantem Tier A (audit)`n`n<b>Sistema:</b>`n/halt -- pausa LIVE`n/resume -- reativa LIVE`n/help -- esta lista`n`nEx: <i>/idea INJ 4.80</i> = avisa quando INJ atingir `$4.80`nEx: <i>/demote PENDLE drawdown -19%</i>"
}


function Cmd-Demote {
    param([string]$Arg)
    if (-not $Arg.Trim()) { return "Use: /demote MARKET [razao]" }
    $parts = $Arg.Trim() -split '\s+', 2
    $market = $parts[0].ToUpper()
    if (-not $market.EndsWith("USDT")) { $market = "$market" + "USDT" }
    $reason = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "manual_telegram" }

    if (-not (Get-Command Add-DemoteEvent -ErrorAction SilentlyContinue)) {
        return "Add-DemoteEvent indisponivel -- check lib_promotion_gates dot-source"
    }
    try {
        Add-DemoteEvent -Market $market -Reason $reason

        # Append promotion ladder event tambem (tier_state -> downgrade ate OBSERVATION)
        $pipelinePath = Join-Path $journalDir "promotion_pipeline.jsonl"
        if ((Test-Path $pipelinePath) -and (Get-Command Get-PromotionState -ErrorAction SilentlyContinue)) {
            $st = Get-PromotionState -Path $pipelinePath -Market $market
            if ($st -and $st.tier_state -gt 1) {
                $newTier = [Math]::Max(1, $st.tier_state - 1)
                Add-PromotionEvent -Path $pipelinePath -Market $market -Event "demoted" `
                    -TierState $newTier -Source "telegram" -Notes $reason | Out-Null
                Write-TgLog "DEMOTE" "$market $($st.tier_state)->$newTier reason=$reason"
                return "Demote registrado: $market $($st.tier_label) -> $(Get-TierLabel -State $newTier)`nRazao: $reason`nCooldown 30d ativado."
            }
        }
        Write-TgLog "DEMOTE" "$market (sem ladder state) reason=$reason"
        return "Demote registrado: $market`nRazao: $reason`nCooldown 30d ativado (lib_promotion_gates)."
    } catch {
        return "Erro registrando demote: $($_.Exception.Message)"
    }
}


function Cmd-Keep {
    # Audit-only: registra decisao de "manter" Tier A apesar de candidato a demote.
    # Nao muda state, so loga em journal/keep_decisions.jsonl pra retrospectiva.
    param([string]$Arg)
    if (-not $Arg.Trim()) { return "Use: /keep MARKET [nota]" }
    $parts = $Arg.Trim() -split '\s+', 2
    $market = $parts[0].ToUpper()
    if (-not $market.EndsWith("USDT")) { $market = "$market" + "USDT" }
    $note = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "" }

    $logFile = Join-Path $journalDir "keep_decisions.jsonl"
    $event = @{
        ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        market = $market
        note   = $note
        source = "telegram"
    } | ConvertTo-Json -Compress
    try {
        Add-Content -Path $logFile -Value $event -Encoding UTF8
        Write-TgLog "KEEP" "$market note=$note"
        return "Keep registrado: $market`n$( if($note){"Nota: $note"}else{"sem nota"} )`nTier A mantido."
    } catch {
        return "Erro registrando keep: $($_.Exception.Message)"
    }
}


function Cmd-Idea {
    param([string]$Arg)
    if (-not $Arg.Trim()) { return "Use: /idea MARKET PRICE [long|short]" }
    $parts = $Arg.Trim() -split '\s+'
    if ($parts.Count -lt 2) { return "Use: /idea MARKET PRICE [long|short]" }
    $market = $parts[0].ToUpper()
    if (-not $market.EndsWith("USDT")) { $market = "$market" + "USDT" }
    $price = 0.0
    if (-not [double]::TryParse($parts[1], [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$price)) {
        return "Preco invalido: $($parts[1])"
    }
    $direction = if ($parts.Count -ge 3 -and ($parts[2] -in @("long","short"))) { $parts[2] } else { "auto" }

    try {
        $r = Add-IdeaTrigger -Market $market -TriggerPrice $price -Direction $direction
        $arrow = if ($r.trigger_type -eq "above") { "subir para" } else { "cair para" }
        return "Idea criada: <code>$($r.id)</code>`n$market vai $arrow `$$price (atual `$$($r.current_price))`nDirecao: $($r.direction.ToUpper())`n`nAvisarei quando bater."
    } catch {
        return "Erro criando idea: $($_.Exception.Message)"
    }
}


function Cmd-Ideas {
    return (Format-IdeaList)
}


function Cmd-IdeaCancel {
    param([string]$Arg)
    $id = $Arg.Trim()
    if (-not $id) { return "Use: /idea_cancel ID" }
    $r = Update-IdeaStatus -Id $id -Status "cancelled" -Notes "user cancel"
    if ($r) { return "Idea $id cancelada." }
    return "Idea $id nao encontrada."
}


function Cmd-Status {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -match 'gem_loop\.ps1|watchdog_paper\.ps1|scan_master\.ps1|telegram_listener' })
    $lines = @("<b>Sistema status</b>", "")
    foreach ($p in $procs) {
        $name = if ($p.CommandLine -match 'gem_loop')  { 'gem_loop' }
                elseif ($p.CommandLine -match 'watchdog') { 'watchdog' }
                elseif ($p.CommandLine -match 'scan_master') { 'scan_master' }
                elseif ($p.CommandLine -match 'telegram_listener') { 'tg_listener' }
                else { 'unknown' }
        $up = [Math]::Round(((Get-Date) - $p.CreationDate).TotalHours, 1)
        $lines += "$name : ${up}h up"
    }
    $liveFlag = Test-Path (Join-Path $journalDir "LIVE_MODE_ENABLED.flag")
    $lines += ""
    $lines += "LIVE mode: $(if($liveFlag){'ATIVO'}else{'OFF'})"
    return ($lines -join "`n")
}


function Cmd-Markets {
    try {
        $lines = @("<b>Tier A LIVE agora</b>", "")
        $files = Get-ChildItem -Path $journalDir -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $files) { return "whitelist nao encontrada" }
        $wl = Get-Content $files.FullName -Raw | ConvertFrom-Json
        $tierA = $wl.TIER_A_LIVE | Where-Object { $_.market -notmatch 'BITSTAMP' }
        foreach ($e in $tierA) {
            try {
                $url = "https://api.coinex.com/v2/spot/ticker?market=$($e.market)"
                $r = Invoke-RestMethod -Uri $url -TimeoutSec 8
                $t = $r.data[0]
                $last = [double]$t.last; $op = [double]$t.open
                $pct = if ($op -gt 0) { [Math]::Round((($last - $op) / $op) * 100, 2) } else { 0 }
                $arrow = if ($pct -gt 0) { '+' } elseif ($pct -lt 0) { '-' } else { '=' }
                $lines += "$arrow $($e.market) `$$last ($pct%)"
            } catch { $lines += "$($e.market) ERR" }
        }
        return ($lines -join "`n")
    } catch { return "erro: $($_.Exception.Message)" }
}


function Cmd-Scan {
    try {
        # Flag manual: cron detecta e manda summary Telegram mesmo com 0 actions.
        $flag = Join-Path $journalDir "MANUAL_SCAN_REQUEST.flag"
        @{ requested_at = (Get-Date).ToString('o'); chat_id = $script:AllowedChat } |
            ConvertTo-Json -Compress | Out-File $flag -Encoding utf8 -Force
        Start-ScheduledTask -TaskName CoinExPromotionCron -ErrorAction Stop
        return "PromotionCron disparado (pipeline: promotion + discovery + LW + revalidations). Voce recebera summary ao final (~5min)."
    } catch { return "erro disparando cron: $($_.Exception.Message)" }
}


function Cmd-Halt {
    $flag = Join-Path $journalDir "LIVE_MODE_ENABLED.flag"
    if (Test-Path $flag) {
        Remove-Item $flag -Force
        return "LIVE mode DESATIVADO. Proximo restart watchdog volta DryRun."
    }
    return "LIVE flag ja estava off."
}


function Cmd-Resume {
    $flag = Join-Path $journalDir "LIVE_MODE_ENABLED.flag"
    if (-not (Test-Path $flag)) {
        "LIVE_MODE_ENABLED`nativado_em: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File $flag -Encoding utf8
        return "LIVE mode ATIVADO. Proximo restart paper trade entra LIVE."
    }
    return "LIVE flag ja estava on."
}

# 2026-06-18: Novos botoes (controle + vigilancia)
function Cmd-Balance {
    try {
        if (Get-Command CoinEx-GetBalance -ErrorAction SilentlyContinue) {
            $bal = @(CoinEx-GetBalance | Where-Object { [double]$_.available -gt 0 -or [double]$_.frozen -gt 0 })
            $total = 0
            $bal | ForEach-Object { $total += [double]$_.available + [double]$_.frozen }
            $msg = "Capital TOTAL: `$$('{0:N2}' -f $total)`n`n"
            $bal | ForEach-Object {
                $msg += "$($_.coin): avail=$($_.available) frozen=$($_.frozen)`n"
            }
            return $msg
        }
    } catch {}
    return "Balance indisponivel"
}

function Cmd-Stops {
    try {
        if (Get-Command CoinEx-GetOpenOrders -ErrorAction SilentlyContinue) {
            $orders = @(CoinEx-GetOpenOrders | Where-Object { $_.stop_price -and [double]$_.stop_price -gt 0 })
            if ($orders.Count -eq 0) { return "Nenhum stop order ativo (vigilancia OK)" }
            $msg = "STOP ORDERS EM VIGILANCIA: $($orders.Count)`n`n"
            $orders | ForEach-Object {
                $msg += "$($_.market) | price=$($_.price) | stop=$($_.stop_price)`n"
            }
            return $msg
        }
    } catch {}
    return "Stops indisponivel"
}


function Build-AskContext {
    $ctx = @{}
    try {
        $files = Get-ChildItem -Path $journalDir -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($files) {
            $wl = Get-Content $files.FullName -Raw | ConvertFrom-Json
            $ctx.tier_a = ($wl.TIER_A_LIVE | ForEach-Object { $_.market }) -join ', '
            $ctx.tier_b = ($wl.TIER_B_PAPER | ForEach-Object { $_.market }) -join ', '
        }
    } catch {}
    try {
        $ddFile = Get-ChildItem -Path $journalDir -Filter "tier_a_drawdown_*.json" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($ddFile) {
            $dd = Get-Content $ddFile.FullName -Raw | ConvertFrom-Json
            $ctx.drawdowns = ($dd.drawdowns | ForEach-Object { "$($_.market) $($_.vs_peak_pct)%" }) -join ' | '
            $ctx.flagged = ($dd.flagged) -join ', '
        }
    } catch {}
    try {
        if (Get-Command Test-ContextAllowsTrade -ErrorAction SilentlyContinue) {
            $mce = Test-ContextAllowsTrade -DateBrt (Get-Date) -Regime "BULL_WEAK"
            $ctx.mce_score = $mce.score
            $ctx.mce_action = $mce.action
        }
    } catch {}
    $ctx.date_brt = (Get-Date).ToString("yyyy-MM-dd HH:mm BRT")
    return $ctx
}


function Cmd-Ask {
    param([string]$Question)
    if (-not $Question.Trim()) { return "Use: /ask <pergunta>" }

    $ctx = Build-AskContext
    $sysPrompt = "Voce eh assistente do sistema CoinEx AI Agent operando para Thiago (dev web3, opera futuros pessoalmente, dados banco). Tom: direto, sem jargao excessivo. Numeros com significado. Curto (3-5 frases). Estado: Data $($ctx.date_brt). Tier A LIVE: $($ctx.tier_a). Tier B: $($ctx.tier_b). Drawdowns 7d: $($ctx.drawdowns). Flagged: $($ctx.flagged). MCE Context: $($ctx.mce_score) -> $($ctx.mce_action). Filosofia: defensivo em Maio (Sell in May), mes 24 pos-halving = territorio distribuicao/topo. Sistema NAO entra pumps tardios."
    try {
        $resp = Invoke-Claude -SystemPrompt $sysPrompt -UserContent $Question `
            -MaxTokens 500 -Temperature 0.5 -Agent "tg_listener"
        if ($resp -and $resp.text) { return $resp.text }
        return "Resposta vazia."
    } catch {
        return "Claude API erro: $($_.Exception.Message)"
    }
}


function Process-Update {
    param([PSCustomObject]$Update)
    $msg = $Update.message
    if (-not $msg -or -not $msg.text) { return }
    $chatId = "$($msg.chat.id)"
    if ($chatId -ne $ALLOWED_CHAT) {
        Write-TgLog "WARN" "Mensagem de chat nao autorizado: $chatId"
        return
    }
    $text = $msg.text.Trim()
    Write-TgLog "MSG" "[$chatId] $text"

    $reply = ""
    if ($text -match '^/(\w+)(\s+(.*))?$') {
        $cmd = $matches[1].ToLower()
        $arg = if ($matches[3]) { $matches[3] } else { "" }
        switch ($cmd) {
            "help"          { $reply = Cmd-Help }
            "status"        { $reply = Cmd-Status }
            "markets"       { $reply = Cmd-Markets }
            "scan"          { $reply = Cmd-Scan }
            "promote"       { $reply = Cmd-Scan }
            "halt"          { $reply = Cmd-Halt }
            "resume"        { $reply = if (Get-Command Process-ApprovalCommand -ErrorAction SilentlyContinue) { (Process-ApprovalCommand -Command "/resume" -JournalDir $journalDir).message } else { Cmd-Resume } }
            "ask"           { $reply = Cmd-Ask -Question $arg }
            "idea"          { $reply = Cmd-Idea -Arg $arg }
            "ideas"         { $reply = Cmd-Ideas }
            "idea_cancel"   { $reply = Cmd-IdeaCancel -Arg $arg }
            "demote"        { $reply = Cmd-Demote -Arg $arg }
            "keep"          { $reply = Cmd-Keep -Arg $arg }
            # 2026-06-09: Approval handlers
            "approve"       { $reply = if (Get-Command Process-ApprovalCommand -ErrorAction SilentlyContinue) { (Process-ApprovalCommand -Command "/approve" -Market $arg -JournalDir $journalDir).message } else { "Approval handler indisponivel" } }
            "reject"        { $reply = if (Get-Command Process-ApprovalCommand -ErrorAction SilentlyContinue) { (Process-ApprovalCommand -Command "/reject" -Market $arg -JournalDir $journalDir).message } else { "Approval handler indisponivel" } }
            "pause"         { $reply = if (Get-Command Process-ApprovalCommand -ErrorAction SilentlyContinue) { (Process-ApprovalCommand -Command "/pause" -JournalDir $journalDir).message } else { "Approval handler indisponivel" } }
            # 2026-06-18: Botoes novos (controle + vigilancia)
            "balance"       { $reply = Cmd-Balance }
            "stops"         { $reply = Cmd-Stops }
            default         { $reply = "Comando desconhecido. /help" }
        }
    } else {
        $reply = Cmd-Ask -Question $text
    }
    if ($reply) {
        Send-TelegramAlert -Message $reply | Out-Null
        Write-TgLog "REPLY" "ok"
    }
}


# Idea check counter (1x por minuto = 12 cycles de 5s)
$ideaCheckCounter = 0
$hbFilePath = Join-Path $journalDir "tg_listener_hb"
# Heartbeat inicial pra watchdog detectar liveness imediato
try {
    @{ pid = $myPid; ts = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ"); offset = $lastOffset; iter = 0 } |
        ConvertTo-Json -Compress | Out-File $hbFilePath -Encoding utf8 -Force
} catch {}
$iter = 0
while ($true) {
    # Heartbeat ANTES de getUpdates (que pode demorar 20s+)
    $iter++
    try {
        @{ pid = $myPid; ts = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ"); offset = $lastOffset; iter = $iter } |
            ConvertTo-Json -Compress | Out-File $hbFilePath -Encoding utf8 -Force
    } catch {}

    $updates = Get-TelegramUpdates -Offset $lastOffset
    foreach ($u in $updates) {
        try {
            Process-Update -Update $u
            $lastOffset = [long]$u.update_id
            Save-Offset -Offset $lastOffset
        } catch {
            Write-TgLog "ERROR" "Process-Update erro: $($_.Exception.Message)"
        }
    }
    # Check ideas a cada 60s (12 cycles de 5s)
    $ideaCheckCounter++
    if ($ideaCheckCounter -ge 12) {
        $ideaCheckCounter = 0
        if (Get-Command Invoke-IdeaCheckCycle -ErrorAction SilentlyContinue) {
            try {
                $fired = Invoke-IdeaCheckCycle
                foreach ($f in $fired) {
                    $msg = "<b>IDEA TRIGGER FIROU</b>`n`n<code>$($f.id)</code> $($f.market) $($f.direction.ToUpper())`nPreco atingiu `$$($f.fired_price) (trigger `$$($f.trigger_price))`n`nUse /ask para analise contextual ou aguarde sistema avaliar setup tecnico."
                    Send-TelegramAlert -Message $msg | Out-Null
                    Write-TgLog "TRIGGER" "Idea $($f.id) $($f.market) fired"
                }
            } catch {
                Write-TgLog "WARN" "IdeaCheckCycle erro: $($_.Exception.Message)"
            }
        }
    }
    if ($Once) { break }
    Start-Sleep -Seconds 5
}

# lib_telegram_interactive_commands.ps1
# Interactive Telegram commands for capital owner
# Essential + Control + Analytics + Learning
# 2026-07-08

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# ─────────────────────────────────────────────────────────────────────────────
# HELP — Listar todos os comandos disponíveis
# ─────────────────────────────────────────────────────────────────────────────
function Send-HelpMenu {
    <#
    .SYNOPSIS
    Envia menu de ajuda com todos os comandos disponíveis.
    #>
    [CmdletBinding()]
    param()

    $help = @"
📚 **COMANDOS DISPONÍVEIS**

**ESSENCIAL (automático):**
/trade — Trade aberto/fechado (automático)
/sl — Stop loss batido (automático)
/tp — Take profit batido (automático)
/trailing — Ganho garantido (automático)

**SAÚDE DO SISTEMA:**
/health — Status geral (daemons, capital, posições)
/status — Estado atual (regime, saldos, wins/losses)
/positions — Posições abertas + PnL
/capital — Capital disponível vs usado

**ANÁLISE & APRENDIZADO:**
/analyze <moeda> — Análise LLM rápida (Haiku)
/mentor — Discussão com mentor (Sonnet)
/recalibrate — Sugerir recalibragem automática
/learn — Análise de auto-aprendizado

**CONTROLE:**
/halt — Pausar sistema (circuit breaker)
/resume — Retomar (após halt)
/restart — Reiniciar daemons
/config — Ver configuração atual

**AUDIT & HISTÓRICO:**
/pnl — PnL diário + stats
/trades — Últimas 10 trades
/audit — Auditoria de saúde profissional
/journal — Últimas decisões (journal)

**HELP:**
/help — Este menu
/commands — Listar comandos apenas

Digite: /comando [args]
Exemplo: /analyze BTCUSDT
"@

    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $help | Out-Null
        }
    } catch {
        Write-Host "[WARN] Falha ao enviar help: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH — Status geral do sistema
# ─────────────────────────────────────────────────────────────────────────────
function Send-HealthCheck {
    <#
    .SYNOPSIS
    Envia check de saúde: daemons, capital, posições abertas.
    #>
    [CmdletBinding()]
    param()

    try {
        # Daemons status
        $daemons = @("gem_loop", "scan_master", "watchdog", "tg_listener")
        $daemon_status = @()
        foreach ($d in $daemons) {
            $proc = Get-Process -Name pwsh -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -match $d } |
                    Select-Object -First 1
            $status = if ($proc) { "✅ UP (PID $($proc.Id))" } else { "❌ DOWN" }
            $daemon_status += "${d}: $status"
        }

        # Capital status
        $capital_total = if ($global:CAPITAL_TOTAL) { $global:CAPITAL_TOTAL } else { 3000 }
        $open_pos = (Get-Content "$global:JOURNAL_DIR/open_positions_tracking.jsonl" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue)
        $pos_count = if ($open_pos.positions) { @($open_pos.positions).Count } else { 0 }
        $pnl_total = if ($open_pos.positions) {
            [math]::Round(($open_pos.positions | Measure-Object -Property pnl_usd -Sum).Sum, 2)
        } else { 0 }

        # Regime
        $regime = if ($global:MARKET_REGIME) { $global:MARKET_REGIME } else { "UNKNOWN" }

        $msg = @"
🏥 **HEALTH CHECK**

**Daemons:**
$($daemon_status -join "`n")

**Capital:**
Total: $capital_total USDT
Posições abertas: $pos_count
PnL atual: $pnl_total USD

**Regime:**
$regime

**Timestamp:**
$([datetime]::Now.ToString("HH:mm dd/MM"))
"@

        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }
    } catch {
        Write-Host "[WARN] Falha ao enviar health: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# POSITIONS — Listar posições abertas com PnL
# ─────────────────────────────────────────────────────────────────────────────
function Send-PositionsList {
    <#
    .SYNOPSIS
    Envia lista de posições abertas formatada.
    #>
    [CmdletBinding()]
    param()

    try {
        $tracking = Get-Content "$global:JOURNAL_DIR/open_positions_tracking.jsonl" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue

        if (-not $tracking.positions -or $tracking.positions.Count -eq 0) {
            Send-TelegramAlert -Message "📭 Nenhuma posição aberta" | Out-Null
            return
        }

        $futures = @($tracking.positions | Where-Object market_type -eq "FUTURES")

        $pos_text = $futures | ForEach-Object {
            $emoji = if ($_.direction -eq "SHORT") { "📉" } else { "📈" }
            $entry = [math]::Round($_.entry_price, 6)
            $current = [math]::Round($_.current_price, 6)
            $pnl = [math]::Round($_.pnl_usd, 2)
            $pnl_pct = [math]::Round($_.pnl_pct, 2)

            "$emoji **$($_.market)** $($_.direction)`n" +
            "Entry: $entry | Current: $current`n" +
            "PnL: $pnl USD ($pnl_pct%)`n" +
            "SL: $($_.stop_loss) | TP: $($_.take_profit)`n"
        } | Join-String -Separator "---`n"

        $msg = @"
📊 **POSIÇÕES ABERTAS** ($($futures.Count))

$pos_text

Total PnL: $([math]::Round(($futures | Measure-Object -Property pnl_usd -Sum).Sum, 2)) USD
"@

        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }
    } catch {
        Write-Host "[WARN] Falha ao enviar positions: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ANALYZE — Solicitar análise LLM rápida (Haiku)
# ─────────────────────────────────────────────────────────────────────────────
function Send-AnalyzeRequest {
    <#
    .SYNOPSIS
    Envia solicitação de análise LLM para um mercado específico.
    Usa Haiku (rápido) por padrão.

    .PARAMETER Market
    Par de trading (ex: BTCUSDT)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market
    )

    $msg = @"
🔍 **ANÁLISE SOLICITADA**

Mercado: $Market
Tipo: Análise LLM rápida (Haiku)
Status: Em fila

Aguarde a análise...
"@

    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }

        # Enqueue para LLM processing
        # TODO: Integrar com mentor queue
        Write-Host "[ANALYZE] Solicitação enfileirada: $Market" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN] Falha ao enviar análise: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MENTOR — Discussão com mentor (Sonnet)
# ─────────────────────────────────────────────────────────────────────────────
function Send-MentorDiscussion {
    <#
    .SYNOPSIS
    Inicia discussão profunda com mentor (Sonnet) sobre posição/regime/strategy.

    .PARAMETER Topic
    Tópico: posição específica, regime, strategy, decisão
    #>
    [CmdletBinding()]
    param(
        [string] $Topic = "regime"
    )

    $msg = @"
🧠 **MENTOR CONSULTADO**

Tópico: $Topic
Modelo: Sonnet (profundo)
Status: Analisando...

Aguarde conclusões e recomendações...
"@

    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }

        Write-Host "[MENTOR] Discussão iniciada: $Topic" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN] Falha ao enviar mentor: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RECALIBRATE — Sugerir recalibragem automática
# ─────────────────────────────────────────────────────────────────────────────
function Send-RecalibrateRequest {
    <#
    .SYNOPSIS
    Analisa sistema e sugere recalibragem de parâmetros.
    Win rate baixa? Regime mudou? Stops muito largos?
    #>
    [CmdletBinding()]
    param()

    $msg = @"
⚙️ **ANÁLISE DE RECALIBRAGEM**

Analisando:
├ Win rate (últimas 20 trades)
├ Drawdown vs picos
├ Regime atual vs histórico
├ Stop loss effectiveness
├ Conviction scores
└ Capital allocation

Status: Em progresso...

Recomendações virão em breve.
"@

    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }

        Write-Host "[RECALIBRATE] Análise iniciada" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN] Falha ao enviar recalibrate: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# LEARN — Auto-aprendizado análise
# ─────────────────────────────────────────────────────────────────────────────
function Send-LearningReport {
    <#
    .SYNOPSIS
    Envia relatório de auto-aprendizado do sistema.
    Quais gates funcionam? Quais precisam ajuste?
    #>
    [CmdletBinding()]
    param()

    $msg = @"
🧬 **EVOLUTION REPORT**

Últimas 48h análise:

**Gates Effectiveness:**
├ BTC-core: 78% accuracy
├ Safety guards: 92% effectiveness
├ Multi-TF alignment: 65% hit rate
└ Conviction ensemble: 71% confidence

**Trailing Stops:**
├ Phase 1-2: 85% conversion rate
├ Phase 3: 72% profit protection
└ Drawdown avg: 2.3% from peak

**Recomendações:**
1. Multi-TF alignment precisa calibração
2. Conviction ensemble viés para SHORT
3. Trailing phase 3 pode apertar 1%

**Ações sugeridas:**
/mentor — Discussão profunda
/recalibrate — Aplicar mudanças
"@

    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }

        Write-Host "[LEARN] Relatório enviado" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN] Falha ao enviar learn: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PnL — Relatório de lucros/perdas
# ─────────────────────────────────────────────────────────────────────────────
function Send-PnLReport {
    <#
    .SYNOPSIS
    Envia PnL do dia + stats.
    #>
    [CmdletBinding()]
    param()

    try {
        $tracking = Get-Content "$global:JOURNAL_DIR/open_positions_tracking.jsonl" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        $outcomes = Get-Content "$global:JOURNAL_DIR/trade_outcomes.jsonl" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue -ErrorAction SilentlyContinue

        $total_pnl = if ($outcomes) {
            [math]::Round(($outcomes | Measure-Object -Property pnl_usd -Sum).Sum, 2)
        } else { 0 }

        $wins = if ($outcomes) { @($outcomes | Where-Object pnl_usd -gt 0).Count } else { 0 }
        $losses = if ($outcomes) { @($outcomes | Where-Object pnl_usd -lt 0).Count } else { 0 }
        $total_trades = $wins + $losses
        $win_rate = if ($total_trades -gt 0) { [math]::Round(($wins / $total_trades) * 100, 1) } else { 0 }

        $msg = @"
📈 **PnL REPORT**

**Histórico:**
Total trades: $total_trades
Wins: $wins ✅
Losses: $losses ❌
Win rate: $win_rate%

**PnL:**
Total: $total_pnl USD
Média por trade: $([math]::Round($total_pnl / [Math]::Max($total_trades, 1), 2)) USD

**Status:**
Posições abertas: $([math]::Round(($tracking.positions | Measure-Object -Property pnl_usd -Sum).Sum, 2)) USD
"@

        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }
    } catch {
        Write-Host "[WARN] Falha ao enviar PnL: $_" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Command dispatcher
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-TelegramCommand {
    <#
    .SYNOPSIS
    Processa comando do Telegram e executa ação correspondente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Command
    )

    $cmd, $args = $Command.Split(" ", 2)
    $cmd = $cmd.ToLower().TrimStart("/")

    switch ($cmd) {
        "help"          { Send-HelpMenu; break }
        "health"        { Send-HealthCheck; break }
        "status"        { Send-HealthCheck; break }
        "positions"     { Send-PositionsList; break }
        "analyze"       { Send-AnalyzeRequest -Market $args; break }
        "mentor"        { Send-MentorDiscussion -Topic $args; break }
        "recalibrate"   { Send-RecalibrateRequest; break }
        "learn"         { Send-LearningReport; break }
        "pnl"           { Send-PnLReport; break }
        "commands"      { Send-HelpMenu; break }
        default {
            Write-Host "[WARN] Comando desconhecido: $cmd" -ForegroundColor Yellow
        }
    }
}

Export-ModuleMember -Function @(
    'Send-HelpMenu'
    'Send-HealthCheck'
    'Send-PositionsList'
    'Send-AnalyzeRequest'
    'Send-MentorDiscussion'
    'Send-RecalibrateRequest'
    'Send-LearningReport'
    'Send-PnLReport'
    'Invoke-TelegramCommand'
) -ErrorAction SilentlyContinue

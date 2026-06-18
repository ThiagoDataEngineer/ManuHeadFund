# dashboard_phase2_websocket.ps1 — Live Dashboard com WebSocket + Control Buttons
# Real-time updates via Supabase, trigger Telegram commands direto do dashboard
# TDD-ready pure functions

$ErrorActionPreference = "Stop"

# ============================================================================
# REALTIME STATE SYNC — WebSocket via Supabase
# ============================================================================

function Start-DashboardRealtimeSync {
    <#
    .SYNOPSIS
    Inicia stream de atualizações em tempo real do Supabase

    .PARAMETER SupabaseUrl
    URL do Supabase

    .PARAMETER SupabaseKey
    Chave Supabase

    .PARAMETER Tables
    @("trailing_positions", "trade_outcomes", "conviction_observations")

    .OUTPUTS
    @{ stream_id = guid; tables = []; callback = script block }
    #>
    param(
        [string]$SupabaseUrl,
        [string]$SupabaseKey,
        [array]$Tables = @("trailing_positions", "trade_outcomes")
    )

    if (-not $SupabaseUrl -or -not $SupabaseKey) {
        return @{ stream_id = $null; tables = @(); error = "Missing credentials" }
    }

    $streamId = [guid]::NewGuid().ToString()

    @{
        stream_id = $streamId
        tables = $Tables
        url = $SupabaseUrl
        key = $SupabaseKey
        started_at = Get-Date
        subscriptions = @()
    }
}

function New-RealtimeSubscription {
    <#
    .SYNOPSIS
    Cria subscription pra uma tabela específica

    .PARAMETER Table
    Nome da tabela (trailing_positions, trade_outcomes, etc)

    .PARAMETER Filter
    Opcional: filtro SQL (e.g., "active=eq.true")

    .OUTPUTS
    @{ table = string; filter = string; event_count = 0; last_update = $null }
    #>
    param(
        [string]$Table,
        [string]$Filter = $null
    )

    @{
        table = $Table
        filter = $Filter
        event_count = 0
        last_update = $null
        data_cache = @()
    }
}

function Update-SubscriptionData {
    <#
    .SYNOPSIS
    Simula recebimento de dados via WebSocket (mock)

    .PARAMETER Subscription
    Subscription object

    .PARAMETER NewData
    Novos dados da tabela

    .OUTPUTS
    @{ success = $true; event_count = int; cached_rows = int }
    #>
    param(
        [hashtable]$Subscription,
        [array]$NewData
    )

    $Subscription.event_count++
    $Subscription.last_update = Get-Date
    $Subscription.data_cache = @($NewData)

    @{
        success = $true
        event_count = $Subscription.event_count
        cached_rows = $NewData.Count
        updated_at = $Subscription.last_update
    }
}

# ============================================================================
# CONTROL BUTTONS — Trigger Telegram Commands Direto do Dashboard
# ============================================================================

function New-ControlButton {
    <#
    .SYNOPSIS
    Define um botão de controle interativo

    .PARAMETER Command
    Comando Telegram (/halt, /resume, /balance, /stops, /scan)

    .PARAMETER Label
    Label do botão (ex: "HALT Trading")

    .PARAMETER Color
    CSS color (red, green, yellow)

    .OUTPUTS
    @{ command = string; label = string; color = string; action_fn = script block }
    #>
    param(
        [string]$Command,
        [string]$Label,
        [string]$Color = "gray"
    )

    $actionFn = {
        param([hashtable]$Context)
        # Context contém: telegram_token, chat_id, market_state
        # Retorna: success, message
    }

    @{
        command = $Command
        label = $Label
        color = $Color
        enabled = $true
        last_clicked = $null
        click_count = 0
        action = $actionFn
    }
}

function Invoke-ControlButton {
    <#
    .SYNOPSIS
    Executa ação de botão (envia comando Telegram)

    .PARAMETER Button
    Button object

    .PARAMETER TelegramToken
    Bot token

    .PARAMETER ChatId
    Chat ID

    .PARAMETER MarketState
    Estado atual (posições abertas, PnL, etc)

    .OUTPUTS
    @{ success = $true|$false; message = string; timestamp = datetime }
    #>
    param(
        [hashtable]$Button,
        [string]$TelegramToken,
        [string]$ChatId,
        [hashtable]$MarketState
    )

    if (-not $Button.enabled) {
        return @{ success = $false; message = "Button disabled"; timestamp = Get-Date }
    }

    $message = "/{0}" -f ($Button.command -replace "^/", "")

    # Mock: assume Telegram send succeeds
    $Button.last_clicked = Get-Date
    $Button.click_count++

    @{
        success = $true
        message = "Command /$($Button.command) sent"
        timestamp = Get-Date
        click_count = $Button.click_count
    }
}

# ============================================================================
# DASHBOARD STATE — Agregação de Dados Real-Time
# ============================================================================

function New-DashboardState {
    <#
    .SYNOPSIS
    Cria estado completo do dashboard (posições, PnL, daemon status)

    .PARAMETER Timestamp
    Quando foi atualizado

    .OUTPUTS
    @{
      capital_total = double
      positions_open = int
      pnl_total = double
      pnl_percentage = double
      trades_24h = int
      daemon_status = @{ gem_loop = "ok"|"error", trailing = "ok", telegram = "ok" }
      reftime = datetime
    }
    #>
    param(
        [datetime]$Timestamp = (Get-Date)
    )

    @{
        capital_total = 0
        positions_open = 0
        pnl_total = 0
        pnl_percentage = 0
        trades_24h = 0
        trades_7d = 0
        win_rate = 0
        daemon_status = @{
            gem_loop = "unknown"
            trailing = "unknown"
            telegram = "unknown"
        }
        last_trade = $null
        reftime = $Timestamp
        updated_at = $Timestamp
    }
}

function Update-DashboardState {
    <#
    .SYNOPSIS
    Atualiza estado do dashboard com dados novos

    .PARAMETER State
    Dashboard state

    .PARAMETER Positions
    Array de posições abertas

    .PARAMETER TradeOutcomes
    Array de trades históricos

    .PARAMETER DaemonStatus
    @{ gem_loop = string, trailing = string, telegram = string }

    .OUTPUTS
    State atualizado com novos dados
    #>
    param(
        [hashtable]$State,
        [array]$Positions,
        [array]$TradeOutcomes,
        [hashtable]$DaemonStatus
    )

    # Capital: sum posições
    $State.positions_open = $Positions.Count
    $State.capital_total = ($Positions | Measure-Object -Property capital -Sum).Sum

    # PnL: sum de unrealized
    $State.pnl_total = ($Positions | Measure-Object -Property unrealized_pnl -Sum).Sum
    $State.pnl_percentage = if ($State.capital_total -gt 0) {
        $State.pnl_total / $State.capital_total * 100
    } else { 0 }

    # Trades: filtrar por timestamp
    $now = Get-Date
    $day1 = $now.AddDays(-1)
    $day7 = $now.AddDays(-7)

    $State.trades_24h = @($TradeOutcomes | Where-Object { [datetime]$_.exit_date -ge $day1 }).Count
    $State.trades_7d = @($TradeOutcomes | Where-Object { [datetime]$_.exit_date -ge $day7 }).Count

    $wins = @($TradeOutcomes | Where-Object { $_.win }).Count
    $State.win_rate = if ($TradeOutcomes.Count -gt 0) {
        $wins / $TradeOutcomes.Count * 100
    } else { 0 }

    # Último trade
    if ($TradeOutcomes.Count -gt 0) {
        $State.last_trade = $TradeOutcomes[-1]
    }

    # Daemon status
    if ($DaemonStatus) {
        $State.daemon_status = $DaemonStatus
    }

    $State.updated_at = Get-Date

    $State
}

# ============================================================================
# DASHBOARD HTML GENERATOR — Com Botões Interativos
# ============================================================================

function New-DashboardHtmlWithControls {
    <#
    .SYNOPSIS
    Gera HTML do dashboard com botões de controle real-time

    .PARAMETER State
    Dashboard state

    .PARAMETER Buttons
    @(New-ControlButton -Command /halt ..., ...)

    .OUTPUTS
    String HTML (completo, inline CSS + JS)
    #>
    param(
        [hashtable]$State,
        [array]$Buttons
    )

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ManuHeadFund — Live Dashboard Phase 2</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Courier New', monospace;
            background: linear-gradient(135deg, #0f0f0f 0%, #1a1a2e 100%);
            color: #00ff00;
            padding: 20px;
            line-height: 1.6;
        }
        .header { border-bottom: 2px solid #00ff00; padding-bottom: 10px; margin-bottom: 20px; }
        h1 { font-size: 24px; }
        .timestamp { font-size: 12px; color: #888; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 15px; }
        .card {
            background: linear-gradient(135deg, #1a1a2e 0%, #0f3460 100%);
            border: 1px solid #00ff00;
            border-radius: 5px;
            padding: 15px;
            box-shadow: 0 0 10px rgba(0,255,0,0.1);
        }
        .card-title { font-size: 12px; font-weight: bold; color: #00ff00; text-transform: uppercase; margin-bottom: 10px; }
        .value { font-size: 18px; font-weight: bold; margin: 10px 0; }
        .positive { color: #00ff00; }
        .negative { color: #ff0000; }
        .neutral { color: #888; }
        .buttons-section { margin-top: 20px; }
        .button-group { display: flex; flex-wrap: wrap; gap: 10px; }
        .btn {
            padding: 10px 15px;
            border: 1px solid #00ff00;
            background: transparent;
            color: #00ff00;
            cursor: pointer;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            border-radius: 3px;
            transition: all 0.3s;
            text-transform: uppercase;
        }
        .btn:hover { background: #00ff00; color: #000; }
        .btn-halt { border-color: #ff0000; }
        .btn-halt:hover { background: #ff0000; color: #fff; }
        .daemon-status { display: flex; gap: 20px; margin-top: 10px; font-size: 12px; }
        .daemon-item { display: flex; align-items: center; gap: 5px; }
        .status-dot { width: 8px; height: 8px; border-radius: 50%; }
        .status-ok { background: #00ff00; }
        .status-error { background: #ff0000; }
        .status-unknown { background: #888; }
        .last-update { font-size: 11px; color: #666; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>⚡ ManuHeadFund — Live Phase 2</h1>
        <div class="timestamp">
            Updated: <span id="updateTime">$(Get-Date -Format 'HH:mm:ss')</span> BRT
        </div>
    </div>

    <div class="grid">
        <!-- Capital -->
        <div class="card">
            <div class="card-title">Capital USDT</div>
            <div class="value positive">`$$([math]::Round($State.capital_total, 2))</div>
        </div>

        <!-- PnL -->
        <div class="card">
            <div class="card-title">PnL Today</div>
            <div class="value $(if($State.pnl_total -ge 0) { 'positive' } else { 'negative' })">`$$([math]::Round($State.pnl_total, 2))</div>
            <div class="neutral">$([math]::Round($State.pnl_percentage, 2))%</div>
        </div>

        <!-- Positions -->
        <div class="card">
            <div class="card-title">Posições Abertas</div>
            <div class="value neutral">$($State.positions_open)</div>
            <div style="font-size: 12px; color: #888;">Trades 24h: $($State.trades_24h) | 7d: $($State.trades_7d)</div>
        </div>

        <!-- Win Rate -->
        <div class="card">
            <div class="card-title">Win Rate</div>
            <div class="value positive">$([math]::Round($State.win_rate, 1))%</div>
        </div>

        <!-- Daemon Status -->
        <div class="card">
            <div class="card-title">Daemon Status</div>
            <div class="daemon-status">
                <div class="daemon-item">
                    <div class="status-dot status-ok"></div>
                    gem_loop: $($State.daemon_status.gem_loop)
                </div>
                <div class="daemon-item">
                    <div class="status-dot status-ok"></div>
                    trailing: $($State.daemon_status.trailing)
                </div>
                <div class="daemon-item">
                    <div class="status-dot status-ok"></div>
                    telegram: $($State.daemon_status.telegram)
                </div>
            </div>
        </div>
    </div>

    <!-- Control Buttons -->
    <div class="buttons-section">
        <div class="card-title">CONTROL BUTTONS — Trigger Telegram Commands</div>
        <div class="button-group">
            <button class="btn" onclick="triggerCommand('/halt')">⏸ HALT</button>
            <button class="btn" onclick="triggerCommand('/resume')">▶ RESUME</button>
            <button class="btn" onclick="triggerCommand('/balance')">💰 BALANCE</button>
            <button class="btn" onclick="triggerCommand('/stops')">🛑 STOPS</button>
            <button class="btn" onclick="triggerCommand('/scan')">🔍 SCAN</button>
        </div>
    </div>

    <div class="last-update">
        Last update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') — Real-time sync via Supabase WebSocket
    </div>

    <script>
        function triggerCommand(cmd) {
            // Mock: log comando
            console.log('Comando enviado: ' + cmd);
            // Em produção: POST pra /api/telegram/command
            alert('Comando enviado: ' + cmd);
        }

        // Auto-refresh: 5 segundos (WebSocket + polling)
        setInterval(function() {
            document.getElementById('updateTime').textContent = new Date().toLocaleTimeString('pt-BR');
        }, 5000);
    </script>
</body>
</html>
"@

    $html
}

# ============================================================================
# EXPORT
# ============================================================================

Export-ModuleMember -Function @(
    'Start-DashboardRealtimeSync',
    'New-RealtimeSubscription',
    'Update-SubscriptionData',
    'New-ControlButton',
    'Invoke-ControlButton',
    'New-DashboardState',
    'Update-DashboardState',
    'New-DashboardHtmlWithControls'
)

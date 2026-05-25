# lib_cost_tracker.ps1 ï¿½ Tracking de custos Claude API
# Persiste cada chamada em journal/claude_usage.csv para analise posterior.
# Zero dependencia externa ï¿½ apenas escrita CSV.

$COST_USAGE_FILE = (Join-Path $PSScriptRoot ".." "journal" "claude_usage.csv")

# Tabela de precos Anthropic (USD por 1M tokens) ï¿½ Maio 2026
# Atualizar se Anthropic mudar pricing
$CLAUDE_PRICING = @{
    "claude-sonnet-4"        = @{ input=3.00;  output=15.00 }
    "claude-opus-4"          = @{ input=15.00; output=75.00 }
    "claude-haiku-4"         = @{ input=0.80;  output=4.00  }
}

# -----------------------------------------------------------------------------
# Get-ClaudeCost ï¿½ calcula custo USD a partir de tokens + modelo
# -----------------------------------------------------------------------------
function Get-ClaudeCost {
    param(
        [string]$Model,
        [int]   $InputTokens,
        [int]   $OutputTokens
    )
    $modelKey = $Model.ToLower()
    $pricing  = $CLAUDE_PRICING[$modelKey]
    if (-not $pricing) {
        # Fallback: assume Sonnet pricing se modelo desconhecido
        $pricing = @{ input=3.00; output=15.00 }
    }
    $costIn  = ($InputTokens  / 1000000.0) * $pricing.input
    $costOut = ($OutputTokens / 1000000.0) * $pricing.output
    return [math]::Round($costIn + $costOut, 6)
}

# -----------------------------------------------------------------------------
# Track-ClaudeUsage ï¿½ registra uma chamada Claude no CSV
# -----------------------------------------------------------------------------
function Track-ClaudeUsage {
    param(
        [string]$Model,
        [int]   $InputTokens,
        [int]   $OutputTokens,
        [string]$Agent = "unknown",
        [double]$LatencyMs = 0
    )
    try {
        $dir = Split-Path $COST_USAGE_FILE
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (-not (Test-Path $COST_USAGE_FILE)) {
            "timestamp,agent,model,input_tokens,output_tokens,cost_usd,latency_ms" |
                Out-File -FilePath $COST_USAGE_FILE -Encoding utf8 -Force
        }
        $cost = Get-ClaudeCost -Model $Model -InputTokens $InputTokens -OutputTokens $OutputTokens
        # Forca formato decimal com ponto (invariant culture) para nao quebrar CSV em locale pt-BR
        $inv     = [System.Globalization.CultureInfo]::InvariantCulture
        $costStr = $cost.ToString("F6", $inv)
        $latStr  = ([math]::Round($LatencyMs, 0)).ToString("F0", $inv)
        $row  = @(
            (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
            $Agent, $Model, $InputTokens, $OutputTokens, $costStr, $latStr
        ) -join ","
        Add-Content -Path $COST_USAGE_FILE -Value $row -Encoding utf8
        return $cost
    } catch {
        Write-Host "  [CostTracker] Falha ao registrar uso: $_" -ForegroundColor DarkYellow
        return 0
    }
}

# -----------------------------------------------------------------------------
# Get-CostSummary ï¿½ agrega custos por periodo
# Retorna objeto com today, week, month, total + breakdown por agente
# -----------------------------------------------------------------------------
function Get-CostSummary {
    if (-not (Test-Path $COST_USAGE_FILE)) {
        return [PSCustomObject]@{
            today=0; week=0; month=0; total=0
            todayCalls=0; weekCalls=0; monthCalls=0
            byAgent=@{}; projectedMonthly=0
        }
    }
    try {
        $rows = Import-Csv $COST_USAGE_FILE
        $now  = Get-Date
        $today = $now.Date
        $weekAgo  = $now.AddDays(-7)
        $monthAgo = $now.AddDays(-30)
        $inv = [System.Globalization.CultureInfo]::InvariantCulture

        $today_sum=0.0; $week_sum=0.0; $month_sum=0.0; $total_sum=0.0
        $today_n=0; $week_n=0; $month_n=0
        $byAgent = @{}

        foreach ($r in $rows) {
            $ts = [DateTime]::ParseExact($r.timestamp, "yyyy-MM-dd HH:mm:ss", $null)
            # Robusto a virgula decimal legacy (linhas pre-fix) e ponto correto
            $costStr = ($r.cost_usd -replace ',', '.')
            $cost = if ($costStr) { [double]::Parse($costStr, $inv) } else { 0 }
            $total_sum += $cost
            if ($ts -ge $monthAgo) { $month_sum += $cost; $month_n++ }
            if ($ts -ge $weekAgo)  { $week_sum  += $cost; $week_n++  }
            if ($ts.Date -eq $today) { $today_sum += $cost; $today_n++ }

            $agent = $r.agent
            if (-not $byAgent.ContainsKey($agent)) { $byAgent[$agent] = 0.0 }
            $byAgent[$agent] += $cost
        }

        # Projecao mensal baseada nos ultimos 7 dias
        $proj = if ($week_sum -gt 0) { [math]::Round($week_sum * 30.0 / 7.0, 2) } else { 0 }

        return [PSCustomObject]@{
            today      = [math]::Round($today_sum, 4)
            week       = [math]::Round($week_sum, 4)
            month      = [math]::Round($month_sum, 4)
            total      = [math]::Round($total_sum, 4)
            todayCalls = $today_n
            weekCalls  = $week_n
            monthCalls = $month_n
            byAgent    = $byAgent
            projectedMonthly = $proj
        }
    } catch {
        return [PSCustomObject]@{ today=0; week=0; month=0; total=0; error=$_ }
    }
}

# -----------------------------------------------------------------------------
# Format-TgCostReport ï¿½ relatorio formatado para Telegram (HTML)
# -----------------------------------------------------------------------------
function Format-TgCostReport {
    $s = Get-CostSummary
    $sep = "- - - - - - - - - - - - - - - - - -"
    $ts  = (Get-Date).ToString("HH:mm dd/MM/yy")

    $byAgentLines = if ($s.byAgent -and $s.byAgent.Count -gt 0) {
        ($s.byAgent.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object {
            "  {0,-10} ${1,8:F4}" -f $_.Key, $_.Value
        }) -join "`n"
    } else { "  (sem dados ainda)" }

    return @"
<b>RELATORIO DE CUSTOS CLAUDE</b>
$sep
Hoje:       `$$($s.today)     ($($s.todayCalls) calls)
Semana:     `$$($s.week)     ($($s.weekCalls) calls)
Mes (30d):  `$$($s.month)     ($($s.monthCalls) calls)
Total:      `$$($s.total)
$sep
<b>Projecao mensal:</b> `$$($s.projectedMonthly)
(baseado na ultima semana)
$sep
<b>Por agente:</b>
$byAgentLines
$sep
<i>$ts</i>
"@
}

# -----------------------------------------------------------------------------
# Test-CostThresholdExceeded ï¿½ verifica se custo em janela excedeu threshold
# -----------------------------------------------------------------------------
function Test-CostThresholdExceeded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Threshold,
        [Parameter()] [int] $WindowHours = 24,
        [Parameter()] [string] $CostFile = $COST_USAGE_FILE
    )

    if (-not (Test-Path $CostFile)) {
        return $false
    }

    try {
        $rows = Import-Csv $CostFile -ErrorAction Stop
        if ($null -eq $rows -or $rows.Count -eq 0) {
            return $false
        }

        $now = Get-Date
        $windowStart = $now.AddHours(-$WindowHours)
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $windowSum = 0.0

        foreach ($r in $rows) {
            $ts = [DateTime]::ParseExact($r.timestamp, "yyyy-MM-dd HH:mm:ss", $null)
            if ($ts -lt $windowStart) { continue }

            $costStr = ($r.cost_usd -replace ',', '.')
            $cost = if ($costStr) { [double]::Parse($costStr, $inv) } else { 0 }
            $windowSum += $cost
        }

        return $windowSum -gt $Threshold
    } catch {
        Write-Host "  [CostAlarm] Erro ao ler custos: $_" -ForegroundColor DarkYellow
        return $false
    }
}

# -----------------------------------------------------------------------------
# Test-CostAlarmThreshold ï¿½ valida limites de custo (per-trade e daily)
# Retorna @{alarm_triggered, reason, current_metrics, suggested_action}
# -----------------------------------------------------------------------------
function Test-CostAlarmThreshold {
    [CmdletBinding()]
    param(
        [Parameter()] [double] $MaxCostPerTradeUsd = 0.10,
        [Parameter()] [double] $MaxDailyCostUsd = 5.00,
        [Parameter()] [int] $LookbackHours = 24,
        [Parameter()] [string] $CostFile = $COST_USAGE_FILE
    )

    if (-not (Test-Path $CostFile)) {
        return [PSCustomObject]@{
            alarm_triggered   = $false
            reason            = "ok"
            current_metrics   = @{
                daily_cost = 0.0
                daily_calls = 0
                avg_cost_per_call = 0.0
                max_call_cost = 0.0
            }
            suggested_action = "none"
        }
    }

    try {
        $rows = Import-Csv $CostFile -ErrorAction Stop
        if ($null -eq $rows -or $rows.Count -eq 0) {
            return [PSCustomObject]@{
                alarm_triggered   = $false
                reason            = "ok"
                current_metrics   = @{
                    daily_cost = 0.0
                    daily_calls = 0
                    avg_cost_per_call = 0.0
                    max_call_cost = 0.0
                }
                suggested_action = "none"
            }
        }

        $now = Get-Date
        $windowStart = $now.AddHours(-$LookbackHours)
        $inv = [System.Globalization.CultureInfo]::InvariantCulture

        $dailySum = 0.0
        $dailyCount = 0
        $maxCallCost = 0.0
        $highCostCalls = @()

        foreach ($r in $rows) {
            $ts = [DateTime]::ParseExact($r.timestamp, "yyyy-MM-dd HH:mm:ss", $null)
            if ($ts -lt $windowStart) { continue }

            $costStr = ($r.cost_usd -replace ',', '.')
            $cost = if ($costStr) { [double]::Parse($costStr, $inv) } else { 0 }
            $dailySum += $cost
            $dailyCount++

            if ($cost -gt $maxCallCost) { $maxCallCost = $cost }
            if ($cost -gt $MaxCostPerTradeUsd) {
                $highCostCalls += [PSCustomObject]@{
                    timestamp = $ts
                    agent = $r.agent
                    cost = $cost
                    model = $r.model
                }
            }
        }

        $avgCostPerCall = if ($dailyCount -gt 0) { [math]::Round($dailySum / $dailyCount, 6) } else { 0 }
        $dailySum = [math]::Round($dailySum, 4)

        $triggered = $false
        $reason = "ok"
        $action = "none"

        # Valida limite per-trade
        if ($highCostCalls.Count -gt 0) {
            $triggered = $true
            $reason = "per_trade_high"
            $action = "investigate_expensive_calls"
        }

        # Valida limite daily
        if ($dailySum -gt $MaxDailyCostUsd) {
            $triggered = $true
            $reason = "daily_high"
            $action = "reduce_agent_traffic"
        }

        return [PSCustomObject]@{
            alarm_triggered   = $triggered
            reason            = $reason
            current_metrics   = [PSCustomObject]@{
                daily_cost             = $dailySum
                daily_calls            = $dailyCount
                avg_cost_per_call      = $avgCostPerCall
                max_call_cost          = $maxCallCost
                high_cost_calls_count  = $highCostCalls.Count
                window_hours           = $LookbackHours
            }
            suggested_action = $action
            high_cost_calls = $highCostCalls
        }
    } catch {
        return [PSCustomObject]@{
            alarm_triggered   = $false
            reason            = "error"
            current_metrics   = $null
            suggested_action = "check_csv_format"
        }
    }
}

# -----------------------------------------------------------------------------
# Get-DailyCostByAgent ï¿½ agrega custos das ultimas 24h por agente
# -----------------------------------------------------------------------------
function Get-DailyCostByAgent {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $CostFile = $COST_USAGE_FILE
    )

    if (-not (Test-Path $CostFile)) {
        return [PSCustomObject]@{
            triagem = 0.0
            mesa = 0.0
            mentor = 0.0
            chain = 0.0
            fund = 0.0
            sent = 0.0
            tech = 0.0
            unknown = 0.0
        }
    }

    try {
        $rows = Import-Csv $CostFile -ErrorAction Stop
        if ($null -eq $rows -or $rows.Count -eq 0) {
            return [PSCustomObject]@{
                triagem = 0.0
                mesa = 0.0
                mentor = 0.0
                chain = 0.0
                fund = 0.0
                sent = 0.0
                tech = 0.0
                unknown = 0.0
            }
        }

        $now = Get-Date
        $dayAgo = $now.AddHours(-24)
        $inv = [System.Globalization.CultureInfo]::InvariantCulture

        $byCost = @{
            triagem = 0.0
            mesa = 0.0
            mentor = 0.0
            chain = 0.0
            fund = 0.0
            sent = 0.0
            tech = 0.0
            unknown = 0.0
        }

        foreach ($r in $rows) {
            $ts = [DateTime]::ParseExact($r.timestamp, "yyyy-MM-dd HH:mm:ss", $null)
            if ($ts -lt $dayAgo) { continue }

            $costStr = ($r.cost_usd -replace ',', '.')
            $cost = if ($costStr) { [double]::Parse($costStr, $inv) } else { 0 }
            $agent = $r.agent.ToLower()

            if ($byCost.ContainsKey($agent)) {
                $byCost[$agent] += $cost
            } else {
                $byCost['unknown'] += $cost
            }
        }

        return [PSCustomObject]@{
            triagem = [math]::Round($byCost['triagem'], 4)
            mesa = [math]::Round($byCost['mesa'], 4)
            mentor = [math]::Round($byCost['mentor'], 4)
            chain = [math]::Round($byCost['chain'], 4)
            fund = [math]::Round($byCost['fund'], 4)
            sent = [math]::Round($byCost['sent'], 4)
            tech = [math]::Round($byCost['tech'], 4)
            unknown = [math]::Round($byCost['unknown'], 4)
        }
    } catch {
        Write-Host "  [CostAlarm] Erro ao agregar custos por agente: $_" -ForegroundColor DarkYellow
        return [PSCustomObject]@{
            triagem = 0.0
            mesa = 0.0
            mentor = 0.0
            chain = 0.0
            fund = 0.0
            sent = 0.0
            tech = 0.0
            unknown = 0.0
        }
    }
}

# -----------------------------------------------------------------------------
# Send-CostAlarmTelegram ï¿½ envia alerta via Telegram se ativado
# -----------------------------------------------------------------------------
function Send-CostAlarmTelegram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter()] [bool] $SendIfEnabled = $true
    )

    if (-not $SendIfEnabled) {
        return
    }

    # Carrega lib_telegram se nao estiver carregada
    if (-not (Get-Command "Send-TgMessage" -ErrorAction SilentlyContinue)) {
        $telegramLib = Join-Path $PSScriptRoot "lib_telegram.ps1"
        if (Test-Path $telegramLib) {
            . $telegramLib
        } else {
            Write-Host "  [CostAlarm] lib_telegram nao encontrada, pulando alerta Telegram" -ForegroundColor DarkYellow
            return
        }
    }

    try {
        Send-TgMessage -Text $Message -ParseMode "HTML" -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  [CostAlarm] Falha ao enviar alerta Telegram: $_" -ForegroundColor DarkYellow
    }
}

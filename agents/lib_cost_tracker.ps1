# lib_cost_tracker.ps1 -- Tracking de custos Claude API
# Persiste cada chamada em journal/claude_usage.csv (fallback local) OU
# Supabase manuheadfund.llm_usage (2026-07-30, ver Track-ClaudeUsage abaixo).

$COST_USAGE_FILE = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "claude_usage.csv")

# Tabela de precos Anthropic (USD por 1M tokens) -- Maio 2026
# 2026-07-30 FIX: chaves nunca batiam com os modelos REAIS usados no projeto
# ("claude-sonnet-5", "claude-haiku-4-5-20251001" -- ver agents/config.ps1)
# -- toda chamada, mesmo de Haiku (~10x mais barato), caia no fallback
# generico de preco de Sonnet, distorcendo qualquer analise de custo real.
# Fix usa match por PREFIXO (nao igualdade exata) pra sobreviver a sufixos
# de versao/data sem precisar atualizar a cada novo modelo lancado.
$CLAUDE_PRICING = @{
    "claude-sonnet-5"        = @{ input=3.00;  output=15.00 }
    "claude-sonnet-4"        = @{ input=3.00;  output=15.00 }
    "claude-opus-4"          = @{ input=15.00; output=75.00 }
    "claude-opus-5"          = @{ input=15.00; output=75.00 }
    "claude-haiku-4-5"       = @{ input=0.80;  output=4.00  }
    "claude-haiku-4"         = @{ input=0.80;  output=4.00  }
    "claude-fable-5"         = @{ input=3.00;  output=15.00 }
}

# -----------------------------------------------------------------------------
# Get-ClaudeCost -- calcula custo USD a partir de tokens + modelo
# -----------------------------------------------------------------------------
function Get-ClaudeCost {
    param(
        [string]$Model,
        [int]   $InputTokens,
        [int]   $OutputTokens
    )
    $modelKey = $Model.ToLower()
    # Match exato primeiro, depois por prefixo (cobre sufixos de data/versao
    # como "claude-haiku-4-5-20251001" batendo em "claude-haiku-4-5").
    $pricing = $CLAUDE_PRICING[$modelKey]
    if (-not $pricing) {
        foreach ($key in $CLAUDE_PRICING.Keys) {
            if ($modelKey.StartsWith($key)) { $pricing = $CLAUDE_PRICING[$key]; break }
        }
    }
    if (-not $pricing) {
        # Fallback: assume Sonnet pricing se modelo desconhecido
        $pricing = @{ input=3.00; output=15.00 }
    }
    $costIn  = ($InputTokens  / 1000000.0) * $pricing.input
    $costOut = ($OutputTokens / 1000000.0) * $pricing.output
    return [math]::Round($costIn + $costOut, 6)
}

# -----------------------------------------------------------------------------
# _Get-LlmUsageRows -- fonte unica de leitura (Supabase real, fallback CSV
# local) usada por Get-CostSummary/Get-DailyCostByAgent/Test-CostAlarmThreshold/
# Test-CostThresholdExceeded. Retorna objetos com .timestamp ([datetime]),
# .agent, .model, .cost_usd ([double]) -- schema uniforme independente da fonte.
# -----------------------------------------------------------------------------
function _Get-LlmUsageRows {
    param([string]$CostFile = $COST_USAGE_FILE)

    if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
        try {
            $records = @(Get-StateRecords -Table "llm_usage")
            if ($records.Count -gt 0) {
                return @($records | ForEach-Object {
                    [PSCustomObject]@{
                        timestamp = [datetime]::Parse([string]$_.ts, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        agent     = [string]$_.agent
                        model     = [string]$_.model
                        cost_usd  = [double]$_.cost_usd
                    }
                })
            }
        } catch {
            Write-Host "  [CostTracker] Supabase read falhou, fallback CSV local: $_" -ForegroundColor DarkYellow
        }
    }

    if (-not (Test-Path $CostFile)) { return @() }
    try {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        return @(Import-Csv $CostFile | ForEach-Object {
            $costStr = ($_.cost_usd -replace ',', '.')
            [PSCustomObject]@{
                timestamp = [DateTime]::ParseExact($_.timestamp, "yyyy-MM-dd HH:mm:ss", $null)
                agent     = [string]$_.agent
                model     = [string]$_.model
                cost_usd  = if ($costStr) { [double]::Parse($costStr, $inv) } else { 0.0 }
            }
        })
    } catch {
        return @()
    }
}

# -----------------------------------------------------------------------------
# Track-ClaudeUsage -- registra uma chamada de LLM (Supabase real, fallback CSV local)
# -----------------------------------------------------------------------------
function Track-ClaudeUsage {
    param(
        [string]$Model,
        [int]   $InputTokens,
        [int]   $OutputTokens,
        [string]$Agent = "unknown",
        [double]$LatencyMs = 0
    )
    $cost = Get-ClaudeCost -Model $Model -InputTokens $InputTokens -OutputTokens $OutputTokens

    # 2026-07-30 FIX: CSV local (journal/claude_usage.csv) nunca sobrevivia entre
    # runs do GitHub Actions (runner efemero, mesma classe de bug ja documentada
    # em gem_position_events/trade_outcomes) -- nenhum historico real de custo
    # jamais acumulava, tornando Send-CostAlarmTelegram/Test-CostAlarmThreshold
    # inuteis mesmo se conectados. Persiste em manuheadfund.llm_usage (Supabase,
    # sobrevive entre runs) quando disponivel; cai pro CSV local so como
    # fallback de ultimo recurso (dev local sem credenciais Supabase).
    if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
        try {
            Save-StateRecords -Table "llm_usage" -Records @([PSCustomObject]@{
                ts            = (Get-Date -Format "o")
                agent         = $Agent
                model         = $Model
                input_tokens  = $InputTokens
                output_tokens = $OutputTokens
                cost_usd      = $cost
                latency_ms    = [math]::Round($LatencyMs, 0)
            })
            return $cost
        } catch {
            Write-Host "  [CostTracker] Supabase falhou, fallback CSV local: $_" -ForegroundColor DarkYellow
        }
    }

    try {
        $dir = Split-Path $COST_USAGE_FILE
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (-not (Test-Path $COST_USAGE_FILE)) {
            "timestamp,agent,model,input_tokens,output_tokens,cost_usd,latency_ms" |
                Out-File -FilePath $COST_USAGE_FILE -Encoding utf8 -Force
        }
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
# Get-CostSummary -- agrega custos por periodo (Supabase real, fallback CSV local)
# Retorna objeto com today, week, month, total + breakdown por agente
# -----------------------------------------------------------------------------
function Get-CostSummary {
    try {
        $rows = @(_Get-LlmUsageRows)
        if ($rows.Count -eq 0) {
            return [PSCustomObject]@{
                today=0; week=0; month=0; total=0
                todayCalls=0; weekCalls=0; monthCalls=0
                byAgent=@{}; projectedMonthly=0
            }
        }
        $now  = Get-Date
        $today = $now.Date
        $weekAgo  = $now.AddDays(-7)
        $monthAgo = $now.AddDays(-30)

        $today_sum=0.0; $week_sum=0.0; $month_sum=0.0; $total_sum=0.0
        $today_n=0; $week_n=0; $month_n=0
        $byAgent = @{}

        foreach ($r in $rows) {
            $ts = $r.timestamp
            $cost = $r.cost_usd
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

    try {
        $rows = @(_Get-LlmUsageRows -CostFile $CostFile)
        if ($rows.Count -eq 0) { return $false }

        $now = Get-Date
        $windowStart = $now.AddHours(-$WindowHours)
        $windowSum = 0.0

        foreach ($r in $rows) {
            if ($r.timestamp -lt $windowStart) { continue }
            $windowSum += $r.cost_usd
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

    try {
        $rows = @(_Get-LlmUsageRows -CostFile $CostFile)
        if ($rows.Count -eq 0) {
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

        $dailySum = 0.0
        $dailyCount = 0
        $maxCallCost = 0.0
        $highCostCalls = @()

        foreach ($r in $rows) {
            if ($r.timestamp -lt $windowStart) { continue }

            $cost = $r.cost_usd
            $dailySum += $cost
            $dailyCount++

            if ($cost -gt $maxCallCost) { $maxCallCost = $cost }
            if ($cost -gt $MaxCostPerTradeUsd) {
                $highCostCalls += [PSCustomObject]@{
                    timestamp = $r.timestamp
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
    # 2026-07-30 FIX: byCost so reconhecia 8 chaves fixas (triagem/mesa/mentor/
    # chain/fund/sent/tech) -- agentes reais como mesa_termal/mesa_radar/
    # mesa_lidar (cada drone loga com Agent="mesa_$Drone", ver mesa_agent.ps1)
    # nunca batiam, caindo tudo em "unknown" e escondendo o detalhamento real
    # por drone. Agora dinamico: agrega por QUALQUER valor de agent presente
    # nos dados reais, sem lista fixa pre-definida.
    try {
        $rows = @(_Get-LlmUsageRows -CostFile $CostFile)
        $byCost = @{}
        if ($rows.Count -eq 0) { return [PSCustomObject]$byCost }

        $now = Get-Date
        $dayAgo = $now.AddHours(-24)

        foreach ($r in $rows) {
            if ($r.timestamp -lt $dayAgo) { continue }
            $agent = if ($r.agent) { $r.agent.ToLower() } else { "unknown" }
            if (-not $byCost.ContainsKey($agent)) { $byCost[$agent] = 0.0 }
            $byCost[$agent] += $r.cost_usd
        }

        $result = @{}
        foreach ($k in $byCost.Keys) { $result[$k] = [math]::Round($byCost[$k], 4) }
        return [PSCustomObject]$result
    } catch {
        Write-Host "  [CostAlarm] Erro ao agregar custos por agente: $_" -ForegroundColor DarkYellow
        return [PSCustomObject]@{}
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

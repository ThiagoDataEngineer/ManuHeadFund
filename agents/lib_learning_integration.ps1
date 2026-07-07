# lib_learning_integration.ps1 — Integração de Aprendizado no Ciclo de Trades
# 2026-07-07: Wire callbacks após entry/exit para alimentar learning engines
# Função: Capturar sinais + outcomes e registrar histórico para auto-evolução

# ============================================================================
# REGISTRO DE ENTRY — Called após Invoke-GemExecute ou Orchestrator entry
# ============================================================================

function Record-TradeEntry {
    <#
    .SYNOPSIS
    Registra sinal de entrada para aprendizado posterior

    .PARAMETER Market
    Par (ex: ETHUSDT)

    .PARAMETER Direction
    LONG | SHORT

    .PARAMETER EntryPrice
    Preço de entrada

    .PARAMETER Signal
    Nome do sinal (pump-fade, rsi-oversold, breakout-volume, etc)

    .PARAMETER Confidence
    Score de confiança 0-100

    .PARAMETER Timestamp
    Timestamp da entrada (default: now)

    .PARAMETER Reasoning
    Texto explicativo da confluência (obrigatório por Regra #4)

    .OUTPUTS
    @{ success = $true|$false; record_id = string }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [ValidateSet('LONG','SHORT')] [string]$Direction,
        [Parameter(Mandatory)] [double]$EntryPrice,
        [Parameter(Mandatory)] [string]$Signal,
        [int]$Confidence = 50,
        [datetime]$Timestamp = (Get-Date),
        [string]$Reasoning = ""
    )

    $journalPath = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    $logPath = Join-Path $journalPath "learning_evolution.jsonl"

    # Garantir que diretório existe
    if (-not (Test-Path $journalPath)) { New-Item -ItemType Directory -Path $journalPath -Force | Out-Null }

    $record = @{
        timestamp = $Timestamp.ToString("u")
        type = "entry"
        market = $Market
        direction = $Direction
        entry_price = $EntryPrice
        signal = $Signal
        confidence = $Confidence
        reasoning = $Reasoning
        record_id = "entry_$($Market)_$($Timestamp.Ticks)"
    } | ConvertTo-Json -Compress

    try {
        Add-Content -Path $logPath -Value $record -Encoding UTF8 -ErrorAction Stop
        return @{ success = $true; record_id = $record.record_id }
    } catch {
        Write-Warning "[Learning] Falha ao registrar entry: $($_.Exception.Message)"
        return @{ success = $false; error = $_.Exception.Message }
    }
}

# ============================================================================
# REGISTRO DE EXIT — Called após trade close (TP/SL/manual)
# ============================================================================

function Record-TradeExit {
    <#
    .SYNOPSIS
    Registra fechamento do trade para análise de outcome

    .PARAMETER Market
    Par

    .PARAMETER ExitPrice
    Preço de saída

    .PARAMETER PnLUsd
    Lucro/perda em USD

    .PARAMETER PnLPct
    Lucro/perda em percentual

    .PARAMETER CloseReason
    "tp" | "sl" | "manual" | "liquidation" | etc

    .PARAMETER HoldDurationHours
    Quantas horas manteve a posição

    .PARAMETER RecordId
    ID da entry correspondente (para correlação)

    .OUTPUTS
    @{ success = $true|$false }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [double]$ExitPrice,
        [Parameter(Mandatory)] [double]$PnLUsd,
        [double]$PnLPct = 0,
        [ValidateSet('tp','sl','manual','liquidation')] [string]$CloseReason = "manual",
        [int]$HoldDurationHours = 0,
        [string]$RecordId = ""
    )

    $journalPath = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    $logPath = Join-Path $journalPath "learning_evolution.jsonl"

    $record = @{
        timestamp = (Get-Date).ToString("u")
        type = "exit"
        market = $Market
        exit_price = $ExitPrice
        pnl_usd = $PnLUsd
        pnl_pct = $PnLPct
        close_reason = $CloseReason
        hold_hours = $HoldDurationHours
        linked_entry_id = $RecordId
        outcome = if ($PnLUsd -gt 0) { "win" } else { if ($PnLUsd -lt 0) { "loss" } else { "breakeven" } }
    } | ConvertTo-Json -Compress

    try {
        Add-Content -Path $logPath -Value $record -Encoding UTF8 -ErrorAction Stop
        return @{ success = $true }
    } catch {
        Write-Warning "[Learning] Falha ao registrar exit: $($_.Exception.Message)"
        return @{ success = $false; error = $_.Exception.Message }
    }
}

# ============================================================================
# TRIGGERS DO APRENDIZADO (executar em cron)
# ============================================================================

function Invoke-LearningCycle {
    <#
    .SYNOPSIS
    Roda ciclo completo de aprendizado:
    1. Analisa logs recentes (erros, rejections)
    2. Calcula propostas de evolução (parametros)
    3. Registra histórico de mudanças

    .PARAMETER Hours
    Quantas horas de histórico analisar (default 24)

    .PARAMETER DryRun
    Se $true, retorna propostas sem aplicar
    #>
    [CmdletBinding()]
    param(
        [int]$Hours = 24,
        [switch]$DryRun
    )

    Write-Host "[Learning] Iniciando ciclo de aprendizado (últimas $Hours horas)..." -ForegroundColor Cyan

    # 1. Carregar learning engine
    if (-not (Get-Command Read-CloudErrorLog -ErrorAction SilentlyContinue)) {
        Write-Warning "[Learning] lib_learning_engine não carregado; pulando análise de erros"
        return $null
    }

    # 2. Analisar logs
    $journalPath = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    $logFile = Join-Path $journalPath "gem_loop.log"

    $analysis = Read-CloudErrorLog -LogPath $logFile -Hours $Hours
    Write-Host "  → Total scanned: $($analysis.total_scanned), Error rate: $($analysis.error_rate)%" -ForegroundColor Yellow

    # 3. Análise de outcomes
    $evolutionPath = Join-Path $journalPath "learning_evolution.jsonl"
    if (Test-Path $evolutionPath) {
        $outcomes = @(Get-Content $evolutionPath -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue)
        $recentExits = $outcomes | Where-Object { $_.type -eq "exit" -and [datetime]$_.timestamp -gt (Get-Date).AddHours(-$Hours) }

        $wins = @($recentExits | Where-Object { $_.outcome -eq "win" })
        $losses = @($recentExits | Where-Object { $_.outcome -eq "loss" })
        $winRate = if ($recentExits.Count -gt 0) { $wins.Count / $recentExits.Count * 100 } else { 0 }

        Write-Host "  → Wins: $($wins.Count), Losses: $($losses.Count), Win rate: $([math]::Round($winRate,1))%" -ForegroundColor Cyan
    }

    # 4. Evolution proposals (se engine está carregado)
    if (Get-Command Get-EvolutionProposals -ErrorAction SilentlyContinue) {
        $current = Get-EvolutionParams
        # Fixtures para teste (TODO: integrar com dados reais)
        $proposals = Get-EvolutionProposals -Current $current -Evidence @{}

        if ($proposals -and $proposals.Count -gt 0) {
            Write-Host "  → Propostas de evolução: $($proposals.Count)" -ForegroundColor Yellow
            $proposals | ForEach-Object {
                Write-Host "     • $($_.param): $($_.before) → $($_.proposed) (motivo: $($_.reason))"
            }

            if (-not $DryRun) {
                Write-Host "  → APLICANDO propostas..." -ForegroundColor Green
                # TODO: wire Invoke-EvolutionProposal
            }
        }
    }

    Write-Host "[Learning] Ciclo concluído." -ForegroundColor Green
}

# ============================================================================
# EXPORTS
# ============================================================================

Export-ModuleMember -Function @(
    'Record-TradeEntry'
    'Record-TradeExit'
    'Invoke-LearningCycle'
)

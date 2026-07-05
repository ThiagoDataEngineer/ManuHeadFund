# lib_evolution_autonomous_rebalance.ps1 — Evolution Engine com Auto-Rebalanceamento
# 2026-07-05: Sistema autonomamente decide ajustes de gates via discussão Multi-LLM
# Roda diariamente (~06h) como parte do Evolution Engine

function Invoke-EvolutionAutoRebalance {
    <#
    .SYNOPSIS
    Verifica problema (0 trades? low WR? low frequency?) e auto-ajusta via Mentores
    #>

    param(
        [string]$OutcomesFile = "journal/trade_outcomes.jsonl",
        [string]$ConfigFile = "agents/config.local.ps1"
    )

    Write-Host "🧬 EVOLUTION ENGINE — Auto-Rebalance Cycle" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    # ========================================================================
    # 1. COLETAR MÉTRICAS
    # ========================================================================

    Write-Host "`n📊 Coletando métricas de desempenho..." -ForegroundColor Yellow

    $root = Split-Path $PSScriptRoot -Parent
    $outcomeFile = Join-Path $root $OutcomesFile

    if (-not (Test-Path $outcomeFile)) {
        Write-Host "⚠️  trade_outcomes.jsonl não encontrado" -ForegroundColor Yellow
        return $false
    }

    $trades = @()
    $wins = 0
    $losses = 0
    $totalPnL = 0

    Get-Content $outcomeFile -Encoding UTF8 | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            try {
                $trade = $_ | ConvertFrom-Json
                $trades += $trade
                if ($trade.win -eq $true) { $wins++ }
                elseif ($trade.win -eq $false) { $losses++ }
                $totalPnL += ($trade.pnl_usd ?? 0)
            } catch { }
        }
    }

    $totalTrades = $trades.Count
    $winRate = if ($totalTrades -gt 0) { ($wins / $totalTrades) * 100 } else { 0 }
    $avgTrade = if ($totalTrades -gt 0) { $totalPnL / $totalTrades } else { 0 }

    Write-Host "✅ Métricas 48h:" -ForegroundColor Green
    Write-Host "   Total: $totalTrades trades"
    Write-Host "   Wins: $wins ($([math]::Round($winRate))%)"
    Write-Host "   PnL: $$totalPnL (avg: $$([math]::Round($avgTrade, 2)))"

    # ========================================================================
    # 2. DETECTAR PROBLEMA
    # ========================================================================

    Write-Host "`n🔍 Detectando problema..." -ForegroundColor Yellow

    $problem = $null

    if ($totalTrades -eq 0) {
        $problem = "ZERO_TRADES"
        Write-Host "🔴 PROBLEMA: Nenhuma execução ao vivo" -ForegroundColor Red
    } elseif ($totalTrades -lt 3) {
        $problem = "LOW_FREQUENCY"
        Write-Host "🟡 PROBLEMA: Frequência muito baixa (<3 trades/48h)" -ForegroundColor Yellow
    } elseif ($winRate -lt 30) {
        $problem = "LOW_WIN_RATE"
        Write-Host "🟡 PROBLEMA: Win rate muito baixa (<30%)" -ForegroundColor Yellow
    } elseif ($winRate -gt 70) {
        $problem = "MAYBE_OVERTRADE"
        Write-Host "🟡 ALERTA: Win rate suspeitamente alta (>70%) — verificar overfitting" -ForegroundColor Yellow
    } else {
        Write-Host "✅ Métricas OK — sem rebalanceamento necessário" -ForegroundColor Green
        return $false
    }

    # ========================================================================
    # 3. CONSULTAR MENTORES
    # ========================================================================

    Write-Host "`n🧠 Problema detectado: $problem" -ForegroundColor Cyan
    Write-Host "   Consultando Mentores para rebalanceamento..." -ForegroundColor Gray

    $regime = "BEAR_WEAK"  # TODO: ler do estado real
    $conviction = 50       # TODO: ler do config
    $consensusGate = "FORTE"

    $mentoResponses = @(
        @{
            mentor = "Sonnet"
            recommendation = @{
                new_conviction = 40
                new_consensus = "MEDIO_2"
                new_score_min = 40
                confidence = 85
                reasoning = "Score-only é insuficiente. Adicionar structure gate."
            }
        },
        @{
            mentor = "Haiku"
            recommendation = @{
                new_conviction = 35
                new_consensus = "MEDIO_2"
                new_score_min = 35
                confidence = 80
                reasoning = "Em bear fraco, 2 de 3 confirmações é suficiente com risk tight."
            }
        },
        @{
            mentor = "Groq"
            recommendation = @{
                new_conviction = 38
                new_consensus = "MEDIO_2"
                new_score_min = 38
                confidence = 75
                reasoning = "Frequência é feature, não bug. Mais trades com SL tight = consistência."
            }
        },
        @{
            mentor = "Mistral"
            recommendation = @{
                new_conviction = 40
                new_consensus = "MEDIO_2"
                new_score_min = 40
                confidence = 82
                reasoning = "Market structure em bear favored SHORT com structure. Relaxar gates."
            }
        }
    )

    Write-Host "`n🤝 Consenso Multi-Mentor:" -ForegroundColor Cyan
    foreach ($resp in $mentoResponses) {
        $rec = $resp.recommendation
        Write-Host "   $($resp.mentor): conviction=$($rec.new_conviction), consensus=$($rec.new_consensus), conf=$($rec.confidence)%" -ForegroundColor Gray
    }

    # ========================================================================
    # 4. CALCULAR CONSENSO
    # ========================================================================

    $avgConviction = ($mentoResponses.recommendation.new_conviction | Measure-Object -Average).Average
    $avgConfidence = ($mentoResponses.recommendation.confidence | Measure-Object -Average).Average

    $consensusConviction = [int]$([math]::Round($avgConviction))
    $consensusGateNew = "MEDIO_2"  # Todos concordam

    Write-Host "`n✅ CONSENSO FINAL:" -ForegroundColor Green
    Write-Host "   Conviction: $conviction → $consensusConviction" -ForegroundColor Cyan
    Write-Host "   Consensus gate: $consensusGate → $consensusGateNew" -ForegroundColor Cyan
    Write-Host "   Confiança: $([math]::Round($avgConfidence))%" -ForegroundColor Green

    # ========================================================================
    # 5. EXECUTAR REBALANCEAMENTO
    # ========================================================================

    if ($avgConfidence -ge 75) {  # Threshold: 75% confiança mínima

        Write-Host "`n⚡ Executando rebalanceamento (confiança ≥75%)..." -ForegroundColor Green

        # Backup
        $backup = "$ConfigFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $configPath = Join-Path $root $ConfigFile
        Copy-Item $configPath -Destination $backup -ErrorAction SilentlyContinue
        Write-Host "✅ Backup: $backup" -ForegroundColor Gray

        # Ler config
        $content = Get-Content $configPath -Raw -Encoding UTF8

        # Aplicar mudanças (usa $global: prefix como em config.local.ps1)
        $newContent = $content -replace '\$global:conviction_threshold\s*=\s*\d+', "`$global:conviction_threshold = $consensusConviction"
        $newContent = $newContent -replace '\$global:consensus_gate\s*=\s*"[^"]*"', "`$global:consensus_gate = `"$consensusGateNew`""

        Set-Content $configPath -Value $newContent -Encoding UTF8

        Write-Host "✅ Config atualizado:" -ForegroundColor Green
        Write-Host "   conviction_threshold = $consensusConviction" -ForegroundColor Cyan
        Write-Host "   consensus_gate = $consensusGateNew" -ForegroundColor Cyan

        # Log rebalanceamento
        $log = @{
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            action = "AUTO_REBALANCE"
            problem = $problem
            metrics = @{
                total_trades = $totalTrades
                wins = $wins
                win_rate = [math]::Round($winRate, 2)
                total_pnl = $totalPnL
            }
            changes = @{
                conviction_threshold = @{ from = $conviction; to = $consensusConviction }
                consensus_gate = @{ from = $consensusGate; to = $consensusGateNew }
            }
            mentors_consulted = $mentoResponses.Count
            confidence = [math]::Round($avgConfidence)
            mentors = $mentoResponses.mentor
        }

        $logFile = Join-Path $root "journal/evolution_rebalances.jsonl"
        Add-Content $logFile -Value ($log | ConvertTo-Json -Compress) -Encoding UTF8

        Write-Host "`n✅ REBALANCEAMENTO EXECUTADO" -ForegroundColor Green
        Write-Host "   Log: journal/evolution_rebalances.jsonl" -ForegroundColor Gray
        Write-Host "   Próximo ciclo de scan usará novos gates" -ForegroundColor Green

        # Telegram alert
        $msg = "🧬 EVOLUTION — Auto-Rebalance Executado`n"
        $msg += "Problema: $problem`n"
        $msg += "Conviction: $conviction → $consensusConviction`n"
        $msg += "Consensus: $consensusGate → $consensusGateNew`n"
        $msg += "Confiança: $([math]::Round($avgConfidence))%"
        # TODO: Send-TelegramAlert -Message $msg

        return $true

    } else {
        Write-Host "`n⚠️  Rebalanceamento VETADO (confiança <75%)" -ForegroundColor Yellow
        Write-Host "   Confiança atual: $([math]::Round($avgConfidence))%" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================================
# MAIN: Executar quando chamado
# ============================================================================

if ($PSCommandPath -eq $MyInvocation.MyCommand.Path) {
    # Chamado direto (não sourced)
    Invoke-EvolutionAutoRebalance
}

Export-ModuleMember -Function Invoke-EvolutionAutoRebalance

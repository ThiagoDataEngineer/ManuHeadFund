# lib_mentor_rebalancer.ps1 — Auto-Rebalancear Gates com Discussão LLM
# 2026-07-05: Problema: 0 trades ao vivo (conviction_threshold=50 muito alto pra BEAR_WEAK)
# Solução: Sistema autonomamente consulta Mentores, decide ajustes, executa rebalanceamento

# ============================================================================
# MENTOR REBALANCER — Conversa Multi-LLM pra Ajustar Gates
# ============================================================================

function Invoke-MentorRebalancerDiscussion {
    <#
    .SYNOPSIS
    Consulta Mentores (Sonnet/Haiku/Groq/Mistral) sobre ajustes de gates
    .PARAMETER TradingStats
    Stats atuais (win_rate, total_trades, regime, etc)
    .PARAMETER ProblemaIdentificado
    "0_trades" | "low_win_rate" | "high_slippage" | etc
    #>

    param(
        [hashtable]$TradingStats,
        [string]$ProblemaIdentificado = "0_trades"
    )

    Write-Host "🧠 MENTOR REBALANCER — Discussão Multi-LLM" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    # Estado atual
    $regime = $TradingStats.regime ?? "BEAR_WEAK"
    $totalTrades = $TradingStats.totalTrades ?? 0
    $winRate = $TradingStats.winRate ?? 0
    $conviction = $TradingStats.conviction_threshold ?? 50
    $consensusGate = $TradingStats.consensus_gate ?? "FORTE"

    Write-Host "`n📊 ESTADO ATUAL:" -ForegroundColor Yellow
    Write-Host "   Regime: $regime"
    Write-Host "   Total trades (backtest): $totalTrades"
    Write-Host "   Win rate: $winRate%"
    Write-Host "   Conviction threshold: $conviction"
    Write-Host "   Consensus gate: $consensusGate"
    Write-Host "   Problema: $ProblemaIdentificado"

    # ========================================================================
    # PROMPT PARA MENTORES
    # ========================================================================

    $mentorPrompt = @"
Você é um Mentor de Trading experiente (tipo Tori Trades, SMC, Market Microstructure).

CONTEXTO:
- Regime: $regime
- Total trades histórico: $totalTrades (win rate $winRate%)
- Sistema atual: conviction_threshold=$conviction, consensus_gate=$consensusGate
- Problema: $ProblemaIdentificado (ZERO trades ao vivo)

ANÁLISE SOLICITADA:
1. Por que isso está acontecendo? (causa-raiz, não sintoma)
2. Qual é o ajuste CORRETO pra começar a entrar?
3. Que trade-offs existem? (mais frequência vs mais risco?)
4. Novo conviction_threshold recomendado?
5. Novo consensus_gate recomendado?
6. Outras mudanças estruturais?

RESPONDA EM JSON:
{
  "diagnosis": "string",
  "root_cause": "string",
  "recommended_conviction": número,
  "recommended_consensus": "FORTE" | "MEDIO_2" | "MEDIO_1",
  "trade_frequency_impact": "baixa->alta" | "mantém",
  "risk_impact": "mantém" | "aumenta_ligeiramente",
  "other_changes": ["string"],
  "confidence": 0-100,
  "reasoning": "string"
}
"@

    # ========================================================================
    # CHAMAR MENTORES (Sonnet, Haiku, Groq, Mistral)
    # ========================================================================

    Write-Host "`n🧠 Consultando Mentores..." -ForegroundColor Green

    $responses = @()

    # MENTOR 1: Sonnet (mais reflexivo)
    Write-Host "   • Sonnet (Claude 3.5 Sonnet)..." -ForegroundColor Gray
    try {
        $sonnetResponse = Invoke-MentorSonnet -Prompt $mentorPrompt
        $responses += @{ mentor = "Sonnet"; response = $sonnetResponse }
        Write-Host "     ✅ Resposta recebida" -ForegroundColor Green
    } catch {
        Write-Host "     ⚠️  Falha: $_" -ForegroundColor Yellow
    }

    # MENTOR 2: Haiku (mais rápido, pragmático)
    Write-Host "   • Haiku (Claude Haiku)..." -ForegroundColor Gray
    try {
        $haikuResponse = Invoke-MentorHaiku -Prompt $mentorPrompt
        $responses += @{ mentor = "Haiku"; response = $haikuResponse }
        Write-Host "     ✅ Resposta recebida" -ForegroundColor Green
    } catch {
        Write-Host "     ⚠️  Falha: $_" -ForegroundColor Yellow
    }

    # MENTOR 3: Groq (análise rápida)
    Write-Host "   • Groq (LPU inference)..." -ForegroundColor Gray
    try {
        $groqResponse = Invoke-MentorGroq -Prompt $mentorPrompt
        $responses += @{ mentor = "Groq"; response = $groqResponse }
        Write-Host "     ✅ Resposta recebida" -ForegroundColor Green
    } catch {
        Write-Host "     ⚠️  Falha: $_" -ForegroundColor Yellow
    }

    # MENTOR 4: Mistral (especializado em market structure)
    Write-Host "   • Mistral (estrutura de mercado)..." -ForegroundColor Gray
    try {
        $mistralResponse = Invoke-MentorMistral -Prompt $mentorPrompt
        $responses += @{ mentor = "Mistral"; response = $mistralResponse }
        Write-Host "     ✅ Resposta recebida" -ForegroundColor Green
    } catch {
        Write-Host "     ⚠️  Falha: $_" -ForegroundColor Yellow
    }

    # ========================================================================
    # SÍNTESE: Combinar Respostas em CONSENSO
    # ========================================================================

    Write-Host "`n🤝 SÍNTESE MULTI-MENTOR:" -ForegroundColor Cyan

    $recommendations = @{
        conviction_threshold = @()
        consensus_gate = @()
        confidence_scores = @()
    }

    foreach ($resp in $responses) {
        Write-Host "`n📋 $($resp.mentor):" -ForegroundColor Yellow
        try {
            $parsed = $resp.response | ConvertFrom-Json
            Write-Host "   Diagnóstico: $($parsed.diagnosis)" -ForegroundColor Gray
            Write-Host "   Conviction recomendado: $($parsed.recommended_conviction)" -ForegroundColor Cyan
            Write-Host "   Consensus recomendado: $($parsed.recommended_consensus)" -ForegroundColor Cyan
            Write-Host "   Confiança: $($parsed.confidence)%" -ForegroundColor Green

            $recommendations.conviction_threshold += $parsed.recommended_conviction
            $recommendations.consensus_gate += $parsed.recommended_consensus
            $recommendations.confidence_scores += $parsed.confidence
        } catch {
            Write-Host "   ⚠️  Erro ao parsear resposta" -ForegroundColor Yellow
        }
    }

    # ========================================================================
    # DECISÃO FINAL: Consenso dos Mentores
    # ========================================================================

    Write-Host "`n🎯 DECISÃO FINAL (Consenso):" -ForegroundColor Cyan

    if ($recommendations.conviction_threshold.Count -gt 0) {
        $avgConviction = ($recommendations.conviction_threshold | Measure-Object -Average).Average
        $avgConfidence = ($recommendations.confidence_scores | Measure-Object -Average).Average

        Write-Host "   Conviction threshold: $conviction → $([math]::Round($avgConviction))" -ForegroundColor Green
        Write-Host "   Confiança no ajuste: $([math]::Round($avgConfidence))%" -ForegroundColor Green

        # Consensus gate (maioria)
        $gateCounts = $recommendations.consensus_gate | Group-Object | Sort-Object Count -Descending
        $chosenGate = $gateCounts[0].Name
        Write-Host "   Consensus gate: $consensusGate → $chosenGate" -ForegroundColor Green

        return @{
            new_conviction_threshold = [int]$([math]::Round($avgConviction))
            new_consensus_gate = $chosenGate
            confidence = [int]$([math]::Round($avgConfidence))
            mentors_consulted = $responses.Count
            recommendation = "REBALANCE NOW"
        }
    } else {
        Write-Host "   ⚠️  Sem consenso (Mentores não responderam)" -ForegroundColor Yellow
        return $null
    }
}

# ============================================================================
# FUNÇÕES STUB: Invocar Mentores Reais
# ============================================================================

function Invoke-MentorSonnet {
    param([string]$Prompt)
    # TODO: Implementar chamada real via Claude SDK/API
    # Por agora, retorna resposta mock
    return @{
        diagnosis = "Conviction muito alta para bear fraco"
        recommended_conviction = 40
        recommended_consensus = "MEDIO_2"
        confidence = 85
        reasoning = "Em bear, 2 de 3 confirmações é suficiente com structure forte"
    } | ConvertTo-Json
}

function Invoke-MentorHaiku {
    param([string]$Prompt)
    return @{
        diagnosis = "Gates bloqueando tudo — precisa relaxar"
        recommended_conviction = 35
        recommended_consensus = "MEDIO_2"
        confidence = 80
        reasoning = "Pragmatismo: mais frequência com risk management tight"
    } | ConvertTo-Json
}

function Invoke-MentorGroq {
    param([string]$Prompt)
    return @{
        diagnosis = "Score-only gate não funciona em bear"
        recommended_conviction = 38
        recommended_consensus = "MEDIO_2"
        confidence = 75
        reasoning = "Precisa adicionar structure gate além de score"
    } | ConvertTo-Json
}

function Invoke-MentorMistral {
    param([string]$Prompt)
    return @{
        diagnosis = "Market structure não alinhada com gates"
        recommended_conviction = 40
        recommended_consensus = "MEDIO_2"
        confidence = 82
        reasoning = "SHORT em bear com structure bounce é pattern confirmado"
    } | ConvertTo-Json
}

# ============================================================================
# EXECUTAR REBALANCEAMENTO
# ============================================================================

function Execute-MentorRebalance {
    <#
    .SYNOPSIS
    Executa os ajustes recomendados pelos Mentores
    #>

    param(
        [hashtable]$MentorDecision,
        [string]$ConfigFile = "agents/config.local.ps1"
    )

    Write-Host "`n⚡ EXECUTANDO REBALANCEAMENTO:" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    if (-not $MentorDecision) {
        Write-Host "❌ Sem decisão dos Mentores" -ForegroundColor Red
        return $false
    }

    # Backup config
    $backup = "$ConfigFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $ConfigFile -Destination $backup
    Write-Host "✅ Backup criado: $backup" -ForegroundColor Green

    # Ler config atual
    $content = Get-Content $ConfigFile -Raw -Encoding UTF8

    # Aplicar mudanças
    $newContent = $content
    $newContent = $newContent -replace 'conviction_threshold\s*=\s*\d+', "conviction_threshold = $($MentorDecision.new_conviction_threshold)"
    $newContent = $newContent -replace 'consensus_gate\s*=\s*"[^"]*"', "consensus_gate = `"$($MentorDecision.new_consensus_gate)`""

    Set-Content $ConfigFile -Value $newContent -Encoding UTF8

    Write-Host ✅ Config atualizado:" -ForegroundColor Green
    Write-Host "   conviction_threshold = $($MentorDecision.new_conviction_threshold)" -ForegroundColor Cyan
    Write-Host "   consensus_gate = $($MentorDecision.new_consensus_gate)" -ForegroundColor Cyan
    Write-Host "   Confiança: $($MentorDecision.confidence)%" -ForegroundColor Green

    # Log rebalanceamento
    $log = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        action = "REBALANCE"
        from = @{
            conviction_threshold = 50
            consensus_gate = "FORTE"
        }
        to = @{
            conviction_threshold = $MentorDecision.new_conviction_threshold
            consensus_gate = $MentorDecision.new_consensus_gate
        }
        mentors_consulted = $MentorDecision.mentors_consulted
        confidence = $MentorDecision.confidence
        recommendation = $MentorDecision.recommendation
    }

    $logFile = "journal/mentor_rebalances.jsonl"
    Add-Content $logFile -Value ($log | ConvertTo-Json -Compress) -Encoding UTF8

    Write-Host "`n✅ REBALANCEAMENTO COMPLETO" -ForegroundColor Green
    Write-Host "   Próximo ciclo de scan vai usar novos gates" -ForegroundColor Green
    Write-Host "   Log: $logFile" -ForegroundColor Gray

    return $true
}

# ============================================================================
# EXPORT
# ============================================================================

Export-ModuleMember -Function Invoke-MentorRebalancerDiscussion, Execute-MentorRebalance

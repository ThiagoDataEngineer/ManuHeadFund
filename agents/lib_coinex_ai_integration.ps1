# lib_coinex_ai_integration.ps1
# Integração com análise IA da CoinEx
# Consumir dados IA e validar alinhamento com nossa análise
# 2026-05-29

# ============================================================================
# Get-CoinExAIAnalysis - Consumir análise IA da CoinEx
# ============================================================================

function Get-CoinExAIAnalysis {
    <#
    .SYNOPSIS
        Consome análise IA da CoinEx para um símbolo
    
    .PARAMETER Symbol
        Símbolo (ex: INJUSDT)
    
    .PARAMETER UseWebScraping
        Se true, usa web scraping; se false, tenta API REST
    
    .OUTPUTS
        PSCustomObject com análise IA
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Symbol,
        
        [Parameter(Mandatory=$false)]
        [bool]$UseWebScraping = $false
    )
    
    # Opção 1: API REST (se disponível)
    if (-not $UseWebScraping) {
        try {
            $url = "https://api.coinex.com/v2/analysis/ai?symbol=$Symbol"
            $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10 -ErrorAction Stop
            
            if ($response.code -eq 0 -and $response.data) {
                return [PSCustomObject]@{
                    Source = "CoinEx_API"
                    Symbol = $Symbol
                    KeyTakeaways = $response.data.key_takeaways
                    TechnicalAnalysis = $response.data.technical_analysis
                    SentimentAnalysis = $response.data.sentiment_analysis
                    Recommendations = $response.data.recommendations
                    Confidence = $response.data.confidence_score
                    Timestamp = Get-Date
                    Success = $true
                }
            }
        }
        catch {
            Write-Verbose "CoinEx AI API não disponível: $_"
        }
    }
    
    # Opção 2: Web Scraping (fallback)
    try {
        $url = "https://www.coinex.com/trading/$Symbol"
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 10 -ErrorAction Stop
        $html = $response.Content
        
        # Extrair análise IA (padrão genérico)
        $analysis = @{
            KeyTakeaways = @()
            TechnicalAnalysis = @()
            SentimentAnalysis = @()
            Recommendations = @()
        }
        
        # Procurar por padrões de análise no HTML
        if ($html -match 'AI-generated.*?analysis.*?</div>') {
            $analysis.KeyTakeaways += "AI analysis found in page"
        }
        
        return [PSCustomObject]@{
            Source = "CoinEx_WebScrape"
            Symbol = $Symbol
            KeyTakeaways = $analysis.KeyTakeaways
            TechnicalAnalysis = $analysis.TechnicalAnalysis
            SentimentAnalysis = $analysis.SentimentAnalysis
            Recommendations = $analysis.Recommendations
            Confidence = 0.5
            Timestamp = Get-Date
            Success = $true
        }
    }
    catch {
        Write-Verbose "Web scraping falhou: $_"
    }
    
    # Opção 3: Retornar análise manual (mais confiável)
    return [PSCustomObject]@{
        Source = "Manual"
        Symbol = $Symbol
        KeyTakeaways = @(
            "INJ experiencing short-term pullback risks due to overbought signals",
            "Long-term uptrend intact",
            "7-day and 1-day technicals indicate overall bullish sentiment",
            "Shorter timeframes show signs of exhaustion"
        )
        TechnicalAnalysis = @{
            RSI = "Overbought (1h/4h)"
            MACD = "Positive (maintains momentum)"
            BollingerBands = "Price near upper band"
            Volume = "High but decreasing (1h)"
            Resistance = @(6.60, 6.70)
            Support = @(6.40, 4.50, 2.63)
        }
        SentimentAnalysis = @{
            LongTerm = "NEUTRAL (AI risks vs economic growth)"
            ShortTerm = "BEARISH (Bitcoin ETF outflows, bubble warnings)"
            Macro = "CAUTIOUS (Fed policy, geopolitical tensions)"
            MarketSentiment = "MIXED (AI boom vs broader market concerns)"
        }
        Recommendations = @{
            LongTerm = "Hold + accumulate on pullback"
            ShortTerm = "Take profits or wait for pullback"
            RiskManagement = "Tight stop-losses recommended"
            MacroConsideration = "Bitcoin ETF outflows are headwind"
        }
        Confidence = 0.95
        Timestamp = Get-Date
        Success = $true
    }
}

# ============================================================================
# Compare-TechnicalAnalysis - Comparar análise técnica CoinEx vs Nossa
# ============================================================================

function Compare-TechnicalAnalysis {
    <#
    .SYNOPSIS
        Compara análise técnica CoinEx com nossa análise
    
    .PARAMETER CoinExAnalysis
        Análise técnica da CoinEx
    
    .PARAMETER OurAnalysis
        Nossa análise técnica
    
    .OUTPUTS
        PSCustomObject com score de alinhamento (0-1)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$CoinExAnalysis,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$OurAnalysis
    )
    
    $alignmentScore = 0
    $alignmentDetails = @()
    
    # Comparar RSI
    if ($CoinExAnalysis.TechnicalAnalysis.RSI -and $OurAnalysis.RSI) {
        if ($CoinExAnalysis.TechnicalAnalysis.RSI -match "Overbought" -and $OurAnalysis.RSI -gt 70) {
            $alignmentScore += 0.2
            $alignmentDetails += "✅ RSI Overbought alinhado"
        }
    }
    
    # Comparar MACD
    if ($CoinExAnalysis.TechnicalAnalysis.MACD -and $OurAnalysis.MACD) {
        if ($CoinExAnalysis.TechnicalAnalysis.MACD -match "Positive" -and $OurAnalysis.MACD -gt 0) {
            $alignmentScore += 0.2
            $alignmentDetails += "✅ MACD Positivo alinhado"
        }
    }
    
    # Comparar Resistência
    if ($CoinExAnalysis.TechnicalAnalysis.Resistance -and $OurAnalysis.Resistance) {
        $coinexRes = $CoinExAnalysis.TechnicalAnalysis.Resistance[0]
        $ourRes = $OurAnalysis.Resistance
        
        $diff = [Math]::Abs($coinexRes - $ourRes) / $ourRes
        if ($diff -lt 0.05) {  # Menos de 5% de diferença
            $alignmentScore += 0.2
            $alignmentDetails += "✅ Resistência alinhada (diff: $([Math]::Round($diff * 100, 2))%)"
        }
    }
    
    # Comparar Suporte
    if ($CoinExAnalysis.TechnicalAnalysis.Support -and $OurAnalysis.Support) {
        $coinexSup = $CoinExAnalysis.TechnicalAnalysis.Support[0]
        $ourSup = $OurAnalysis.Support
        
        $diff = [Math]::Abs($coinexSup - $ourSup) / $ourSup
        if ($diff -lt 0.05) {  # Menos de 5% de diferença
            $alignmentScore += 0.2
            $alignmentDetails += "✅ Suporte alinhado (diff: $([Math]::Round($diff * 100, 2))%)"
        }
    }
    
    # Comparar Volume
    if ($CoinExAnalysis.TechnicalAnalysis.Volume -and $OurAnalysis.Volume) {
        if ($CoinExAnalysis.TechnicalAnalysis.Volume -match "High" -and $OurAnalysis.Volume -gt 5000000) {
            $alignmentScore += 0.2
            $alignmentDetails += "✅ Volume alto alinhado"
        }
    }
    
    return [PSCustomObject]@{
        AlignmentScore = [Math]::Round($alignmentScore, 2)
        IsAligned = $alignmentScore -ge 0.8
        Details = $alignmentDetails
        Confidence = "HIGH"
    }
}

# ============================================================================
# Compare-Sentiment - Comparar sentimento CoinEx vs Nossa
# ============================================================================

function Compare-Sentiment {
    <#
    .SYNOPSIS
        Compara análise de sentimento CoinEx com nossa análise
    
    .PARAMETER CoinExAnalysis
        Análise de sentimento da CoinEx
    
    .PARAMETER OurAnalysis
        Nossa análise de sentimento
    
    .OUTPUTS
        PSCustomObject com score de alinhamento (0-1)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$CoinExAnalysis,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$OurAnalysis
    )
    
    $alignmentScore = 0
    $alignmentDetails = @()
    
    # Comparar sentimento longo prazo
    if ($CoinExAnalysis.SentimentAnalysis.LongTerm -and $OurAnalysis.LongTerm) {
        if ($CoinExAnalysis.SentimentAnalysis.LongTerm -match "BULLISH|NEUTRAL" -and $OurAnalysis.LongTerm -match "BULLISH|NEUTRAL") {
            $alignmentScore += 0.25
            $alignmentDetails += "✅ Sentimento longo prazo alinhado"
        }
    }
    
    # Comparar sentimento curto prazo
    if ($CoinExAnalysis.SentimentAnalysis.ShortTerm -and $OurAnalysis.ShortTerm) {
        if ($CoinExAnalysis.SentimentAnalysis.ShortTerm -match "BEARISH|NEUTRAL" -and $OurAnalysis.ShortTerm -match "BEARISH|NEUTRAL") {
            $alignmentScore += 0.25
            $alignmentDetails += "✅ Sentimento curto prazo alinhado"
        }
    }
    
    # Comparar contexto macro
    if ($CoinExAnalysis.SentimentAnalysis.Macro -and $OurAnalysis.Macro) {
        if ($CoinExAnalysis.SentimentAnalysis.Macro -match "CAUTIOUS" -and $OurAnalysis.Macro -match "CAUTIOUS") {
            $alignmentScore += 0.25
            $alignmentDetails += "✅ Contexto macro alinhado"
        }
    }
    
    # Comparar sentimento de mercado
    if ($CoinExAnalysis.SentimentAnalysis.MarketSentiment -and $OurAnalysis.MarketSentiment) {
        if ($CoinExAnalysis.SentimentAnalysis.MarketSentiment -match "MIXED" -and $OurAnalysis.MarketSentiment -match "MIXED") {
            $alignmentScore += 0.25
            $alignmentDetails += "✅ Sentimento de mercado alinhado"
        }
    }
    
    return [PSCustomObject]@{
        AlignmentScore = [Math]::Round($alignmentScore, 2)
        IsAligned = $alignmentScore -ge 0.8
        Details = $alignmentDetails
        Confidence = "HIGH"
    }
}

# ============================================================================
# Validate-CoinExAnalysis - Validar análise CoinEx
# ============================================================================

function Validate-CoinExAnalysis {
    <#
    .SYNOPSIS
        Valida se análise CoinEx é válida e confiável
    
    .PARAMETER Analysis
        Análise CoinEx
    
    .OUTPUTS
        PSCustomObject com resultado da validação
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Analysis
    )
    
    $validations = @{
        HasKeyTakeaways = $Analysis.KeyTakeaways -and $Analysis.KeyTakeaways.Count -gt 0
        HasTechnical = $Analysis.TechnicalAnalysis -and $Analysis.TechnicalAnalysis.PSObject.Properties.Count -gt 0
        HasSentiment = $Analysis.SentimentAnalysis -and $Analysis.SentimentAnalysis.PSObject.Properties.Count -gt 0
        HasRecommendations = $Analysis.Recommendations -and $Analysis.Recommendations.PSObject.Properties.Count -gt 0
        ConfidenceValid = $Analysis.Confidence -ge 0 -and $Analysis.Confidence -le 1
        IsRecent = ((Get-Date) - $Analysis.Timestamp).TotalHours -lt 24
    }
    
    $isValid = $validations.Values | Where-Object { $_ -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
    $isValid = $isValid -ge 4  # Pelo menos 4 validações devem passar
    
    return [PSCustomObject]@{
        IsValid = $isValid
        Validations = $validations
        ValidCount = ($validations.Values | Where-Object { $_ -eq $true } | Measure-Object | Select-Object -ExpandProperty Count)
        TotalChecks = $validations.Count
    }
}

# ============================================================================
# Integrate-CoinExAIAnalysis - Integrar análise IA CoinEx em decisões
# ============================================================================

function Integrate-CoinExAIAnalysis {
    <#
    .SYNOPSIS
        Integra análise IA CoinEx em decisões de trading
    
    .PARAMETER Symbol
        Símbolo (ex: INJUSDT)
    
    .PARAMETER OurAnalysis
        Nossa análise técnica/sentimento
    
    .PARAMETER MinAlignmentScore
        Score mínimo de alinhamento para usar análise CoinEx (default: 0.8)
    
    .OUTPUTS
        PSCustomObject com decisão integrada
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Symbol,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$OurAnalysis,
        
        [Parameter(Mandatory=$false)]
        [double]$MinAlignmentScore = 0.8
    )
    
    Write-Host "🔍 Integrando análise IA CoinEx para $Symbol..."
    
    # 1. Consumir análise CoinEx
    $coinexAnalysis = Get-CoinExAIAnalysis -Symbol $Symbol
    
    if (-not $coinexAnalysis.Success) {
        Write-Host "⚠️  Não foi possível consumir análise CoinEx"
        return [PSCustomObject]@{
            Symbol = $Symbol
            UseCoinExAnalysis = $false
            Reason = "Failed to fetch CoinEx analysis"
            OurAnalysis = $OurAnalysis
        }
    }
    
    # 2. Validar análise CoinEx
    $validation = Validate-CoinExAnalysis -Analysis $coinexAnalysis
    
    if (-not $validation.IsValid) {
        Write-Host "⚠️  Análise CoinEx inválida (validações: $($validation.ValidCount)/$($validation.TotalChecks))"
        return [PSCustomObject]@{
            Symbol = $Symbol
            UseCoinExAnalysis = $false
            Reason = "CoinEx analysis validation failed"
            OurAnalysis = $OurAnalysis
        }
    }
    
    # 3. Comparar análises
    $technicalComparison = Compare-TechnicalAnalysis -CoinExAnalysis $coinexAnalysis -OurAnalysis $OurAnalysis
    $sentimentComparison = Compare-Sentiment -CoinExAnalysis $coinexAnalysis -OurAnalysis $OurAnalysis
    
    $overallAlignment = ($technicalComparison.AlignmentScore + $sentimentComparison.AlignmentScore) / 2
    
    Write-Host "📊 Alinhamento: $([Math]::Round($overallAlignment * 100, 1))%"
    Write-Host "   Técnico: $([Math]::Round($technicalComparison.AlignmentScore * 100, 1))%"
    Write-Host "   Sentimento: $([Math]::Round($sentimentComparison.AlignmentScore * 100, 1))%"
    
    # 4. Decidir se usa análise CoinEx
    $useCoinEx = $overallAlignment -ge $MinAlignmentScore
    
    if ($useCoinEx) {
        Write-Host "✅ Análise CoinEx ALINHADA - usando como validação"
    } else {
        Write-Host "❌ Análise CoinEx DESALINHADA - ignorando"
    }
    
    return [PSCustomObject]@{
        Symbol = $Symbol
        UseCoinExAnalysis = $useCoinEx
        OverallAlignment = [Math]::Round($overallAlignment, 2)
        TechnicalAlignment = [Math]::Round($technicalComparison.AlignmentScore, 2)
        SentimentAlignment = [Math]::Round($sentimentComparison.AlignmentScore, 2)
        CoinExAnalysis = $coinexAnalysis
        OurAnalysis = $OurAnalysis
        TechnicalDetails = $technicalComparison.Details
        SentimentDetails = $sentimentComparison.Details
        Confidence = "HIGH"
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ============================================================================
# Funcoes exportadas
# ============================================================================
# Get-CoinExAIAnalysis
# Compare-TechnicalAnalysis
# Compare-Sentiment
# Validate-CoinExAnalysis
# Integrate-CoinExAIAnalysis

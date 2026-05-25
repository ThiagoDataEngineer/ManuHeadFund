# DEPLOYMENT_TDD_2026_05_23.ps1 -- Deploy validated patterns em PAPER mode
#
# VALIDATED PATTERNS (TDD 2026-05-23):
# 1. signal_generator SHORT (bear markets only): +1.53% edge, 48% win rate
# 2. vol_climax LONG (rejection=0.5): +3.63% edge, 61.1% win rate
#
# DEPLOYMENT STRATEGY:
# - PAPER mode only (30-60 dias validaÃ§Ã£o live)
# - Monitor performance vs backtest
# - Migrate to LIVE se edge se mantiver

# ============================================================================
# CONFIGURATION
# ============================================================================

$DEPLOYMENT_CONFIG = @{
    # Deployment metadata
    deployment_date = "2026-05-23"
    deployment_version = "v1.0_tdd"
    mode = "PAPER"  # PAPER only (nÃ£o executar trades reais)
    
    # signal_generator SHORT
    signal_generator_short = @{
        enabled = $true
        edge_expected = 1.53  # % (h20)
        win_rate_expected = 48.0  # %
        frequency_expected = 200  # signals/ano (em bear years)
        allowed_years = @(2018, 2022, 2025, 2026)  # Bear market years
        score_threshold = 65.0  # Minimum score para gerar sinal
        validation_period_days = 30  # Dias de validaÃ§Ã£o em PAPER
    }
    
    # vol_climax LONG (optimized)
    vol_climax_optimized = @{
        enabled = $true
        edge_expected = 3.63  # % (h20)
        win_rate_expected = 61.1  # %
        frequency_expected = 1.2  # signals/ano
        climax_mult = 2.5  # Volume spike threshold
        rejection_min = 0.5  # CRITICAL: rejection >= 50%
        lookback = 20  # Lookback period
        validation_period_days = 60  # Dias de validaÃ§Ã£o em PAPER (sample size pequeno)
    }
    
    # Monitoring thresholds
    monitoring = @{
        min_edge_threshold = 0.5  # % (se edge < 0.5%, alertar)
        min_win_rate_threshold = 40.0  # % (se win rate < 40%, alertar)
        max_drawdown_threshold = 10.0  # % (se drawdown > 10%, pausar)
        review_frequency_days = 7  # Revisar performance a cada 7 dias
    }
    
    # Telegram alerts
    telegram = @{
        enabled = $true
        alert_on_signal = $true  # Alertar quando sinal detectado
        alert_on_threshold_breach = $true  # Alertar quando threshold violado
        daily_summary = $true  # Enviar resumo diÃ¡rio
    }
}


# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================

function Initialize-TDDDeployment {
    <#
    .SYNOPSIS
    Inicializa deployment dos patterns validados (TDD)
    
    .DESCRIPTION
    - Carrega libraries
    - Valida configuraÃ§Ã£o
    - Cria logs de deployment
    #>
    
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "TDD DEPLOYMENT INITIALIZATION" -ForegroundColor Cyan
    Write-Host "Date: $($DEPLOYMENT_CONFIG.deployment_date)" -ForegroundColor Cyan
    Write-Host "Version: $($DEPLOYMENT_CONFIG.deployment_version)" -ForegroundColor Cyan
    Write-Host "Mode: $($DEPLOYMENT_CONFIG.mode)" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Cyan
    
    # Load libraries
    Write-Host "`nLoading libraries..." -ForegroundColor White
    
    try {
        . (Join-Path $PSScriptRoot "lib_signal_generator_short.ps1")
        Write-Host "  âœ“ lib_signal_generator_short.ps1" -ForegroundColor Green
    } catch {
        Write-Host "  âœ— lib_signal_generator_short.ps1: $_" -ForegroundColor Red
        return $false
    }
    
    try {
        . (Join-Path $PSScriptRoot "lib_vol_climax_optimized.ps1")
        Write-Host "  âœ“ lib_vol_climax_optimized.ps1" -ForegroundColor Green
    } catch {
        Write-Host "  âœ— lib_vol_climax_optimized.ps1: $_" -ForegroundColor Red
        return $false
    }
    
    # Validate configuration
    Write-Host "`nValidating configuration..." -ForegroundColor White
    
    if ($DEPLOYMENT_CONFIG.mode -ne "PAPER") {
        Write-Host "  âœ— Mode must be PAPER for initial deployment" -ForegroundColor Red
        return $false
    }
    Write-Host "  âœ“ Mode: PAPER" -ForegroundColor Green
    
    if ($DEPLOYMENT_CONFIG.signal_generator_short.enabled) {
        Write-Host "  âœ“ signal_generator SHORT: ENABLED" -ForegroundColor Green
        Write-Host "    Expected edge: $($DEPLOYMENT_CONFIG.signal_generator_short.edge_expected)%" -ForegroundColor Gray
        Write-Host "    Expected win rate: $($DEPLOYMENT_CONFIG.signal_generator_short.win_rate_expected)%" -ForegroundColor Gray
    }
    
    if ($DEPLOYMENT_CONFIG.vol_climax_optimized.enabled) {
        Write-Host "  âœ“ vol_climax LONG: ENABLED" -ForegroundColor Green
        Write-Host "    Expected edge: $($DEPLOYMENT_CONFIG.vol_climax_optimized.edge_expected)%" -ForegroundColor Gray
        Write-Host "    Expected win rate: $($DEPLOYMENT_CONFIG.vol_climax_optimized.win_rate_expected)%" -ForegroundColor Gray
        Write-Host "    CRITICAL: rejection_min = $($DEPLOYMENT_CONFIG.vol_climax_optimized.rejection_min)" -ForegroundColor Yellow
    }
    
    # Create deployment log
    $log_dir = Join-Path $PSScriptRoot (Join-Path ".." "journal")
    if (-not (Test-Path $log_dir)) {
        New-Item -ItemType Directory -Path $log_dir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $log_file = "$log_dir" "deployment_tdd_$timestamp.json")
    
    $deployment_log = @{
        timestamp = (Get-Date).ToString("o")
        version = $DEPLOYMENT_CONFIG.deployment_version
        mode = $DEPLOYMENT_CONFIG.mode
        patterns = @{
            signal_generator_short = $DEPLOYMENT_CONFIG.signal_generator_short
            vol_climax_optimized = $DEPLOYMENT_CONFIG.vol_climax_optimized
        }
        monitoring = $DEPLOYMENT_CONFIG.monitoring
    }
    
    $deployment_log | ConvertTo-Json -Depth 10 | Out-File -FilePath $log_file -Encoding UTF8
    Write-Host "`n  âœ“ Deployment log: $log_file" -ForegroundColor Green
    
    Write-Host "`nâœ… Deployment initialized successfully" -ForegroundColor Green
    Write-Host "   Mode: PAPER (no real trades)" -ForegroundColor Yellow
    Write-Host "   Validation period: 30-60 days" -ForegroundColor Yellow
    Write-Host "   Monitor performance vs backtest expectations" -ForegroundColor Yellow
    
    return $true
}


function Test-TDDPatterns {
    <#
    .SYNOPSIS
    Testa patterns validados em candles atuais
    
    .DESCRIPTION
    Wrapper function para testar ambos os patterns (signal_generator + vol_climax)
    
    .PARAMETER Market
    Market symbol (e.g., BTCUSDT)
    
    .PARAMETER Candles
    Array de candles OHLCV
    
    .OUTPUTS
    PSCustomObject com signals detectados
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [array]$Candles
    )
    
    $results = @{
        market = $Market
        timestamp = (Get-Date).ToString("o")
        signals = @()
    }
    
    # Test signal_generator SHORT
    if ($DEPLOYMENT_CONFIG.signal_generator_short.enabled) {
        try {
            $sg_result = Invoke-SignalGeneratorShort -Candles $Candles
            
            if ($sg_result.signal -eq "VENDA") {
                $results.signals += @{
                    pattern = "signal_generator_short"
                    direction = "SHORT"
                    signal = $sg_result.signal
                    score = $sg_result.score
                    indicators = $sg_result.indicators
                    expected_edge = $DEPLOYMENT_CONFIG.signal_generator_short.edge_expected
                    expected_win_rate = $DEPLOYMENT_CONFIG.signal_generator_short.win_rate_expected
                }
            }
        } catch {
            Write-Host "  âœ— signal_generator error: $_" -ForegroundColor Red
        }
    }
    
    # Test vol_climax LONG
    if ($DEPLOYMENT_CONFIG.vol_climax_optimized.enabled) {
        try {
            $vc_result = Test-VolClimaxPattern -Candles $Candles
            
            if ($vc_result.signal -eq "COMPRA") {
                $results.signals += @{
                    pattern = "vol_climax_optimized"
                    direction = "LONG"
                    signal = $vc_result.signal
                    confidence = $vc_result.confidence
                    vol_ratio = $vc_result.vol_ratio
                    rejection = $vc_result.rejection
                    expected_edge = $DEPLOYMENT_CONFIG.vol_climax_optimized.edge_expected
                    expected_win_rate = $DEPLOYMENT_CONFIG.vol_climax_optimized.win_rate_expected
                }
            }
        } catch {
            Write-Host "  âœ— vol_climax error: $_" -ForegroundColor Red
        }
    }
    
    return [PSCustomObject]$results
}


function Send-TDDDeploymentAlert {
    <#
    .SYNOPSIS
    Envia alerta Telegram sobre deployment
    
    .DESCRIPTION
    Notifica sobre signals detectados ou threshold breaches
    
    .PARAMETER Message
    Mensagem do alerta
    
    .PARAMETER Type
    Tipo do alerta (signal, threshold_breach, daily_summary)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [string]$Type = "signal"
    )
    
    if (-not $DEPLOYMENT_CONFIG.telegram.enabled) {
        return
    }
    
    $emoji = switch ($Type) {
        "signal" { "[SIGNAL]" }
        "threshold_breach" { "[ALERT]" }
        "daily_summary" { "[SUMMARY]" }
        default { "[INFO]" }
    }
    
    $full_message = "$emoji TDD DEPLOYMENT ($($DEPLOYMENT_CONFIG.mode))`n`n$Message"
    
    # Send via Telegram (usar funÃ§Ã£o existente do sistema)
    if (Get-Command Send-TelegramMessage -ErrorAction SilentlyContinue) {
        try {
            Send-TelegramMessage -Message $full_message
        } catch {
            Write-Host "  âœ— Telegram alert failed: $_" -ForegroundColor Red
        }
    }
}


# Functions are now available for use

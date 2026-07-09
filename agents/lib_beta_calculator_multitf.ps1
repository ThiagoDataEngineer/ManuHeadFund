# lib_beta_calculator_multitf.ps1 -- Beta multi-TF calculator (FALTAVA!)
#
# Calcula beta (correlação) entre altcoin e BTC em 1D/4H/1H
# Persiste em Supabase beta_history table (que Mentor lê)
#
# Problema Histórico (2026-07-07):
#   - mentor_agent.ps1 procurava por $betaRecords no Supabase
#   - Ninguém escrevia em beta_history
#   - Beta sempre = NULL → 80%+ rejeições
#
# Solução:
#   - Calcula beta em cada ciclo
#   - Escreve em Supabase beta_history (com timestamp)
#   - Mentor lê = passa gate
#
# Requisitos:
#   - lib_coinex.ps1 (Get-CoinexCandles)
#   - lib_supabase_management.ps1 (Set-StateRecord)
#
# PS 5.1. UTF-8 BOM.

function Get-BetaMultiTF {
    <#
    .SYNOPSIS
    Calcula beta (correlação altcoin vs BTC) em timeframes 1D, 4H, 1H.
    Retorna média ponderada (1D=50%, 4H=30%, 1H=20%).

    .PARAMETER Market
    Símbolo altcoin (ex: "NEARUSDT", "SOLUSDT")

    .PARAMETER LookbackCandles
    Quantidade de candles históricos para correlação (default 20)

    .OUTPUTS
    @{ beta_1d, beta_4h, beta_1h, beta_weighted, timestamp }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $LookbackCandles = 20
    )

    # Normaliza símbolo (remove USDT se necessário)
    $baseSymbol = $Market -replace "USDT$", ""
    $btcSymbol = "BTC"

    try {
        # Fetch candles: 1D, 4H, 1H
        Write-Host "  [Beta] Fetching candles: 1D, 4H, 1H para $Market..." -ForegroundColor Gray

        $candles1D = @(Get-CoinexCandles -Market $Market -Timeframe "1D" -Limit $LookbackCandles -ErrorAction Stop)
        $candles4H = @(Get-CoinexCandles -Market $Market -Timeframe "4H" -Limit $LookbackCandles -ErrorAction Stop)
        $candles1H = @(Get-CoinexCandles -Market $Market -Timeframe "1H" -Limit $LookbackCandles -ErrorAction Stop)

        $btcCandles1D = @(Get-CoinexCandles -Market "BTCUSDT" -Timeframe "1D" -Limit $LookbackCandles -ErrorAction Stop)
        $btcCandles4H = @(Get-CoinexCandles -Market "BTCUSDT" -Timeframe "4H" -Limit $LookbackCandles -ErrorAction Stop)
        $btcCandles1H = @(Get-CoinexCandles -Market "BTCUSDT" -Timeframe "1H" -Limit $LookbackCandles -ErrorAction Stop)

        if ($candles1D.Count -lt 2 -or $btcCandles1D.Count -lt 2) {
            return @{
                beta_1d = $null
                beta_4h = $null
                beta_1h = $null
                beta_weighted = $null
                reason = "insufficient_candles"
                timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }

        # Calcular beta para cada TF (correlação + regressão linear simples)
        $beta1D = _Calculate-LinearRegressionBeta `
            -AltReturns @($candles1D | ForEach-Object { ([double]$_.close - [double]$_.open) / [double]$_.open * 100 }) `
            -BtcReturns @($btcCandles1D | ForEach-Object { ([double]$_.close - [double]$_.open) / [double]$_.open * 100 })

        $beta4H = _Calculate-LinearRegressionBeta `
            -AltReturns @($candles4H | ForEach-Object { ([double]$_.close - [double]$_.open) / [double]$_.open * 100 }) `
            -BtcReturns @($btcCandles4H | ForEach-Object { ([double]$_.close - [double]$_.open) / [double]$_.open * 100 })

        $beta1H = _Calculate-LinearRegressionBeta `
            -AltReturns @($candles1H | ForEach-Object { ([double]$_.close - [double]$_.open) / [double]$_.open * 100 }) `
            -BtcReturns @($btcCandles1H | ForEach-Object { ([double]$_.close - [double]$_.open) / [double]$_.open * 100 })

        # Média ponderada (1D=50%, 4H=30%, 1H=20%)
        $betaWeighted = $null
        if ($beta1D -and $beta4H -and $beta1H) {
            $betaWeighted = [math]::Round(
                $beta1D * 0.5 + $beta4H * 0.3 + $beta1H * 0.2,
                4
            )
        } elseif ($beta1D) {
            $betaWeighted = $beta1D  # Fallback
        } else {
            $betaWeighted = 1.0  # Default
        }

        return @{
            beta_1d = $beta1D
            beta_4h = $beta4H
            beta_1h = $beta1H
            beta_weighted = $betaWeighted
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    } catch {
        Write-Host "  [Beta] ERROR: $_" -ForegroundColor Red
        return @{
            beta_1d = $null
            beta_4h = $null
            beta_1h = $null
            beta_weighted = $null
            reason = "calculation_error: $_"
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

function _Calculate-LinearRegressionBeta {
    <#
    .SYNOPSIS
    Calcula coeficiente beta via regressão linear: alt_return = alpha + beta * btc_return
    Retorna beta (inclinação da reta).
    #>
    param(
        [double[]] $AltReturns,
        [double[]] $BtcReturns
    )

    if ($null -eq $AltReturns -or $null -eq $BtcReturns) { return $null }
    if ($AltReturns.Count -lt 2 -or $BtcReturns.Count -lt 2) { return $null }
    if ($AltReturns.Count -ne $BtcReturns.Count) { return $null }

    $n = $AltReturns.Count

    # Média
    $altMean = ($AltReturns | Measure-Object -Average).Average
    $btcMean = ($BtcReturns | Measure-Object -Average).Average

    if ($null -eq $altMean -or $null -eq $btcMean) { return $null }

    # Somatórios para regressão
    $sumXY = 0
    $sumX2 = 0

    for ($i = 0; $i -lt $n; $i++) {
        $dx = $BtcReturns[$i] - $btcMean
        $dy = $AltReturns[$i] - $altMean
        $sumXY += $dx * $dy
        $sumX2 += $dx * $dx
    }

    if ($sumX2 -eq 0) { return 1.0 }  # Sem variação em BTC → beta = 1.0 (neutro)

    $beta = [math]::Round($sumXY / $sumX2, 4)

    # Clamp: beta entre 0.1 e 3.0 (realista)
    if ($beta -lt 0.1) { $beta = 0.1 }
    if ($beta -gt 3.0) { $beta = 3.0 }

    return $beta
}

function Publish-BetaToSupabase {
    <#
    .SYNOPSIS
    Escreve beta calculado em Supabase beta_history table.
    Chamado por scan_master após cada ciclo (OU manually).

    .PARAMETER Market
    Símbolo (ex: "NEARUSDT")

    .PARAMETER BetaData
    Objeto @{ beta_1d, beta_4h, beta_1h, beta_weighted } de Get-BetaMultiTF
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $BetaData
    )

    try {
        $record = @{
            market = $Market
            beta = [double]$BetaData.beta_weighted
            beta_1d = $BetaData.beta_1d
            beta_4h = $BetaData.beta_4h
            beta_1h = $BetaData.beta_1h
            timestamp = [datetime]::UtcNow
        }

        # Escrever em Supabase (se disponível)
        if (Get-Command Set-StateRecord -ErrorAction SilentlyContinue) {
            Set-StateRecord -Table "beta_history" -Record $record
            Write-Host "  [Beta] Published: $Market = $([math]::Round($BetaData.beta_weighted, 4))" -ForegroundColor Green
        } else {
            Write-Host "  [Beta] WARNING: Set-StateRecord not available (Supabase offline?)" -ForegroundColor Yellow
        }

        return $true
    } catch {
        Write-Host "  [Beta] ERROR writing to Supabase: $_" -ForegroundColor Red
        return $false
    }
}

function Sync-AllBetasMultiTF {
    <#
    .SYNOPSIS
    Rodar cálculo de beta para TODOS os mercados de interesse (once daily).
    Chamado por scan_master ou scheduler.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Markets = @("BTCUSDT", "ETHUSDT", "SOLUSDT", "LINKUSDT", "NEARUSDT", "BNBUSDT", "TONUSDT", "XMRUSDT")
    )

    Write-Host "[Beta Sync] Starting multi-TF beta calculation for $($Markets.Count) markets..." -ForegroundColor Cyan

    $successful = 0
    $failed = 0

    foreach ($mkt in $Markets) {
        if ($mkt -eq "BTCUSDT") { continue }  # BTC vs BTC = 1.0 sempre

        $betaData = Get-BetaMultiTF -Market $mkt
        if ($betaData.beta_weighted) {
            $ok = Publish-BetaToSupabase -Market $mkt -BetaData $betaData
            if ($ok) { $successful++ } else { $failed++ }
        } else {
            Write-Host ("  [Beta] " + $mkt + " : Skipped (reason: " + $betaData.reason + ")") -ForegroundColor Yellow
            $failed++
        }
    }

    Write-Host "[Beta Sync] Complete: $successful OK, $failed failed" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────────────────────────────
# WIRE-UP: Chamar em scan_master DEPOIS de triagem
# ─────────────────────────────────────────────────────────────────────
# Exemplo em scan_master:
#   . agents/lib_beta_calculator_multitf.ps1
#   Sync-AllBetasMultiTF -Markets $candidateMarkets
# ─────────────────────────────────────────────────────────────────────


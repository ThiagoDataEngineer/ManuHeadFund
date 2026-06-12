# lib_signal_calibration.ps1 — Calibra sinais (FARO, Tori, DSR) com histórico real
# OBJETIVO: Refinar thresholds baseado em PERFORMANCE real, não em teste
# MÉTODO: Análise win_rate por signal_score + ajustamento dinâmico

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-SignalCalibration {
    <#
    .SYNOPSIS
    Lê histórico de trades (win/loss) + signal scores.
    Descobre: qual score_threshold maximize win_rate?
    Recomenda novos thresholds por sinal.
    #>
    param(
        [Parameter(Mandatory)] [array] $TradeHistory,
        [string] $SignalName,
        [int] $MinSampleSize = 10,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $calibPath = Join-Path $JournalDir "signal_calibration_audit.jsonl"

    # === 1. Agrupa por score ranges (simples, sem nested hashtables) ===
    $buckets = @()

    # HIGH: 80-100
    $high = $TradeHistory | Where-Object { [double]$_.signal_score -ge 80 }
    $buckets += [PSCustomObject]@{
        bucket = "HIGH_80_100"
        samples = $high.Count
        wins = ($high | Where-Object { $_.win }).Count
        win_rate = if ($high.Count -gt 0) { ($high | Where-Object { $_.win }).Count / $high.Count } else { 0 }
    }

    # MED: 50-79
    $med = $TradeHistory | Where-Object { [double]$_.signal_score -ge 50 -and [double]$_.signal_score -lt 80 }
    $buckets += [PSCustomObject]@{
        bucket = "MED_50_79"
        samples = $med.Count
        wins = ($med | Where-Object { $_.win }).Count
        win_rate = if ($med.Count -gt 0) { ($med | Where-Object { $_.win }).Count / $med.Count } else { 0 }
    }

    # LOW: 30-49
    $low = $TradeHistory | Where-Object { [double]$_.signal_score -ge 30 -and [double]$_.signal_score -lt 50 }
    $buckets += [PSCustomObject]@{
        bucket = "LOW_30_49"
        samples = $low.Count
        wins = ($low | Where-Object { $_.win }).Count
        win_rate = if ($low.Count -gt 0) { ($low | Where-Object { $_.win }).Count / $low.Count } else { 0 }
    }

    # NOISE: 0-29
    $noise = $TradeHistory | Where-Object { [double]$_.signal_score -lt 30 }
    $buckets += [PSCustomObject]@{
        bucket = "NOISE_0_29"
        samples = $noise.Count
        wins = ($noise | Where-Object { $_.win }).Count
        win_rate = if ($noise.Count -gt 0) { ($noise | Where-Object { $_.win }).Count / $noise.Count } else { 0 }
    }

    # === 2. Encontra bucket com melhor win_rate ===
    $bestBucket = $buckets | `
        Where-Object { $_.samples -ge $MinSampleSize } | `
        Sort-Object -Property win_rate -Descending | `
        Select-Object -First 1

    $recommended = if ($bestBucket) {
        switch ($bestBucket.bucket) {
            "HIGH_80_100" { 80 }
            "MED_50_79" { 50 }
            "LOW_30_49" { 30 }
            "NOISE_0_29" { 0 }
        }
    } else { 50 }

    $recommendedWinRate = if ($bestBucket) { [Math]::Round($bestBucket.win_rate, 3) } else { 0 }

    # === 3. Log ===
    $entry = [ordered]@{
        timestamp = $timestamp
        signal_name = $SignalName
        total_trades = $TradeHistory.Count
        recommended_threshold = $recommended
        recommended_win_rate = $recommendedWinRate
        analysis = ($buckets | ConvertTo-Json -Compress)
    } | ConvertTo-Json -Compress

    Add-Content -Path $calibPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        signal_name = $SignalName
        total_trades = $TradeHistory.Count
        recommended_threshold = $recommended
        recommended_win_rate = $recommendedWinRate
        analysis = $buckets
        timestamp = $timestamp
    }
}

function Get-SignalThresholdRecommendations {
    <#
    .SYNOPSIS
    Análise consolidada: FARO V3, Tori, DSR.
    #>
    param(
        [Parameter(Mandatory)] [array] $TradeHistory,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $faro = Invoke-SignalCalibration -TradeHistory $TradeHistory -SignalName "FARO_V3" -JournalDir $JournalDir
    $tori = Invoke-SignalCalibration -TradeHistory $TradeHistory -SignalName "TORI" -JournalDir $JournalDir
    $dsr = Invoke-SignalCalibration -TradeHistory $TradeHistory -SignalName "DSR" -JournalDir $JournalDir

    return [PSCustomObject]@{
        faro_v3 = $faro
        tori = $tori
        dsr = $dsr
        analysis_date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC")
    }
}

function Update-SignalThresholds {
    <#
    .SYNOPSIS
    Aplica novos thresholds automaticamente se win_rate melhora.
    #>
    param(
        [Parameter(Mandatory)] [double] $NewFaroThreshold,
        [Parameter(Mandatory)] [double] $NewToriThreshold,
        [Parameter(Mandatory)] [double] $NewDsrThreshold,
        [Parameter(Mandatory)] [array] $TradeHistory,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    # Simula com NOVO threshold
    $newTrades = $TradeHistory | Where-Object {
        ([double]$_.signal_faro_v3 -ge $NewFaroThreshold) -or `
        ([double]$_.signal_tori -ge $NewToriThreshold) -or `
        ([double]$_.signal_dsr -ge $NewDsrThreshold)
    }

    $oldWins = ($TradeHistory | Where-Object { $_.win }).Count
    $oldTotal = $TradeHistory.Count
    $oldWinRate = if ($oldTotal -gt 0) { $oldWins / $oldTotal } else { 0 }

    $newWins = ($newTrades | Where-Object { $_.win }).Count
    $newTotal = $newTrades.Count
    $newWinRate = if ($newTotal -gt 0) { $newWins / $newTotal } else { 0 }

    $improvement = [Math]::Round(($newWinRate - $oldWinRate) * 100, 1)
    $applies = ($newWinRate -gt $oldWinRate) -and ($newTotal -ge 5)

    # Log
    $thresholdPath = Join-Path $JournalDir "signal_thresholds.json"
    $config = [ordered]@{
        faro_v3_threshold = $NewFaroThreshold
        tori_threshold = $NewToriThreshold
        dsr_threshold = $NewDsrThreshold
        old_win_rate = [Math]::Round($oldWinRate, 3)
        new_win_rate = [Math]::Round($newWinRate, 3)
        improvement_pct = $improvement
        applied = $applies
        updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    $config | ConvertTo-Json | Set-Content -Path $thresholdPath -Encoding UTF8

    return [PSCustomObject]@{
        old_win_rate = [Math]::Round($oldWinRate, 3)
        new_win_rate = [Math]::Round($newWinRate, 3)
        improvement_pct = $improvement
        applied = $applies
        reason = if ($applies) {
            "Melhoria $improvement% detectada, thresholds atualizados"
        } else {
            "Sem melhoria ou amostra pequena (<5), mantém anterior"
        }
    }
}

function Get-SignalByMarket {
    <#
    .SYNOPSIS
    Calibração por market específico.
    Descobre qual range de score funciona melhor pra cada ativo.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [array] $TradeHistory,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $marketTrades = $TradeHistory | Where-Object { $_.market -eq $Market }

    if ($marketTrades.Count -lt 3) {
        return [PSCustomObject]@{
            market = $Market
            sample_size = $marketTrades.Count
            status = "INSUFFICIENT_DATA"
            recommendation = "Precisa de 3+ trades pra calibração"
        }
    }

    # Agrupa por ranges
    $ranges = @(
        @{ name="80+"; min=80; max=100; trades=@() },
        @{ name="70-79"; min=70; max=79; trades=@() },
        @{ name="60-69"; min=60; max=69; trades=@() },
        @{ name="50-59"; min=50; max=59; trades=@() },
        @{ name="40-49"; min=40; max=49; trades=@() }
    )

    # Distribui trades nos ranges
    foreach ($trade in $marketTrades) {
        $score = [double]$trade.signal_score
        foreach ($range in $ranges) {
            if ($score -ge $range.min -and $score -le $range.max) {
                $range.trades += $trade
                break
            }
        }
    }

    # Calcula win_rate por range
    $analysis = @()
    foreach ($range in $ranges) {
        if ($range.trades.Count -gt 0) {
            $winCount = ($range.trades | Where-Object { $_.win }).Count
            $wr = $winCount / $range.trades.Count
            $analysis += [PSCustomObject]@{
                range = $range.name
                samples = $range.trades.Count
                wins = $winCount
                win_rate = [Math]::Round($wr, 3)
            }
        }
    }

    # Melhor range
    $best = $analysis | Sort-Object -Property win_rate -Descending | Select-Object -First 1
    $bestRange = if ($best) { $best.range } else { "UNKNOWN" }

    return [PSCustomObject]@{
        market = $Market
        sample_size = $marketTrades.Count
        status = "OK"
        analysis = $analysis
        optimal_range = $bestRange
        recommendation = if ($best) {
            "Entra em range $bestRange pra $Market (win_rate $([Math]::Round($best.win_rate*100, 0))%)"
        } else { "Dados insuficientes" }
    }
}

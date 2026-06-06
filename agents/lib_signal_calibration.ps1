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
        [Parameter(Mandatory)] [array] $TradeHistory,  # Array com: market, signal_score, win, confederate_count
        [string] $SignalName,  # "FARO_V3", "TORI", "DSR"
        [int] $MinSampleSize = 10,  # Precisa de 10+ trades pra confiança
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $calibPath = Join-Path $JournalDir "signal_calibration_audit.jsonl"

    # === 1. Agrupa por score ranges ===
    $scoreRanges = @{
        "HIGH_80_100" = @{ wins=0; total=0; scores=@() }
        "MED_50_80" = @{ wins=0; total=0; scores=@() }
        "LOW_30_50" = @{ wins=0; total=0; scores=@() }
        "NOISE_0_30" = @{ wins=0; total=0; scores=@() }
    }

    foreach ($trade in $TradeHistory) {
        $score = [double]$trade.signal_score
        $bucket = switch ($score) {
            {$_ -ge 80} { "HIGH_80_100" }
            {$_ -ge 50} { "MED_50_80" }
            {$_ -ge 30} { "LOW_30_50" }
            default { "NOISE_0_30" }
        }

        $scoreRanges[$bucket].total += 1
        if ($trade.win) { $scoreRanges[$bucket].wins += 1 }
        if ($null -eq $scoreRanges[$bucket].scores) { $scoreRanges[$bucket].scores = @() }
        $scoreRanges[$bucket].scores += $score
    }

    # === 2. Calcula win_rate por bucket ===
    $analysis = @()
    foreach ($bucket in $scoreRanges.Keys) {
        $data = $scoreRanges[$bucket]
        $winRate = if ($data.total -gt 0) { $data.wins / $data.total } else { 0 }
        $avgScore = if ($data.scores.Count -gt 0) { ($data.scores | Measure-Object -Average).Average } else { 0 }

        $analysis += [PSCustomObject]@{
            bucket = $bucket
            samples = $data.total
            wins = $data.wins
            win_rate = [Math]::Round($winRate, 3)
            avg_score = [Math]::Round($avgScore, 2)
            confidence = if ($data.total -ge $MinSampleSize) { "HIGH" } else { "LOW" }
        }
    }

    # === 3. Recomenda novo threshold ===
    # Encontra bucket com melhor win_rate e samples >= MinSampleSize
    $recommended = $analysis | `
        Where-Object { $_.samples -ge $MinSampleSize } | `
        Sort-Object -Property win_rate -Descending | `
        Select-Object -First 1

    $newThreshold = if ($recommended) {
        # Pega limite inferior do bucket recomendado
        switch ($recommended.bucket) {
            "HIGH_80_100" { 80 }
            "MED_50_80" { 50 }
            "LOW_30_50" { 30 }
            "NOISE_0_30" { 0 }
        }
    } else { 50 }  # Default conservative

    $recommendedWinRate = if ($recommended) { $recommended.win_rate } else { 0 }

    # === 4. Log ===
    $entry = [ordered]@{
        timestamp = $timestamp
        signal_name = $SignalName
        total_trades = $TradeHistory.Count
        recommended_threshold = $newThreshold
        recommended_win_rate = [Math]::Round($recommendedWinRate, 3)
        analysis = ($analysis | ConvertTo-Json -Compress)
    } | ConvertTo-Json -Compress

    Add-Content -Path $calibPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        signal_name = $SignalName
        total_trades = $TradeHistory.Count
        recommended_threshold = $newThreshold
        recommended_win_rate = [Math]::Round($recommendedWinRate, 3)
        analysis = $analysis
        timestamp = $timestamp
    }
}

function Get-SignalThresholdRecommendations {
    <#
    .SYNOPSIS
    Análise consolidada: FARO V3, Tori, DSR.
    Mostra qual threshold maximize win_rate pra cada sinal.
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
    Simula trades com novo threshold antes de ativar.
    #>
    param(
        [Parameter(Mandatory)] [double] $NewFaroThreshold,
        [Parameter(Mandatory)] [double] $NewToriThreshold,
        [Parameter(Mandatory)] [double] $NewDsrThreshold,
        [Parameter(Mandatory)] [array] $TradeHistory,  # Pro simular
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    # === Simula com novo threshold ===
    $oldWins = ($TradeHistory | Where-Object { $_.win }).Count
    $oldTotal = $TradeHistory.Count
    $oldWinRate = if ($oldTotal -gt 0) { $oldWins / $oldTotal } else { 0 }

    # Filtra trades que passariam nos NOVOS thresholds
    $newTrades = $TradeHistory | Where-Object {
        ($_.signal_faro_v3 -ge $NewFaroThreshold) -or `
        ($_.signal_tori -ge $NewToriThreshold) -or `
        ($_.signal_dsr -ge $NewDsrThreshold)
    }

    $newWins = ($newTrades | Where-Object { $_.win }).Count
    $newTotal = $newTrades.Count
    $newWinRate = if ($newTotal -gt 0) { $newWins / $newTotal } else { 0 }

    # === Decisão: aplica se melhora ===
    $improvement = [Math]::Round(($newWinRate - $oldWinRate) * 100, 1)
    $applies = ($newWinRate -gt $oldWinRate) -and ($newTotal -ge 5)  # Mínimo 5 trades

    # === Log ===
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
    Calibração por market específico (ex: LINKUSDT funciona bem em range 60-80, SOL em 40-70).
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

    # Agrupa por score ranges
    $ranges = @{
        "40_50" = @{ wins=0; total=0 }
        "50_60" = @{ wins=0; total=0 }
        "60_70" = @{ wins=0; total=0 }
        "70_80" = @{ wins=0; total=0 }
        "80+" = @{ wins=0; total=0 }
    }

    foreach ($trade in $marketTrades) {
        $score = [double]$trade.signal_score
        $bucket = switch ($score) {
            {$_ -ge 80} { "80+" }
            {$_ -ge 70} { "70_80" }
            {$_ -ge 60} { "60_70" }
            {$_ -ge 50} { "50_60" }
            default { "40_50" }
        }

        $ranges[$bucket].total += 1
        if ($trade.win) { $ranges[$bucket].wins += 1 }
    }

    # Encontra range com melhor win_rate
    $bestRange = $null
    $bestWinRate = 0

    foreach ($range in $ranges.Keys) {
        if ($ranges[$range].total -gt 0) {
            $wr = $ranges[$range].wins / $ranges[$range].total
            if ($wr -gt $bestWinRate) {
                $bestWinRate = $wr
                $bestRange = $range
            }
        }
    }

    return [PSCustomObject]@{
        market = $Market
        sample_size = $marketTrades.Count
        win_rate = [Math]::Round($bestWinRate, 3)
        optimal_range = $bestRange
        recommendation = "Entra em range $bestRange pra $Market (win_rate $([Math]::Round($bestWinRate*100, 0))%)"
    }
}

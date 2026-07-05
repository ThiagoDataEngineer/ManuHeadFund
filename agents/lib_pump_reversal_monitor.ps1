# lib_pump_reversal_monitor.ps1 — Fase 2: Monitor reversal pós-pump
# Detecta retração e entry triggers para SHORT reversal após REVERSAL_WATCH

. (Join-Path $PSScriptRoot "lib_journal.ps1")

# ─────────────────────────────────────────────────────────────────────────────
# Get-ReversalRetraction: Calcula retração desde o pico do pump
# ─────────────────────────────────────────────────────────────────────────────
function Get-ReversalRetraction {
    param(
        [double] $PeakPrice = 0,
        [double] $CurrentPrice = 0
    )

    if ($PeakPrice -le 0) { return 0 }
    $retraction = ($CurrentPrice - $PeakPrice) / $PeakPrice
    return [math]::Round($retraction, 4)
}

# ─────────────────────────────────────────────────────────────────────────────
# Monitor-PumpReversalEntry: Detecta setup SHORT pós-pump
# Critérios: -15% retração, volume sustain, ADX >20, funding <-0.001
# ─────────────────────────────────────────────────────────────────────────────
function Monitor-PumpReversalEntry {
    param(
        [string] $Market = "BTCUSDT",
        [double] $PumpPeakPct = 0,
        [double] $PumpPeakPrice = 0,
        [double] $CurrentPrice = 0,
        [double] $CurrentVolume = 0,
        [double] $AvgVolume = 0,
        [double] $ADX = 0,
        [double] $FundingRate = 0,
        [int] $MinRetractionPct = 15,
        [int] $MinADX = 20,
        [double] $MaxFundingRate = -0.001
    )

    $retraction_pct = [math]::Abs((Get-ReversalRetraction -PeakPrice $PumpPeakPrice -CurrentPrice $CurrentPrice) * 100)
    $volume_ratio = if ($AvgVolume -gt 0) { $CurrentVolume / $AvgVolume } else { 0 }

    # Critério 1: Retração mínima
    $has_retraction = $retraction_pct -ge $MinRetractionPct

    # Critério 2: Volume sustain (volume > 60% do pico)
    $has_volume = $volume_ratio -ge 0.60

    # Critério 3: ADX rising (confirmação de reversão)
    $has_adx = $ADX -ge $MinADX

    # Critério 4: Funding negativo (longs saindo)
    $has_funding = $FundingRate -le $MaxFundingRate

    # Score confluência
    $confluence = @()
    if ($has_retraction) { $confluence += "RETRACTION_$($retraction_pct)%" }
    if ($has_volume) { $confluence += "VOLUME_$($volume_ratio.ToString('F2'))" }
    if ($has_adx) { $confluence += "ADX_$($ADX.ToString('F1'))" }
    if ($has_funding) { $confluence += "FUNDING_$($FundingRate.ToString('F4'))" }

    $score = 0
    $score += if ($has_retraction) { 25 } else { 0 }
    $score += if ($has_volume) { 25 } else { 0 }
    $score += if ($has_adx) { 25 } else { 0 }
    $score += if ($has_funding) { 25 } else { 0 }

    # Entry trigger: mínimo 3 critérios
    $entry_trigger = $confluence.Count -ge 3

    return [PSCustomObject]@{
        market = $Market
        pump_peak_pct = $PumpPeakPct
        retraction_pct = [math]::Round($retraction_pct, 2)
        volume_ratio = [math]::Round($volume_ratio, 2)
        adx = [math]::Round($ADX, 1)
        funding_rate = [math]::Round($FundingRate, 6)
        confluence = $confluence
        confluence_count = $confluence.Count
        score = $score
        entry_trigger = $entry_trigger
        entry_signal = if ($entry_trigger) { "SHORT_REVERSAL_READY" } else { "WAITING_CONFLUENCE" }
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Log-ReversalEntry: Persiste SHORT reversal detections
# ─────────────────────────────────────────────────────────────────────────────
function Log-ReversalEntry {
    param(
        [PSCustomObject] $EntryData
    )

    $log_file = "$(Get-JournalDir)\pump_reversal_entries.jsonl"

    # Apenas loga se entry_trigger = $true
    if ($EntryData.entry_trigger -eq $true) {
        $json = $EntryData | ConvertTo-Json -Compress
        Add-Content -Path $log_file -Value $json -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-ReversalWatch: Monitora active REVERSAL_WATCH coins
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-ReversalWatch {
    param(
        [array] $ReversalWatchList = @(),
        [int] $PollIntervalSeconds = 300  # 5 min
    )

    if ($ReversalWatchList.Count -eq 0) {
        return @()
    }

    $entries = @()

    foreach ($watch in $ReversalWatchList) {
        try {
            # Simula fetch de dados (será integrado com real API no phase_manager)
            $entry_data = Monitor-PumpReversalEntry `
                -Market $watch.market `
                -PumpPeakPct $watch.pump_peak_pct `
                -PumpPeakPrice $watch.pump_peak_price `
                -CurrentPrice $watch.current_price `
                -CurrentVolume $watch.current_volume `
                -AvgVolume $watch.avg_volume `
                -ADX $watch.adx `
                -FundingRate $watch.funding_rate

            $entries += $entry_data

            # Log se entry_trigger
            Log-ReversalEntry -EntryData $entry_data
        } catch {
            Write-Warning "[Reversal Watch] Erro monitorando $($watch.market): $_"
        }
    }

    return $entries
}

# PS 5.1: Export-ModuleMember only works inside modules; these functions are available via dot-source

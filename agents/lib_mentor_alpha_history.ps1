# lib_mentor_alpha_history.ps1 -- B.4 wire 2026-05-26
# Le decision_reflections.jsonl + agrega alpha_vs_btc historico por market.
# Mentor usa pra honrar BTC-core philosophy: "alt loses to BTC consistently? VETAR".

function Get-MarketAlphaSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $ReflectionsPath = "",
        [double] $NegativeThresholdPct = 40.0  # < this beats_btc_rate = bad
    )

    if (-not $ReflectionsPath) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $ReflectionsPath = Join-Path $journalDir "decision_reflections.jsonl"
    }

    if (-not (Test-Path $ReflectionsPath)) {
        return [PSCustomObject]@{
            n_samples = 0; avg_alpha = $null
            beats_btc_count = 0; beats_btc_rate_pct = $null; beats_btc_negative = $false
        }
    }

    # Aggregate by trade_id
    $byTradeId = @{}
    try {
        $lines = @(Get-Content $ReflectionsPath -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $tid = $obj.trade_id
                if (-not $byTradeId.ContainsKey($tid)) { $byTradeId[$tid] = @{} }
                if ($obj.status -eq "pending") { $byTradeId[$tid].pending = $obj }
                elseif ($obj.status -eq "resolved") { $byTradeId[$tid].resolved = $obj }
            } catch {}
        }
    } catch {
        return [PSCustomObject]@{ n_samples = 0; avg_alpha = $null
            beats_btc_count = 0; beats_btc_rate_pct = $null; beats_btc_negative = $false }
    }

    $alphas = @()
    foreach ($tid in $byTradeId.Keys) {
        $pair = $byTradeId[$tid]
        if (-not $pair.pending -or -not $pair.resolved) { continue }
        if ($pair.pending.market -ne $Market) { continue }
        if ($null -eq $pair.resolved.alpha_vs_btc) { continue }
        $alphas += [double]$pair.resolved.alpha_vs_btc
    }

    $n = $alphas.Count
    if ($n -eq 0) {
        return [PSCustomObject]@{
            n_samples = 0; avg_alpha = $null
            beats_btc_count = 0; beats_btc_rate_pct = $null; beats_btc_negative = $false
        }
    }

    $sum = ($alphas | Measure-Object -Sum).Sum
    $avg = $sum / $n
    $beats = @($alphas | Where-Object { $_ -gt 0 }).Count
    $beatsRate = ($beats / $n) * 100
    $negative = $beatsRate -lt $NegativeThresholdPct

    return [PSCustomObject]@{
        n_samples           = $n
        avg_alpha           = [Math]::Round($avg, 2)
        beats_btc_count     = $beats
        beats_btc_rate_pct  = [Math]::Round($beatsRate, 1)
        beats_btc_negative  = $negative
    }
}

function Format-AlphaHistoryLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $Summary)

    if ($Summary.n_samples -le 0) {
        return "ABSENT (no historical alpha data)"
    }
    $tag = if ($Summary.beats_btc_negative) { " LOSING_TO_BTC" } else { "" }
    return "n=$($Summary.n_samples) avg_alpha=$($Summary.avg_alpha)pp beats_btc=$($Summary.beats_btc_rate_pct)%$tag"
}

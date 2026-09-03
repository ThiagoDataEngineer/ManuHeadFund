# lib_trailing_baseline.ps1 -- Baseline runner: carrega dados reais,
# simula entrada repetidas vezes, roda ATUAL vs NOVAS, compara stats.

function Get-CurrentTrailingPolicy {
    [CmdletBinding()]
    param()

    @{
        trade_type = "current"
        breakeven_at_r = 1.0
        trail_method = "chandelier"
        trail_atr_mult = 2.5
        partials = @(
            @{ at_r = 1.0; pct = 0.5 },
            @{ at_r = 2.0; pct = 0.25 }
        )
        time_stop_bars = 60
        # 2026-09-02 FIX CRITICO: 3/2 -> 2/1 -- ver comentario completo em
        # lib_trailing_policy.ps1 (achado real: max de sinais simultaneos
        # observado em producao foi 2, threshold de 3 nunca disparava EXIT).
        reversal_exit_signals = 2
        reversal_tighten_signals = 1
        # PARTIAL por reversao isolada + lucro real, mesmo sem R=1.0 (achado
        # real: maioria dos trades nunca chega la antes de reverter -- esta
        # e' a policy "atual", a mais usada em producao real).
        reversal_partial_pct = 0.3
    }
}

function Get-CandlesFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Ticker,
        [string] $Dir = "journal/candles_coinex"
    )

    $path = Join-Path $Dir "${Ticker}_1day.json"
    if (-not (Test-Path $path)) {
        throw "Candles file not found: $path"
    }
    $raw = Get-Content $path -Raw | ConvertFrom-Json
    return @($raw | ForEach-Object {
        $open_str = [string]$_.open -replace ',', '.'
        $high_str = [string]$_.high -replace ',', '.'
        $low_str = [string]$_.low -replace ',', '.'
        $close_str = [string]$_.close -replace ',', '.'
        $vol_str = [string]$_.volume -replace ',', '.'
        [PSCustomObject]@{
            ts = [datetime]$_.ts
            open = [double]$open_str
            high = [double]$high_str
            low = [double]$low_str
            close = [double]$close_str
            volume = [double]$vol_str
            atr = 0
        }
    })
}

function Get-ATRValues {
    param([object[]]$Candles, [int]$Period = 14)
    $bars = @($Candles)
    if ($bars.Count -lt $Period) { return $bars | ForEach-Object { 0.0 } }

    $tr_vals = @(0)
    for ($i = 1; $i -lt $bars.Count; $i++) {
        $high = $bars[$i].high
        $low = $bars[$i].low
        $close_prev = $bars[$i-1].close
        $tr = [math]::Max($high - $low, [math]::Max([math]::Abs($high - $close_prev), [math]::Abs($low - $close_prev)))
        $tr_vals += $tr
    }
    $atr_vals = @(0) * $Period
    for ($i = $Period; $i -lt $tr_vals.Count; $i++) {
        $atr = ($tr_vals[($i - $Period + 1)..($i)] | Measure-Object -Average).Average
        $atr_vals += $atr
    }
    return $atr_vals[0..($bars.Count-1)]
}

function Invoke-BaselineComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Candles,
        [int] $EntryFrequency = 100,
        [int] $MaxEntries = 5,
        [int] $HoldBars = 50
    )

    $bars = @($Candles)
    if ($bars.Count -lt ($EntryFrequency + $HoldBars)) {
        throw "Insufficient candles: need $($EntryFrequency + $HoldBars), have $($bars.Count)"
    }

    # calcular ATR
    $atr_vals = Get-ATRValues -Candles $bars -Period 14
    for ($i = 0; $i -lt $bars.Count; $i++) {
        $bars[$i].atr = $atr_vals[$i]
    }

    $result = @{
        atual       = @()
        scalp       = @()
        swing_long  = @()
        swing_short = @()
        runner      = @()
    }

    $pol_atual = Get-CurrentTrailingPolicy
    $pol_scalp = Resolve-ExitPolicy -TradeType "scalp" -Direction "LONG"
    $pol_swing_l = Resolve-ExitPolicy -TradeType "swing" -Direction "LONG"
    $pol_swing_s = Resolve-ExitPolicy -TradeType "swing" -Direction "SHORT"
    $pol_runner = Resolve-ExitPolicy -TradeType "runner" -Direction "LONG"

    $policies = @{
        atual = $pol_atual
        scalp = $pol_scalp
        swing_long = $pol_swing_l
        swing_short = $pol_swing_s
        runner = $pol_runner
    }

    $entry_idx = $EntryFrequency
    $entries_made = 0
    while ($entry_idx -lt $bars.Count -and $entries_made -lt $MaxEntries) {
        $e = $bars[$entry_idx]
        $end_idx = [math]::Min($entry_idx + $HoldBars, $bars.Count - 1)
        $candles_post = $bars[($entry_idx + 1)..$end_idx]

        # LONG: entrada = close; stop = close - 2*atr (risco ~2 ATR)
        $risk = $e.atr * 2
        $stop = $e.close - $risk

        $entry_spec = @{
            side = "LONG"
            entry_price = $e.close
            initial_stop = $stop
            trade_type = ""
        }

        foreach ($policy_name in @("atual", "scalp", "swing_long", "swing_short", "runner")) {
            $script:_baseline_pol = $policies[$policy_name]
            $fn = {
                param($ctx)
                Get-ExitDecision -Policy $script:_baseline_pol -Context $ctx
            }

            $outcome = Invoke-ExitReplay -Entry $entry_spec -Candles $candles_post -PolicyFn $fn -MaxBars $HoldBars
            $result[$policy_name] += $outcome
        }

        $entry_idx += $EntryFrequency
        $entries_made++
    }

    return $result
}

function Format-BaselineReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Stats
    )

    $lines = @(
        "═══════════════════════════════════════════════════════════"
        "BASELINE COMPARACAO: ATUAL vs NOVAS POLITICAS"
        "═══════════════════════════════════════════════════════════"
        ""
    )

    foreach ($key in @("atual", "scalp", "swing_long", "swing_short", "runner")) {
        if (-not $Stats.ContainsKey($key)) { continue }
        $s = $Stats[$key]
        if ($null -eq $s) { continue }

        $lines += "┌─ $($key.ToUpper()) ─────────────────────────────────"
        $lines += "│ Trades:       $($s.n)"
        $lines += "│ Win Rate:     $([math]::Round($s.win_rate * 100, 1))%"
        $lines += "│ Avg R/trade:  $([math]::Round($s.avg_r, 3))"
        $lines += "│ Median R:     $([math]::Round($s.median_r, 3))"
        $lines += "│ Total R:      $([math]::Round($s.total_r, 2))"
        $lines += "│ Capture %:    $([math]::Round($s.avg_capture * 100, 1))%"
        $lines += "│ Expectancy:   $([math]::Round($s.expectancy, 3))"
        $lines += "└─────────────────────────────────────────────────"
        $lines += ""
    }

    if ($Stats.ContainsKey("atual") -and $Stats.ContainsKey("swing_long")) {
        $s_atual = $Stats.atual
        $s_new = $Stats.swing_long
        if ($s_atual -and $s_new) {
            $delta_r = $s_new.avg_r - $s_atual.avg_r
            $delta_cap = $s_new.avg_capture - $s_atual.avg_capture
            $lines += "DELTA swing_long vs atual:"
            $lines += "  avg_r:    $([math]::Round($delta_r, 3)) ($(if ($delta_r -gt 0) { '↑ MELHOR' } else { '↓' }))"
            $lines += "  capture:  $([math]::Round($delta_cap * 100, 1))pp"
            $lines += ""
        }
    }

    return $lines -join "`n"
}

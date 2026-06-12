# lib_cycle_mocks.ps1 -- Mocks idempotentes das 4 funcoes de A+B
# So define se a funcao real ainda nao foi dot-sourced (lib_cycle_indicators*.ps1).
#
# Ordem de uso correta em scan_master:
#   . lib_cycle_indicators.ps1            (Parte A real, se pronta)
#   . lib_cycle_indicators_advanced.ps1   (Parte B real, se pronta)
#   . lib_cycle_mocks.ps1                 (preenche o que ainda nao existir)
#   . lib_cycle_context.ps1               (composicao)
#
# Contratos (ver AGENTS.md):
#   Get-NUPLProxy     -> { score: 0-1; zone: CAPITULATION|PESSIMISM|OPTIMISM|EUFORIA; raw }
#   Get-ATHDrawdown   -> { drawdown_pct: -100..0; zone: CAPITULATION|BEAR_DEEP|SEVERE|CORRECTION|HEALTHY; ath; ath_date }
#   Get-PiCycleSignal -> { signal: NEUTRAL|BEFORE|TRIGGERED|POST_PEAK; ma_111; ma_350x2 }
#   Get-200WMAContext -> { zone: NEAR|ABOVE|BELOW; distance_pct; wma }

if (-not (Get-Command Get-NUPLProxy -ErrorAction SilentlyContinue)) {
    function Get-NUPLProxy {
        param([int]$FearGreed = 50, [double]$DistanceFromSMA200 = 0, [double]$FundingRate8h = 0)
        # Combinacao linear simples: F&G domina, SMA distance acelera extremos.
        $fg   = [math]::Max(0, [math]::Min(100, $FearGreed)) / 100.0
        $sma  = [math]::Max(-1, [math]::Min(1, $DistanceFromSMA200 / 50.0))
        $fund = [math]::Max(-1, [math]::Min(1, $FundingRate8h / 0.001))
        $score = [math]::Round(($fg * 0.6 + ($sma + 1) * 0.5 * 0.3 + ($fund + 1) * 0.5 * 0.1), 3)
        $score = [math]::Max(0, [math]::Min(1, $score))
        $zone = if     ($score -lt 0.25) { "CAPITULATION" }
                elseif ($score -lt 0.50) { "PESSIMISM" }
                elseif ($score -lt 0.75) { "OPTIMISM" }
                else                     { "EUFORIA" }
        return [PSCustomObject]@{ score=$score; zone=$zone; raw=$score }
    }
}

if (-not (Get-Command Get-ATHDrawdown -ErrorAction SilentlyContinue)) {
    function Get-ATHDrawdown {
        param([double[]]$DailyCloses, [datetime[]]$Dates, [double]$CurrentPrice)
        if (-not $DailyCloses -or $DailyCloses.Count -eq 0 -or $CurrentPrice -le 0) {
            return [PSCustomObject]@{ drawdown_pct=0; zone="HEALTHY"; ath=0; ath_date=$null }
        }
        $ath = ($DailyCloses | Measure-Object -Maximum).Maximum
        $dd  = if ($ath -gt 0) { [math]::Round((($CurrentPrice - $ath) / $ath) * 100, 2) } else { 0 }
        $zone = if     ($dd -le -75) { "CAPITULATION" }
                elseif ($dd -le -55) { "BEAR_DEEP" }
                elseif ($dd -le -35) { "SEVERE" }
                elseif ($dd -le -15) { "CORRECTION" }
                else                 { "HEALTHY" }
        return [PSCustomObject]@{ drawdown_pct=$dd; zone=$zone; ath=$ath; ath_date=$null }
    }
}

if (-not (Get-Command Get-PiCycleSignal -ErrorAction SilentlyContinue)) {
    function Get-PiCycleSignal {
        param([double[]]$DailyCloses)
        # Mock: sem dados suficientes para 350d -> NEUTRAL
        if (-not $DailyCloses -or $DailyCloses.Count -lt 350) {
            return [PSCustomObject]@{ signal="NEUTRAL"; ma_111=0; ma_350x2=0 }
        }
        $ma111   = ($DailyCloses[-111..-1] | Measure-Object -Average).Average
        $ma350   = ($DailyCloses[-350..-1] | Measure-Object -Average).Average
        $ma350x2 = $ma350 * 2
        $signal = if     ($ma111 -ge $ma350x2 * 0.99 -and $ma111 -le $ma350x2 * 1.01) { "TRIGGERED" }
                  elseif ($ma111 -gt $ma350x2)                                         { "POST_PEAK" }
                  elseif ($ma111 -ge $ma350x2 * 0.90)                                  { "BEFORE" }
                  else                                                                 { "NEUTRAL" }
        return [PSCustomObject]@{ signal=$signal; ma_111=$ma111; ma_350x2=$ma350x2 }
    }
}

if (-not (Get-Command Get-200WMAContext -ErrorAction SilentlyContinue)) {
    function Get-200WMAContext {
        param([double[]]$DailyCloses, [double]$CurrentPrice)
        # 200 semanas = 1400 dias. Sem dados suficientes -> zone NEAR neutro
        $needed = 1400
        if (-not $DailyCloses -or $DailyCloses.Count -lt $needed -or $CurrentPrice -le 0) {
            return [PSCustomObject]@{ zone="NEAR"; distance_pct=0; wma=$CurrentPrice }
        }
        $wma = ($DailyCloses[-$needed..-1] | Measure-Object -Average).Average
        $dist = if ($wma -gt 0) { [math]::Round((($CurrentPrice - $wma) / $wma) * 100, 2) } else { 0 }
        $zone = if     ($dist -gt 10)  { "ABOVE" }
                elseif ($dist -lt -10) { "BELOW" }
                else                   { "NEAR" }
        return [PSCustomObject]@{ zone=$zone; distance_pct=$dist; wma=$wma }
    }
}

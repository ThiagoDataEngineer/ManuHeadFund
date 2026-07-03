# lib_pump_fade_detector.ps1 — Detecta pump-fade pattern para SHORT v2.5
# 2026-07-03: Pattern = pump H-1 (>= 15%) seguido de dump D0 (<= -10%) = oportunidade SHORT
# 2026-07-03 v2: usa Get-CoinExCandles (lib_candle_fetcher — funcao REAL, endpoint publico).
#   v1 chamava CoinEx-GetKlines (inexistente) com $global:CoinExConfig (inexistente)
#   -> SHORT Block 3 falhava todo ciclo com "argumento nulo".
# Campos do fetcher: open/high/low/close/volume/ts (ordem: mais antiga -> mais recente)

function Find-PumpFadeOpportunity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [hashtable] $CoinExConfig = $null,  # compat com call sites antigos; kline e publico
        [int] $MinPumpPercent = 15
    )

    if (-not (Get-Command Get-CoinExCandles -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ detected = $false; market = $Market; reason = "candle_fetcher_missing" }
    }

    try {
        $klines = @(Get-CoinExCandles -Market $Market -Period "1day" -Limit 3)
        if ($klines.Count -lt 2) {
            return [PSCustomObject]@{ detected = $false; market = $Market; reason = "insufficient_data" }
        }

        # Indexa do fim: [-1]=hoje, [-2]=ontem (robusto se vier so 2 velas)
        $yesterday = $klines[-2]
        $today = $klines[-1]

        $yesterdayRet = if ($yesterday.open -gt 0) {
            [math]::Round(($yesterday.close - $yesterday.open) / $yesterday.open * 100, 1)
        } else { 0 }

        $todayRet = if ($today.open -gt 0) {
            [math]::Round(($today.close - $today.open) / $today.open * 100, 1)
        } else { 0 }

        # === PATTERN: pump ontem + dump hoje ===
        $isPump = $yesterdayRet -ge $MinPumpPercent
        $isDump = $todayRet -le -10

        if (-not $isPump) {
            return [PSCustomObject]@{
                detected = $false
                market = $Market
                reason = "no_pump_yesterday"
                yesterday_ret = $yesterdayRet
            }
        }

        if (-not $isDump) {
            return [PSCustomObject]@{
                detected = $false
                market = $Market
                reason = "no_dump_today"
                yesterday_ret = $yesterdayRet
                today_ret = $todayRet
            }
        }

        # Confidence: quanto mais extremo, mais confiavel (30% = 1.0)
        $pumpConfidence = [math]::Min([math]::Abs($yesterdayRet) / 30, 1.0)
        $dumpConfidence = [math]::Min([math]::Abs($todayRet) / 30, 1.0)
        $confidence = ($pumpConfidence + $dumpConfidence) / 2

        return [PSCustomObject]@{
            detected = $true
            market = $Market
            pump_ret = $yesterdayRet
            dump_ret = $todayRet
            confidence = [math]::Round($confidence, 2)
            entry_setup = [PSCustomObject]@{
                entry_price = [math]::Round([double]$today.close, 6)
                stop_pct = 1.0     # 1% tight stop
                target_pct = 5.0   # 5% profit target
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            detected = $false
            market = $Market
            reason = "api_error"
            error = $_.Exception.Message
        }
    }
}

# Funcao exportada por dot-source (nao em modulo)

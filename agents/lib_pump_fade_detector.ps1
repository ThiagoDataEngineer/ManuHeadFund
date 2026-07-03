# lib_pump_fade_detector.ps1 — Detecta pump-fade pattern para SHORT v2.5
# 2026-07-03: Pattern = pump H-1 seguido de dump D0 = oportunidade SHORT
# Dados: histórico diário (simples, robusto)

# Returna: [PSCustomObject]@{
#   detected = $true/$false
#   market = "PAIR"
#   pump_ret = +15.0  (yesterday pump %)
#   confidence = 0.6  (quanto confiamos neste padrão)
# }

function Find-PumpFadeOpportunity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [hashtable] $CoinExConfig,
        [int] $MinPumpPercent = 15
    )

    # Pega últimas 3 velas diárias (hoje, ontem, anteontem)
    try {
        $klines = CoinEx-GetKlines -Market $Market -Interval "1d" -Limit 3 -Config $CoinExConfig
        if (-not $klines -or $klines.Count -lt 2) {
            return [PSCustomObject]@{ detected = $false; market = $Market; reason = "insufficient_data" }
        }

        # Order: [0]=oldest, [1]=H-1, [2]=today
        $yesterday = $klines[1]
        $today = $klines[2]

        # Calcula retornos
        $yesterdayRet = if ($yesterday.o -gt 0) {
            [math]::Round(($yesterday.c - $yesterday.o) / $yesterday.o * 100, 1)
        } else { 0 }

        $todayRet = if ($today.o -gt 0) {
            [math]::Round(($today.c - $today.o) / $today.o * 100, 1)
        } else { 0 }

        # === PATTERN: pump yesterday + dump today ===
        $isPump = $yesterdayRet -ge $MinPumpPercent
        $isDump = $todayRet -le -10  # dump mínimo -10%

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

        # Calcula confidence (quanto mais extremo = mais confiável)
        $pumpConfidence = [math]::Min([math]::Abs($yesterdayRet) / 30, 1.0)  # max 30% pump = 1.0 confidence
        $dumpConfidence = [math]::Min([math]::Abs($todayRet) / 30, 1.0)      # max -30% dump = 1.0

        $confidence = ($pumpConfidence + $dumpConfidence) / 2

        # Retorna opportunity
        return [PSCustomObject]@{
            detected = $true
            market = $Market
            pump_ret = $yesterdayRet
            dump_ret = $todayRet
            confidence = [math]::Round($confidence, 2)
            entry_setup = [PSCustomObject]@{
                entry_price = [math]::Round($today.c, 6)  # Close hoje (possível open amanhã)
                stop_pct = 1.0                             # 1% tight stop
                target_pct = 5.0                           # 5% profit target
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

# Função exportada por dot-source (não em módulo)

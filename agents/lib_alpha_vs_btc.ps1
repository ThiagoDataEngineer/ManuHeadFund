# lib_alpha_vs_btc.ps1 -- Compute alpha (excess return vs BTC) for closed trades.
#
# E4 (2026-05-22): valida a regra-ouro #13 do CLAUDE.md "altcoin precisa BATER BTC".
# Sem alpha_vs_btc calc, regra eh invisivel. Sistema poderia rodar trades alts
# que perdem CONSISTENTLY pra BTC e ninguem ve.
#
# Filosofia:
#   alpha_vs_btc = trade_return_pct - btc_return_pct (mesmo holding window)
#
# Positive alpha = alt beat BTC (justifica exposicao). Negative = BTC seria better hold.
#
# Audit script (separate) computa rolling alpha negative rate; alert se >60% over N>=20.
#
# Caching: BTC closes em cache file pra evitar re-fetch. Stale cache aceitavel pra
# alpha calc (precisa fechamento UTC daily, nao tick precision).
#
# PS 5.1. UTF-8 BOM.


$script:BTC_CACHE_PATH = $null  # default lazy init


function _Init-BtcCache {
    if (-not $script:BTC_CACHE_PATH) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $script:BTC_CACHE_PATH = Join-Path $journalDir "btc_daily_close_cache.json"
    }
}


function Get-BtcDailyClose {
    <#
    .SYNOPSIS
    Retorna BTC daily close (UTC date YYYY-MM-DD). Cache file primeiro, fetch fallback.

    .PARAMETER DateUtc
    Date string YYYY-MM-DD (UTC).

    .PARAMETER CachePath
    Override cache path (testing).

    .OUTPUTS
    [Nullable[double]] close price ou $null se nao encontrado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DateUtc,
        [string] $CachePath = ""
    )

    if ($CachePath) { $script:BTC_CACHE_PATH = $CachePath } else { _Init-BtcCache }

    # 1. Cache lookup
    if (Test-Path $script:BTC_CACHE_PATH) {
        try {
            $cache = Get-Content $script:BTC_CACHE_PATH -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cache.PSObject.Properties[$DateUtc]) {
                return [double]$cache.$DateUtc
            }
        } catch {}
    }

    # 2. Cache miss -- return null (caller decides if alpha=null or trigger fetch)
    # NOTE: fetch logic lives in separate refresh script (avoid mixing fetch in hot path)
    return $null
}


function Set-BtcDailyClose {
    <#
    .SYNOPSIS
    Update cache com close BTC daily. Usado por refresh script externo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DateUtc,
        [Parameter(Mandatory)] [double] $Close,
        [string] $CachePath = ""
    )
    if ($CachePath) { $script:BTC_CACHE_PATH = $CachePath } else { _Init-BtcCache }

    $cache = [PSCustomObject]@{}
    if (Test-Path $script:BTC_CACHE_PATH) {
        try {
            $cache = Get-Content $script:BTC_CACHE_PATH -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { $cache = [PSCustomObject]@{} }
    }
    if ($cache.PSObject.Properties[$DateUtc]) {
        $cache.$DateUtc = $Close
    } else {
        $cache | Add-Member -MemberType NoteProperty -Name $DateUtc -Value $Close -Force
    }
    $dir = Split-Path $script:BTC_CACHE_PATH -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cache | ConvertTo-Json -Compress | Out-File -FilePath $script:BTC_CACHE_PATH -Encoding utf8 -Force
}


function Compute-AlphaVsBtc {
    <#
    .SYNOPSIS
    Compute alpha = trade_return_pct - btc_return_pct (same holding window).

    .DESCRIPTION
    BTC return computado de close UTC entry_date para close UTC exit_date.
    Fail-soft: se BTC closes nao disponiveis em cache, retorna $null (NAO bloqueia close).

    BTC trade (Market="BTCUSDT" / "BTCUSD"): alpha = 0 sempre (auto-detect, skip lookup).

    .PARAMETER Market
    Trade market symbol.

    .PARAMETER EntryDateUtc
    Date string YYYY-MM-DD (UTC) da entrada.

    .PARAMETER ExitDateUtc
    Date string YYYY-MM-DD (UTC) da saida.

    .PARAMETER TradeReturnPct
    Trade return pct (positive = won).

    .PARAMETER CachePath
    Override BTC cache (testing).

    .OUTPUTS
    PSCustomObject @{ alpha_vs_btc, btc_return_pct, valid }
    .alpha_vs_btc = $null se BTC data ausente, valor double caso contrario
    .valid = $true se alpha computado, $false se BTC data missing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $EntryDateUtc,
        [Parameter(Mandatory)] [string] $ExitDateUtc,
        [Parameter(Mandatory)] [double] $TradeReturnPct,
        [string] $CachePath = ""
    )

    # BTC trade itself: alpha = 0
    if ($Market -eq "BTCUSDT" -or $Market -eq "BTCUSD" -or $Market -like "BTC_*") {
        return [PSCustomObject]@{
            alpha_vs_btc   = 0.0
            btc_return_pct = $TradeReturnPct
            valid          = $true
        }
    }

    $btcEntry = Get-BtcDailyClose -DateUtc $EntryDateUtc -CachePath $CachePath
    $btcExit  = Get-BtcDailyClose -DateUtc $ExitDateUtc  -CachePath $CachePath

    if ($null -eq $btcEntry -or $null -eq $btcExit -or $btcEntry -le 0) {
        return [PSCustomObject]@{
            alpha_vs_btc   = $null
            btc_return_pct = $null
            valid          = $false
        }
    }

    $btcReturn = ($btcExit - $btcEntry) / $btcEntry * 100
    $alpha = $TradeReturnPct - $btcReturn

    return [PSCustomObject]@{
        alpha_vs_btc   = [math]::Round($alpha, 2)
        btc_return_pct = [math]::Round($btcReturn, 2)
        valid          = $true
    }
}


function Get-AlphaNegativeRate {
    <#
    .SYNOPSIS
    Computa porcentagem trades com alpha_vs_btc < 0 sobre N samples mais recentes.

    .DESCRIPTION
    Usado por audit script. Se rate >60% sobre N>=20 trades = alert
    "pipeline esta perdendo pra BTC consistently".

    Le list of alphas (caller responsabilidade) e retorna rate stats.

    .PARAMETER Alphas
    Array de valores alpha_vs_btc (excluir nulls antes de passar).

    .PARAMETER MinSampleSize
    Skip stats se sample menor (default 20).

    .OUTPUTS
    PSCustomObject @{ n, negative_count, negative_rate_pct, alert, threshold_pct }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Alphas,
        [int] $MinSampleSize = 20,
        [double] $AlertThresholdPct = 60.0
    )

    $n = $Alphas.Count
    if ($n -lt $MinSampleSize) {
        return [PSCustomObject]@{
            n                  = $n
            negative_count     = 0
            negative_rate_pct  = $null
            alert              = $false
            reason             = "insufficient_sample (n=$n < $MinSampleSize)"
            threshold_pct      = $AlertThresholdPct
        }
    }

    $neg = ($Alphas | Where-Object { $_ -lt 0 }).Count
    $rate = ($neg / $n) * 100
    $alert = $rate -ge $AlertThresholdPct

    return [PSCustomObject]@{
        n                  = $n
        negative_count     = $neg
        negative_rate_pct  = [math]::Round($rate, 1)
        alert              = $alert
        reason             = if ($alert) { "pipeline alt-trades losing to BTC ($neg/$n = $([math]::Round($rate,1))%)" } else { "ok" }
        threshold_pct      = $AlertThresholdPct
    }
}

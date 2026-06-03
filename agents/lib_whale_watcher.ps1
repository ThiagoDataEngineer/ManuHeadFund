# lib_whale_watcher.ps1 -- Monitor whale TXs via mempool.space (BTC).
#
# MVP 2026-05-21 sessao extra. Free API sem signup.
#
# Strategy:
#   1. Poll https://mempool.space/api/mempool/recent (lista TXs pendentes recentes)
#   2. Filter por valor total > threshold (default: 100 BTC, ~$7.7M @ $77k/BTC)
#   3. Dedupe via journal/whale_alerts_seen.jsonl (anti re-alert)
#   4. TG alert via Send-TelegramAlert
#
# Fail-open: erro de API nao quebra outros loops. Just-in-time read state.
# PS 5.1, UTF-8 BOM.

function Get-WhaleSeenPath {
    if (-not $global:JOURNAL_DIR) {
        $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
    }
    Join-Path $global:JOURNAL_DIR "whale_alerts_seen.jsonl"
}


function Test-WhaleTxSeen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TxId,
        [string] $SeenPath = (Get-WhaleSeenPath),
        [int] $WithinHours = 24
    )
    if (-not (Test-Path $SeenPath)) { return $false }
    $cutoff = (Get-Date).AddHours(-1 * [Math]::Abs($WithinHours))
    try {
        $lines = Get-Content $SeenPath -Encoding UTF8 -ErrorAction Stop
        foreach ($l in $lines) {
            $l = $l.Trim(); if (-not $l) { continue }
            try {
                $e = $l | ConvertFrom-Json -ErrorAction Stop
                if ($e.txid -eq $TxId -and $e.ts) {
                    [datetime]$ts = [datetime]::MinValue
                    if ([DateTime]::TryParse([string]$e.ts, [ref]$ts) -and $ts -ge $cutoff) {
                        return $true
                    }
                }
            } catch { continue }
        }
    } catch {}
    return $false
}


function Add-WhaleTxSeen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TxId,
        [Parameter(Mandatory)][double] $ValueBtc,
        [string] $SeenPath = (Get-WhaleSeenPath)
    )
    $entry = @{
        txid = $TxId
        value_btc = [Math]::Round($ValueBtc, 4)
        ts = (Get-Date).ToString('o')
    }
    try {
        $entry | ConvertTo-Json -Compress | Add-Content -Path $SeenPath -Encoding utf8 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}


function Get-MempoolRecentTxs {
    <#
    .SYNOPSIS
    Fetch mempool.space recent pending TXs. Retorna array de objs com txid+value.
    .PARAMETER MinBtc
    Threshold em BTC pra retornar. Default 100 BTC (~$7.7M @ $77k).
    #>
    [CmdletBinding()]
    param(
        [double] $MinBtc = 100.0,
        [int] $TimeoutSec = 15
    )
    try {
        # /mempool/recent retorna ate 500 ultimos TXs recentes (txid, fee, vsize, value)
        $resp = Invoke-RestMethod -Uri "https://mempool.space/api/mempool/recent" `
            -Method GET -TimeoutSec $TimeoutSec -ErrorAction Stop
        if (-not $resp) { return @() }
        # value vem em satoshis. Converter pra BTC.
        $whales = @()
        foreach ($tx in $resp) {
            if (-not $tx.value) { continue }
            $btc = [double]$tx.value / 100000000.0
            if ($btc -ge $MinBtc) {
                $whales += [PSCustomObject]@{
                    txid = [string]$tx.txid
                    value_btc = [Math]::Round($btc, 4)
                    fee_sat = $tx.fee
                    vsize = $tx.vsize
                }
            }
        }
        return @($whales | Sort-Object value_btc -Descending)
    } catch {
        Write-Verbose "Get-MempoolRecentTxs erro: $($_.Exception.Message)"
        return @()
    }
}


function Get-WhaleConviction {
    <#
    .SYNOPSIS
    Mapeia tamanho da whale TX (BTC) para conviccao 0-100 (log-scaled).
    100 BTC -> 70 (baseline whale), 1000 BTC -> 100 (cap). Whales menores caem
    abaixo do limiar (70) e nao disparam trigger -- gate de custo natural.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][double] $ValueBtc)
    if ($ValueBtc -le 0) { return 0 }
    $c = 70 + ([Math]::Log10($ValueBtc / 100.0) * 30)
    if ($c -lt 0)   { $c = 0 }
    if ($c -gt 100) { $c = 100 }
    return [int][Math]::Round($c)
}


function Invoke-WhaleWatcherCycle {
    <#
    .SYNOPSIS
    Roda 1 cycle de whale watching: fetch + filter + dedupe + alert.
    .OUTPUTS
    PSCustomObject { fetched, new_alerts, total_btc_alerted }
    #>
    [CmdletBinding()]
    param(
        [double] $MinBtc = 100.0,
        [int] $DedupeHours = 24,
        [switch] $DryRun
    )
    $whales = Get-MempoolRecentTxs -MinBtc $MinBtc
    $newAlerts = @()
    foreach ($w in $whales) {
        if (Test-WhaleTxSeen -TxId $w.txid -WithinHours $DedupeHours) { continue }
        $newAlerts += $w
        if (-not $DryRun) {
            [void](Add-WhaleTxSeen -TxId $w.txid -ValueBtc $w.value_btc)
            if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                $usdEst = $w.value_btc * 77000  # rough; orchestrator pode ter cotacao real
                $msg = "<b>WHALE</b> $($w.value_btc) BTC (~`$$([Math]::Round($usdEst/1e6,1))M)`ntxid: <code>$($w.txid.Substring(0,16))...</code>`nFee: $($w.fee_sat) sat | VSize: $($w.vsize)"
                try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
            }
            # Fast-path: enfileira trigger event-driven (conviction-gated). Whale BTC
            # mempool -> reanalise imediata de BTCUSDT (regime anchor). ClusterKey=txid
            # dedupa o mesmo evento. Producer desacoplado do consumer via JSONL.
            if (Get-Command Add-SignalTrigger -ErrorAction SilentlyContinue) {
                $conv = Get-WhaleConviction -ValueBtc $w.value_btc
                try { Add-SignalTrigger -Market "BTCUSDT" -Signal "whale" -Conviction $conv -Direction "auto" -ClusterKey $w.txid -Notes "$($w.value_btc) BTC mempool" | Out-Null } catch {}
            }
        }
    }
    return [PSCustomObject]@{
        fetched = @($whales).Count
        new_alerts = @($newAlerts).Count
        total_btc_alerted = ([double](@($newAlerts | Measure-Object -Property value_btc -Sum).Sum))
    }
}

# lib_heartbeat.ps1 -- nucleo PURO do heartbeat (sem I/O).
# Heartbeat le trade_outcomes do Supabase (cloud ground-truth). Estas funcoes
# decidem staleness; o script heartbeat_alert.ps1 faz o I/O (query + Telegram).
# PS 5.1 safe. ASCII-only.

function Select-LatestOutcomeClosedAt {
    # Dado um array de outcomes, retorna o maior timestamp de fechamento como
    # [datetime] (UTC), ou $null. Aceita campo 'closed_at' (Supabase) ou 'ts'
    # (JSONL local). Ignora valores nao parseaveis.
    [CmdletBinding()]
    param([object[]] $Outcomes)

    if (-not $Outcomes -or @($Outcomes).Count -eq 0) { return $null }

    $latest = $null
    foreach ($o in $Outcomes) {
        if ($null -eq $o) { continue }
        $raw = $null
        if ($o.PSObject.Properties['closed_at'] -and $o.closed_at) { $raw = [string]$o.closed_at }
        elseif ($o.PSObject.Properties['ts'] -and $o.ts)           { $raw = [string]$o.ts }
        if (-not $raw) { continue }

        $dt = $null
        try {
            $dt = [datetime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture,
                  [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
        } catch { continue }

        if ($null -eq $latest -or $dt -gt $latest) { $latest = $dt }
    }
    return $latest
}

function Get-HeartbeatVerdict {
    # Decide se deve alertar. Puro.
    [CmdletBinding()]
    param(
        $LatestClosedAtUtc,
        [Parameter(Mandatory)] [datetime] $NowUtc,
        [int] $ThresholdHours = 6
    )
    if ($null -eq $LatestClosedAtUtc) {
        return [PSCustomObject]@{ alert = $true; reason = "no_trades"; hours_since = $null }
    }
    $latest = [datetime]$LatestClosedAtUtc
    $hours = ($NowUtc.ToUniversalTime() - $latest.ToUniversalTime()).TotalHours
    if ($hours -gt $ThresholdHours) {
        return [PSCustomObject]@{ alert = $true; reason = "stale"; hours_since = $hours }
    }
    return [PSCustomObject]@{ alert = $false; reason = "alive"; hours_since = $hours }
}

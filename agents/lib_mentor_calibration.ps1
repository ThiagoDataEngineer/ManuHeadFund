# lib_mentor_calibration.ps1 -- C.5 wire 2026-05-26
# Calibration dashboard: agrega reflections + decisions pra medir Mentor accuracy
# por (veredicto_5tier, provider, regime). Detecta overconfidence drift sem fe.
#
# Win = pnl_pct > 0. Trader real mediria alpha, mas sem alpha_vs_btc populado
# ainda (B.4 nascente), win_rate por pnl serve como baseline.

function Get-MentorCalibration {
    [CmdletBinding()]
    param([string] $ReflectionsPath = "")

    if (-not $ReflectionsPath) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $ReflectionsPath = Join-Path $journalDir "decision_reflections.jsonl"
    }

    $empty = [PSCustomObject]@{
        total_resolved = 0
        by_veredicto = @()
        by_provider = @()
        by_regime = @()
    }
    if (-not (Test-Path $ReflectionsPath)) { return $empty }

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
    } catch { return $empty }

    # Aggregate
    $byVeredicto = @{}
    $byProvider = @{}
    $byRegime = @{}
    $total = 0

    foreach ($tid in $byTradeId.Keys) {
        $pair = $byTradeId[$tid]
        if (-not $pair.pending -or -not $pair.resolved) { continue }
        $pnl = [double]$pair.resolved.pnl_pct
        $win = $pnl -gt 0
        $tier5 = if ($pair.pending.PSObject.Properties['veredicto_5tier']) { [string]$pair.pending.veredicto_5tier } else { "UNKNOWN" }
        $prov = if ($pair.pending.PSObject.Properties['provider_used']) { [string]$pair.pending.provider_used } else { "unknown" }
        $reg = if ($pair.pending.PSObject.Properties['regime']) { [string]$pair.pending.regime } else { "unknown" }

        $total++
        foreach ($pair2 in @(@($byVeredicto, $tier5), @($byProvider, $prov), @($byRegime, $reg))) {
            $dict = $pair2[0]; $key = $pair2[1]
            if (-not $dict.ContainsKey($key)) {
                $dict[$key] = @{ n = 0; wins = 0; pnl_sum = 0.0 }
            }
            $dict[$key].n++
            if ($win) { $dict[$key].wins++ }
            $dict[$key].pnl_sum += $pnl
        }
    }

    function _Render([hashtable]$Dict, [string]$KeyName) {
        $rows = @()
        foreach ($k in $Dict.Keys) {
            $v = $Dict[$k]
            $row = [PSCustomObject]@{
                $KeyName        = $k
                n               = $v.n
                wins            = $v.wins
                win_rate_pct    = [Math]::Round(($v.wins / $v.n) * 100, 2)
                avg_pnl_pct     = [Math]::Round($v.pnl_sum / $v.n, 2)
            }
            $rows += $row
        }
        return ,@($rows | Sort-Object -Property n -Descending)
    }

    return [PSCustomObject]@{
        total_resolved = $total
        by_veredicto = (_Render -Dict $byVeredicto -KeyName "veredicto_5tier")
        by_provider  = (_Render -Dict $byProvider  -KeyName "provider")
        by_regime    = (_Render -Dict $byRegime    -KeyName "regime")
    }
}

function Format-CalibrationReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $Calibration)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("=== MENTOR CALIBRATION REPORT ===")
    [void]$sb.AppendLine("total_resolved: $($Calibration.total_resolved)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("BY VEREDICTO_5TIER:")
    foreach ($r in $Calibration.by_veredicto) {
        [void]$sb.AppendLine("  $($r.veredicto_5tier): n=$($r.n) wins=$($r.wins) win_rate=$($r.win_rate_pct)% avg_pnl=$($r.avg_pnl_pct)%")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("BY PROVIDER:")
    foreach ($r in $Calibration.by_provider) {
        [void]$sb.AppendLine("  $($r.provider): n=$($r.n) win_rate=$($r.win_rate_pct)% avg_pnl=$($r.avg_pnl_pct)%")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("BY REGIME:")
    foreach ($r in $Calibration.by_regime) {
        [void]$sb.AppendLine("  $($r.regime): n=$($r.n) win_rate=$($r.win_rate_pct)% avg_pnl=$($r.avg_pnl_pct)%")
    }
    return $sb.ToString()
}

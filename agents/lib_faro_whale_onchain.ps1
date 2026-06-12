# lib_faro_whale_onchain.ps1 — Exchange flows + large holders
function Get-WhaleOnChain {
    param([string] $Market, [decimal] $TopHoldersSupplyPct = 0, [decimal] $ExchangeOutflow = 0, [decimal] $ExchangeInflow = 0, [int] $CommunitySize = 0)
    $score = 0
    if ($TopHoldersSupplyPct -gt 0) {
        if ($TopHoldersSupplyPct -lt 40) { $score += 10 }
        elseif ($TopHoldersSupplyPct -lt 60) { $score += 5 }
    }
    if ($ExchangeOutflow -gt 0 -or $ExchangeInflow -gt 0) {
        $netFlow = $ExchangeOutflow - $ExchangeInflow
        $totalFlow = [Math]::Max($ExchangeOutflow, $ExchangeInflow)
        if ($totalFlow -gt 0) {
            $netPct = $netFlow / $totalFlow
            if ($netPct -gt 0.3) { $score += 10 }
            elseif ($netPct -gt 0.15) { $score += 6 }
            elseif ($netPct -gt 0.05) { $score += 3 }
        }
    }
    if ($score -eq 0 -and $CommunitySize -gt 0) {
        if ($CommunitySize -ge 50000) { $score = 10 }
        elseif ($CommunitySize -ge 20000) { $score = 7 }
        elseif ($CommunitySize -ge 10000) { $score = 4 }
    }
    return [Math]::Min($score, 20)
}

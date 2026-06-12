# lib_kelly_wire.ps1 -- Integra Kelly adaptive + feedback loop pra sizing real.
#
# Resolve-AdaptiveSizing(Market, Mode, Capital):
#   1. Le trade_outcomes.jsonl filtrado por market
#   2. Se >= MinTrades historicos: chama Get-AdaptiveSizeFromTrades (Kelly real)
#   3. Senao: fallback fixed 1% (compat com sistema antigo)
#
# Wire usage:
#   gem_executor:  $sz = Resolve-AdaptiveSizing -Market $mkt -Mode "GEM" -Capital $cap
#                  $usd_size = $sz.size_usd
#   orchestrator:  $sz = Resolve-AdaptiveSizing -Market $mkt -Mode "TIER_A" -Capital $cap
#
# Mantem assinatura compat com codigo legado via fallback. Opt-in completo:
#   uma flag $global:USE_KELLY_SIZING = $true ativaria; default OFF pra rollout gradual.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Resolve-AdaptiveSizing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [double] $Capital,
        [string] $OutcomePath = (Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl"),
        [int] $MinTrades = 10
    )
    if (-not (Test-Path $OutcomePath)) {
        $sizeUsd = [Math]::Round($Capital * 0.01, 2)
        return [PSCustomObject]@{
            fallback = $true; reason = "no_outcomes_file"
            size_usd = $sizeUsd; f_used = 0.01; mode = $Mode; capital = $Capital
        }
    }

    # Le outcomes filtrado por market + mode (mais especifico ganha)
    $rows = @()
    foreach ($line in Get-Content $OutcomePath -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if (-not $line) { continue }
        try {
            $o = $line | ConvertFrom-Json
            if ($o.market -ne $Market) { continue }
            if ($Mode -and $o.mode -ne $Mode) { continue }
            $rows += $o
        } catch {}
    }

    if ($rows.Count -lt $MinTrades) {
        $sizeUsd = [Math]::Round($Capital * 0.01, 2)
        return [PSCustomObject]@{
            fallback = $true; reason = "insufficient_trades_$($rows.Count)_lt_$MinTrades"
            size_usd = $sizeUsd; f_used = 0.01; mode = $Mode; capital = $Capital
            n_trades = $rows.Count
        }
    }

    # Extrai R-multiples e delega
    $trades = @($rows | ForEach-Object { [double]$_.r })
    return Get-AdaptiveSizeFromTrades -Trades $trades -Mode $Mode -Capital $Capital -MinTrades $MinTrades
}

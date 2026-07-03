# lib_balance_fetcher.ps1 — Snapshot de saldo real SPOT + FUTURES por ciclo
# 2026-07-03 v2: delega a CoinEx-GetSpotCapitalUSDT / CoinEx-GetFuturesCapitalUSDT
# (lib_coinex.ps1 — chamadas ASSINADAS, com fallback fresco). A v1 usava
# Invoke-RestMethod sem HMAC e retornava sempre 0.
# Salva em journal/balance_snapshot.json — lido por show_balance.ps1 e sizing.

function Get-RealBalance {
    [CmdletBinding()]
    param(
        [hashtable] $CoinExConfig  # aceito por compat; lib_coinex usa globals
    )

    $spotUsdt = 0.0
    $futuresUsdt = 0.0

    if (Get-Command CoinEx-GetSpotCapitalUSDT -ErrorAction SilentlyContinue) {
        try { $spotUsdt = [double](CoinEx-GetSpotCapitalUSDT) } catch { $spotUsdt = 0.0 }
    }
    if (Get-Command CoinEx-GetFuturesCapitalUSDT -ErrorAction SilentlyContinue) {
        try { $futuresUsdt = [double](CoinEx-GetFuturesCapitalUSDT) } catch { $futuresUsdt = 0.0 }
    }

    $primary = "NONE"
    if ($spotUsdt -gt $futuresUsdt -and $spotUsdt -gt 0) { $primary = "SPOT" }
    elseif ($futuresUsdt -gt 0) { $primary = "FUTURES" }

    return [PSCustomObject]@{
        timestamp = [datetime]::UtcNow.ToString("O")
        spot = [PSCustomObject]@{ usdt = [math]::Round($spotUsdt, 2) }
        futures = [PSCustomObject]@{ usdt = [math]::Round($futuresUsdt, 2) }
        primary_carteira = $primary
    }
}

function Save-BalanceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Balance,
        [string] $Path = ""
    )
    if (-not $Path) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $Path = Join-Path $journalDir "balance_snapshot.json"
    }
    try {
        ($Balance | ConvertTo-Json -Depth 5) | Out-File -FilePath $Path -Encoding UTF8 -Force
        return $true
    } catch {
        return $false
    }
}

function Read-LatestBalance {
    [CmdletBinding()]
    param([string] $Path = "journal/balance_snapshot.json")
    if (Test-Path $Path) {
        try { return Get-Content $Path -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

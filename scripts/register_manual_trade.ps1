# register_manual_trade.ps1 -- Registra trade fechado manualmente no trade_outcomes.jsonl
# Isso alimenta o DSR, Kelly graduation e alpha_vs_btc
#
# Uso:
#   pwsh -File scripts\register_manual_trade.ps1 `
#       -Market BTCUSDT -Side LONG `
#       -EntryPrice 103000 -ExitPrice 107000 `
#       -EntryDate "2026-05-20" -ExitDate "2026-05-22" `
#       -SizeUsd 100 -CloseReason "manual" -Notes "fechei na mao"
#
# Campos obrigatorios: Market, Side, EntryPrice, ExitPrice, EntryDate, ExitDate, SizeUsd

param(
    [Parameter(Mandatory=$true)]  [string]$Market,
    [Parameter(Mandatory=$true)]  [ValidateSet("LONG","SHORT")] [string]$Side,
    [Parameter(Mandatory=$true)]  [double]$EntryPrice,
    [Parameter(Mandatory=$true)]  [double]$ExitPrice,
    [Parameter(Mandatory=$true)]  [string]$EntryDate,
    [Parameter(Mandatory=$true)]  [string]$ExitDate,
    [Parameter(Mandatory=$true)]  [double]$SizeUsd,
    [string]$CloseReason = "manual",
    [string]$Notes       = "",
    [double]$BtcEntryPrice = 0,   # preco BTC na entrada (para calcular alpha)
    [double]$BtcExitPrice  = 0    # preco BTC na saida (para calcular alpha)
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$journalDir  = Join-Path $projectRoot "journal"
$outcomesFile = Join-Path $journalDir "trade_outcomes.jsonl"
$dsrFile      = Join-Path $journalDir "dsr_global.json"

# Calcula PnL
$pnlPct = if ($Side -eq "LONG") {
    [math]::Round(($ExitPrice - $EntryPrice) / $EntryPrice * 100, 4)
} else {
    [math]::Round(($EntryPrice - $ExitPrice) / $EntryPrice * 100, 4)
}
$pnlUsd = [math]::Round($SizeUsd * $pnlPct / 100, 2)
$win    = $pnlPct -gt 0

# Calcula alpha vs BTC (se precos BTC fornecidos)
$alphaPct = $null
if ($BtcEntryPrice -gt 0 -and $BtcExitPrice -gt 0) {
    $btcReturn = ($BtcExitPrice - $BtcEntryPrice) / $BtcEntryPrice * 100
    $alphaPct  = [math]::Round($pnlPct - $btcReturn, 4)
}

# Monta o registro
$tradeId = "$Market-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$record = [PSCustomObject]@{
    trade_id      = $tradeId
    market        = $Market
    side          = $Side
    entry_price   = $EntryPrice
    exit_price    = $ExitPrice
    entry_date    = $EntryDate
    exit_date     = $ExitDate
    size_usd      = $SizeUsd
    pnl_pct       = $pnlPct
    pnl_usd       = $pnlUsd
    win           = $win
    alpha_vs_btc  = $alphaPct
    close_reason  = $CloseReason
    notes         = $Notes
    source        = "manual_register"
    registered_at = (Get-Date).ToString("o")
}

# Salva em trade_outcomes.jsonl
$line = $record | ConvertTo-Json -Compress
Add-Content -Path $outcomesFile -Value $line -Encoding UTF8

Write-Host ""
Write-Host "=== TRADE REGISTRADO ===" -ForegroundColor Green
Write-Host "  Market:  $Market $Side" -ForegroundColor White
Write-Host "  Entry:   `$$EntryPrice  ->  Exit: `$$ExitPrice" -ForegroundColor White
$pnlColor = if ($win) { "Green" } else { "Red" }
Write-Host "  PnL:     $pnlPct% (`$$pnlUsd)" -ForegroundColor $pnlColor
if ($null -ne $alphaPct) {
    $alphaColor = if ($alphaPct -gt 0) { "Green" } else { "Red" }
    Write-Host "  Alpha:   $alphaPct% vs BTC" -ForegroundColor $alphaColor
}
Write-Host "  ID:      $tradeId" -ForegroundColor DarkGray
Write-Host ""

# Atualiza dsr_global.json
if (Test-Path $dsrFile) {
    try {
        $dsr = Get-Content $dsrFile -Raw -Encoding UTF8 | ConvertFrom-Json

        # Garante que per_market existe
        if (-not $dsr.PSObject.Properties['per_market']) {
            $dsr | Add-Member -MemberType NoteProperty -Name per_market -Value ([PSCustomObject]@{})
        }

        # Pega ou cria entrada do market
        $existing = if ($dsr.per_market.PSObject.Properties[$Market]) {
            $dsr.per_market.$Market
        } else {
            [PSCustomObject]@{ n_trades=0; dsr=0.5; win_rate=0.0; sharpe_30d=0.0; bootstrap=$true }
        }

        $nOld  = [int]$existing.n_trades
        $nNew  = $nOld + 1
        $wins  = [math]::Round([double]$existing.win_rate * $nOld) + ([int]$win)
        $newWr = [math]::Round($wins / $nNew, 4)
        # DSR simples: win_rate com floor 0.3 e ceil 0.9
        $newDsr = [math]::Max(0.3, [math]::Min(0.9, $newWr))

        $dsr.per_market.$Market = [PSCustomObject]@{
            n_trades     = $nNew
            dsr          = $newDsr
            win_rate     = $newWr
            sharpe_30d   = 0.0
            bootstrap    = $false
            last_updated = (Get-Date).ToString("o")
        }

        $dsr | Add-Member -MemberType NoteProperty -Name as_of -Value (Get-Date).ToString("o") -Force
        $dsr | ConvertTo-Json -Depth 5 | Set-Content $dsrFile -Encoding UTF8

        Write-Host "  DSR atualizado: $Market n=$nNew win_rate=$newWr dsr=$newDsr" -ForegroundColor Cyan
    } catch {
        Write-Host "  WARN: nao foi possivel atualizar dsr_global.json: $_" -ForegroundColor Yellow
    }
}

# Conta total de outcomes para Kelly
$totalOutcomes = @(Get-Content $outcomesFile -Encoding UTF8 -ErrorAction SilentlyContinue).Count
Write-Host "  Total outcomes: $totalOutcomes/10 para Kelly graduation" -ForegroundColor DarkCyan

if ($totalOutcomes -ge 10) {
    $kellyFlag = Join-Path $journalDir "USE_KELLY_SIZING.flag"
    if (-not (Test-Path $kellyFlag)) {
        "Kelly ativado em $(Get-Date)" | Set-Content $kellyFlag -Encoding UTF8
        Write-Host "  KELLY ATIVADO! Flag criada." -ForegroundColor Green
    }
}

# faro_v3_entry.ps1 — Auto-entry on ENTRA/URGENTE signals
# Runs after faro_v3_engine to place orders on confirmed candidates

param([bool] $DryRun = $false, [double] $CapitalPercent = 0.01, [int] $MaxPositions = 5)

$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

$libs = @(
    "constants_loader.ps1",
    "config.ps1",
    "lib_coinex.ps1",
    "lib_order_idempotency.ps1"
)
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}

$timestamp = Get-Date -Format "o"
$timestamp_dt = Get-Date
Write-Host "🟢 FARO V3 Entry started — auto-entry mode" -ForegroundColor Cyan

# Get current capital
try {
    $totalCap = CoinEx-GetTotalCapitalUSDT
    if ($totalCap -le 0) {
        Write-Warning "WARN: Capital is 0 or negative; skipping entries"
        exit 0
    }
} catch {
    Write-Warning "WARN: Failed to get capital: $_"
    exit 1
}

$positionSize = $totalCap * $CapitalPercent
Write-Host "📊 Capital: `$$totalCap | Position size: `$$positionSize" -ForegroundColor Yellow

# Check active position count
# 2026-07-15 cloud fix: journal/faro_v3_positions.jsonl e local e NAO persiste
# entre runs do GitHub Actions (runner efemero) -- o guard MaxPositions nunca
# limitava na nuvem. Fonte de verdade: posicoes reais abertas na exchange.
$activeCount = 0
$exchangeCountOk = $false
if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
    try {
        $exchangePos = @(CoinEx-GetPendingPositions -ErrorAction Stop)
        $activeCount = @($exchangePos).Count
        $exchangeCountOk = $true
        Write-Host "Posicoes abertas na exchange: $activeCount (fonte: API)" -ForegroundColor Yellow
    } catch {
        Write-Warning "WARN: contagem via exchange falhou: $_"
    }
}
if (-not $exchangeCountOk) {
    # Fallback legado (ambiente local com daemon)
    $posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
    if (Test-Path $posFile) {
        Get-Content $posFile | ForEach-Object {
            try {
                $obj = $_ | ConvertFrom-Json
                if ($obj.status -eq "active") { $activeCount++ }
            } catch {}
        }
    }
}

if ($activeCount -ge $MaxPositions) {
    Write-Host "WARN: Max positions ($MaxPositions) reached ($activeCount abertas); skipping new entries" -ForegroundColor Yellow
    exit 0
}

# Garantir que $posFile esteja definido para uso posterior (escrita em Add-Content)
if (-not (Test-Path Variable:posFile)) {
    $posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
}

# Read recent candidates (last 10 minutes)
$candFile = Join-Path $journalDir "faro_v3_candidates.jsonl"
if (-not (Test-Path $candFile)) {
    Write-Host "ℹ️  No candidates found"
    exit 0
}

$entries = @()
Get-Content $candFile | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        $candTs = [datetime]$obj.ts
        $age = ($timestamp_dt - $candTs).TotalMinutes
        if ($age -le 30 -and $obj.decision -in "ENTRA","URGENTE") {
            $entries += $obj
        }
    } catch {}
} | Sort-Object -Property score -Descending

if ($entries.Count -eq 0) {
    Write-Host "ℹ️  No entry signals in last 30 minutes"
    exit 0
}

Write-Host "🎯 Found $($entries.Count) entry signals" -ForegroundColor Green

# 2026-07-16 FIX: $activePositions nunca era definida neste arquivo -- guard
# de MaxPositions comparava contra $null.Count (=0 em PowerShell), ignorando
# silenciosamente o $activeCount real ja calculado acima (via API da exchange).
# Corrigido pra usar $activeCount (a fonte de verdade real) + $entered.Count
# (posicoes abertas NESTE ciclo, ainda nao refletidas na exchange).
$entered = @()
foreach ($entry in $entries) {
    if ($activeCount + $entered.Count -ge $MaxPositions) { break }

    $market = $entry.market
    # 2026-07-16: direction-aware. Antes SEMPRE side="buy" (LONG) -- um sinal
    # SHORT do engine (adicionado no mesmo commit) seria executado como COMPRA,
    # o oposto do que o sinal detectou. CoinEx-PlaceOrder ja manda pro book de
    # FUTURES (market_type="FUTURES" fixo na lib) mesmo pra LONG -- side "sell"
    # sem posicao previa abre short nativo, sem lib adicional necessaria.
    $direction = if ($entry.PSObject.Properties['direction'] -and $entry.direction -eq "SHORT") { "SHORT" } else { "LONG" }
    $orderSide = if ($direction -eq "SHORT") { "sell" } else { "buy" }
    try {
        # Fetch current price + volatility
        $ticker = CoinEx-GetTicker -market $market
        $currentPrice = [double]$ticker.last
        if (-not $currentPrice) { continue }

        # Calculate volatility (simple 24h range)
        $volatility = [double](($ticker.high24h - $ticker.low24h) / $ticker.last)
        $vol_pct = $volatility * 100

        # Dynamic position sizing: lower vol = larger position
        $sizeMultiplier = if ($vol_pct -gt 20) { 0.8 } elseif ($vol_pct -gt 15) { 1.0 } else { 1.2 }
        $quantity = ($positionSize * $sizeMultiplier) / $currentPrice

        # Calculate stops + targets -- SHORT espelha LONG (stop ACIMA, alvo
        # ABAIXO do preco de entrada; mesmas distancias percentuais).
        if ($direction -eq "SHORT") {
            $stop = $currentPrice * 1.08     # +8% stop (preco subiu contra a posicao)
            $target1 = $currentPrice * 0.50  # -50%
            $target2 = $currentPrice * 0.10  # -90% (equivalente simetrico ao 2.50x LONG em retorno, cap logico em 0)
        } else {
            $stop = $currentPrice * 0.92     # -8% stop
            $target1 = $currentPrice * 1.50  # +50%
            $target2 = $currentPrice * 2.50  # +150%
        }

        # Check idempotency (no duplicate entry for this market today)
        if (Test-Path $posFile) {
            $existing = Get-Content $posFile |
                Where-Object { $_ | ConvertFrom-Json | Where-Object { $_.market -eq $market -and $_.status -eq "active" } }
            if ($existing) {
                Write-Host "⏭️  $market already has active position; skipping" -ForegroundColor Gray
                continue
            }
        }

        # Place order
        Write-Host "📍 Entering $market $direction | price=$([Math]::Round($currentPrice,6)) | size=$([Math]::Round($quantity,4)) | stop=$([Math]::Round($stop,6)) | t1=$([Math]::Round($target1,6)) | t2=$([Math]::Round($target2,6))" -ForegroundColor Cyan

        if (-not $DryRun) {
            try {
                $result = CoinEx-PlaceOrder -market $market -side $orderSide -type "market" -amount $quantity -stopLoss $stop -takeProfit $target2
                if ($result) {
                    $position = [PSCustomObject]@{
                        ts = $timestamp
                        market = $market
                        direction = $direction
                        entry_price = $currentPrice
                        quantity = $quantity
                        stop = $stop
                        target1 = $target1
                        target1_closed = $false
                        target2 = $target2
                        volatility = $vol_pct
                        signal_score = $entry.score
                        signal_count = $entry.signal_count
                        reason = $entry.decision
                        status = "active"
                        order_id = $(if ($null -ne $result.order_id) { $result.order_id } else { "unknown" })
                    }
                    Add-Content -Path $posFile -Value ($position | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
                    $entered += $position
                    Write-Host "✅ Order placed: $market $direction" -ForegroundColor Green
                } else {
                    Write-Warning "WARN: PlaceOrder failed for $market"
                }
            } catch {
                Write-Warning "WARN: Exception in ${market}: $_"
            }
        } else {
            Write-Host "✅ [DRY RUN] Would enter $market $direction" -ForegroundColor Cyan
        }
    } catch {
        Write-Warning "WARN: Error processing ${market}: $_"
    }
}

Write-Host "🟢 FARO V3 Entry completed | $($entered.Count) new positions opened" -ForegroundColor Green

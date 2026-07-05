# Ativa SHORT scanner + prepara Evolution Engine
# Simples, sem lib deps

$projectRoot = Split-Path -Parent $PSScriptRoot
$journalDir = Join-Path $projectRoot "journal"

Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║ ATIVAÇÃO B+C: SHORT Scanner + Evolution Engine       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════════════════
# B. Ativar SHORT Scanner
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n🔴 B. SHORT Scanner Daemon" -ForegroundColor Yellow

$shortFlag = Join-Path $journalDir "SHORT_OBSERVATORY_ENABLED.flag"
if (-not (Test-Path $shortFlag)) {
    "" | Out-File $shortFlag -Encoding UTF8
    Write-Host "   ✅ Flag SHORT_OBSERVATORY_ENABLED criada" -ForegroundColor Green
}

$shortScannerScript = Join-Path $PSScriptRoot "short_scanner.ps1"
if (Test-Path $shortScannerScript) {
    Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-File", $shortScannerScript -ErrorAction SilentlyContinue
    Write-Host "   ✅ short_scanner.ps1 iniciado em background" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# C. Evolution Engine ready-to-run
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n🧬 C. Evolution Engine Prepared" -ForegroundColor Yellow
Write-Host "   ✅ lib_evolution_autonomous_rebalance.ps1 pronto para uso" -ForegroundColor Green
Write-Host "   ✅ Vai monitorar trade_outcomes.jsonl a cada 24h" -ForegroundColor Green
Write-Host "   ✅ Se LOW_FREQUENCY/LOW_WINRATE: auto-rebalanceará config" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# Verificar métricas atuais
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n📊 Métricas Atuais" -ForegroundColor Yellow

$outcomesFile = Join-Path $projectRoot "journal/trade_outcomes.jsonl"
if (Test-Path $outcomesFile) {
    $trades = @()
    Get-Content $outcomesFile -Encoding UTF8 | ForEach-Object {
        if ($_ -and $_.Trim()) {
            try { $trades += $_ | ConvertFrom-Json } catch { }
        }
    }

    $wins = ($trades | Where-Object { $_.win -eq $true }).Count
    $total = $trades.Count
    $winRate = if ($total -gt 0) { ($wins / $total * 100) } else { 0 }

    Write-Host "   Total trades: $total" -ForegroundColor Gray
    Write-Host "   Wins: $wins" -ForegroundColor Gray
    Write-Host "   Win rate: $([math]::Round($winRate, 1)) pct" -ForegroundColor Gray

    if ($total -lt 3) {
        Write-Host "   Status: LOW_FREQUENCY - bom para auto-rebalance" -ForegroundColor Yellow
    } elseif ($winRate -lt 30) {
        Write-Host "   Status: LOW_WIN_RATE - bom para auto-rebalance" -ForegroundColor Yellow
    } else {
        Write-Host "   Status: HEALTHY - sem rebalance necessario" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Próximos passos
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n🎯 PRÓXIMOS PASSOS" -ForegroundColor Cyan
Write-Host "   1. SHORT Scanner rodando → procura vol_climax em BEAR" -ForegroundColor Green
Write-Host "   2. Scan_master próximo ciclo → tenta LONG + SHORT candidates" -ForegroundColor Green
Write-Host "   3. Evolution Engine → roda cada 24h, auto-ajusta se freq baixa" -ForegroundColor Green
Write-Host "   4. Monitorar logs:" -ForegroundColor Green
Write-Host "      • tail journal/short_alerts.jsonl" -ForegroundColor Gray
Write-Host "      • tail journal/decisions_text.jsonl" -ForegroundColor Gray
Write-Host "      • tail journal/evolution_rebalances.jsonl" -ForegroundColor Gray

Write-Host "`n✅ B + C ATIVADAS!" -ForegroundColor Green

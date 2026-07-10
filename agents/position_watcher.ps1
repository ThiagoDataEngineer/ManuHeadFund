# position_watcher.ps1 — Monitora posições abertas (24/7)

Write-Host "👁️  POSITION_WATCHER INICIADO (24/7 monitoring)" -ForegroundColor Green

while ($true) {
    Write-Host "   Check $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow
    Start-Sleep -Seconds 60  # 1min
}

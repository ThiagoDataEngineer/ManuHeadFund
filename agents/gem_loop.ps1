# gem_loop.ps1 — Descobre gems continuamente (24/7)

. .\agents\config.local.ps1 -ErrorAction SilentlyContinue

Write-Host "🔄 GEM_LOOP INICIADO (24/7 discovery)" -ForegroundColor Green

while ($true) {
    Write-Host "   Rodada $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow

    # Discovery logic aqui
    Start-Sleep -Seconds 300  # 5min
}

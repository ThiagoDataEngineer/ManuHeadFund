# install_autostart.ps1 -- Auto-start watchdog_paper no logon via Startup folder
# (alternativa user-level que NAO precisa admin).
#
# Cria atalho em:
#   %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CoinexAIPaper.lnk
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts\install_autostart.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\install_autostart.ps1 -Uninstall

param([switch]$Uninstall)

$startupDir = [Environment]::GetFolderPath("Startup")
$linkPath   = Join-Path $startupDir "CoinexAIPaper.lnk"
$linkGem    = Join-Path $startupDir "CoinexAIGem.lnk"   # 2026-05-18 paralelo
$wd         = Split-Path -Parent $PSScriptRoot
$wdScript   = Join-Path $PSScriptRoot "watchdog_paper.ps1"
$gemScript  = Join-Path $PSScriptRoot "gem_loop.ps1"

if ($Uninstall) {
    foreach ($p in @($linkPath, $linkGem)) {
        if (Test-Path $p) {
            Remove-Item $p -Force
            Write-Host "Removido: $p" -ForegroundColor Green
        }
    }
    return
}

if (-not (Test-Path $wdScript)) {
    Write-Host "ERRO: $wdScript nao encontrado" -ForegroundColor Red
    exit 1
}

Write-Host "Instalando auto-start (Startup folder, user-level)..." -ForegroundColor Cyan

$psExe   = (Get-Command powershell.exe).Source
$psArgs  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$wdScript`""

# 1) watchdog_paper shortcut
$ws    = New-Object -ComObject WScript.Shell
$short = $ws.CreateShortcut($linkPath)
$short.TargetPath       = $psExe
$short.Arguments        = $psArgs
$short.WorkingDirectory = $wd
$short.WindowStyle      = 7   # Minimized
$short.Description      = "CoinEx AI Paper Trade Watchdog - auto-start on logon"
$short.Save()

# 2) gem_loop shortcut (paralelo)
if (Test-Path $gemScript) {
    $psArgsGem = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$gemScript`""
    $shortGem  = $ws.CreateShortcut($linkGem)
    $shortGem.TargetPath       = $psExe
    $shortGem.Arguments        = $psArgsGem
    $shortGem.WorkingDirectory = $wd
    $shortGem.WindowStyle      = 7
    $shortGem.Description      = "CoinEx AI GemAgent Loop - paralelo (1h cycle)"
    $shortGem.Save()
}

if (Test-Path $linkPath) {
    Write-Host ""
    Write-Host "OK -- atalhos criados:" -ForegroundColor Green
    Write-Host "  $linkPath"
    if (Test-Path $linkGem) {
        Write-Host "  $linkGem"
    }
    Write-Host ""
    Write-Host "Apos proximo logon (ou reboot), watchdog + gem_loop iniciam automaticamente em background." -ForegroundColor Cyan
    Write-Host "Remover: powershell -File scripts\install_autostart.ps1 -Uninstall"
} else {
    Write-Host "FALHA: atalho nao foi criado." -ForegroundColor Red
    exit 1
}

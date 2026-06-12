# publish_dashboard_pages.ps1 - Publica dashboard/ na branch gh-pages (2026-06-12)
# GitHub Pages serve a branch -> dashboard online em
#   https://thiagodataengineer.github.io/ManuHeadFund/
# Estrategia: branch orfa com 1 commit (force push) - zero ruido no main,
# historico de dados nao se acumula. Chamado pelo update_dashboard_json quando
# journal/DASHBOARD_PUBLISH.flag existe (opt-in).

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dashDir = Join-Path $projectRoot "dashboard"
$tmp = Join-Path $env:TEMP ("ghpages_" + [guid]::NewGuid().ToString("N").Substring(0, 8))

try {
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    Copy-Item "$dashDir\*.html", "$dashDir\*.css", "$dashDir\*.js", "$dashDir\*.json" $tmp -ErrorAction SilentlyContinue
    # agents.html como pagina inicial? Nao - index aponta pro manu
    Copy-Item (Join-Path $dashDir "manu.html") (Join-Path $tmp "index.html") -Force

    Push-Location $tmp
    git init -q -b gh-pages
    git add -A
    git -c user.name="dashboard-bot" -c user.email="bot@manuheadfund.local" commit -q -m "dashboard data $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $remote = git -C $projectRoot remote get-url origin
    git push -q --force $remote gh-pages:gh-pages
    Pop-Location
    Write-Host "[publish] dashboard publicado em gh-pages ($(Get-Date -Format 'HH:mm:ss'))"
} catch {
    Write-Warning "[publish] falhou: $_"
    if ((Get-Location).Path -eq $tmp) { Pop-Location }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

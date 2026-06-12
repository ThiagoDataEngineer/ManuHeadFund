# publish_dashboard_pages.ps1 - Publica dashboard/ na branch gh-pages (2026-06-12)
# GitHub Pages serve a branch -> https://thiagodataengineer.github.io/ManuHeadFund/
#
# SEGURANCA (repo publico): dados (capital/posicoes) NUNCA sobem em claro.
# dashboard_data.json e cifrado AES-256-GCM (lib_dashboard_crypto, 5 TDD) com
# senha de $env:DASHBOARD_PAGES_PASSWORD (config.local.ps1) -> manu_data.enc.js.
# Browser decifra via unlock.js (WebCrypto). Sem senha definida = ABORTA.
#
# Branch orfa com 1 commit (force push) - zero ruido no main.
# Chamado pelo update_dashboard_json quando journal/DASHBOARD_PUBLISH.flag existe.

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dashDir = Join-Path $projectRoot "dashboard"
$tmp = Join-Path $env:TEMP ("ghpages_" + [guid]::NewGuid().ToString("N").Substring(0, 8))

# Senha: env ou config.local.ps1
if (-not $env:DASHBOARD_PAGES_PASSWORD) {
    $cfgLocal = Join-Path $projectRoot "agents\config.local.ps1"
    if (Test-Path $cfgLocal) { . $cfgLocal }
}
if (-not $env:DASHBOARD_PAGES_PASSWORD) {
    Write-Warning "[publish] DASHBOARD_PAGES_PASSWORD ausente - NAO publica dados em claro. Abortando."
    return
}

. (Join-Path $projectRoot "agents\lib_dashboard_crypto.ps1")

try {
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    # Paginas + css + unlock (NUNCA manu_data.js / data.js / *.json em claro)
    Copy-Item (Join-Path $dashDir "manu.html") (Join-Path $tmp "manu.html")
    Copy-Item (Join-Path $dashDir "manu.html") (Join-Path $tmp "index.html")
    Copy-Item (Join-Path $dashDir "agents.html") (Join-Path $tmp "agents.html")
    Copy-Item (Join-Path $dashDir "unlock.js") (Join-Path $tmp "unlock.js")
    Copy-Item (Join-Path $dashDir "shared.css") (Join-Path $tmp "shared.css") -ErrorAction SilentlyContinue

    # Dados cifrados
    $json = Get-Content (Join-Path $dashDir "dashboard_data.json") -Raw
    $envlp = Protect-DashboardData -Json $json -Password $env:DASHBOARD_PAGES_PASSWORD
    $encJs = "const MANU_DATA_ENC = " + ($envlp | ConvertTo-Json -Compress) + ";"
    Set-Content (Join-Path $tmp "manu_data.enc.js") $encJs -Encoding utf8

    Push-Location $tmp
    git init -q -b gh-pages
    git add -A
    git -c user.name="dashboard-bot" -c user.email="bot@manuheadfund.local" commit -q -m "dashboard data $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $remote = git -C $projectRoot remote get-url origin
    git push -q --force $remote gh-pages:gh-pages
    Pop-Location
    Write-Host "[publish] dashboard CIFRADO publicado em gh-pages ($(Get-Date -Format 'HH:mm:ss'))"
} catch {
    Write-Warning "[publish] falhou: $_"
    if ((Get-Location).Path -eq $tmp) { Pop-Location }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

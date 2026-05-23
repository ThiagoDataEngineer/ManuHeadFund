# Teste rápido: valida que gem_loop.ps1 carrega sem erros
# Uso: pwsh -File scripts/test_gem_loop_load.ps1

$ErrorActionPreference = "Stop"

$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path -Parent $scriptRoot
$agentsDir    = Join-Path $projectRoot "agents"

Write-Host "Testing gem_loop.ps1 load sequence..."
Write-Host "ProjectRoot: $projectRoot"
Write-Host "AgentsDir: $agentsDir"

Set-Location $projectRoot

# Simular o bloco de carregamento do gem_loop.ps1 corrigido
try {
    Write-Host "[1/3] Loading config..."
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    Write-Host "  ✓ Config loaded"
} catch {
    Write-Host "  ✗ Config failed: $($_.Exception.Message)"
    exit 1
}

try {
    Write-Host "[2/3] Loading core libs..."
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_journal.ps1") -ErrorAction Stop
    Write-Host "  ✓ Core libs loaded"
} catch {
    Write-Host "  ✗ Core libs failed: $($_.Exception.Message)"
    exit 1
}

try {
    Write-Host "[3/3] Loading gem agents..."
    . (Join-Path $agentsDir "gem_agent.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "gem_executor.ps1") -ErrorAction Stop
    Write-Host "  ✓ Gem agents loaded"
} catch {
    Write-Host "  ✗ Gem agents failed: $($_.Exception.Message)"
    exit 1
}

# Validar função
if (-not (Get-Command "Invoke-GemScan" -ErrorAction SilentlyContinue)) {
    Write-Host "  ✗ Invoke-GemScan NOT available"
    exit 1
}

Write-Host "  ✓ Invoke-GemScan available"
Write-Host ""
Write-Host "SUCCESS: All loads succeeded. gem_loop.ps1 is ready to run."
Write-Host ""

# Show available gem functions
Write-Host "Available gem functions:"
Get-Command -Name "Invoke-Gem*" | ForEach-Object { Write-Host "  - $_" }

# generate_dashboard_html.ps1
# Gera HTML do dashboard a partir dos dados
# 2026-05-24

param(
    [Parameter(Mandatory)] $Data,
    [Parameter(Mandatory)] $Positions,
    [Parameter(Mandatory)] $Capital,
    [Parameter(Mandatory)] [string] $OutputPath
)

# Ler template HTML base
$templatePath = (Join-Path $PSScriptRoot ".." "dashboard" "template.html")

if (-not (Test-Path $templatePath)) {
    Write-Host "Template nao encontrado, usando dashboard atual como base" -ForegroundColor Yellow
    $templatePath = (Join-Path $PSScriptRoot ".." "dashboard" "index.html")
}

# Ler HTML base
$html = Get-Content $templatePath -Raw -Encoding UTF8

# Substituir placeholders com dados reais
$html = $html -replace '{{TIMESTAMP}}', $Data.timestamp
$html = $html -replace '{{POSITIONS_COUNT}}', $Positions.Count
$html = $html -replace '{{CAPITAL}}', [Math]::Round($Capital, 0)
$html = $html -replace '{{WIN_RATE}}', $Data.trading_metrics.win_rate
$html = $html -replace '{{APPROVAL_RATE}}', $Data.mentor_decisions.approval_rate
$html = $html -replace '{{TRADES_24H}}', $Data.trading_metrics.trades_24h

# Salvar HTML atualizado
$html | Out-File $OutputPath -Encoding UTF8

Write-Host "HTML gerado: $OutputPath" -ForegroundColor Green

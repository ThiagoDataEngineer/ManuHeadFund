# fix_claude_models.ps1 - Corrige nomes de modelos Claude em todo o projeto
$ErrorActionPreference = "Stop"

Write-Host "`n=== CORRIGINDO NOMES DE MODELOS CLAUDE ===" -ForegroundColor Cyan

$replacements = @{
    'claude-sonnet-4' = 'claude-sonnet-4'
    'claude-haiku-4-20251001' = 'claude-haiku-4'
    'claude-haiku-4' = 'claude-haiku-4'
}

$patterns = @(
    "agents\*.ps1",
    "scripts\*.ps1",
    "tests\*.ps1",
    "backtest\*.py"
)

$totalFiles = 0
$totalReplacements = 0

foreach ($pattern in $patterns) {
    $files = Get-ChildItem (Join-Path $PSScriptRoot (Join-Path ".." "$pattern")) -Recurse -ErrorAction SilentlyContinue
    
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        
        $modified = $false
        $fileReplacements = 0
        
        foreach ($old in $replacements.Keys) {
            $new = $replacements[$old]
            if ($content -match [regex]::Escape($old)) {
                $count = ([regex]::Matches($content, [regex]::Escape($old))).Count
                $content = $content -replace [regex]::Escape($old), $new
                $modified = $true
                $fileReplacements += $count
                $totalReplacements += $count
            }
        }
        
        if ($modified) {
            Set-Content $file.FullName -Value $content -NoNewline -Encoding UTF8
            Write-Host "  [x] $($file.Name): $fileReplacements substituicoes" -ForegroundColor Green
            $totalFiles++
        }
    }
}

Write-Host "`n=== RESUMO ===" -ForegroundColor Cyan
Write-Host "Arquivos modificados: $totalFiles" -ForegroundColor Green
Write-Host "Total de substituicoes: $totalReplacements" -ForegroundColor Green
Write-Host "`nModelos corrigidos:" -ForegroundColor Yellow
foreach ($old in $replacements.Keys) {
    Write-Host "  $old -> $($replacements[$old])" -ForegroundColor White
}
Write-Host ""

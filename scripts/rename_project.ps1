# rename_project.ps1 - Renomeia projeto de Coinex_AI_USER_API para ManuHeadFund
# IMPORTANTE: Executar com sistema parado e backup feito!

$ErrorActionPreference = "Stop"

$OLD_NAME = "Coinex_AI_USER_API"
$NEW_NAME = "ManuHeadFund"
$OLD_PATH = "C:\Users\thiag\$OLD_NAME"
$NEW_PATH = "C:\Users\thiag\$NEW_NAME"
$BACKUP_PATH = "C:\Users\thiag\${OLD_NAME}_BACKUP_$(Get-Date -Format 'yyyy_MM_dd_HHmmss')"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  RENOMEACAO DE PROJETO" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nDE:   $OLD_NAME" -ForegroundColor Red
Write-Host "PARA: $NEW_NAME" -ForegroundColor Green
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 0: PRE-CHECKS
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 0] Pre-checks..." -ForegroundColor Yellow

# Check 1: Verificar se pasta existe
if (-not (Test-Path $OLD_PATH)) {
    Write-Host "  ERRO: Pasta $OLD_PATH nao encontrada!" -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Pasta origem encontrada" -ForegroundColor Green

# Check 2: Verificar se nova pasta ja existe
if (Test-Path $NEW_PATH) {
    Write-Host "  ERRO: Pasta $NEW_PATH ja existe!" -ForegroundColor Red
    Write-Host "  Delete a pasta existente ou escolha outro nome" -ForegroundColor Yellow
    exit 1
}
Write-Host "  OK: Pasta destino disponivel" -ForegroundColor Green

# Check 3: Verificar espaco em disco
$drive = Get-PSDrive C
$freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
if ($freeSpaceGB -lt 2) {
    Write-Host "  AVISO: Pouco espaco em disco ($freeSpaceGB GB)" -ForegroundColor Yellow
    Write-Host "  Recomendado: pelo menos 2GB livres" -ForegroundColor Yellow
    $continue = Read-Host "  Continuar mesmo assim? (s/n)"
    if ($continue -ne "s") { exit 1 }
} else {
    Write-Host "  OK: Espaco em disco suficiente ($freeSpaceGB GB)" -ForegroundColor Green
}

# Check 4: Verificar processos rodando
$processes = Get-Process | Where-Object { $_.Path -like "*$OLD_NAME*" }
if ($processes) {
    Write-Host "  AVISO: Processos rodando no projeto:" -ForegroundColor Yellow
    $processes | ForEach-Object { Write-Host "    - $($_.Name) (PID: $($_.Id))" -ForegroundColor Yellow }
    $continue = Read-Host "  Continuar mesmo assim? (s/n)"
    if ($continue -ne "s") { exit 1 }
} else {
    Write-Host "  OK: Nenhum processo rodando" -ForegroundColor Green
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 1: BACKUP
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 1] Criando backup..." -ForegroundColor Yellow
Write-Host "  Origem: $OLD_PATH" -ForegroundColor Gray
Write-Host "  Destino: $BACKUP_PATH" -ForegroundColor Gray

try {
    Copy-Item $OLD_PATH $BACKUP_PATH -Recurse -Force
    Write-Host "  OK: Backup criado com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "  ERRO: Falha ao criar backup: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 2: ANALISE
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 2] Analisando arquivos..." -ForegroundColor Yellow

$extensions = @("*.ps1", "*.py", "*.md", "*.json", "*.ini", "*.env", "*.csv", "*.txt")
$allFiles = Get-ChildItem $OLD_PATH -Recurse -File -Include $extensions -ErrorAction SilentlyContinue

$filesToModify = @()
foreach ($file in $allFiles) {
    try {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match $OLD_NAME) {
            $filesToModify += $file
        }
    } catch {
        # Ignorar arquivos binarios ou inacessiveis
    }
}

Write-Host "  Total de arquivos: $($allFiles.Count)" -ForegroundColor White
Write-Host "  Arquivos a modificar: $($filesToModify.Count)" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 3: SUBSTITUICAO
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 3] Substituindo referencias..." -ForegroundColor Yellow

$modified = 0
$errors = 0

foreach ($file in $filesToModify) {
    try {
        $content = Get-Content $file.FullName -Raw
        
        # Substituir todas as variacoes
        $newContent = $content -replace [regex]::Escape($OLD_NAME), $NEW_NAME
        $newContent = $newContent -replace [regex]::Escape($OLD_NAME.ToLower()), $NEW_NAME.ToLower()
        $newContent = $newContent -replace [regex]::Escape($OLD_NAME.ToUpper()), $NEW_NAME.ToUpper()
        
        # Salvar apenas se houve mudanca
        if ($content -ne $newContent) {
            Set-Content $file.FullName -Value $newContent -NoNewline
            $modified++
            Write-Host "  ." -NoNewline -ForegroundColor Green
        }
    } catch {
        Write-Host "  X" -NoNewline -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "  Arquivos modificados: $modified" -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "  Erros: $errors" -ForegroundColor Red
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 4: RENOMEAR PASTA
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 4] Renomeando pasta..." -ForegroundColor Yellow
Write-Host "  DE:   $OLD_PATH" -ForegroundColor Red
Write-Host "  PARA: $NEW_PATH" -ForegroundColor Green

try {
    Rename-Item $OLD_PATH $NEW_NAME
    Write-Host "  OK: Pasta renomeada com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "  ERRO: Falha ao renomear pasta: $_" -ForegroundColor Red
    Write-Host "  Restaurando backup..." -ForegroundColor Yellow
    Remove-Item $OLD_PATH -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item $BACKUP_PATH $OLD_PATH -Recurse -Force
    Write-Host "  Backup restaurado" -ForegroundColor Green
    exit 1
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 5: VALIDACAO
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 5] Validando..." -ForegroundColor Yellow

# Verificar se ainda ha referencias ao nome antigo
$remainingRefs = Get-ChildItem $NEW_PATH -Recurse -File -Include $extensions -ErrorAction SilentlyContinue |
    Where-Object { 
        try {
            $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
            $content -match $OLD_NAME
        } catch {
            $false
        }
    }

if ($remainingRefs) {
    Write-Host "  AVISO: Ainda ha $($remainingRefs.Count) arquivos com referencias ao nome antigo:" -ForegroundColor Yellow
    $remainingRefs | Select-Object -First 5 | ForEach-Object {
        Write-Host "    - $($_.FullName -replace [regex]::Escape($NEW_PATH), '')" -ForegroundColor Yellow
    }
    if ($remainingRefs.Count -gt 5) {
        Write-Host "    ... e mais $($remainingRefs.Count - 5) arquivos" -ForegroundColor Yellow
    }
} else {
    Write-Host "  OK: Nenhuma referencia ao nome antigo encontrada!" -ForegroundColor Green
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# FASE 6: TESTES
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "[FASE 6] Executando testes..." -ForegroundColor Yellow

$testsPassed = 0
$testsFailed = 0

# Teste 1: Verificar se pasta existe
if (Test-Path $NEW_PATH) {
    Write-Host "  OK: Pasta $NEW_NAME existe" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAIL: Pasta $NEW_NAME nao encontrada" -ForegroundColor Red
    $testsFailed++
}

# Teste 2: Verificar se arquivos principais existem
$criticalFiles = @(
    "agents\config.ps1",
    "agents\chain_agent.ps1",
    "agents\lib_whale_detection.ps1",
    "tests\test_whale_manual.ps1"
)

foreach ($file in $criticalFiles) {
    $fullPath = Join-Path $NEW_PATH $file
    if (Test-Path $fullPath) {
        Write-Host "  OK: $file existe" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  FAIL: $file nao encontrado" -ForegroundColor Red
        $testsFailed++
    }
}

Write-Host ""
Write-Host "  Testes passados: $testsPassed" -ForegroundColor Green
Write-Host "  Testes falhados: $testsFailed" -ForegroundColor $(if($testsFailed -eq 0){"Green"}else{"Red"})
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RESUMO" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backup criado em:" -ForegroundColor Yellow
Write-Host "  $BACKUP_PATH" -ForegroundColor White
Write-Host ""
Write-Host "Projeto renomeado:" -ForegroundColor Yellow
Write-Host "  DE:   $OLD_NAME" -ForegroundColor Red
Write-Host "  PARA: $NEW_NAME" -ForegroundColor Green
Write-Host ""
Write-Host "Arquivos modificados: $modified" -ForegroundColor Cyan
Write-Host "Referencias restantes: $($remainingRefs.Count)" -ForegroundColor $(if($remainingRefs.Count -eq 0){"Green"}else{"Yellow"})
Write-Host "Testes passados: $testsPassed/$($testsPassed + $testsFailed)" -ForegroundColor $(if($testsFailed -eq 0){"Green"}else{"Yellow"})
Write-Host ""

if ($testsFailed -eq 0 -and $remainingRefs.Count -eq 0) {
    Write-Host "STATUS: SUCESSO!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host ""
    Write-Host "Proximos passos:" -ForegroundColor Yellow
    Write-Host "  1. Testar sistema: cd $NEW_PATH" -ForegroundColor White
    Write-Host "  2. Rodar testes: powershell -File tests\test_whale_manual.ps1" -ForegroundColor White
    Write-Host "  3. Se tudo OK, deletar backup: Remove-Item '$BACKUP_PATH' -Recurse" -ForegroundColor White
} else {
    Write-Host "STATUS: CONCLUIDO COM AVISOS" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Revisar:" -ForegroundColor Yellow
    Write-Host "  - Referencias restantes ao nome antigo" -ForegroundColor White
    Write-Host "  - Testes que falharam" -ForegroundColor White
    Write-Host ""
    Write-Host "Se necessario, restaurar backup:" -ForegroundColor Yellow
    Write-Host "  Remove-Item '$NEW_PATH' -Recurse -Force" -ForegroundColor White
    Write-Host "  Rename-Item '$BACKUP_PATH' '$OLD_NAME'" -ForegroundColor White
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

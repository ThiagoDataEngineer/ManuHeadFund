# lib_loader_auto.ps1 — Auto-carrega TODAS as libs do diretório
# 2026-07-02 FIX v3 (CAUSA RAIZ definitiva):
#   v1: loader carregava A SI MESMO -> recursao infinita (fixado: exclui a si mesmo)
#   v2: dot-source DENTRO de funcao definia as funcoes no escopo LOCAL da funcao
#       -> "256 carregadas" mas nenhuma visivel pro caller. Fix: auto-load INLINE
#       no top-level (dot-source herda o escopo de quem carregou este arquivo).
#   Guard $global:LIBS_AUTOLOADED: roda UMA vez por sessao.

if (-not $global:LIBS_AUTOLOADED) {
    $global:LIBS_AUTOLOADED = $true

    $__libs = @(Get-ChildItem -Path $PSScriptRoot -Filter "lib_*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "lib_loader_auto.ps1" } | Sort-Object Name)
    $__loaded = 0
    $__failed = @()

    foreach ($__lib in $__libs) {
        try {
            . $__lib.FullName
            $__loaded++
        } catch {
            $__failed += $__lib.Name
        }
    }

    Write-Host "[LIBS] Carregadas: $__loaded / $($__libs.Count) | Falhas: $($__failed.Count)" -ForegroundColor Cyan
    if ($__failed.Count -gt 0) {
        Write-Host "  Problemas em: $($__failed -join ', ')" -ForegroundColor Yellow
    }

    $global:LIBS_AUTOLOAD_RESULT = @{
        total  = $__libs.Count
        loaded = $__loaded
        failed = $__failed
    }
}

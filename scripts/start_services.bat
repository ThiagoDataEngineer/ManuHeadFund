@echo off
REM ========================================
REM GEM_LOOP + SCAN_MASTER - Startup Script
REM ========================================

setlocal enabledelayedexpansion

set WD=C:\Users\thiag\Coinex_AI_USER_API
set SCRIPTS=%WD%\scripts
set LOGS=%WD%\journal

echo ========================================
echo INICIANDO SERVICOS
echo ========================================
echo.

REM Kill old instances
echo [1/2] Limpando processos antigos...
for /f "tokens=2" %%a in ('tasklist ^| findstr "powershell"') do (
    tasklist /V /FI "PID eq %%a" | find "gem_loop" >nul && (
        echo  - Matando powershell %%a
        taskkill /PID %%a /F >nul 2>&1
    )
)
timeout /t 2 /nobreak >nul

REM Start gem_loop
echo.
echo [2/2] Iniciando gem_loop (intraday gems)...
cd /d %WD%
start "GEM_LOOP" powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%SCRIPTS%\gem_loop.ps1" ^
    -Force

timeout /t 3 /nobreak >nul

echo.
echo ========================================
echo STATUS FINAL
echo ========================================
tasklist | find "powershell" >nul && (
    echo [OK] Services started
    if exist "%LOGS%\gem_loop.log" (
        echo.
        echo Ultimos eventos (gem_loop.log):
        for /f "usebackq tokens=*" %%a in (`powershell -Command "(Get-Content '%LOGS%\gem_loop.log' | Select-Object -Last 5)"`) do echo   %%a
    )
) || (
    echo [ERRO] Nenhum processo iniciado
    exit /B 1
)

echo.
echo Aberto em: %WD%
cd /d %WD%

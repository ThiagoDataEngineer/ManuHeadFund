#!/usr/bin/env cmd
@REM ================================================================
@REM GEM_LOOP - Quick Command Reference
@REM ================================================================

@echo.
@echo ================================================================
@echo GEM_LOOP - COMANDOS RAPIDOS
@echo ================================================================
@echo.

@REM START SERVICE
@echo [1] INICIAR GEM_LOOP (PowerShell - Recomendado)
@echo cd C:\Users\thiag\Coinex_AI_USER_API
@echo .\scripts\start_services.ps1
@echo.

@REM ALTERNATIVE START
@echo [2] INICIAR GEM_LOOP (CMD - Alternativo)
@echo cd C:\Users\thiag\Coinex_AI_USER_API
@echo scripts\start_services.bat
@echo.

@REM DIRECT START
@echo [3] INICIAR GEM_LOOP (Manual)
@echo powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\thiag\Coinex_AI_USER_API\scripts\gem_loop.ps1" -Force
@echo.

@REM TEST SOURCING
@echo [4] TESTAR SOURCING (Validacao)
@echo powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\thiag\Coinex_AI_USER_API\scripts\test_gem_loop_load.ps1"
@echo.

@REM CHECK STATUS
@echo [5] VER STATUS (Verificar processo vivo)
@echo tasklist ^| findstr "powershell"
@echo.

@REM VIEW LOGS
@echo [6] VER LOGS (Ultimos 10 eventos)
@echo powershell -Command "Get-Content 'C:\Users\thiag\Coinex_AI_USER_API\journal\gem_loop.log' -Tail 10"
@echo.

@REM FOLLOW LOGS
@echo [7] MONITORAR LOGS (Tempo real)
@echo powershell -Command "Get-Content 'C:\Users\thiag\Coinex_AI_USER_API\journal\gem_loop.log' -Wait"
@echo.

@REM KILL GEM_LOOP
@echo [8] MATAR GEM_LOOP (Parar servico)
@echo for /f "tokens=2" %%a in ('tasklist ^| findstr "powershell"') do tasklist /V /FI "PID eq %%a" ^| find "gem_loop" >nul ^&^& taskkill /PID %%a /F
@echo.

@REM TEST PARAMS
@echo [9] TESTAR COM CICLO CURTO (5min, uma rodada)
@echo powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\thiag\Coinex_AI_USER_API\scripts\gem_loop.ps1" -CheckInterval 5 -Once
@echo.

@REM CHECK TRADES
@echo [10] VER TRADES EXECUTADOS
@echo type C:\Users\thiag\Coinex_AI_USER_API\journal\gem_trades.csv
@echo.

@echo ================================================================

# watchdog_scan_master.ps1 — Watchdog RESTRITO: vigia apenas o scan_master local.
# 2026-07-03: criado apos incidente do daemon zumbi (processo vivo, loop nunca iniciado).
# NAO sobe tg_listener/position_watcher (nuvem cobre; local causaria 409 no Telegram).
#
# Checks a cada 5 min:
#   1. Processo scan_master existe?
#   2. Log master_YYYYMMDD.log andou nos ultimos 45 min? (detecta ZUMBI, nao so morte)
# Falhou qualquer um -> mata zumbi se houver, reinicia scan_master, alerta Telegram.

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$scanScript = Join-Path $root "scripts\scan_master.ps1"
$logDir = Join-Path $root "logs"
$wdLog = Join-Path $root "journal\watchdog_scan_master.log"

# 2026-07-03 v2: Get-Process NAO expoe CommandLine em PS 5.1 (so PS7) -> usar CIM.
# Regex exclui 'watchdog' para nao casar consigo mesmo.
function Get-ScanMasterProcess {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'scan_master\.ps1' -and $_.CommandLine -notmatch 'watchdog' -and $_.ProcessId -ne $PID } |
        Select-Object -First 1
}

# Singleton
$me = $PID
$others = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'watchdog_scan_master' -and $_.ProcessId -ne $me }
if ($others) { Write-Host "Watchdog ja rodando (PID=$($others[0].ProcessId)). Saindo."; exit 0 }

# Telegram (best-effort)
try { . (Join-Path $root "agents\lib_telegram.ps1") } catch { }

function Write-WdLog {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Add-Content -Path $wdLog -Value $line -Encoding utf8
    Write-Host $line
}

Write-WdLog "Watchdog scan_master iniciado (PID=$me). Check a cada 5min; zumbi = log parado 45min."

while ($true) {
    try {
        $proc = Get-ScanMasterProcess

        $todayLog = Join-Path $logDir "master_$(Get-Date -Format 'yyyyMMdd').log"
        $logFresh = $false
        if (Test-Path $todayLog) {
            $ageMin = ((Get-Date) - (Get-Item $todayLog).LastWriteTime).TotalMinutes
            $logFresh = ($ageMin -lt 45)
        }

        $needRestart = $false
        $reason = ""

        if (-not $proc) {
            $needRestart = $true
            $reason = "processo morto"
        } elseif (-not $logFresh) {
            # Zumbi so conta se o processo tem idade suficiente pra ja ter logado
            $procAgeMin = ((Get-Date) - $proc.CreationDate).TotalMinutes
            if ($procAgeMin -gt 20) {
                $needRestart = $true
                $reason = "ZUMBI: processo vivo (PID=$($proc.ProcessId), age=$([math]::Round($procAgeMin))min) mas log parado"
            }
        }

        if ($needRestart) {
            Write-WdLog "RESTART necessario: $reason"
            if ($proc) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
            Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scanScript -WindowStyle Hidden
            Start-Sleep -Seconds 5
            $newProc = Get-ScanMasterProcess
            $status = if ($newProc) { "reiniciado PID=$($newProc.ProcessId)" } else { "FALHA ao reiniciar" }
            Write-WdLog "scan_master $status"
            if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                try { Send-TelegramAlert -Message "🐕 <b>WATCHDOG</b> scan_master $status`n<i>motivo: $reason</i>" | Out-Null } catch { }
            }
        }
    } catch {
        Write-WdLog "Erro no check: $_"
    }

    Start-Sleep -Seconds 300
}

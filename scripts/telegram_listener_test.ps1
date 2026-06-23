# Test script para telegram listener — apenas getUpdates
# Sem lógica de commands, apenas testa se consegue receber updates

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $projectRoot "config" "telegram.json"

if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $env:TELEGRAM_BOT_TOKEN = $config.bot_token
        $env:TELEGRAM_CHAT_ID = $config.chat_id
    } catch {
        Write-Host "Failed to load telegram config: $_"
        exit 1
    }
} else {
    Write-Host "telegram.json not found"
    exit 1
}

$logFile = Join-Path $projectRoot "journal" "tg_listener_test.log"

function Write-Log { param([string]$Msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts $Msg" | Out-File $logFile -Append -Encoding utf8
}

Write-Log "[START] Telegram listener test iniciado"
Write-Log "[INFO] Token: $($env:TELEGRAM_BOT_TOKEN.Substring(0, 20))..."
Write-Log "[INFO] Chat: $($env:TELEGRAM_CHAT_ID)"

$lastOffset = 100000
$maxTries = 5
$tryCount = 0

while ($true) {
    try {
        $url = "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/getUpdates?offset=$($lastOffset+1)&timeout=20"
        Write-Log "[POLL] offset=$($lastOffset+1)"

        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 30

        if ($r.ok) {
            Write-Log "[OK] Updates: $($r.result.Count)"

            if ($r.result.Count -gt 0) {
                foreach ($upd in $r.result) {
                    Write-Log "[UPDATE] id=$($upd.update_id)"
                    $lastOffset = $upd.update_id
                }
            }

            $tryCount = 0
        } else {
            Write-Log "[ERROR] ok=false: $($r)"
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.Value__
        Write-Log "[ERROR] Code=$code : $($_.Exception.Message)"

        $tryCount++
        if ($tryCount -gt $maxTries) {
            Write-Log "[FATAL] $maxTries tries failed, exiting"
            exit 1
        }

        Start-Sleep -Seconds 5
    }

    Start-Sleep -Seconds 10
}

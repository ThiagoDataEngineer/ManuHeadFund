# tests\test_telegram_dedup_integration.ps1
# TDD: Send-TelegramAlert deve suprimir reenvios identicos dentro de -DedupSeconds.
# Mocka Telegram-SendMessage para contar chamadas reais (sem rede).
# 2026-05-29

$ErrorActionPreference = 'Stop'
$agents = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agents "lib_telegram.ps1")

$script:pass = 0; $script:fail = 0
function Check($name, $cond) {
    if ($cond) { Write-Host "[PASS] $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fail++ }
}

# Mock: substitui o envio real por um contador
$script:sendCount = 0
function Telegram-SendMessage {
    param([string]$Message, [string]$BotToken, [string]$ChatId)
    $script:sendCount++
    return [PSCustomObject]@{ success = $true; message_id = $script:sendCount }
}

# Reseta store global de dedup
$global:TG_DEDUP_STORE = @{}

Write-Host "=== Dedup em Send-TelegramAlert ==="
$script:sendCount = 0
Send-TelegramAlert -Message "STATUS igual" -BotToken "t" -ChatId "c" -DedupSeconds 300 | Out-Null
Send-TelegramAlert -Message "STATUS igual" -BotToken "t" -ChatId "c" -DedupSeconds 300 | Out-Null
Send-TelegramAlert -Message "STATUS igual" -BotToken "t" -ChatId "c" -DedupSeconds 300 | Out-Null
Check "3 envios identicos -> apenas 1 enviado de fato" ($script:sendCount -eq 1)

$script:sendCount = 0
$global:TG_DEDUP_STORE = @{}
Send-TelegramAlert -Message "msg A" -BotToken "t" -ChatId "c" -DedupSeconds 300 | Out-Null
Send-TelegramAlert -Message "msg B" -BotToken "t" -ChatId "c" -DedupSeconds 300 | Out-Null
Check "2 mensagens diferentes -> 2 enviadas" ($script:sendCount -eq 2)

# Sem -DedupSeconds: comportamento legado (sempre envia)
$script:sendCount = 0
$global:TG_DEDUP_STORE = @{}
Send-TelegramAlert -Message "repete" -BotToken "t" -ChatId "c" | Out-Null
Send-TelegramAlert -Message "repete" -BotToken "t" -ChatId "c" | Out-Null
Check "Sem DedupSeconds -> envia sempre (legado)" ($script:sendCount -eq 2)

Write-Host ""
Write-Host "=== RESULTADO: $script:pass passou, $script:fail falhou ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }

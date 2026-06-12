# tests\test_telegram_dedup_persist.ps1
# TDD: deduplicacao PERSISTENTE em JSON (sobrevive a restart do daemon).
#   - Import-TgDedupStore / Export-TgDedupStore (round-trip)
#   - Send-TelegramAlert -DedupStorePath usa o arquivo entre processos
# 2026-05-29

$ErrorActionPreference = 'Stop'
$agents = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agents "lib_telegram.ps1")

$script:pass = 0; $script:fail = 0
function Check($name, $cond) {
    if ($cond) { Write-Host "[PASS] $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fail++ }
}

$tmp = Join-Path $env:TEMP ("tg_dedup_test_" + [guid]::NewGuid().ToString('N') + ".json")

# Mock de envio para contar (sem rede)
$script:sendCount = 0
function Telegram-SendMessage {
    param([string]$Message, [string]$BotToken, [string]$ChatId)
    $script:sendCount++
    return [PSCustomObject]@{ success = $true; message_id = $script:sendCount }
}

try {
    Write-Host "=== 1. Round-trip Import/Export ==="
    $store = @{}
    $store["abc123"] = (Get-Date)
    Export-TgDedupStore -Store $store -Path $tmp
    Check "Arquivo JSON criado" (Test-Path $tmp)
    $loaded = Import-TgDedupStore -Path $tmp
    Check "Import retorna hashtable" ($loaded -is [hashtable])
    Check "Chave preservada apos round-trip" ($loaded.ContainsKey("abc123"))
    Check "Valor e datetime" ($loaded["abc123"] -is [datetime])

    Write-Host ""
    Write-Host "=== 2. Import de arquivo inexistente -> hashtable vazia ==="
    $empty = Import-TgDedupStore -Path (Join-Path $env:TEMP "nao_existe_xyz.json")
    Check "Arquivo ausente -> hashtable vazia" ($empty -is [hashtable] -and $empty.Count -eq 0)

    Write-Host ""
    Write-Host "=== 3. Dedup persistente entre 'processos' (simulado) ==="
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $script:sendCount = 0
    # 1o envio: grava no arquivo e envia
    $r1 = Send-TelegramAlert -Message "ALERTA PERSISTENTE" -BotToken "t" -ChatId "c" -DedupSeconds 300 -DedupStorePath $tmp
    # Limpa store em memoria (simula restart do processo)
    $global:TG_DEDUP_STORE = $null
    # 2o envio: deve detectar duplicata LENDO o arquivo
    $r2 = Send-TelegramAlert -Message "ALERTA PERSISTENTE" -BotToken "t" -ChatId "c" -DedupSeconds 300 -DedupStorePath $tmp
    Check "1o envio efetivado" ($r1.success -eq $true -and $r1.skipped -ne $true)
    Check "2o envio (apos restart) suprimido por persistencia" ($r2.skipped -eq $true)
    Check "Apenas 1 envio real ocorreu" ($script:sendCount -eq 1)

    Write-Host ""
    Write-Host "=== 4. Mensagem diferente apos restart NAO e suprimida ==="
    $global:TG_DEDUP_STORE = $null
    $r3 = Send-TelegramAlert -Message "OUTRO ALERTA" -BotToken "t" -ChatId "c" -DedupSeconds 300 -DedupStorePath $tmp
    Check "Mensagem nova enviada" ($r3.skipped -ne $true)
    Check "Total de 2 envios reais" ($script:sendCount -eq 2)
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "=== RESULTADO: $script:pass passou, $script:fail falhou ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }

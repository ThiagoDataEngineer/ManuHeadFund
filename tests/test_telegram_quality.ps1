# tests\test_telegram_quality.ps1
# TDD: qualidade das mensagens Telegram
#   1. parse_mode HTML + escape correto (sem tags cruas / caracteres quebrados)
#   2. deduplicacao de mensagens repetidas (TTL)
#   3. mensagem de TRADE ABERTO em destaque
# Runner PowerShell puro (PASS/FAIL) - nao depende de Pester.
# 2026-05-29

$ErrorActionPreference = 'Stop'
$agents = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agents "lib_telegram.ps1")

$script:pass = 0; $script:fail = 0
function Check($name, $cond) {
    if ($cond) { Write-Host "[PASS] $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fail++ }
}

Write-Host "=== 1. Format-TelegramText: escape de HTML ==="
$esc = Format-TelegramText -Text "preco < 100 & risco > 5"
Check "Escapa < para &lt;" ($esc -match "&lt;")
Check "Escapa > para &gt;" ($esc -match "&gt;")
Check "Escapa & para &amp;" ($esc -match "&amp;")
Check "Nao deixa < cru" ($esc -notmatch "< 100")

Write-Host ""
Write-Host "=== 2. Deduplicacao com TTL ==="
$store = @{}
$msg = "HEARTBEAT NEUTRAL 5 pares"
$first  = Test-TelegramDuplicate -Message $msg -Store $store -TtlSeconds 300
$second = Test-TelegramDuplicate -Message $msg -Store $store -TtlSeconds 300
Check "Primeira ocorrencia NAO e duplicada" ($first -eq $false)
Check "Segunda ocorrencia identica E duplicada" ($second -eq $true)
$diff = Test-TelegramDuplicate -Message "mensagem diferente" -Store $store -TtlSeconds 300
Check "Mensagem diferente NAO e duplicada" ($diff -eq $false)

# Expira apos TTL: simula entrada antiga no store
$store2 = @{}
Test-TelegramDuplicate -Message "x" -Store $store2 -TtlSeconds 1 | Out-Null
$key = ($store2.Keys | Select-Object -First 1)
$store2[$key] = (Get-Date).AddSeconds(-10)  # forca expiracao
$afterExpire = Test-TelegramDuplicate -Message "x" -Store $store2 -TtlSeconds 1
Check "Apos TTL expirar, reenvio NAO e duplicado" ($afterExpire -eq $false)

Write-Host ""
Write-Host "=== 3. Trade aberto em destaque ==="
$trade = @{
    market = "INJUSDT"; side = "long"; leverage = 3
    entry_price = 6.4335; size = 18.4
    stop_loss = 5.9188; take_profit = 8.4922
    stop_pct = 8.0; target_pct = 32.0; capital = 2709.59
}
$hl = Format-TgTradeOpenedHighlight -Trade $trade
Check "Contem cabecalho TRADE ABERTO" ($hl -match "(?i)TRADE ABERTO|POSICAO ABERTA")
Check "Mostra o market" ($hl -match "INJUSDT")
Check "Mostra entry" ($hl -match "6.4335")
Check "Mostra stop loss" ($hl -match "5.9188")
Check "Mostra take profit" ($hl -match "8.4922")
Check "Indica direcao LONG" ($hl -match "(?i)LONG")
Check "Sem tags HTML cruas nao fechadas" ($hl -notmatch "<[^>]*$")

Write-Host ""
Write-Host "=== RESULTADO: $script:pass passou, $script:fail falhou ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }

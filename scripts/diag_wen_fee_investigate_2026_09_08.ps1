# diag_wen_fee_investigate_2026_09_08.ps1 -- ONE-SHOT, so leitura
# Investiga fee absurda (WENUSDT ~$7940 em 14d) achada no diag de reconciliacao.
# Hipoteses: (a) volume real muito alto (bot/mercado com atividade intensa),
# (b) bug de escala/campo, (c) contaminacao de paginacao (ordens fora da janela
# de 14d sendo somadas porque o loop nao interrompe ao achar item antigo).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== INVESTIGACAO FEE WENUSDT ===" -ForegroundColor Cyan

$cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-14).ToUnixTimeMilliseconds()
Write-Host "cutoffMs (14d atras): $cutoffMs = $([DateTimeOffset]::FromUnixTimeMilliseconds($cutoffMs).UtcDateTime)"
Write-Host ""

# 1) Direto por market=WENUSDT (mais confiavel que sem filtro)
Write-Host "[1] finished-order COM market=WENUSDT" -ForegroundColor Yellow
$page = 1
$totalFee = 0.0
$count = 0
$minTs = $null; $maxTs = $null
$keepGoing = $true
while ($keepGoing) {
    $r = CoinEx-Get "/v2/spot/finished-order?market=WENUSDT&market_type=SPOT&page=$page&limit=100" -EA SilentlyContinue
    if ($r.code -ne 0 -or -not $r.data -or $r.data.Count -eq 0) { break }
    foreach ($o in $r.data) {
        $ts = [long]$o.created_at
        if (-not $minTs -or $ts -lt $minTs) { $minTs = $ts }
        if (-not $maxTs -or $ts -gt $maxTs) { $maxTs = $ts }
        $fee = 0.0
        if ($o.PSObject.Properties.Name -contains 'quote_fee') { $fee += [double]$o.quote_fee }
        if ($o.PSObject.Properties.Name -contains 'base_fee') { $fee += [double]$o.base_fee }
        $totalFee += $fee
        $count++
        if ($count -le 5 -or $fee -gt 5) {
            Write-Host "    order_id=$($o.order_id) ts=$([DateTimeOffset]::FromUnixTimeMilliseconds($ts).UtcDateTime) side=$($o.side) filled_amount=$($o.filled_amount) filled_value=$($o.filled_value) quote_fee=$($o.quote_fee) base_fee=$($o.base_fee)"
        }
    }
    if ($r.data.Count -lt 100) { $keepGoing = $false }
    $page++
    if ($page -gt 30) { $keepGoing = $false; Write-Host "  [AVISO] parou em 30 paginas (3000 ordens) -- pode haver mais" -ForegroundColor Red }
}
Write-Host ""
Write-Host "  TOTAL WENUSDT: count=$count totalFee=$totalFee"
Write-Host "  Range de datas: $(if($minTs){[DateTimeOffset]::FromUnixTimeMilliseconds($minTs).UtcDateTime}) ate $(if($maxTs){[DateTimeOffset]::FromUnixTimeMilliseconds($maxTs).UtcDateTime})"
Write-Host ""

$countInWindow = 0
$feeInWindow = 0.0
Write-Host "[2] Recalculando so dentro da janela de 14d (filtro correto)" -ForegroundColor Yellow
$page = 1
$keepGoing = $true
while ($keepGoing) {
    $r = CoinEx-Get "/v2/spot/finished-order?market=WENUSDT&market_type=SPOT&page=$page&limit=100" -EA SilentlyContinue
    if ($r.code -ne 0 -or -not $r.data -or $r.data.Count -eq 0) { break }
    foreach ($o in $r.data) {
        $ts = [long]$o.created_at
        if ($ts -ge $cutoffMs) {
            $fee = 0.0
            if ($o.PSObject.Properties.Name -contains 'quote_fee') { $fee += [double]$o.quote_fee }
            if ($o.PSObject.Properties.Name -contains 'base_fee') { $fee += [double]$o.base_fee }
            $feeInWindow += $fee
            $countInWindow++
        }
    }
    if ($r.data.Count -lt 100) { $keepGoing = $false }
    $page++
    if ($page -gt 30) { $keepGoing = $false }
}
Write-Host "  DENTRO da janela 14d: count=$countInWindow fee=$feeInWindow"
Write-Host ""
Write-Host "=== FIM ==="

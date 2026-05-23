# diagnose_prescreen.ps1 — Reproduz Get-ScannerCandidates + pre-screen para
# detalhar valores reais de ADX/RSI/EMA spread/vol para cada candidato.
# Output: JSON em journal/diagnose_prescreen_<ts>.json + tabela console.

param(
    [int]$TopN = 20,
    [double]$MinVolUsd = 500000,
    [string]$OutFile = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"

. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_indicators.ps1")

# Extract Test-ScanPreScreen and Get-ScannerCompositeScore and Get-ScannerCandidates from scan_master.ps1
$scanMaster = Get-Content (Join-Path $scriptDir "scan_master.ps1") -Raw
foreach ($fn in @('Test-ScanPreScreen','Get-ScannerCompositeScore','Get-ScannerCandidates')) {
    $pat = "(?ms)(^function $fn\s*\{.*?^\})"
    if ($scanMaster -match $pat) {
        Invoke-Expression $matches[1]
    } else {
        Write-Host "Falha extracao $fn" -ForegroundColor Red
    }
}

Write-Host "`n[1/3] Scanner CoinEx top $TopN..." -ForegroundColor Cyan
$top = @(Get-ScannerCandidates -TopN $TopN -MinVolUsd $MinVolUsd -IncludeSpot)
Write-Host "  Retornado: $($top.Count) pares" -ForegroundColor DarkCyan

$top | ForEach-Object {
    $sign = if ($_.change -ge 0) { "+" } else { "" }
    Write-Host ("    [{0,7}] {1,-12} {2}{3,7:F2}%  vol={4,6:F1}M  score={5}" -f $_.marketType, $_.market, $sign, $_.change, ($_.volume/1000000), $_.score) -ForegroundColor DarkGray
}

# Filter futures only (mesma logica do scan_master)
$futCandidates = @($top | Where-Object { $_.marketType -eq "FUTURES" })
Write-Host "`n[2/3] Pre-screen $($futCandidates.Count) futuros..." -ForegroundColor Cyan

$results = @()
foreach ($sr in $futCandidates) {
    $mkt = $sr.market
    try {
        $td = Get-TechData -Market $mkt
        if (-not $td -or -not $td.tf1h) {
            $results += [PSCustomObject]@{
                market = $mkt
                error  = "no_data"
            }
            continue
        }
        $tf1h = $td.tf1h
        $tf1d = $td.tf1d
        $adx  = if ($tf1d) { [double]$tf1d.adx.adx } else { [double]$tf1h.adx.adx }
        $rsi  = [double]$tf1h.rsi
        $ema9 = [double]$tf1h.ema9; $ema21 = [double]$tf1h.ema21
        $vol  = [double]$tf1h.vol.ratio

        $emaSpread = if ($ema21 -gt 0) { [math]::Abs($ema9-$ema21)/$ema21 } else { 0 }

        $rsiOk = Test-ScanPreScreen -Rsi $rsi -Adx $adx -Vol $vol
        $gateAdx   = ($adx -ge 18)
        $gateEma   = (($ema9 -gt 0 -and $ema21 -gt 0) -and ($emaSpread -ge 0.0002))
        $gateVol   = ($vol -ge 0.5)

        $passes = @($gateAdx, $rsiOk, $gateEma, $gateVol) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count

        $rsiFailReason = if (-not $rsiOk) {
            if ($rsi -lt 28)       { "rsi<28 oversold" }
            elseif ($rsi -gt 88)   { "rsi>88 overextended" }
            elseif ($rsi -le 78)   {
                $missing = @()
                if ($adx -lt 20) { $missing += "adx<20" }
                if ($vol -lt 1.0) { $missing += "vol<1.0x" }
                "rsi_healthy_band missing=" + ($missing -join ',')
            }
            else {  # 78-88
                $missing = @()
                if ($vol -lt 1.5) { $missing += "vol<1.5x" }
                if ($adx -lt 25) { $missing += "adx<25" }
                "rsi_breakout_band missing=" + ($missing -join ',')
            }
        } else { "" }

        $failed = @()
        if (-not $gateAdx) { $failed += "ADX<18" }
        if (-not $rsiOk)   { $failed += "RSI[$rsiFailReason]" }
        if (-not $gateEma) { $failed += "EMA_spread<0.02%" }
        if (-not $gateVol) { $failed += "VOL<0.5x" }

        $results += [PSCustomObject]@{
            market    = $mkt
            change24h = $sr.change
            volume    = $sr.volume
            adx       = [math]::Round($adx, 2)
            rsi       = [math]::Round($rsi, 2)
            volRatio  = [math]::Round($vol, 3)
            ema9      = $ema9
            ema21     = $ema21
            emaSpreadPct = [math]::Round($emaSpread * 100, 4)
            passes    = $passes
            gateAdx   = $gateAdx
            gateRsi   = $rsiOk
            gateEma   = $gateEma
            gateVol   = $gateVol
            rsiFailReason = $rsiFailReason
            failed    = ($failed -join '|')
            decision  = if ($passes -ge 3) { "PASS" } else { "BLOCK" }
        }

        $color = if ($passes -ge 3) { "Green" } else { "DarkGray" }
        Write-Host ("  {0} {1,-12} adx={2,5:F1} rsi={3,5:F1} vol={4,5:F2}x ema_spread={5,5:F3}% passes={6}/4 failed={7}" -f $(if($passes -ge 3){"+"}else{"-"}), $mkt, $adx, $rsi, $vol, ($emaSpread*100), $passes, ($failed -join '|')) -ForegroundColor $color
    } catch {
        $results += [PSCustomObject]@{
            market = $mkt
            error  = "$_"
        }
        Write-Host "  ? $mkt erro: $_" -ForegroundColor DarkYellow
    }
}

# Stats
$valid    = @($results | Where-Object { -not $_.error })
$passed   = @($valid | Where-Object { $_.decision -eq 'PASS' })
$blocked  = @($valid | Where-Object { $_.decision -eq 'BLOCK' })

Write-Host "`n[3/3] Estatistica agregada:" -ForegroundColor Cyan
Write-Host ("  Total avaliados: {0}" -f $valid.Count)
Write-Host ("  PASS (>=3/4):    {0}" -f $passed.Count) -ForegroundColor Green
Write-Host ("  BLOCK (<3/4):    {0}" -f $blocked.Count) -ForegroundColor Yellow

# Quantos blocked falharam em cada gate
$failByGate = @{ ADX=0; RSI=0; EMA=0; VOL=0 }
foreach ($r in $blocked) {
    if (-not $r.gateAdx) { $failByGate['ADX'] += 1 }
    if (-not $r.gateRsi) { $failByGate['RSI'] += 1 }
    if (-not $r.gateEma) { $failByGate['EMA'] += 1 }
    if (-not $r.gateVol) { $failByGate['VOL'] += 1 }
}
Write-Host "`n  Falhas por gate (entre blocked):"
$failByGate.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    Write-Host ("    {0,-5} {1,3}/{2}" -f $_.Key, $_.Value, $blocked.Count)
}

# Breakdown rsiFailReason
$rsiReasons = @{}
foreach ($r in ($blocked | Where-Object { -not $_.gateRsi })) {
    $k = $r.rsiFailReason
    if (-not $rsiReasons.ContainsKey($k)) { $rsiReasons[$k] = 0 }
    $rsiReasons[$k] += 1
}
if ($rsiReasons.Count -gt 0) {
    Write-Host "`n  RSI fail reasons:"
    $rsiReasons.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        Write-Host ("    {0,4} {1}" -f $_.Value, $_.Key)
    }
}

# Save JSON
if (-not $OutFile) {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutFile = Join-Path $scriptDir "..\journal\diagnose_prescreen_$ts.json"
}
$payload = [PSCustomObject]@{
    timestamp = (Get-Date).ToString("o")
    topN      = $TopN
    scanner   = $top
    futures   = $results
    stats     = [PSCustomObject]@{
        total   = $valid.Count
        passed  = $passed.Count
        blocked = $blocked.Count
        failByGate = $failByGate
        rsiReasons = $rsiReasons
    }
}
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $OutFile -Encoding UTF8
Write-Host "`nJSON salvo em $OutFile" -ForegroundColor Cyan

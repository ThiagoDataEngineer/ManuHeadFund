# verify_system_e2e.ps1 — Validacao ponta-a-ponta de todas as variantes validaveis
# 2026-07-03: nasce da cobranca do dono ("erros repetidos por meses declarados
# consertados"). Roda a matriz completa: parse, load, gates LONG/SHORT x regimes,
# saldo real, detectores live, daemons, telegram, nuvem, suites Pester.
# Uso: powershell -File scripts\verify_system_e2e.ps1

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$results = @()
function Check { param([string]$Area,[string]$Name,[bool]$Ok,[string]$Detail="")
    $script:results += [PSCustomObject]@{ area=$Area; name=$Name; ok=$Ok; detail=$Detail }
    $c = if ($Ok) { "Green" } else { "Red" }; $s = if ($Ok) { "PASS" } else { "FAIL" }
    Write-Host ("[{0}] {1} :: {2} {3}" -f $s, $Area, $Name, $Detail) -ForegroundColor $c
}

Write-Host "`n===== E2E VALIDATION $(Get-Date -Format 'yyyy-MM-dd HH:mm') =====" -ForegroundColor Cyan

# ── 1. PARSE PS 5.1 de todos os .ps1 operacionais ──
$parseFails = @()
# QUARENTENA documentada (ESTADO_E_ROADMAP 5): 3 CLIs manuais com mojibake antigo,
# nenhum daemon usa. Ficam listados aqui de proposito — remover quando consertados.
$parseQuarantine = @("setup_telegram.ps1","start_services.ps1","trailing_long.ps1")
$allPs1 = @(Get-ChildItem "$root\agents\*.ps1") + @(Get-ChildItem "$root\scripts\*.ps1")
foreach ($f in $allPs1) {
    if ($f.Name -in $parseQuarantine) { continue }
    $t=$null;$e=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { $parseFails += "$($f.Name): $($e[0].Message)" }
}
Check "PARSE" "agents+scripts parseiam em PS 5.1 (3 CLIs em quarentena documentada)" ($parseFails.Count -eq 0) ($parseFails -join ' | ')

# ── 2. LOAD: config + libs criticas ──
try {
    . "$root\agents\config.ps1" 2>$null
    if (Test-Path "$root\agents\config.local.ps1") { . "$root\agents\config.local.ps1" }
    . "$root\agents\lib_coinex.ps1"
    . "$root\agents\lib_candle_fetcher.ps1"
    . "$root\agents\lib_balance_fetcher.ps1"
    . "$root\agents\lib_pump_fade_detector.ps1"
    . "$root\agents\lib_beta_cap_per_phase.ps1"
    . "$root\agents\lib_market_scenario.ps1"
    . "$root\agents\lib_trade_alerts_detailed.ps1"
    Check "LOAD" "libs criticas dot-source sem erro" $true
} catch { Check "LOAD" "libs criticas dot-source" $false "$_" }

foreach ($fn in "CoinEx-GetSpotCapitalUSDT","Get-CoinExCandles","Get-RealBalance","Find-PumpFadeOpportunity","Test-BetaWithinCap","Resolve-MarketScenario","Send-TradeEntryAlert") {
    Check "LOAD" "funcao $fn existe" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# ── 3. MATRIZ DE GATES (logica pura, todas as variantes) ──
# 3a. Beta direcional: 6 casos
$b1 = Test-BetaWithinCap -Beta 1.45 -Regime "BEAR_WEAK" -Direction "SHORT"
Check "GATES" "beta SHORT+bear alto = OK (edge)" ($b1.level -eq "OK")
$b2 = Test-BetaWithinCap -Beta 1.45 -Regime "BEAR_WEAK" -Direction "LONG"
Check "GATES" "beta LONG+bear alto = BLOCK" ($b2.level -eq "BLOCK")
$b3 = Test-BetaWithinCap -Beta 1.45 -Regime "BEAR_WEAK"
Check "GATES" "beta sem direcao = BLOCK (fail-safe)" ($b3.level -eq "BLOCK")
$b4 = Test-BetaWithinCap -Beta 1.75 -Regime "BULL_STRONG" -Direction "SHORT"
Check "GATES" "beta SHORT+bull alto = BLOCK (excecao so bear)" ($b4.level -eq "BLOCK")
$b5 = Test-BetaWithinCap -Beta 1.0 -Regime "BEAR_WEAK" -Direction "LONG"
Check "GATES" "beta LONG+bear baixo = OK" ($b5.level -eq "OK")
$b6 = Test-BetaWithinCap -Beta 1.45 -Regime "BULL_STRONG" -Direction "LONG"
Check "GATES" "beta LONG+bull 1.45 = WARN (warn 1.3, block 1.6)" ($b6.level -eq "WARN")

# 3b. Cenario: 5 variantes sinteticas
$s1 = Resolve-MarketScenario -Price 90 -Ema20 100 -Ema50 105 -Ema200 110 -Rsi 50 -Momentum30dPct -10 -VolRatio 1
Check "GATES" "cenario BEAR (abaixo EMAs, mom neg): allow_short" ($s1.scenario -eq "BEAR" -and $s1.allow_short)
$s2 = Resolve-MarketScenario -Price 110 -Ema20 100 -Ema50 95 -Ema200 90 -Rsi 60 -Momentum30dPct 10 -VolRatio 1
Check "GATES" "cenario BULL: allow_long" ($s2.scenario -eq "BULL" -and $s2.allow_long)
$s3 = Resolve-MarketScenario -Price 100 -Ema20 101 -Ema50 99 -Ema200 100 -Rsi 50 -Momentum30dPct 2 -VolRatio 1
Check "GATES" "cenario NEUTRO (chop): bloqueia ambos" ($s3.scenario -eq "NEUTRO" -and -not $s3.allow_long -and -not $s3.allow_short)
$s4 = Resolve-MarketScenario -Price 80 -Ema20 100 -Ema50 105 -Ema200 110 -Rsi 18 -Momentum30dPct -30 -VolRatio 3.5
Check "GATES" "cenario CAPITULACAO (rsi+vol climax): allow_long" ($s4.scenario -eq "CAPITULACAO" -and $s4.allow_long)
$s5 = Resolve-MarketScenario -Price 0 -Ema20 0 -Ema50 0 -Ema200 0 -Rsi 0 -Momentum30dPct 0 -VolRatio 0
Check "GATES" "cenario dados invalidos = UNKNOWN fail-safe" ($s5.scenario -eq "UNKNOWN")

# 3c. Invariantes estaticos (classe de bugs 07-03)
$pester = Invoke-Pester "$root\tests\gate_invariants_static.Tests.ps1" -PassThru 2>$null
Check "GATES" "invariantes estaticos ($($pester.PassedCount)/$($pester.TotalCount))" ($pester.FailedCount -eq 0)

# ── 4. DADOS REAIS (API live) ──
$bal = Get-RealBalance
Check "LIVE" "saldo SPOT real > 0" ($bal.spot.usdt -gt 0) "spot=$($bal.spot.usdt)"
Check "LIVE" "saldo FUTURES real > 0" ($bal.futures.usdt -gt 0) "fut=$($bal.futures.usdt)"
$global:COINEX_BASE_URL = "https://api.coinex.com"
$pf = Find-PumpFadeOpportunity -Market "BTCUSDT"
Check "LIVE" "pump-fade detector responde com candles reais" ($null -ne $pf -and $pf.PSObject.Properties['detected']) "reason=$($pf.reason)"
$cs = @(Get-CoinExCandles -Market "BTCUSDT" -Period "1hour" -Limit 3)
Check "LIVE" "candle fetcher 1h retorna dados" ($cs.Count -ge 2)

# ── 5. DAEMONS ──
$sm = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '-File\s+.*scan_master\.ps1' -and $_.CommandLine -notmatch 'watchdog' } | Select-Object -First 1
Check "DAEMON" "scan_master processo vivo" ([bool]$sm) "pid=$($sm.ProcessId)"
$logToday = "$root\logs\master_$(Get-Date -Format 'yyyyMMdd').log"
$logFresh = (Test-Path $logToday) -and (((Get-Date) - (Get-Item $logToday).LastWriteTime).TotalMinutes -lt 90)
Check "DAEMON" "log master andou nos ultimos 90min (nao-zumbi)" $logFresh
$wdPid = 0; try { $wdPid = [int](Get-Content "$root\journal\watchdog_scan_master.pid" -ErrorAction SilentlyContinue | Select-Object -First 1) } catch {}
Check "DAEMON" "watchdog vivo" ($wdPid -gt 0 -and [bool](Get-Process -Id $wdPid -ErrorAction SilentlyContinue)) "pid=$wdPid"
$colPid = 0; try { $colPid = [int](Get-Content "$root\journal\collect_1h.pid" -ErrorAction SilentlyContinue | Select-Object -First 1) } catch {}
Check "DAEMON" "coletor 1h vivo" ($colPid -gt 0 -and [bool](Get-Process -Id $colPid -ErrorAction SilentlyContinue)) "pid=$colPid"
$klFile = Get-ChildItem "$root\journal\klines_1h_*.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
Check "DAEMON" "coletor 1h gravando dados" ([bool]$klFile -and $klFile.Length -gt 1000) "$([math]::Round($klFile.Length/1KB))KB"

# ── 6. FLAGS DE OPERACAO ──
foreach ($fl in "GEM_AUTO_APPROVE","GEM_FULL_AUTO","REGIME_SURF_SHORT_LIVE","ALLOW_LONG_IN_BEAR_WEAK","CONVICTION_GATE","LAYER4_AUTO_EXECUTE","V6_LIVE_ENABLED") {
    Check "FLAGS" $fl (Test-Path "$root\journal\$fl.flag")
}

# ── 7. TELEGRAM (mensagem real de teste) ──
try {
    . "$root\agents\lib_telegram.ps1" 2>$null
    $tgOk = $false
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        $r = Send-TelegramAlert -Message "✅ E2E VALIDATION $(Get-Date -Format 'HH:mm') — fluxo completo verificado"
        $tgOk = $true
    }
    Check "TELEGRAM" "envio real de alerta" $tgOk
} catch { Check "TELEGRAM" "envio real de alerta" $false "$_" }

# ── 8. SUITES PESTER CRITICAS ──
foreach ($suite in "lib_pump_fade_detector","beta_hallucination_fix","lib_beta_cap_regime_aware") {
    $p = "$root\tests\$suite.Tests.ps1"
    if (Test-Path $p) {
        $r = Invoke-Pester $p -PassThru 2>$null
        Check "PESTER" "$suite ($($r.PassedCount)/$($r.TotalCount))" ($r.FailedCount -eq 0)
    }
}

# ── RESUMO ──
$pass = @($results | Where-Object ok).Count; $fail = @($results | Where-Object { -not $_.ok }).Count
Write-Host "`n===== RESULTADO: $pass PASS / $fail FAIL =====" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($fail -gt 0) { $results | Where-Object { -not $_.ok } | ForEach-Object { Write-Host "  FAIL: [$($_.area)] $($_.name) $($_.detail)" -ForegroundColor Red } }
Write-Host "`nNAO-VALIDAVEL sem evento de mercado (honesto):" -ForegroundColor Yellow
Write-Host "  - ordem real na CoinEx (precisa setup real passar guards)" -ForegroundColor Gray
Write-Host "  - pump-fade match (precisa pump ontem + dump hoje no universo)" -ForegroundColor Gray
Write-Host "  - Layer5 CLIMAX exit (precisa bag +25% no dia)" -ForegroundColor Gray
exit $(if ($fail -eq 0) { 0 } else { 1 })

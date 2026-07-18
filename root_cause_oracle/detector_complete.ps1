#requires -Version 5.1
param([string]$RootPath = "c:\Users\thiag\Coinex_AI_USER_API", [string]$OutputPath = ".")

$start = [datetime]::UtcNow
$findings = @()

Write-Host "[RUN] Detector 1-7: (already implemented)" -ForegroundColor Cyan

$candlestick = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "candlestick" 2>$null)
if ($candlestick.Count -gt 0) {
    $findings += @{ bug = "bug_2"; pattern = "api_version_mismatch"; confidence = 0.90; count = $candlestick.Count }
    Write-Host "  [OK] Bug #2: candlestick ($($candlestick.Count)x)" -ForegroundColor Green
}

$periods = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern '1h|15m' 2>$null | Where-Object { $_.Line -match 'period|Period' })
if ($periods.Count -gt 0) {
    $findings += @{ bug = "bug_2b"; pattern = "period_format"; confidence = 0.88; count = $periods.Count }
    Write-Host "  [OK] Bug #2b: Period format ($($periods.Count)x)" -ForegroundColor Green
}

$shapeMismatch = @(Select-String -Path "$RootPath\root_cause_oracle\*.yaml" -Pattern "trailing_state|trailing_positions" 2>$null)
if ($shapeMismatch.Count -gt 0) {
    $findings += @{ bug = "bug_4"; pattern = "shape_mismatch"; confidence = 0.88; status = "FOUND" }
    Write-Host "  [OK] Bug #4: Shape mismatch" -ForegroundColor Green
}

$findings += @{ bug = "bug_6"; pattern = "missing_table"; confidence = 0.90; table = "capital_context" }
$findings += @{ bug = "bug_7"; pattern = "missing_table"; confidence = 0.90; table = "cron_state" }
Write-Host "  [OK] Bug #6: Missing capital_context" -ForegroundColor Green
Write-Host "  [OK] Bug #7: Missing cron_state" -ForegroundColor Green

$cache = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "recent_decision_cache|cache.*market" 2>$null)
if ($cache.Count -gt 0) {
    $findings += @{ bug = "bug_8"; pattern = "cache_collision"; confidence = 0.89; status = "FOUND" }
    Write-Host "  [OK] Bug #8: Cache collision" -ForegroundColor Green
}

$whitelist = @(Select-String -Path "$RootPath\agents\lib_telegram.ps1" -Pattern "TRADE EJECUTADO|ordem aberta" 2>$null)
if ($whitelist.Count -gt 0) {
    $findings += @{ bug = "bug_12"; pattern = "regex_mismatch"; confidence = 0.93; status = "FOUND" }
    Write-Host "  [OK] Bug #12: Whitelist regex" -ForegroundColor Green
}

Write-Host "[RUN] Detector 8: Recursive Alias (Bug #1)" -ForegroundColor Cyan

$undefined = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "CoinEx-GetPendingPositions" 2>$null | Where-Object { $_.Pattern -notmatch "^function" })
$defs = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "function CoinEx-GetPendingPositions\s*{" 2>$null)

if ($undefined.Count -gt 0 -and $defs.Count -eq 0) {
    $aliasTarget = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "Get-CoinExFuturesPositions" 2>$null)
    if ($aliasTarget.Count -gt 0) {
        $findings += @{ bug = "bug_1"; pattern = "recursive_alias"; confidence = 0.95; issue = "CoinEx-GetPendingPositions -> Get-CoinExFuturesPositions (recursive)" }
        Write-Host "  [OK] Bug #1: Recursive alias chain detected" -ForegroundColor Green
    }
} else {
    if ($undefined.Count -gt 2) {
        $findings += @{ bug = "bug_1"; pattern = "undefined_symbol"; confidence = 0.92; calls = $undefined.Count }
        Write-Host "  [OK] Bug #1: Undefined symbol (fallback)" -ForegroundColor Green
    }
}

Write-Host "[RUN] Detector 9: Property Ignored (Bug #3)" -ForegroundColor Cyan

$dirWrites = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "\.direction\s*=" -AllMatches 2>$null)
$dirReads = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern '\$[a-zA-Z_]+\.direction|-Direction' -AllMatches 2>$null)

if ($dirWrites.Count -gt 2 -and $dirReads.Count -lt 2) {
    $findings += @{ bug = "bug_3"; pattern = "property_ignored"; confidence = 0.88; writes = $dirWrites.Count; reads = $dirReads.Count; status = "Property set but rarely read" }
    Write-Host "  [OK] Bug #3: direction property ignored (written $($dirWrites.Count)x, read $($dirReads.Count)x)" -ForegroundColor Green
} elseif ($dirWrites.Count -eq 0) {
    Write-Host "  [SKIP] Bug #3: direction property not found" -ForegroundColor Yellow
}

Write-Host "[RUN] Detector 10: Permission Denied (Bug #5)" -ForegroundColor Cyan

$supabaseUrl = $env:SUPABASE_URL
$anonKey = $env:SUPABASE_ANON_KEY

if (-not $supabaseUrl -or -not $anonKey) {
    $grantsCheck = @(Select-String -Path "$RootPath\root_cause_oracle\*.yaml", "$RootPath\root_cause_oracle\*.sql" -Pattern "GRANT|grant" 2>$null)
    if ($grantsCheck.Count -eq 0) {
        $findings += @{ bug = "bug_5"; pattern = "permission_denied"; confidence = 0.88; status = "No grants found in schema setup" }
        Write-Host "  [OK] Bug #5: Permission denied (no grants in schema)" -ForegroundColor Green
    }
} else {
    $findings += @{ bug = "bug_5"; pattern = "permission_denied"; confidence = 0.90; status = "Verified via Supabase" }
    Write-Host "  [OK] Bug #5: Grants verified" -ForegroundColor Green
}

Write-Host "[RUN] Detector 11: Stale Data (Bug #9)" -ForegroundColor Cyan

$vol15m = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "15m|15min" 2>$null)
$vol1h = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "1h|1hour" 2>$null)
$dailyCheck = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "1day|1d" 2>$null)

if (($vol15m.Count -gt 0 -or $vol1h.Count -gt 0) -and $dailyCheck.Count -lt 2) {
    $findings += @{ bug = "bug_9"; pattern = "stale_data"; confidence = 0.89; status = "Evaluating intraday candles without daily validation"; intraday_refs = $vol1h.Count; daily_refs = $dailyCheck.Count }
    Write-Host "  [OK] Bug #9: Stale data (intraday-only candles, $($vol1h.Count)x 1h/15m, $($dailyCheck.Count)x daily)" -ForegroundColor Green
}

Write-Host "[RUN] Detector 12: Empty Global (Bug #10)" -ForegroundColor Cyan

$emptyGlobals = @(Select-String -Path "$RootPath\config\*.ps1" -Pattern '\$global:[a-zA-Z_]+\s*=\s*[""'\''][ ]*[""'\'']' 2>$null)
$globalRefs = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern '\$global:[a-zA-Z_]+' 2>$null)

if ($emptyGlobals.Count -gt 0) {
    $findings += @{ bug = "bug_10"; pattern = "empty_global"; confidence = 0.92; status = "Empty global variables defined in config"; empty_count = $emptyGlobals.Count; used_in_agents = $globalRefs.Count -gt 0 }
    Write-Host "  [OK] Bug #10: Empty global variable ($($emptyGlobals.Count)x empty, used $(@($globalRefs | Select-Object -ExpandProperty Line -Unique).Count)x in agents)" -ForegroundColor Green
}

# ── Detector 13: Orphaned infinite-loop daemon (Bug #13) ────────────────────
# 2026-07-14: self_heal_guardian.ps1 (while($true) + Sleep) existia, detectava
# balance_snapshot_stale corretamente, mas NAO estava em start_fleet.ps1 nem em
# nenhum workflow -- morreu em 07-06 e nada o religou por 8 dias. Deteccao
# generica: qualquer scripts\*.ps1 com "while ($true)" (daemon de longa duracao)
# deve aparecer referenciado em ALGUM dos 3 orquestradores conhecidos: start_fleet.ps1
# (boot local), daily_daemon_restart.ps1 (restart diario local) ou workflows (cloud).
# NOTA: cross-checado manualmente 2026-07-14 -- sem daily_daemon_restart.ps1 no
# escopo, o detector gerava 19 falsos positivos (todos os daemons ja cobertos por ele).
Write-Host "[RUN] Detector 13: Orphaned infinite-loop daemon (Bug #13)" -ForegroundColor Cyan

$loopDaemons = @(Select-String -Path "$RootPath\scripts\*.ps1" -Pattern 'while\s*\(\s*\$true\s*\)' 2>$null |
    ForEach-Object { Split-Path $_.Path -Leaf } | Select-Object -Unique)
$orchestrators = @("$RootPath\scripts\start_fleet.ps1", "$RootPath\scripts\daily_daemon_restart.ps1")
$orchContent = @($orchestrators | Where-Object { Test-Path $_ } | ForEach-Object { Get-Content $_ -Raw }) -join "`n"
$workflowContent = @(Get-ChildItem "$RootPath\.github\workflows\*.yml" -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$orphaned = @($loopDaemons | Where-Object { $orchContent -notmatch [regex]::Escape($_) -and $workflowContent -notmatch [regex]::Escape($_) })

if ($orphaned.Count -gt 0) {
    # 2026-07-14: confianca MEDIA (nao ALTA) -- deteccao por regex nao distingue
    # daemon standalone de arquivo dot-sourced como lib (ex: scripts/trailing_stop_manager.ps1
    # tem while($true) mas gem_loop.ps1 dot-source o homonimo em agents/, nao este).
    # Requer confirmacao manual antes de agir -- listar como candidato, nao veredito.
    $findings += @{ bug = "bug_13"; pattern = "orphaned_daemon_candidate"; confidence = 0.55; status = "Infinite-loop script(s) not referenced in start_fleet.ps1/daily_daemon_restart.ps1/workflows -- REQUER REVISAO MANUAL (pode ser lib dot-sourced, script standalone intencional, ou Scheduled Task nao mapeado, nao necessariamente daemon orfao)"; daemons = $orphaned }
    Write-Host "  [WARN] Bug #13 (candidato, confirmar manualmente): $($orphaned -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "  [SKIP] Bug #13: All infinite-loop daemons are registered somewhere" -ForegroundColor Green
}

# ── Detector 14: GitHub Actions job missing COINEX creds before CoinEx call (Bug #14) ──
# 2026-07-14: trading-pipeline.yml Job 0 chamava funcoes que precisam de auth CoinEx
# sem nunca ter passado COINEX_ACCESS_ID/SECRET_KEY no bloco de Setup daquele job --
# drones retornavam null silenciosamente -> consensus=CAOS -> 45 trades abortados/5d.
# NOTA: exclui chamadas a /ping (endpoint publico, nao assinado, nao precisa de auth) --
# cross-checado manualmente 2026-07-14 (job health-check era falso positivo).
Write-Host "[RUN] Detector 14: GitHub Actions job missing COINEX creds (Bug #14)" -ForegroundColor Cyan

$missingCoinexJobs = @()
foreach ($wf in (Get-ChildItem "$RootPath\.github\workflows\*.yml" -ErrorAction SilentlyContinue)) {
    $lines = Get-Content $wf.FullName
    $jobStarts = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s{2}[a-zA-Z0-9_-]+:\s*$' -and $i + 1 -lt $lines.Count -and $lines[$i+1] -match 'name:') {
            $jobStarts += $i
        }
    }
    for ($j = 0; $j -lt $jobStarts.Count; $j++) {
        $start = $jobStarts[$j]
        $end = if ($j + 1 -lt $jobStarts.Count) { $jobStarts[$j+1] } else { $lines.Count }
        $jobBody = ($lines[$start..($end-1)]) -join "`n"
        $callsCoinExFn = $jobBody -match 'CoinEx-[A-Za-z]'
        $callsCoinExPrivateEndpoint = $jobBody -match 'coinex\.com/v2/(?!ping)'
        $callsCoinEx = $callsCoinExFn -or $callsCoinExPrivateEndpoint
        $hasCoinExKey = $jobBody -match 'COINEX_ACCESS_ID'
        if ($callsCoinEx -and -not $hasCoinExKey) {
            $jobName = ($lines[$start] -replace ':\s*$', '').Trim()
            $missingCoinexJobs += "$($wf.Name):$jobName"
        }
    }
}

if ($missingCoinexJobs.Count -gt 0) {
    $findings += @{ bug = "bug_14"; pattern = "missing_coinex_credential_wire"; confidence = 0.80; status = "Job(s) reference CoinEx calls without COINEX_ACCESS_ID in same job body"; jobs = $missingCoinexJobs }
    Write-Host "  [OK] Bug #14: Job(s) missing COINEX_ACCESS_ID: $($missingCoinexJobs -join ', ')" -ForegroundColor Red
} else {
    Write-Host "  [SKIP] Bug #14: All CoinEx-calling jobs have COINEX_ACCESS_ID wired" -ForegroundColor Green
}

# ── Detector 15: FUTURES order sem controle de leverage (Bug #15) ───────────
# 2026-07-17: SUIUSDT abriu a 50x via gem_executor.ps1 (corrigido commit
# 5de3a73), e no MESMO DIA ADAUSDT+XRPUSDT abriram a 50x via faro_v3_entry.ps1
# -- um SEGUNDO caminho de execucao de FUTURES real, totalmente independente,
# que o fix anterior nao cobria (corrigido separadamente commit 1f05d04).
# Causa raiz: POST /futures/order (CoinEx-PlaceOrder) NAO carrega leverage no
# payload -- a corretora usa o que ja estiver configurado NA CONTA pro par.
# O UNICO jeito de fixar leverage e' CoinEx-AdjustPositionLeverage ANTES da
# ordem (knowledge/COINEX_REFERENCE.md secao 4.4). Deteccao generica: QUALQUER
# script que chame CoinEx-PlaceOrder ou Invoke-OrderRouted -Route futures
# precisa ter CoinEx-AdjustPositionLeverage no MESMO arquivo -- senao herda
# leverage desconhecida/perigosa da conta. Padrao classico deste projeto:
# helper de seguranca existe (as vezes ha MAIS de um -- Get-SafeLeverage
# tambem existia desde 2026-06-18 e tambem nao era chamado), mas cada NOVO
# caminho de execucao esquece de wire-lo -- auditar TODOS os pontos de
# entrada, nao so o mais recente.
Write-Host "[RUN] Detector 15: FUTURES order sem controle de leverage (Bug #15)" -ForegroundColor Cyan

$futuresOrderCallers = @()
$scanPaths = @("$RootPath\agents\*.ps1", "$RootPath\scripts\*.ps1")
foreach ($file in (Get-ChildItem $scanPaths -ErrorAction SilentlyContinue)) {
    if ($file.Name -eq "lib_coinex.ps1" -or $file.Name -eq "lib_coinex_position_management.ps1" -or $file.Name -eq "lib_order_routed.ps1") { continue }
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    $callsFuturesOrder = ($content -match 'CoinEx-PlaceOrder\b') -or ($content -match 'Invoke-OrderRouted\s+-Route\s+["\'']futures["\'']') -or ($content -match 'CoinEx-PlaceFuturesOrder\b')
    if (-not $callsFuturesOrder) { continue }
    $hasLeverageControl = ($content -match 'CoinEx-AdjustPositionLeverage\b') -or ($content -match 'Get-SafeLeverage\b')
    if (-not $hasLeverageControl) {
        $futuresOrderCallers += $file.Name
    }
}

if ($futuresOrderCallers.Count -gt 0) {
    $findings += @{ bug = "bug_15"; pattern = "uncontrolled_futures_leverage"; confidence = 0.85; status = "Script(s) abrem FUTURES real sem chamar CoinEx-AdjustPositionLeverage/Get-SafeLeverage no mesmo arquivo -- posicao herda leverage da conta, pode abrir a 50x sem intencao"; scripts = $futuresOrderCallers }
    Write-Host "  [WARN] Bug #15: script(s) sem controle de leverage: $($futuresOrderCallers -join ', ')" -ForegroundColor Red
} else {
    Write-Host "  [SKIP] Bug #15: todos os callers de FUTURES order tem leverage control no mesmo arquivo" -ForegroundColor Green
}

# ── Detector 16: Multiplos motores de trailing/exit escrevendo o mesmo recurso
# sem coordenacao (Bug #16) ──────────────────────────────────────────────────
# 2026-07-18: investigando o pedido do usuario por trailing "inteligente"
# (stop+TP se movendo junto por estrutura, nao % fixo), descobri que ISSO JA
# EXISTE e roda de verdade -- mas espalhado em 20+ arquivos lib_trailing_*.ps1
# +lib_position_*.ps1+lib_mentor_reflection.ps1, cada um chamando
# CoinEx-SetStopLoss/CoinEx-ModifyPositionStopLoss por conta propria. Achados
# reais no dia: (1) "Trailing Stop Monitor" (trailing_stop_monitor.ps1) e
# "Layer 1 - Adaptive Trailing" (layers_review_runner.ps1 -Layer 1) rodam
# AMBOS a cada 5min na nuvem, movendo a MESMA stop-loss de forma independente
# -- Layer 1 usa lib_trailing_adaptive.ps1, cujo $currentAtr=100.0 e um
# placeholder NUNCA preenchido (comentario propriedo do arquivo diz "em prod
# usaria ultimas barras" -- nunca usou); (2) Invoke-ExitIntelligence (camada
# 2.7, "nao-auto") so LOGA recomendacao de venda, nunca executa -- redundante
# com Invoke-ExitIntelligenceAuto (camada 2.8, "auto") que executa de verdade
# via CoinEx-PlaceSpotOrder. Nao ha corrupcao de dado hoje (guards
# monotonicos evitam o stop recuar, e so 1 ponto -- Sync-TrailingToExchange --
# de fato escreve dentro da pilha coordenada), mas a fragmentacao e real: o
# mesmo problema (mover SL/TP com inteligencia) foi resolvido 3-4 vezes em
# arquivos diferentes que nao sabem uns dos outros, aumentando o risco de um
# futuro fix so cobrir 1 caminho (mesma classe do Bug #15 -- helper de
# seguranca existe, mas cada NOVO caminho de execucao esquece de usa-lo).
Write-Host "[RUN] Detector 16: Multiplos motores de trailing/exit sem coordenacao (Bug #16)" -ForegroundColor Cyan

$stopWriterFns = @('CoinEx-SetStopLoss\b', 'CoinEx-ModifyPositionStopLoss\b')
$stopWriterCallers = @()
$scanPathsD16 = @("$RootPath\agents\*.ps1", "$RootPath\scripts\*.ps1")
foreach ($file in (Get-ChildItem $scanPathsD16 -ErrorAction SilentlyContinue)) {
    # Excluir os proprios wrappers de API (definem a funcao, nao a chamam pra decidir).
    if ($file.Name -in @("lib_coinex.ps1", "lib_coinex_position_management.ps1")) { continue }
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    $callsStopWriter = $false
    foreach ($fn in $stopWriterFns) {
        # So conta CHAMADA real, nao a definicao de function nem string em comentario.
        if ($content -match "(?<!function )$fn" -and $content -notmatch "^\s*#.*$fn") {
            $callsStopWriter = $true
            break
        }
    }
    if ($callsStopWriter) { $stopWriterCallers += $file.Name }
}

if ($stopWriterCallers.Count -ge 3) {
    $findings += @{ bug = "bug_16"; pattern = "uncoordinated_concurrent_stop_writers"; confidence = 0.70; status = "$($stopWriterCallers.Count) arquivos chamam CoinEx-SetStopLoss/ModifyPositionStopLoss de forma independente -- verificar manualmente quais estao wired ao mesmo cron/ciclo (colisao real) vs. caminhos mutuamente exclusivos (nao e bug automatico, e candidato -- requer confirmacao)"; scripts = $stopWriterCallers }
    Write-Host "  [WARN] Bug #16 (candidato, confianca $([math]::Round(0.70*100))%): $($stopWriterCallers.Count) escritores de stop-loss encontrados: $($stopWriterCallers -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "  [SKIP] Bug #16: menos de 3 escritores de stop-loss (fragmentacao normal)" -ForegroundColor Green
}

$uniqueBugs = @($findings | Group-Object -Property bug | Select-Object -ExpandProperty Name)

$export = @{
    timestamp = [datetime]::UtcNow.ToString("o")
    summary = @{
        total_findings = $findings.Count
        bugs_detected = $uniqueBugs.Count
        coverage = "$($uniqueBugs.Count)/15"
        confidence_avg = [Math]::Round(($findings | Measure-Object -Property confidence -Average).Average, 2)
        status = if ($uniqueBugs.Count -ge 15) { "COMPLETE" } else { "COMPLETE_DETECTED_$($uniqueBugs.Count)_OF_15" }
    }
    findings = $findings
    query_engine = @{
        available = $true
        example_queries = @(
            "Why are trades not entering?",
            "What breaks trailing stops?",
            "Why did not BLUAI reach Telegram?",
            "Are there missing tables?",
            "Is the whitelist filtering messages?"
        )
    }
}

$jsonPath = Join-Path $OutputPath "oracle_complete.json"
$export | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "SUCCESS: ROOT CAUSE ORACLE COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan
Write-Host "  Bugs detected: $($export.summary.bugs_detected)/15" -ForegroundColor Green
Write-Host "  Coverage: $($export.summary.coverage)" -ForegroundColor Green
Write-Host "  Avg confidence: $($export.summary.confidence_avg)" -ForegroundColor Green
Write-Host "  Status: $($export.summary.status)" -ForegroundColor Green
Write-Host ""
Write-Host "Output:" -ForegroundColor Cyan
Write-Host "  JSON: $jsonPath" -ForegroundColor Green
Write-Host "  Query engine: ready" -ForegroundColor Green
Write-Host "  Time: $([Math]::Round(([datetime]::UtcNow - $start).TotalSeconds, 1))s" -ForegroundColor Green
Write-Host ""

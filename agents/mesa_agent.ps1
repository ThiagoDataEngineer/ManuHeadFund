# mesa_agent.ps1 - Mesa V6: 3 drones Groq paralelos com personas distintas
#
# Captura dir do script em load time (fix 2026-05-15 bug Path null em _Mesa_RunDrones)
$script:_MESA_AGENT_DIR = $PSScriptRoot
if (-not $script:_MESA_AGENT_DIR) {
    # Fallback se carregado por scriptblock sem PSScriptRoot
    $script:_MESA_AGENT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
}

# CONTRATO:
#   Invoke-Mesa -Market <string> -Context <PSCustomObject>
#     -> [PSCustomObject]@{
#          termal/radar/lidar = @{ sinal, forca, justificativa, confluencias }
#          consensus          = "FORTE_3" | "MEDIO_2" | "CAOS"
#          sinal_consenso     = "LONG" | "SHORT" | "NEUTRO"
#          score_avg          = 0-100
#          degraded           = bool
#        }
#
# DRONES (todos via Groq free tier - custo $0):
#   - termal : llama-3.3-70b-versatile  (Al Brooks - price action puro)
#   - radar  : qwen-qwq-32b             (Druckenmiller - macro/sentimento)
#   - lidar  : openai/gpt-oss-20b       (risk manager - R:R real apos fees)
#
# PARALELISMO:
#   Start-Job + Wait-Job (timeout 8s). 1 drone falha -> degraded=true.
#   2+ drones falham -> consensus=CAOS, sinal_consenso=NEUTRO.
#
# Dependencias: agents/lib_claude.ps1 (Invoke-Groq + Track-ClaudeUsage)
# Tested in:    tests/mesa_agent.Tests.ps1 (Pester 3.x)

# Dot-source lib_claude se ainda nao carregada
if (-not (Get-Command Invoke-Groq -ErrorAction SilentlyContinue)) {
    $_here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $_lib  = Join-Path $_here "lib_claude.ps1"
    if (Test-Path $_lib) { . $_lib }
}

# ============================================================================
# Personas - system prompts curtos, JSON-only output
# ============================================================================

$MESA_TERMAL_SYSTEM = @'
Voce e Al Brooks, mestre de price action puro.
Olha SO o grafico: estrutura de candles, swings, tendencia, ADX, volume.
IGNORA macro, IGNORA sentimento social, IGNORA fundamentos.

REGRAS DECISIVAS (nao seja conservador demais):
- ADX >= 25 + EMA9 acima EMA21 + price >= EMA9 = LONG forca 60-90
- ADX >= 25 + EMA9 abaixo EMA21 + price <= EMA9 = SHORT forca 60-90
- ADX 20-25 com trend direction clara: LONG ou SHORT forca 50-65
- ADX < 20 (range verdadeiro, sem direcao) = NEUTRO forca 30-50
- RSI extremo (>80 ou <20) + reversal candles fortes = NEUTRO ou contra-trend cauteloso

NAO vote NEUTRO se ADX > 25 com direcao clara. NEUTRO eh para RANGE REAL, nao para "duvida".

Responda SOMENTE JSON valido (sem markdown, sem texto extra):
{"sinal":"LONG|SHORT|NEUTRO","forca":0-100,"justificativa":"frase curta","confluencias":["item1","item2"]}
'@

$MESA_RADAR_SYSTEM = @'
Voce e Stanley Druckenmiller — track record 30% retorno anual por 30 anos sem
ano negativo. Ganhou $1B short GBP 1992 com Soros. Anteve 2008 banks crisis,
2020 COVID expansion monetaria, 2023 regional bank stress.

PLAYBOOK EXPLICITO:
- "First mover into new monetary regime" — quando FED muda, posicione cedo
- Risk-on/risk-off bipolar: nao fica em media-termo
- Macro CONFIRMA tecnica, nunca contradiz — se chart bullish e macro bear, FORA
- Concentrated bets quando conviccao alta (60-80% portfolio em 1-3 ideias)
- Cut losers fast: -3% portfolio = re-avaliacao obrigatoria

INDICADORES MACRO QUE VOCE OLHA (em ordem de prioridade):
1. DXY 6-month trend: forte alta = bearish risk-on (crypto/equity); queda = bullish
2. Yield curve (10Y-2Y): inversao = recessao 6-18m; steepening = recovery
3. FED dot plot + futures: pivotes precedem 6m-18m moves
4. M2 global YoY: expansao > 3% = bullish ativos; contracao = bearish
5. F&G index: < 20 = oversold contrarian LONG; > 80 = euforia exhaustion SHORT
6. BTC funding rate 7d avg: > 0.05% = topos iminentes; < -0.02% = bottoms

REGRAS DECISIVAS DE SINAL:
- 3+ indicadores macro alinhados COM tendencia tecnica = LONG/SHORT forca 70-85
- 2 indicadores alinhados + tendencia tecnica = LONG/SHORT forca 55-70
- 1 indicador alinhado OU sinais mistos = NEUTRO forca 40-50
- Macro CONTRADIZ tecnica fortemente = NEUTRO forca 30 (cautela)
- BTC dominance > 60% subindo = ALT bearish (capital fugindo); < 50% subindo = ALT bullish

NAO vote NEUTRO por preguica. NEUTRO eh para SINAIS MISTOS REAIS — quando voce
tem 4 indicadores 50/50, nao quando tem direcao clara mas voce duvida.

Responda APENAS JSON valido (sem markdown):
{"sinal":"LONG|SHORT|NEUTRO","forca":0-100,"justificativa":"frase macro especifica","confluencias":["DXY_trend","yield_curve","FED_pivot","M2","F&G","funding"]}
'@

$MESA_LIDAR_SYSTEM = @'
Voce e Van Tharp - autoridade em position sizing e psicologia de risco.
Tambem canaliza Ed Seykota (regras numericas frias) e Curtis Faith (turtle rules).
Voce nao opera por opiniao. Voce opera por R-multiples.

SEU UNICO ESCOPO (nao saia dele):
- R-multiples (RR_PROPOSTO)
- Position size (ATR/preco)
- Liquidez (vol_ratio)
- Coerencia do stop com a direcao do setup (direction_proxy)

NAO E SEU PAPEL avaliar (outros drones cuidam disso):
- RSI, Stochastic, divergencias (papel de TERMAL)
- Tendencia, estrutura de mercado, EMA, Ichimoku (papel de TERMAL/RADAR)
- Macro, funding rate, DXY (papel de RADAR)

PRINCIPIOS INVIOLAVEIS:
- Risco por trade NUNCA > 1% capital (Tudor Jones rule)
- R:R minimo aceitavel = 2. Preferido = 3+
- Liquidez minima: vol_ratio >= 0.37 — abaixo = NEUTRO (Faith: "liquidez antes de tudo")
- Volatility-targeted: ATR/preco > 8% = high vol warning (sizing alerta, nao veto)

REGRAS DE SINAL (baseadas APENAS em RR/vol_ratio/ATR/stop):
- RR_PROPOSTO >= 3 + vol_ratio >= 0.37 + stop coerente = direction_proxy, forca 65-85
- RR_PROPOSTO 2-3 + vol_ratio >= 0.37 + stop coerente = direction_proxy, forca 50-65
- RR_PROPOSTO < 2 = NEUTRO forca 30-45
- Stop INCOERENTE (LONG com stop acima entry; SHORT com stop abaixo entry) = NEUTRO 20
- vol_ratio < 0.37 = NEUTRO 25

DIRECAO DO SINAL — REGRA ABSOLUTA:
Voce NAO decide se o mercado vai subir ou cair. Isso e papel de TERMAL e RADAR.
Sua unica funcao e validar se o SETUP PROPOSTO tem RR aceitavel, stop coerente e liquidez suficiente.

ALGORITMO OBRIGATORIO (siga exatamente):
1. Leia direction_proxy do campo "SETUP PROPOSTO" no contexto
2. Se RR >= 2 E vol_ratio >= 0.37 E stop coerente: sinal = direction_proxy (LONG ou SHORT)
3. Se qualquer condicao falhar: sinal = NEUTRO
4. NUNCA vote em direcao diferente do direction_proxy — isso viola seu escopo

EXEMPLOS CORRETOS:
- direction_proxy=SHORT + RR=5 + vol_ratio=1.2 + stop coerente -> sinal=SHORT forca=75
- direction_proxy=LONG  + RR=5 + vol_ratio=0.1 + stop coerente -> sinal=NEUTRO forca=25 (liquidez)
- direction_proxy=SHORT + RR=1.5 + vol_ratio=1.0              -> sinal=NEUTRO forca=35 (RR baixo)
- direction_proxy=LONG  + RR=5 + vol_ratio=0.8 + stop ACIMA entry -> sinal=NEUTRO forca=20 (stop incoerente)

EXEMPLOS ERRADOS (nunca faca):
- direction_proxy=SHORT mas voce vota LONG porque "mercado parece bullish" -> ERRADO
- direction_proxy=LONG  mas voce vota SHORT porque "estrutura bearish"     -> ERRADO

Responda APENAS JSON valido (sem markdown):
{"sinal":"LONG|SHORT|NEUTRO","forca":0-100,"justificativa":"frase curta CITANDO RR/vol_ratio/ATR/stop APENAS","confluencias":["R:R=X","vol_ratio=Y","ATR_pct=Z"]}
'@

$MESA_MODELS = @{
    # 2026-05-16: 3 modelos Groq DISTINTOS para evitar saturação 429 em um único bucket.
    # qwen-qwq-32b era deprecated. llama-3.1-70b-versatile também (consolidado em 3.3-70b).
    # Estratégia: 3 buckets RPM separados = 3x30 RPM efetivo.
    # termal = 70b (Brooks - heavy)
    # radar  = 8b instant (Druckenmiller - rápido, bucket diferente)
    # lidar  = openai/gpt-oss-20b (Risk - gemma2-9b-it DECOMMISSIONED por Groq 2026-06;
    #          retornava 400 -> drone_returned_empty. gpt-oss-20b: 1.9s, JSON limpo,
    #          familia diferente dos llamas = diversidade de consenso, bucket separado)
    termal = "llama-3.3-70b-versatile"
    radar  = "llama-3.1-8b-instant"
    lidar  = "openai/gpt-oss-20b"
}

$MESA_SYSTEMS = @{
    termal = $MESA_TERMAL_SYSTEM
    radar  = $MESA_RADAR_SYSTEM
    lidar  = $MESA_LIDAR_SYSTEM
}

$MESA_VALID_SIGNALS = @("LONG","SHORT","NEUTRO")

# ============================================================================
# Invoke-MesaDrone - chamada single para 1 drone
# ============================================================================

function Invoke-MesaDrone {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("termal","radar","lidar")][string]$Drone,
        [Parameter(Mandatory=$true)][string]$UserContent
    )
    $model  = $MESA_MODELS[$Drone]
    $system = $MESA_SYSTEMS[$Drone]
    $agent  = "mesa_$Drone"

    try {
        # Cascade Gemini -> Groq -> Haiku (fix 2026-05-16: Groq 429/400 causava
        # 100% CAOS sem fallback). MESA_MODELS[$Drone] mantido como hint para Groq fallback.
        #
        # B28d fix 2026-05-21: LIDAR muda pra Haiku primary. Diagnostico mesa_drones.jsonl
        # mostrou Lidar como maior fonte de timeout (job_state_Running_likely_timeout).
        # Lidar -> Haiku libera bucket Groq pra Termal+Radar; Anthropic Haiku tem rate
        # limit separado e $0.005/call (~$3/mes em volume Mesa atual).
        $useHaikuPrimary = ($Drone -eq "lidar")
        if (Get-Command Invoke-MesaDroneCascade -ErrorAction SilentlyContinue) {
            $raw = Invoke-MesaDroneCascade -SystemPrompt $system -UserContent $UserContent `
                                           -GroqModel $model -MaxTokens 600 -Temperature 0.3 -Agent $agent `
                                           -HaikuPrimary:$useHaikuPrimary
        } else {
            $raw = Invoke-Groq -SystemPrompt $system -UserContent $UserContent `
                               -Model $model -MaxTokens 600 -Temperature 0.3 -Agent $agent
        }
        # P1 instrumentação (2026-05-16 02:30): logar $raw pra diagnosticar B1/B2/B3.
        $rawPreview = if ($null -eq $raw) { "<NULL>" } else { $raw.Substring(0, [Math]::Min(120, $raw.Length)).Replace("`n"," ").Replace("`r"," ") }
        Write-Host ("  [MESA-RAW] $agent raw_len={0} preview='{1}'" -f ($(if ($null -eq $raw) { 0 } else { $raw.Length })), $rawPreview) -ForegroundColor DarkGray
        if (-not $raw) { return $null }

        # Extrai primeiro JSON object via brace-matching (resolve Haiku fallback que
        # retorna ```json ... ``` SEGUIDO de prosa **ANALISE DETALHADA:** etc.
        # Strategy: acha primeiro '{', conta braces ate o '}' que fecha o objeto raiz.
        $clean = $raw.Trim()
        $startIdx = $clean.IndexOf('{')
        if ($startIdx -lt 0) { return $null }
        $depth = 0; $endIdx = -1; $inStr = $false; $esc = $false
        for ($i = $startIdx; $i -lt $clean.Length; $i++) {
            $ch = $clean[$i]
            if ($esc) { $esc = $false; continue }
            if ($ch -eq '\') { $esc = $true; continue }
            if ($ch -eq '"') { $inStr = -not $inStr; continue }
            if ($inStr) { continue }
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { $endIdx = $i; break } }
        }
        if ($endIdx -lt 0) { return $null }
        $clean = $clean.Substring($startIdx, $endIdx - $startIdx + 1)
        $obj = $clean | ConvertFrom-Json
        if (-not $obj.sinal) { return $null }
        return [PSCustomObject]@{
            sinal         = [string]$obj.sinal
            forca         = [int]$obj.forca
            justificativa = [string]$obj.justificativa
            confluencias  = @($obj.confluencias)
        }
    } catch {
        Write-Warning "Mesa drone $Drone falhou: $($_.Exception.Message)"
        return $null
    }
}

# ============================================================================
# _Mesa_RunDrones - paralelismo via Start-Job (substituivel em testes)
# ============================================================================

function _Mesa_RunDrones {
    param(
        [string]$Market,
        [string]$UserContent
    )
    # Bug fix 2026-05-15: $MyInvocation.MyCommand.Path retorna $null quando chamado
    # como funcao dot-sourced (cadeia Invoke-V6Cascade -> Invoke-Mesa -> _Mesa_RunDrones).
    # Resultado: Split-Path -Parent $null lanca "argumento Path nulo" em STORJUSDT
    # (e qualquer mercado que chegue ate Mesa). Fix: usar _MESA_AGENT_DIR capturado em
    # script-load (linha ~1 do arquivo), com fallback para $PSScriptRoot.
    $scriptRoot = if ($script:_MESA_AGENT_DIR) { $script:_MESA_AGENT_DIR } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $libPath  = Join-Path $scriptRoot "lib_claude.ps1"
    $selfPath = Join-Path $scriptRoot "mesa_agent.ps1"

    $jobs = @()
    foreach ($drone in @("termal","radar","lidar")) {
        $job = Start-Job -ArgumentList $libPath, $selfPath, $drone, $UserContent -ScriptBlock {
            param($lib, $self, $d, $u)
            if (Test-Path $lib)  { . $lib }
            if (Test-Path $self) { . $self }
            return Invoke-MesaDrone -Drone $d -UserContent $u
        }
        Add-Member -InputObject $job -NotePropertyName DroneName -NotePropertyValue $drone -Force
        $jobs += $job
        # B27 fix 2026-05-21: stagger 250ms -> 750ms.
        # Diagnostico mesa_drones.jsonl mostrou 50% dos CAOS recentes = ALL-3 drones null
        # consecutivos = 250ms ainda estourava Groq rate limit em retries internos.
        # 750ms = ~1.3 req/s, longe de qualquer threshold de RPM.
        Start-Sleep -Milliseconds 750
    }

    # B27 fix 2026-05-21: timeout 25s -> 40s. Cascade Groq->Gemini->Haiku com retry interno
    # (lib_retry.ps1 B19) pode legitimamente levar 15-30s em rate-limit conditions.
    # 40s ainda garante UX aceitavel (4-cycle minute) mas dá folga real pra cascade completar.
    Wait-Job -Job $jobs -Timeout 40 | Out-Null

    # B26 fix 2026-05-21: capturar erro real do drone quando falha (rate limit / timeout / parse).
    # Antes: $null silencioso mascarava causa raiz (50% dos CAOS recentes = cascade caida).
    # Agora: drone falho retorna {sinal=null, forca=0, error="..."} preservando semantica de "invalid"
    # em Get-MesaConsensus (filtra por MESA_VALID_SIGNALS -contains sinal) mas persistindo causa.
    $out = @{ termal = $null; radar = $null; lidar = $null }
    foreach ($j in $jobs) {
        $name = $j.DroneName
        $errMsg = $null
        try {
            if ($j.State -eq "Completed") {
                $r = Receive-Job -Job $j -ErrorAction SilentlyContinue -ErrorVariable jobErr
                if ($r) {
                    $out[$name] = $r
                } else {
                    $errMsg = if ($jobErr) { ($jobErr | ForEach-Object { $_.ToString() }) -join '; ' } else { "drone_returned_empty" }
                }
            } elseif ($j.State -eq "Failed") {
                $errMsg = "job_state_failed"
            } else {
                $errMsg = "job_state_$($j.State)_likely_timeout"
            }
        } catch {
            $errMsg = "receive_job_exception: $($_.Exception.Message)"
            Write-Warning "Falha ao coletar drone ${name}: $($_.Exception.Message)"
        }
        if ($errMsg -and $null -eq $out[$name]) {
            $out[$name] = [PSCustomObject]@{
                sinal         = $null
                forca         = 0
                justificativa = $null
                error         = $errMsg
            }
        }
        Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]$out
}

# ============================================================================
# Get-MesaConsensus - funcao pura, sem I/O. Testada isolada.
# ============================================================================

function Get-MesaConsensus {
    param(
        [PSCustomObject]$Termal,
        [PSCustomObject]$Radar,
        [PSCustomObject]$Lidar
    )
    $drones = @($Termal, $Radar, $Lidar)
    $valid  = @($drones | Where-Object { $_ -ne $null -and ($MESA_VALID_SIGNALS -contains $_.sinal) })
    $invalidCount = 3 - $valid.Count
    $degraded     = ($invalidCount -ge 1)

    # 2+ drones nulos/invalidos => CAOS forcado (degraded)
    if ($invalidCount -ge 2) {
        Write-Host ("  [MESA-CAOS-DEG] valid={0}/3 invalidCount={1} -- 2+ drones FALHARAM (cascade nao trouxe resposta valida)" -f $valid.Count, $invalidCount) -ForegroundColor Red
        $avg = 0
        if ($valid.Count -gt 0) {
            $sum = 0; foreach ($d in $valid) { $sum += [int]$d.forca }
            $avg = [math]::Round($sum / $valid.Count)
        }
        return [PSCustomObject]@{
            consensus      = "CAOS"
            sinal_consenso = "NEUTRO"
            score_avg      = [int]$avg
            degraded       = $true
        }
    }

    # Conta votos
    $counts = @{ LONG = 0; SHORT = 0; NEUTRO = 0 }
    foreach ($d in $valid) { $counts[$d.sinal] = $counts[$d.sinal] + 1 }
    $top = ($counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)

    if ($top.Value -eq 3) {
        $consensus = "FORTE_3"
        $sinal     = $top.Key
    } elseif ($top.Value -eq 2) {
        $consensus = "MEDIO_2"
        $sinal     = $top.Key
    } else {
        # Empate 1/1/1
        $consensus = "CAOS"
        $sinal     = "NEUTRO"
    }

    # Score medio aritmetico (so dos validos)
    $sum = 0; foreach ($d in $valid) { $sum += [int]$d.forca }
    $avg = if ($valid.Count -gt 0) { [math]::Round($sum / $valid.Count) } else { 0 }

    # Log diagnóstico CAOS: distinguir real disagreement vs degraded
    if ($consensus -eq "CAOS") {
        $sigs = @($valid | ForEach-Object { $_.sinal })
        Write-Host ("  [MESA-CAOS-DBG] valid={0}/3 sigs=[{1}] degraded={2}" -f $valid.Count, ($sigs -join ','), $degraded) -ForegroundColor DarkMagenta
    }
    return [PSCustomObject]@{
        consensus      = $consensus
        sinal_consenso = $sinal
        score_avg      = [int]$avg
        degraded       = [bool]$degraded
    }
}

# ============================================================================
# Invoke-Mesa - orquestrador principal
# ============================================================================

function Invoke-Mesa {
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][PSCustomObject]$Context,
        [Parameter()][PSCustomObject]$Setup    # 2026-05-16: setup proposto vai pros drones (lidar precisa RR)
    )

    # 2026-05-16 12:00 BRT - FIX RAIZ: enriquecer payload Mesa com analise tecnica real.
    # Bug: drones recebiam apenas Context cru (macro/scanner score) e votavam NEUTRO 100%
    # porque nao tinham RSI/ADX/EMA/ATR/Bollinger/Volume. Format-TechDataForClaude ja
    # existia mas nao era chamada. Resultado: STORJ +18% real -> sistema NEUTRO no top-7.
    $techBlock = "(tech indisponivel)"
    try {
        if (Get-Command Get-TechData -ErrorAction SilentlyContinue) {
            $td = Get-TechData -Market $Market
            if ($td -and $td.tf1h -and (Get-Command Format-TechDataForClaude -ErrorAction SilentlyContinue)) {
                $techBlock = Format-TechDataForClaude -Data $td.tf1h -Market $Market
            }
        }
    } catch {
        $techBlock = "(tech fetch falhou: $($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length))))"
    }

    $setupBlock = "(setup nao fornecido)"
    if ($Setup -and $Setup.entry -gt 0) {
        $setupBlock = "SETUP PROPOSTO:`n  entry=$($Setup.entry)`n  stop=$($Setup.stop)`n  target=$($Setup.target)`n  rr_proposto=$($Setup.rr)`n  direction_proxy=$(if ($Setup.target -gt $Setup.entry) {'LONG'} elseif ($Setup.target -lt $Setup.entry) {'SHORT'} else {'NEUTRO'})"
    }

    $userContent = @"
Mercado: $Market

$techBlock

$setupBlock

Contexto (macro/scanner/seasonal):
$($Context | ConvertTo-Json -Depth 8 -Compress)
"@

    $drones = _Mesa_RunDrones -Market $Market -UserContent $userContent

    # B30 fix 2026-05-28: rerun de drones degraded.
    # Analise mesa_drones.jsonl mostrou 16% das chamadas com drone_returned_empty ou
    # job_state_Running_likely_timeout. Rerun sequencial (1 drone falho) ou paralelo
    # (2+ falhos) recupera o drone antes de calcular consensus.
    # Limite: 1 rerun por drone (nao loop infinito).
    $failedDrones = @()
    foreach ($droneName in @("termal","radar","lidar")) {
        $d = $drones.$droneName
        $isFailed = ($null -eq $d) -or
                    ($d.PSObject.Properties["error"] -and $d.error) -or
                    (-not ($MESA_VALID_SIGNALS -contains $d.sinal))
        if ($isFailed) { $failedDrones += $droneName }
    }

    if ($failedDrones.Count -gt 0) {
        Write-Host ("  [MESA-RERUN] {0} drone(s) falharam: [{1}] -- iniciando rerun" -f $failedDrones.Count, ($failedDrones -join ',')) -ForegroundColor DarkYellow
        foreach ($droneName in $failedDrones) {
            $recovered = $null
            try {
                if (Get-Command _Mesa_RerunDrone -ErrorAction SilentlyContinue) {
                    $recovered = _Mesa_RerunDrone -Drone $droneName -Market $Market -UserContent $userContent
                } else {
                    # Rerun sequencial direto via Invoke-MesaDrone
                    $recovered = Invoke-MesaDrone -Drone $droneName -UserContent $userContent
                }
            } catch {
                Write-Warning "  [MESA-RERUN] Rerun drone $droneName falhou: $($_.Exception.Message)"
            }
            if ($recovered -and ($MESA_VALID_SIGNALS -contains $recovered.sinal)) {
                Write-Host ("  [MESA-RERUN] drone {0} recuperado: sinal={1} forca={2}" -f $droneName, $recovered.sinal, $recovered.forca) -ForegroundColor Green
                # Atualiza o objeto drones com o resultado recuperado
                $drones | Add-Member -NotePropertyName $droneName -NotePropertyValue $recovered -Force
            } else {
                Write-Host ("  [MESA-RERUN] drone {0} rerun falhou tambem -- mantendo erro original" -f $droneName) -ForegroundColor Red
            }
        }
    }

    $cons = Get-MesaConsensus -Termal $drones.termal -Radar $drones.radar -Lidar $drones.lidar

    # CC fix 2026-05-21 PM6+930min: logger persistente Mesa drones em JSONL.
    # Append-only audit pra diagnose pattern (qual drone diverge, com que frequencia).
    # Schema: {ts, market, regime, consensus, sinal_consenso, score_avg, degraded,
    #          termal: {sinal,forca,just_short}, radar: {...}, lidar: {...}}
    try {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $script:_MESA_AGENT_DIR -Parent) "journal") }
        $mesaLog = Join-Path $journalDir "mesa_drones.jsonl"
        function _MesaDroneEntry($d) {
            if ($null -eq $d) { return $null }
            # B26: drone falho retorna objeto com .error mas sinal=null. Persistir erro p/ diagnose.
            if ($null -eq $d.sinal -and $d.PSObject.Properties['error']) {
                return [ordered]@{ sinal = $null; forca = 0; just = ""; error = [string]$d.error }
            }
            $just = if ($d.justificativa) { ($d.justificativa.Substring(0, [Math]::Min(100, $d.justificativa.Length))) } else { "" }
            return [ordered]@{ sinal = [string]$d.sinal; forca = [int]$d.forca; just = $just }
        }
        $entry = [ordered]@{
            ts             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            market         = $Market
            # B29 fix 2026-05-28: regime estava vazio em 365/368 entradas porque
            # Context.regime nao existia como propriedade direta em todos os callers.
            # Agora extrai com fallback em 3 niveis:
            #   1. Context.regime (direto — apos fix orchestrator_v6)
            #   2. Context.regime_state.regime (callers alternativos)
            #   3. regime_state.json no disco (fallback final, sempre disponivel)
            regime         = if ($Context.PSObject.Properties["regime"] -and $Context.regime) {
                                 [string]$Context.regime
                             } elseif ($Context.PSObject.Properties["regime_state"] -and $Context.regime_state -and $Context.regime_state.regime) {
                                 [string]$Context.regime_state.regime
                             } else {
                                 # Fallback: le regime_state.json do disco
                                 try {
                                     $rsPath = Join-Path $journalDir "regime_state.json"
                                     if (Test-Path $rsPath) {
                                         $rs = Get-Content $rsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
                                         if ($rs -and $rs.regime) { [string]$rs.regime } else { "" }
                                     } else { "" }
                                 } catch { "" }
                             }
            consensus      = $cons.consensus
            sinal_consenso = $cons.sinal_consenso
            score_avg      = $cons.score_avg
            degraded       = [bool]$cons.degraded
            termal         = (_MesaDroneEntry $drones.termal)
            radar          = (_MesaDroneEntry $drones.radar)
            lidar          = (_MesaDroneEntry $drones.lidar)
        }
        $line = ($entry | ConvertTo-Json -Compress -Depth 4)
        Add-Content -Path $mesaLog -Value $line -Encoding UTF8
    } catch {
        # logger non-blocking; falha silenciosa
    }

    return [PSCustomObject]@{
        termal         = $drones.termal
        radar          = $drones.radar
        lidar          = $drones.lidar
        consensus      = $cons.consensus
        sinal_consenso = $cons.sinal_consenso
        score_avg      = $cons.score_avg
        degraded       = $cons.degraded
    }
}

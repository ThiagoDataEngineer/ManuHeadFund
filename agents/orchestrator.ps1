# orchestrator.ps1 — Pipeline completo: todos os agentes + MentorAgent veto
# Fluxo: Tech(40%) -> Fund(15%) -> Sent(20%) -> Chain(25%) -> MacroCtx -> Score -> Mentor -> Decisao
# Pesos baseados em AGENTS.md (GlobalAgent extinto — macro via lib_macro.ps1)
param(
    [string]$Market = "BTCUSDT",
    [switch]$DryRun,
    [switch]$SkipFund,
    [switch]$SkipSent,
    [switch]$SkipChain,
    [switch]$SkipMentor,
    [switch]$AutoApprove   # apenas para testes automatizados — nunca usar em producao real
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding             = [System.Text.Encoding]::UTF8
$null = cmd /c chcp 65001 2`>nul

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "lib_claude.ps1")
. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_macro.ps1")
. (Join-Path $PSScriptRoot "lib_indicators.ps1")
. (Join-Path $PSScriptRoot "lib_seasonality.ps1")
. (Join-Path $PSScriptRoot "tech_agent_ai.ps1")
. (Join-Path $PSScriptRoot "fund_agent.ps1")
. (Join-Path $PSScriptRoot "sent_agent.ps1")
. (Join-Path $PSScriptRoot "chain_agent.ps1")
. (Join-Path $PSScriptRoot "mentor_agent.ps1")
. (Join-Path $PSScriptRoot "position_sizer.ps1")
. (Join-Path $PSScriptRoot "lib_telegram.ps1")

# Pesos ativos — selecionados por macro_bias em runtime (WEIGHTS_BULL/BEAR/NEUTRAL em config.ps1)
# $w e definido apos Get-MacroContext; este bloco e apenas documentacao dos defaults
$AGENT_WEIGHTS = $WEIGHTS_NEUTRAL

function Convert-SinalToScore {
    param([string]$Sinal, [double]$Forca = 50)
    # Converte sinal direcional + forca em score 0-100 para o alvo LONG
    switch ($Sinal) {
        "LONG"    { return [math]::Round(50 + $Forca * 0.5, 0) }     # 50-100
        "SHORT"   { return [math]::Round(50 - $Forca * 0.5, 0) }     # 0-50
        "NEUTRO"  { return 50 }
        default   { return 50 }
    }
}

function Get-SentScore {
    param([object]$SentResult)
    if (-not $SentResult) { return 50 }
    $base = switch ($SentResult.sentimento) {
        "BULLISH" { 50 + $SentResult.intensidade * 0.5 }
        "BEARISH" { 50 - $SentResult.intensidade * 0.5 }
        default   { 50 }
    }
    # Ajuste contrarian: se contrarian_signal = true, inverte o sinal
    if ($SentResult.contrarian_signal -eq $true) { $base = 100 - $base }
    return [math]::Round([math]::Max(0, [math]::Min(100, $base)), 0)
}

function Get-FundScore {
    param([object]$FundResult)
    if (-not $FundResult) { return 50 }
    $base = $FundResult.score_fundamental
    # Penaliza se macro bearish
    if ($FundResult.macro_outlook -eq "BEARISH") { $base = $base * 0.8 }
    if ($FundResult.recomendacao -eq "EVITAR") { $base = [math]::Min($base, 30) }
    if ($FundResult.recomendacao -eq "ACUMULAR") { $base = [math]::Max($base, 60) }
    return [math]::Round([math]::Max(0, [math]::Min(100, $base)), 0)
}

function Get-ChainScore {
    param([object]$ChainResult)
    if (-not $ChainResult) { return 50 }
    $base = $ChainResult.chain_score
    if ($ChainResult.chain_bias -eq "BEARISH") { $base = [math]::Min($base, 40) }
    if ($ChainResult.nupl_fase -eq "EUFORIA") { $base = [math]::Min($base, 35) }
    if ($ChainResult.nupl_fase -eq "CAPITULACAO") { $base = [math]::Max($base, 65) }
    return [math]::Round([math]::Max(0, [math]::Min(100, $base)), 0)
}

function Invoke-OrchestratorAgent {
    param(
        [string]$Market         = "BTCUSDT",
        [switch]$SkipFund,
        [switch]$SkipSent,
        [switch]$SkipChain,
        [switch]$SkipMentor,
        [switch]$DryRun          # Nao executa ordem, apenas analisa
    )

    $startTime = Get-Date
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     ORCHESTRATOR — PIPELINE COMPLETO              ║" -ForegroundColor Cyan
    Write-Host "║     $Market | $(Get-Date -Format 'yyyy-MM-dd HH:mm')              ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # ── FASE 0: Verificar seguranca do mercado + taxas reais ─────────────────

    Write-Host "[0/6] Verificando mercado CoinEx..." -ForegroundColor DarkGray
    $mktInfo = CoinEx-GetMarketInfo $Market
    if ($mktInfo -and -not $mktInfo.isSafe) {
        $noticeText = $mktInfo.notices -join " | "
        Write-Host "  AVISO DE MERCADO: $noticeText" -ForegroundColor Red
        Write-Host "  Status: $($mktInfo.status) — pipeline abortado por seguranca." -ForegroundColor Red
        return [PSCustomObject]@{
            market   = $Market; decisao  = "ABORTAR"
            motivo   = "Mercado com restricao ou notice de risco: $noticeText"
            timestamp= (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
    }
    if ($mktInfo) {
        $leverageInfo = if ($mktInfo.maxLeverage) { " | MaxLev=$($mktInfo.maxLeverage)x MaintMargin=$($mktInfo.maintMarginRate)" } else { "" }
        Write-Host "  Status: $($mktInfo.status)$leverageInfo" -ForegroundColor DarkGray
    }

    $feeCtx = CoinEx-GetFeeContext $Market
    Write-Host "  Fees: maker=$($feeCtx.makerRate*100)% taker=$($feeCtx.takerRate*100)% round-trip=$($feeCtx.roundTrip)% | funding8h=$($feeCtx.funding8h)% holdCost24h=$($feeCtx.holdCost24h)% [$($feeCtx.source)]" -ForegroundColor DarkGray

    # Capital FUTURES real — Orchestrator opera apenas futuros com alavancagem
    $capitalReal = CoinEx-GetFuturesCapitalUSDT
    Write-Host "  Capital futures: $capitalReal USDT (tempo real)" -ForegroundColor DarkGray

    # ── FASE 0.5: Macro Context (FRED, cache 24h, zero Claude) ───────────────

    Write-Host "[0.5/6] MacroContext (FRED, cache 24h)..." -ForegroundColor DarkGray
    $macro = Get-MacroContext
    Write-Host "  Macro: $($macro.macro_bias) | Score: $($macro.score) | DXY: $($macro.dxy_trend) | M2: $($macro.m2_trend) | Yield: $($macro.yield_curve) | Fed: $($macro.fed_funds_rate)% [$($macro.source)]" -ForegroundColor DarkGray

    # Pesos adaptativos conforme regime macro
    $w = switch ($macro.macro_bias) {
        "BULLISH"  { $WEIGHTS_BULL }
        "BEARISH"  { $WEIGHTS_BEAR }
        default    { $WEIGHTS_NEUTRAL }
    }
    Write-Host "  Pesos ativos [$($macro.macro_bias)]: Tech=$([int]($w.Tech*100))% Chain=$([int]($w.Chain*100))% Sent=$([int]($w.Sent*100))% Fund=$([int]($w.Fund*100))%" -ForegroundColor DarkGray

    # ── BTC Tech Regime (camada tecnica BTC, complementa macro FRED) ──────────
    $btc = Get-BtcTechRegime
    Write-Host "  BTC regime: $($btc.regime) | $($btc.reason)" -ForegroundColor DarkGray

    # 2026-05-25: Em BEAR, sistema agora preferencia SHORTs em vez de bloquear.
    # Anterior: BEAR -> ABORTAR (zero trades em mercado bear).
    # Agora: BEAR -> bias SHORT, capital reduzido 50%, paper acumula historico.
    # LIVE mode ainda exige confirmacao manual via Telegram.
    $btcBiasOverride = $null
    if ($btc.regime -eq "BEAR") {
        Write-Host "  BTC BEAR: prefereciando SHORTs, capital reduzido a 50%" -ForegroundColor Yellow
        $capitalReal = [math]::Round($capitalReal * 0.50, 2)
        $btcBiasOverride = "SHORT"
    }
    if ($btc.regime -eq "DISTRIBUICAO") {
        $capitalReal = [math]::Round($capitalReal * 0.25, 2)
        Write-Host "  BTC em DISTRIBUICAO: capital reduzido a 25% ($capitalReal USDT)" -ForegroundColor Yellow
    }

    # ── SAZONALIDADE — ajusta score minimo sem bloquear ──────────────────────
    # MarketTier diferencia penalty DoW (BTC -8 / ETH -10 / ALT -15 em quinta)
    $marketTier = Get-MarketTier -Market $Market
    $seasonal = Get-SeasonalityContext -MarketTier $marketTier
    $scoreMinimo = $SCORE_MINIMO + $seasonal.scoreAdjustment
    $scoreMinimo = [math]::Max(50, [math]::Min(85, $scoreMinimo))  # limita 50-85
    $seasonalLabel = "[$($seasonal.window)/$marketTier] momento=$($seasonal.momentScore)/100 scanRec=$($seasonal.scanIntervalMin)min scoreBar=$scoreMinimo (adj=$($seasonal.scoreAdjustment))"
    Write-Host "  Sazonalidade: $seasonalLabel" -ForegroundColor DarkGray

    # ── PRE-SCREEN TECNICO (sem Claude — custo zero) ─────────────────────────
    # Bloqueia o pipeline antes de qualquer chamada AI se o mercado nao tem setup

    Write-Host "[0.8/6] Pre-screen tecnico local..." -ForegroundColor DarkGray
    $preData = Get-TechData -Market $Market
    $prePass = $false
    $preMotivo = ""

    if ($preData -and $preData.tf1h) {
        $tf1h    = $preData.tf1h
        $tf1d    = $preData.tf1d
        $adxVal  = if ($tf1d) { [double]$tf1d.adx.adx } else { [double]$tf1h.adx.adx }
        $rsiVal  = [double]$tf1h.rsi
        $ema9    = [double]$tf1h.ema9
        $ema21   = [double]$tf1h.ema21
        $volRatio= [double]$tf1h.vol.ratio

        $adxOk  = $adxVal -ge 18                                        # tendencia minima (diario)
        $rsiOk  = $rsiVal -ge 28 -and $rsiVal -le 78                    # nao sobreextendido (1h)
        $emaOk  = [math]::Abs($ema9 - $ema21) / $ema21 -ge 0.0002      # nao flat (0.02% minimo)
        $volOk  = $volRatio -ge 0.5                                      # volume minimo aceitavel

        $passCount = @($adxOk, $rsiOk, $emaOk, $volOk) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
        $prePass = $passCount -ge 3

        $preMotivo = "ADX(1d)=$([math]::Round($adxVal,1)) RSI(1h)=$([math]::Round($rsiVal,1)) EMA=$( if($emaOk){'ok'}else{'flat'}) Vol=$([math]::Round($volRatio,2))x passes=$passCount/4"
        Write-Host "  $preMotivo" -ForegroundColor DarkGray
    } else {
        $prePass = $true   # sem dados = deixa passar (falha aberta)
        Write-Host "  Sem dados locais — pipeline continua" -ForegroundColor DarkGray
    }

    if (-not $prePass) {
        Write-Host "  [BLOQUEADO] Setup insuficiente — pipeline encerrado sem custo AI." -ForegroundColor Yellow
        $tgMsg = "[~] PRE-SCREEN BLOQUEOU $Market`n$preMotivo`nNenhum custo AI gerado.`n$(Get-Date -Format 'HH:mm dd/MM/yy')"
        Send-TelegramAlert -Message $tgMsg | Out-Null
        return [PSCustomObject]@{
            market         = $Market
            timestamp      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            decisao        = "ABORTAR"
            motivo         = "Pre-screen tecnico bloqueou: $preMotivo"
            scorePonderado = 0
            sinalTech      = "NEUTRO"
            forcaTech      = 0
            qualidadeSetup = "D"
            entryPrice     = 0; stopLoss = 0; alvo1 = 0
            rrFinal = 0; rrBruto = 0
            feeContext = $feeCtx; quantidadeUnits = 0
            capitalTotal = $capitalReal; riscoUSD = 0
            mentorVeredicto = "BLOQUEADO"; mentorMensagem = "Pre-screen local bloqueou pipeline."
            ordemId = $null; elapsed = ((Get-Date) - $startTime).TotalSeconds
            macroContext = $macro; agents = $null
        }
    }

    # ── FASE 1: Coletar analises de todos os agentes ──────────────────────────

    Write-Host "[1/6] TechAgent ($([int]($w.Tech*100))%)..." -ForegroundColor Cyan
    $tech = Invoke-TechAgent -Market $Market

    $fund  = $null
    $sent  = $null
    $chain = $null

    if (-not $SkipFund) {
        Write-Host "[2/6] FundAgent ($([int]($w.Fund*100))%)..." -ForegroundColor Cyan
        $fund = Invoke-FundAgent -Market $Market
    } else { Write-Host "[2/6] FundAgent: SKIP" -ForegroundColor Gray }

    if (-not $SkipSent) {
        Write-Host "[3/6] SentAgent ($([int]($w.Sent*100))%)..." -ForegroundColor Cyan
        $sent = Invoke-SentAgent -Market $Market
    } else { Write-Host "[3/6] SentAgent: SKIP" -ForegroundColor Gray }

    if (-not $SkipChain) {
        Write-Host "[4/6] ChainAgent ($([int]($w.Chain*100))%)..." -ForegroundColor Cyan
        $chain = Invoke-ChainAgent -Market $Market
    } else { Write-Host "[4/6] ChainAgent: SKIP" -ForegroundColor Gray }

    # ── FASE 2: Score ponderado ────────────────────────────────────────────────

    Write-Host "[5/6] Calculando score ponderado..." -ForegroundColor Cyan

    $techScore  = Convert-SinalToScore -Sinal $tech.sinal -Forca $tech.forca
    $fundScore  = Get-FundScore  $fund
    $sentScore  = Get-SentScore  $sent
    $chainScore = Get-ChainScore $chain

    # Pesos adaptativos ($w selecionado por macro_bias acima)
    $totalWeight = $w.Tech  # tech sempre presente
    if ($fund)  { $totalWeight += $w.Fund  }
    if ($sent)  { $totalWeight += $w.Sent  }
    if ($chain) { $totalWeight += $w.Chain }

    $scorePonderado = $techScore * $w.Tech
    if ($fund)  { $scorePonderado += $fundScore  * $w.Fund  }
    if ($sent)  { $scorePonderado += $sentScore  * $w.Sent  }
    if ($chain) { $scorePonderado += $chainScore * $w.Chain }
    $scorePonderado = [math]::Round($scorePonderado / $totalWeight, 1)

    # Determinar direcao consenso
    $sinalFinal = $tech.sinal
    $sinalColor = switch ($sinalFinal) { "LONG" { "Green" } "SHORT" { "Red" } default { "Yellow" } }

    Write-Host ""
    Write-Host "┌─ SCORES DOS AGENTES ──────────────────────────────┐" -ForegroundColor White
    Write-Host "│  Tech  ($([int]($w.Tech*100))%): $techScore/100  | Sinal: $($tech.sinal) | Forca: $($tech.forca)" -ForegroundColor White
    if ($fund)  { Write-Host "│  Fund  ($([int]($w.Fund*100))%): $fundScore/100  | Macro: $($fund.macro_outlook)" -ForegroundColor White }
    if ($sent)  { Write-Host "│  Sent  ($([int]($w.Sent*100))%): $sentScore/100  | Sent: $($sent.sentimento) ($($sent.intensidade))" -ForegroundColor White }
    if ($chain) { Write-Host "│  Chain ($([int]($w.Chain*100))%): $chainScore/100  | Bias: $($chain.chain_bias)" -ForegroundColor White }
    Write-Host "│  ─────────────────────────────────────────────────" -ForegroundColor White
    Write-Host "│  SCORE PONDERADO: $scorePonderado/100  | SINAL: $sinalFinal" -ForegroundColor $sinalColor
    Write-Host "└───────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""

    # ── FASE 3: Position sizing preliminar ────────────────────────────────────

    $validation = Test-TradeSetup `
        -CapitalTotal    $capitalReal `
        -EntryPrice      $tech.preco_entrada `
        -StopLoss        $tech.stop_loss `
        -Alvo1           $tech.alvo1 `
        -ScorePonderado  $scorePonderado `
        -Sinal           $tech.sinal `
        -RRMinimo        $RR_MINIMO `
        -RiscoMaxPct     $RISCO_MAXIMO_PCT `
        -ScoreMinimo     $scoreMinimo `
        -Market          $Market `
        -FeeContext      $feeCtx

    # ── FASE 4: MentorAgent — veto final ──────────────────────────────────────

    $mentor = $null
    if (-not $SkipMentor) {
        Write-Host "[6/6] MentorAgent (veto final)..." -ForegroundColor Cyan
        $mentor = Invoke-MentorAgent `
            -Market          $Market `
            -TechResult      $tech `
            -FundResult      $fund `
            -SentResult      $sent `
            -ChainResult     $chain `
            -ScorePonderado  $scorePonderado `
            -CapitalTotal    $capitalReal `
            -RiscoMaxPct     $RISCO_MAXIMO_PCT `
            -FeeContext      $feeCtx `
            -MacroContext    $macro.resumo
    } else { Write-Host "[6/6] MentorAgent: SKIP" -ForegroundColor Gray }

    # ── FASE 5: Decisao final ─────────────────────────────────────────────────

    $decisaoFinal = "AGUARDAR"
    $motivoFinal  = ""

    if ($mentor) {
        switch ($mentor.veredicto) {
            "EXECUTAR" {
                if ($validation.aprovado) {
                    $decisaoFinal = if ($DryRun) { "DRY_RUN_EXECUTAR" } else { "EXECUTAR" }
                } else {
                    $decisaoFinal = "BLOQUEADO_SIZING"
                    $motivoFinal  = $validation.mensagem
                }
            }
            "REVISAR" {
                $decisaoFinal = "REVISAR"
                $motivoFinal  = $mentor.motivo_veto
            }
            "ABORTAR" {
                $decisaoFinal = "ABORTAR"
                $motivoFinal  = $mentor.motivo_veto
            }
        }
    } elseif ($validation.aprovado -and $scorePonderado -ge ($SCORE_MINIMO + 10) -and $tech.sinal -ne "NEUTRO") {
        $decisaoFinal = if ($DryRun) { "DRY_RUN_EXECUTAR" } else { "EXECUTAR_SEM_MENTOR" }
    } else {
        $decisaoFinal = "AGUARDAR"
        $motivoFinal  = if (-not $validation.aprovado) { $validation.mensagem } else { "Score insuficiente: $scorePonderado/100" }
    }

    $decisaoColor = switch -Wildcard ($decisaoFinal) {
        "*EXECUTAR*" { "Green" }
        "REVISAR"    { "Yellow" }
        "ABORTAR"    { "Red" }
        default      { "DarkYellow" }
    }

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor $decisaoColor
    Write-Host "║  DECISAO FINAL: $decisaoFinal" -ForegroundColor $decisaoColor
    if ($motivoFinal) {
        Write-Host "║  Motivo: $($motivoFinal.Substring(0, [math]::Min(48, $motivoFinal.Length)))" -ForegroundColor $decisaoColor
    }
    if ($mentor) {
        Write-Host "║  Mentor: $($mentor.mensagem_mentor.Substring(0, [math]::Min(48, $mentor.mensagem_mentor.Length)))" -ForegroundColor $decisaoColor
    }
    Write-Host "║  Tempo: ${elapsed}s" -ForegroundColor $decisaoColor
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor $decisaoColor
    Write-Host ""

    # ── FASE 6: Aprovacao manual obrigatoria + execucao ──────────────────────

    $ordemExecutada = $null
    if ($decisaoFinal -eq "EXECUTAR" -and -not $DryRun) {
        $qtd       = if ($mentor) { $mentor.tamanho_posicao_aprovado } else { $validation.sizing.quantidadeUnits }

        # ── CONFIRMACAO OBRIGATORIA DE THIAGO ────────────────────────────────
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║  APROVACAO MANUAL OBRIGATORIA                     ║" -ForegroundColor Yellow
        Write-Host "║  Par:    $Market                                  " -ForegroundColor Yellow
        Write-Host "║  Sinal:  $($tech.sinal) | R:R bruto $rrBrutoFinal | Efetivo $rrFinalVal" -ForegroundColor Yellow
        Write-Host "║  Entry:  $entry | Stop: $stopFinal | Alvo: $alvoFinal" -ForegroundColor Yellow
        Write-Host "║  Qtd:    $qtd | Risco: $([math]::Round($capitalReal * $RISCO_MAXIMO_PCT, 2)) USDT (1% de $capitalReal)" -ForegroundColor Yellow
        Write-Host "║  Score:  $scorePonderado/100 | Setup: $($tech.qualidade_setup)" -ForegroundColor Yellow
        Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""

        if ($AutoApprove) {
            Write-Host "  [AutoApprove ativo — apenas para testes]" -ForegroundColor DarkYellow
            $confirmado = $true
        } else {
            $rrFinalVal = if ($stopFinal -gt 0 -and $entry -gt 0 -and $alvoFinal -gt 0) {
                $sd2 = [math]::Abs($entry - $stopFinal); $td2 = [math]::Abs($alvoFinal - $entry)
                if ($sd2 -gt 0) { [math]::Round($td2/$sd2, 1) } else { 0 }
            } else { 0 }
            $approvalMsg = Format-TgSetupApproval `
                -Market    $Market `
                -Sinal     $tech.sinal `
                -Score     $scorePonderado `
                -Setup     $tech.qualidade_setup `
                -Entry     $entry `
                -Stop      $stopFinal `
                -Target    $alvoFinal `
                -RR        $rrFinalVal `
                -RiscoUsd  ([math]::Round($capitalReal * $RISCO_MAXIMO_PCT, 2)) `
                -Qtd       $qtd `
                -MentorConf (if ($mentor) { $mentor.confianca } else { 0 }) `
                -MentorMsg  (if ($mentor) { $mentor.mensagem_mentor } else { "" })
            $confirmado = Wait-TelegramApproval -Message $approvalMsg -TimeoutSeconds 300
        }

        if (-not $confirmado) {
            Write-Host "  Execucao cancelada. Ordem NAO enviada." -ForegroundColor Yellow
            $decisaoFinal = "CANCELADO_THIAGO"
            $motivoFinal  = "Aprovacao manual nao concedida"
        } else {
            # ── EXECUCAO ─────────────────────────────────────────────────────
            Write-Host "  Aprovado. Enviando ordem..." -ForegroundColor Green
            try {
                $lado = if ($tech.sinal -eq "LONG") { "buy" } else { "sell" }
                $ordemExecutada = CoinEx-PlaceOrder -Market $Market -Side $lado -Amount $qtd -Type "market"

                if ($ordemExecutada -and $ordemExecutada.order_id) {
                    Write-Host "  Ordem executada: ID=$($ordemExecutada.order_id)" -ForegroundColor Green
                    try {
                        CoinEx-SetStopLoss -Market $Market -OrderId $ordemExecutada.order_id -StopPrice $stopFinal | Out-Null
                        Write-Host "  Stop loss definido: $stopFinal" -ForegroundColor Green
                    } catch { Write-Warning "  Falha ao definir stop loss: $_" }
                }
            } catch {
                Write-Warning "Falha ao executar ordem: $_"
                $decisaoFinal = "ERRO_EXECUCAO"
            }
        }
    }

    # ── Retorno estruturado ───────────────────────────────────────────────────

    $stopFinal  = if ($mentor -and $mentor.stop_final)  { $mentor.stop_final }  else { $tech.stop_loss }
    $alvoFinal  = if ($mentor -and $mentor.alvo_final)  { $mentor.alvo_final }  else { $tech.alvo1 }
    $entry      = $tech.preco_entrada
    $rrBrutoFinal = if ($entry -gt 0 -and $stopFinal -gt 0 -and $alvoFinal -gt 0) {
        $sd = [math]::Abs($entry - $stopFinal)
        $td = [math]::Abs($alvoFinal - $entry)
        if ($sd -gt 0) { [math]::Round($td / $sd, 2) } else { 0 }
    } else { $validation.rr }

    # ── Telegram resultado ────────────────────────────────────────────────────
    try {
        $orchResultObj = [PSCustomObject]@{
            market         = $Market
            decisao        = $decisaoFinal
            scorePonderado = $scorePonderado
            sinalTech      = $tech.sinal
            qualidadeSetup = $tech.qualidade_setup
            entryPrice     = $entry
            stopLoss       = $stopFinal
            alvo1          = $alvoFinal
            rrBruto        = $rrBrutoFinal
            mentorMensagem = if ($mentor) { $mentor.mensagem_mentor } else { "" }
        }
        Send-TelegramAlert -Message (Format-TgSetupResult -Result $orchResultObj -DryRun:$DryRun) | Out-Null
    } catch {}

    return [PSCustomObject]@{
        market          = $Market
        timestamp       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        decisao         = $decisaoFinal
        motivo          = $motivoFinal
        scorePonderado  = $scorePonderado
        sinalTech       = $tech.sinal
        forcaTech       = $tech.forca
        qualidadeSetup  = $tech.qualidade_setup
        entryPrice      = $entry
        stopLoss        = $stopFinal
        alvo1           = $alvoFinal
        rrFinal         = if ($mentor -and $mentor.rr_final) { $mentor.rr_final } else { $validation.rrEfetivo }
        rrBruto         = $rrBrutoFinal
        feeContext      = $feeCtx
        quantidadeUnits = if ($mentor) { $mentor.tamanho_posicao_aprovado } else { if ($validation.sizing) { $validation.sizing.quantidadeUnits } else { 0 } }
        capitalTotal    = $capitalReal
        riscoUSD        = [math]::Round($capitalReal * $RISCO_MAXIMO_PCT, 2)
        mentorVeredicto = if ($mentor) { $mentor.veredicto } else { "N/A" }
        mentorMensagem  = if ($mentor) { $mentor.mensagem_mentor } else { "" }
        ordemId         = if ($ordemExecutada) { $ordemExecutada.order_id } else { $null }
        elapsed         = $elapsed
        macroContext     = $macro
        seasonality     = $seasonal
        scoreMinimo     = $scoreMinimo
        agents          = [PSCustomObject]@{
            tech   = $tech
            fund   = $fund
            sent   = $sent
            chain  = $chain
            mentor = $mentor
        }
    }
}

# Execucao direta (se chamado como script, nao dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-OrchestratorAgent @PSBoundParameters
}

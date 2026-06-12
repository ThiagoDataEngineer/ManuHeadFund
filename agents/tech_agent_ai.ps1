# tech_agent_ai.ps1 — TechAgent com Claude API
# Personas: Al Brooks + Wyckoff + Stan Weinstein + ICT + Tori Trades (ver PERSONAS.md)
# Uso: . (Join-Path $PSScriptRoot "tech_agent_ai.ps1"); Invoke-TechAgent -Market "BTCUSDT"

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "lib_claude.ps1")

$TECH_SYSTEM_PROMPT = @'
Voce e um analista tecnico de elite com 20 anos de experiencia em mercados financeiros,
especializado em crypto desde 2013.

Seu framework tecnico integra:
- Price Action puro (Al Brooks): cada candle e uma batalha compradores vs vendedores
- Wyckoff Method: acumulacao, distribuicao, springs, upthrusts (WYCKOFF_SMC.md)
- Stan Weinstein 4 fases: nunca comprar em Fase 4, nunca vender em Fase 2
- Elder Triple Screen: tendencia no HTF, pullback no MTF, entrada no LTF
- ICT/SMC: order blocks, FVGs, liquidity sweeps, Power of 3
- Bulkowski: padroes com taxa de acerto real (flags 67%, H&S 83%)
- Connors RSI(2): extremos de curto prazo em tendencia de longo

Suas regras absolutas:
1. Stop loss antes de qualquer entrada. Sem stop = sem trade.
2. R:R minimo 1:2. Preferido 1:3.
3. Confluencia de 3+ fatores antes de agir.
4. Tendencia do 1D define o bias. Nao operar contra o 1D sem razao clara.
5. ADX < 20 = mercado em range = evitar breakouts.

--- ANALISE DE ESTRUTURA DE TRENDLINE (camada Tori Trades) ---

Alem dos indicadores acima, voce tambem e especialista em estrutura de trendlines.
Voce recebera os swing highs e swing lows do 4H e o bias do 1W/1D.
Sua tarefa adicional: identificar se existe uma trendline de qualidade para ancorar a entrada.

Criterios inegociaveis para uma trendline ser valida:
- Minimo 2 toques (ideal 3+) nos swing points fornecidos
- Minimo 6 candles de distancia entre toques
- Inclinacao moderada (nao vertical)
- Cada toque gerou rejeicao real (fechamento longe da linha)

Classificacao:
A+  = 3+ toques, dados de 3+ semanas, inclinacao ideal, rejeicoes limpas
A   = 3 toques, condicoes minimas cumpridas
B   = 2 toques fortes — so com confluencia adicional forte
C   = 2 toques fracos ou dados insuficientes
NONE = nenhuma trendline valida identificavel nos dados fornecidos

Dois setups possiveis:
BOUNCE: preco testando trendline valida — Action Line = Safety Line = a propria trendline
BREAK_3TP: candle 4H fechando alem de trendline com 3+ toques — requer Safety Line oposta
BREAK_2TP: candle 4H fechando alem de trendline com 2 toques — mais cautela, Safety Line obrigatoria

Verdict:
ENTER  = trendline A ou A+, timing ON_LINE, HTF alinhado
WAIT   = trendline existe mas timing nao e agora (TOO_EARLY) ou qualidade B
SKIP   = sem trendline valida, qualidade C, timing MISSED, ou HTF contrario

Regra critica: se verdict = SKIP, voce DEVE rebaixar qualidade_setup para "C"
e adicionar "trendline_invalid": true no JSON de saida.
Se verdict = ENTER, adicione "Trendline [quality] [setup_type] confirmada" em confluencias.

Responda APENAS com JSON valido no formato especificado. Sem texto adicional.
'@

# Constroi resultado de fallback quando Claude esta indisponivel.
# Usa score hardcoded de tech_agent.ps1 ($data.totalScore/$data.consensus/$data.atrStop1h).
# Funcao pura — sem I/O, sem chamadas externas. Testavel isoladamente.
function Invoke-TechFallback {
    param([object]$Data, [double]$EntryPrice)
    $sinal = switch ($Data.consensus) {
        "LONG-FORTE"  { "LONG"  }
        "LONG"        { "LONG"  }
        "SHORT-FORTE" { "SHORT" }
        "SHORT"       { "SHORT" }
        default       { "NEUTRO" }
    }
    $forca = [math]::Min(100, [math]::Max(0, [int](50 + ($Data.totalScore / 25.0) * 50)))
    $stop  = if ($sinal -eq "LONG")  { [math]::Round($EntryPrice - $Data.atrStop1h, 4) }
             elseif ($sinal -eq "SHORT") { [math]::Round($EntryPrice + $Data.atrStop1h, 4) }
             else { 0 }
    Write-Host "  [TechAgent] FALLBACK hardcoded — Claude indisponivel | $sinal forca=$forca score=$($Data.totalScore) consenso=$($Data.consensus)" -ForegroundColor DarkYellow
    return [PSCustomObject]@{
        sinal             = $sinal
        forca             = $forca
        qualidade_setup   = "C"
        justificativa     = "Fallback hardcoded — Claude indisponivel (score=$($Data.totalScore), consenso=$($Data.consensus))"
        preco_entrada     = $EntryPrice
        stop_loss         = $stop
        alvo1             = 0
        alvo2             = 0
        rr_calculado      = 0
        trendline_invalid = $true
        confluencias      = @("Fallback hardcoded: $($Data.consensus)")
        riscos            = @("Claude indisponivel — analise sem confirmacao AI")
    }
}

# Aplica regras da camada Tori ao resultado do Claude.
# Funcao pura — sem I/O, sem chamadas externas. Testavel isoladamente.
function Invoke-ToriPostProcess {
    param([object]$Result)
    if (-not $Result -or -not $Result.trendline -or -not $Result.trendline.verdict) {
        return $Result
    }
    
    # FIX 2026-05-23: Fallback para estrutura nascente (2 touches)
    # Problema: 60% dos gems bloqueados por exigir 3+ touches
    # Solução: Se 2 touches + quality B/A + slope válido → permitir ENTER
    $touches = 0
    if ($Result.trendline.PSObject.Properties['touchpoints']) {
        $touches = [int]$Result.trendline.touchpoints
    }
    $quality = if ($Result.trendline.quality) { "$($Result.trendline.quality)" } else { "NONE" }
    
    if ($Result.trendline.verdict -eq "WAIT" -and $touches -eq 2 -and $quality -in @("B", "A", "A+")) {
        # Override: estrutura nascente válida
        $Result.trendline.verdict = "ENTER"
        $Result.trendline.reason = "estrutura_nascente_2_touches_quality_$quality"
        Write-Host "  [ToriLayer] FALLBACK 2-TOUCH: WAIT → ENTER (2 touches quality=$quality)" -ForegroundColor Cyan
    }
    
    switch ($Result.trendline.verdict) {
        "SKIP" {
            $Result.qualidade_setup   = "C"
            $Result.trendline_invalid = $true
            Write-Host "  [ToriLayer] SKIP — trendline invalida, qualidade_setup rebaixada para C" -ForegroundColor DarkYellow
        }
        "ENTER" {
            $label = "Trendline $($Result.trendline.quality) $($Result.trendline.setup_type) confirmada"
            $Result | Add-Member -MemberType NoteProperty -Name confluencias `
                -Value (@($Result.confluencias) + $label) -Force
            Write-Host "  [ToriLayer] ENTER — $label" -ForegroundColor DarkGreen
        }
        "WAIT" {
            Write-Host "  [ToriLayer] WAIT — sem trendline valida para ancorar entrada" -ForegroundColor DarkGray
        }
    }
    return $Result
}

# Get-ToriTrendlineSignal
# Gate de qualidade tecnica para GEMs: roda Invoke-TechAgent (Claude + Tori post-process)
# e retorna um objeto compacto { signal=ENTER|SKIP|WAIT; reason } usavel pelo gem_executor.
#
# 2026-06-03 RELAX: Tori muito restritivo bloqueava gems com score alto por falta de trendline perfeita.
# Novo behavior: deixa Mentor decidir. Tori soh bloqueia em erro critico (Claude null/erro).
# - Claude disponivel (mesmo sem trendline perfeita) -> ENTER (Mentor filtra)
# - Claude erro/null -> WAIT (deixa pra proximo ciclo)
# - Verdict explicito SKIP -> SKIP (respeita)
function Get-ToriTrendlineSignal {
    param(
        [Parameter(Mandatory)] [string] $Market
    )
    $r = Invoke-TechAgent -Market $Market
    if (-not $r) {
        return [PSCustomObject]@{ signal = "WAIT"; conviction = 0; reason = "tech_agent_null" }
    }

    # Extrai conviction de tori_proximity (0-100 gradation)
    $conviction = 0
    if (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue) {
        try {
            $statePath = Join-Path $global:JOURNAL_DIR "tori_proximity_state.json"
            $tp = Get-ToriProximityForMarket -Market $Market -StatePath $statePath -MaxAgeMinutes 60
            if ($tp -and $tp.PSObject.Properties['conviction']) {
                $conviction = [int]$tp.conviction
            }
        } catch {}
    }

    # 2026-06-12: SKIP explicito do Tori VOLTA a bloquear. O bypass de 2026-06-11
    # ("sempre ENTER, Mentor decide") deixou TRUMPUSDT LONG entrar as 10:30 com
    # Tori dizendo SKIP (bias semanal downtrend) -> -4.4% cortado no mesmo dia.
    # Balanco: SKIP explicito = veto tecnico real (bloqueia); sem verdict/dados
    # ausentes = ENTER com conviction (nao congela o pipeline, Mentor filtra).
    if ($r.trendline -and $r.trendline.verdict) {
        $verdict = "$($r.trendline.verdict)".ToUpper()
        if ($verdict -eq "SKIP") {
            return [PSCustomObject]@{ signal = "SKIP"; conviction = $conviction; reason = "$($r.trendline.reason)" }
        }
    }
    $reasonTxt = if ($r.trendline -and $r.trendline.reason) { "$($r.trendline.reason)" } else { "sem_verdict_mentor_decide" }
    return [PSCustomObject]@{ signal = "ENTER"; conviction = $conviction; reason = $reasonTxt }
}

function Invoke-TechAgent {
    param(
        [string]$Market       = "BTCUSDT",
        [switch]$Verbose
    )

    Write-Host "  [TechAgent] Coletando dados: $Market..." -ForegroundColor DarkCyan

    # Chama tech_agent.ps1 existente em modo silencioso
    $techPath = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "tech_agent.ps1")
    $data = & $techPath -Market $Market -Once -Quiet

    if (-not $data) {
        return [PSCustomObject]@{ erro="TechAgent sem dados para $Market"; sinal="NEUTRO"; forca=0 }
    }

    $tf1h = $data.tf1h
    $tf4h = $data.tf4h
    $tf1d = $data.tf1d
    $tf1w = $data.tf1w
    $swings4h = $data.swings4h

    # Formata swing points para o contexto
    $swingHighsStr = if ($swings4h -and $swings4h.highs) {
        ($swings4h.highs | ForEach-Object { "$($_.price) ($($_.barsAgo) candles atras)" }) -join " | "
    } else { "N/A" }
    $swingLowsStr = if ($swings4h -and $swings4h.lows) {
        ($swings4h.lows | ForEach-Object { "$($_.price) ($($_.barsAgo) candles atras)" }) -join " | "
    } else { "N/A" }

    $context = @"
PAR: $Market
TIMESTAMP: $($data.timestamp)
PRECO ATUAL: $($tf1h.close)

=== TIMEFRAME 1W (HTF bias - camada Tori) ===
Close: $($tf1w.close) | Estrutura: $($tf1w.structure)
EMA50=$($tf1w.ema50) EMA200=$($tf1w.ema200) | Weinstein: $($tf1w.weinstein)
Bias semanal: $(if($tf1w.close -gt $tf1w.ema50){"ACIMA EMA50 — uptrend semanal"}else{"ABAIXO EMA50 — downtrend semanal"})

=== TIMEFRAME 1D (tendencia macro - Stan Weinstein) ===
Close: $($tf1d.close) | Estrutura: $($tf1d.structure)
EMA9=$($tf1d.ema9) EMA21=$($tf1d.ema21) EMA50=$($tf1d.ema50) EMA200=$($tf1d.ema200)
RSI14=$($tf1d.rsi) | RSI2=$($tf1d.rsi2) | ADX=$($tf1d.adx.adx) (+DI=$($tf1d.adx.pdi) -DI=$($tf1d.adx.ndi))
MACD=$($tf1d.macd.macd) | ATR=$($tf1d.atr)
Bollinger: L=$($tf1d.bb.lower) M=$($tf1d.bb.mid) U=$($tf1d.bb.upper)
Weinstein: $($tf1d.weinstein) | Ichimoku: $($tf1d.ichimoku.bias) | SuperTrend: $($tf1d.supertrend.trend)
Padroes: $($tf1d.patterns -join ", ") | Divergencia: $($tf1d.divergence)
Wyckoff: $($tf1d.wyckoff) | SMC: $($tf1d.smc.signal)
Fib 38.2%=$($tf1d.fib.f382) 50%=$($tf1d.fib.f500) 61.8%=$($tf1d.fib.f618)
Volume Profile: POC=$($tf1d.vp.poc) VAH=$($tf1d.vp.vah) VAL=$($tf1d.vp.val)
VSA: $($tf1d.vsa) | Donchian: $($tf1d.donchian.signal)

=== TIMEFRAME 4H (estrutura e setup) ===
Close: $($tf4h.close) | Estrutura: $($tf4h.structure)
EMA9=$($tf4h.ema9) EMA21=$($tf4h.ema21) EMA50=$($tf4h.ema50)
RSI14=$($tf4h.rsi) | RSI2=$($tf4h.rsi2) | ADX=$($tf4h.adx.adx)
MACD=$($tf4h.macd.macd) | ATR=$($tf4h.atr)
Bollinger: L=$($tf4h.bb.lower) M=$($tf4h.bb.mid) U=$($tf4h.bb.upper)
Weinstein: $($tf4h.weinstein) | Wyckoff: $($tf4h.wyckoff)
Padroes: $($tf4h.patterns -join ", ") | Squeeze: $($tf4h.squeeze)
SMC: Bull OB=$($tf4h.smc.bullOB) Bear OB=$($tf4h.smc.bearOB) | $($tf4h.smc.signal)
Stoch: K=$($tf4h.stoch.k) D=$($tf4h.stoch.d) | $($tf4h.stoch.signal)

=== TIMEFRAME 1H (entrada) ===
Close: $($tf1h.close) | Estrutura: $($tf1h.structure)
EMA9=$($tf1h.ema9) EMA21=$($tf1h.ema21) EMA50=$($tf1h.ema50)
RSI14=$($tf1h.rsi) | RSI2=$($tf1h.rsi2) | ADX=$($tf1h.adx.adx)
ATR=$($tf1h.atr) | Pullback: $($tf1h.pullback)
VWAP: $($tf1h.vwap.vwap) +1SD=$($tf1h.vwap.upper1) -1SD=$($tf1h.vwap.lower1)
ORB: $($tf1h.orb.signal) ($($tf1h.orb.high)/$($tf1h.orb.low))
NR7: $($tf1h.nr7) | VSA: $($tf1h.vsa)
Padroes: $($tf1h.patterns -join ", ")

=== ELDER TRIPLE SCREEN ===
Screen1 (1D): $($data.elder.trend) | Screen2 ok: $($data.elder.screen2ok) | Screen3: $($data.elder.screen3) | ATIVO: $($data.elder.active)

=== CONTEXTO ===
Power of 3 (ICT): $($data.po3)
Funding Rate: $($data.funding.rate)% | $($data.funding.signal)
Ciclo pos-halving: $($data.cycle.monthsPostHalving)m | $($data.cycle.phase)
Sazonalidade: $($data.cycle.seasonal)
Stop sugerido (2x ATR 1H): $($data.atrStop1h)
Score tecnico hardcoded: $($data.totalScore) -> $($data.consensus)

=== SWING POINTS 4H (para analise de trendlines — camada Tori) ===
Swing Highs recentes: $swingHighsStr
Swing Lows recentes:  $swingLowsStr
(Use esses pontos para identificar trendlines validas. Conecte highs para resistencia/downtrend, lows para suporte/uptrend.)
"@

    $question = @"
$context

Com base nessa analise completa de multiplos timeframes, responda em JSON:
{
  "sinal": "LONG" | "SHORT" | "NEUTRO",
  "forca": 0-100,
  "qualidade_setup": "A" | "B+" | "B" | "C",
  "timeframe_dominante": "1H" | "4H" | "1D",
  "preco_entrada": numero,
  "stop_loss": numero,
  "stop_estrutural_razao": "texto explicando por que esse stop faz sentido estruturalmente",
  "alvo1": numero,
  "alvo2": numero,
  "rr_calculado": numero,
  "confluencias": ["lista dos 3+ fatores que convergem — inclua trendline se verdict=ENTER"],
  "riscos": ["lista dos principais riscos dessa entrada"],
  "weinstein_fase": "1-4 + descricao",
  "wyckoff_contexto": "texto",
  "elder_screen": "ATIVO" | "AGUARDAR",
  "trendline": {
    "quality": "A+" | "A" | "B" | "C" | "NONE",
    "setup_type": "BOUNCE" | "BREAK_3TP" | "BREAK_2TP" | "NONE",
    "action_line": numero,
    "safety_line": numero,
    "touchpoints": numero,
    "weeks_of_data": numero,
    "entry_timing": "ON_LINE" | "MISSED" | "TOO_EARLY",
    "htf_aligned": true | false,
    "sweep_risk": "HIGH" | "MEDIUM" | "LOW",
    "verdict": "ENTER" | "WAIT" | "SKIP",
    "reason": "texto objetivo em 1 frase"
  },
  "trendline_invalid": false,
  "justificativa": "2-3 frases diretas sobre o setup"
}
"@

    if ($Verbose) { Write-Host $context -ForegroundColor DarkGray }

    # R3 fix 2026-05-21: usar Invoke-TechCascadeJson (Groq→Gemini→Haiku) ao inves
    # de Invoke-ClaudeJson (Sonnet default). Economia: ~$0.27/dia = ~$8/mes.
    Write-Host "  [TechAgent] Consultando cascade Groq->Gemini->Haiku..." -ForegroundColor DarkCyan
    if (Get-Command Invoke-TechCascadeJson -ErrorAction SilentlyContinue) {
        $result = Invoke-TechCascadeJson -SystemPrompt $TECH_SYSTEM_PROMPT -UserContent $question -Temperature $CLAUDE_TEMP_TRADE -Agent "tech"
    } else {
        $result = Invoke-ClaudeJson -SystemPrompt $TECH_SYSTEM_PROMPT -UserContent $question -Temperature $CLAUDE_TEMP_TRADE -Agent "tech"
    }

    if (-not $result) {
        return Invoke-TechFallback -Data $data -EntryPrice $tf1h.close
    }

    # Pos-processamento camada Tori
    $result = Invoke-ToriPostProcess $result

    Write-Host "  [TechAgent] $($result.sinal) | Forca=$($result.forca) | Setup=$($result.qualidade_setup) | Tori=$($result.trendline.verdict)" -ForegroundColor $(if($result.sinal -eq "LONG"){"Green"}elseif($result.sinal -eq "SHORT"){"Red"}else{"Yellow"})
    return $result
}

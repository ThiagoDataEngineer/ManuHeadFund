# lib_seasonality.ps1 — Contexto de sazonalidade para ajuste de threshold
# NAO bloqueia o pipeline — apenas informa a qualidade do momento e ajusta o score minimo.
# Dot-source: . (Join-Path $PSScriptRoot "lib_seasonality.ps1")

# ── Tabela de janelas horarias (BRT = UTC-3) ──────────────────────────────────
# Baseado em: abertura NY (12h BRT), pico liquidez (12h-17h BRT),
# fechamento EU (18h BRT), mercado asiatico (22h-5h BRT).

# Markets do tier "eth" (top5 mcap, comportamento intermediario entre BTC e alts)
$SEASONALITY_ETH_TIER_MARKETS = @("ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT")

# Classifica market por tier de comportamento (DoW calibracao)
function Get-MarketTier {
    param([string]$Market = "")
    $m = $Market.ToUpperInvariant()
    if ($m -eq "BTCUSDT") { return "btc" }
    if ($m -in $SEASONALITY_ETH_TIER_MARKETS) { return "eth" }
    return "alt"
}

# Retorna contexto de sazonalidade para o momento atual
function Get-SeasonalityContext {
    param(
        [DateTime]$Now = (Get-Date),  # BRT — Get-Date ja retorna hora local
        [string]$MarketTier = "btc"   # btc | eth | alt (calibracao DoW diferenciada)
    )

    # Normaliza MarketTier; fallback seguro para btc
    $tier = $MarketTier.ToLowerInvariant()
    if ($tier -notin "btc","eth","alt") { $tier = "btc" }

    $hour = $Now.Hour
    $dow  = $Now.DayOfWeek          # [DayOfWeek] enum
    $dom  = $Now.Day                # dia do mes
    $month= $Now.Month

    # ── Janela horaria ────────────────────────────────────────────────────────
    # PRIME    = abertura NY + sobreposicao EU/NY  (12h-17h BRT)
    # GOOD     = pre-abertura EU, tarde NY         (8h-12h | 17h-20h BRT)
    # NEUTRAL  = fechamento NY, noite americana    (20h-23h | 5h-8h BRT)
    # SLOW     = madrugada (mercado asiatico lento)(23h-5h BRT)

    $window = switch ($hour) {
        { $_ -ge 12 -and $_ -lt 17 } { "PRIME"   }
        { $_ -ge 8  -and $_ -lt 12 } { "GOOD"    }
        { $_ -ge 17 -and $_ -lt 20 } { "GOOD"    }
        { $_ -ge 20 -and $_ -lt 23 } { "NEUTRAL" }
        { $_ -ge 5  -and $_ -lt 8  } { "NEUTRAL" }
        default                        { "SLOW"    }   # 23h-5h
    }

    # ── Ajuste por dia da semana (CALIBRADO EMPIRICAMENTE em 14 anos BTC) ─────
    # Validacao: backtest/calendar_effects_btc.py + dow_refinement.py (2026-05-13)
    # Sample: 5382 dias 2011-2026
    # Resultados empiricos (mean log return %):
    #   Mon +0.551 (melhor)  Wed +0.337  Tue +0.214  Fri +0.212
    #   Sun +0.041  Sat -0.034  Thu -0.164 (pior)
    # Significancia: Mon vs Thu p=0.0068 (SIG); efeito sobrevive 3 dos 4 subperiodos
    # Por regime: Thu em bear macro = -0.645%/dia (catastrofico); Mon em bull = +1.056%
    # Estrategia "Skip Thursday" sobre 14 anos: 3.5x retorno vs Buy&Hold
    # Penalty Thursday por tier (validado em dow_universe_coinex.py, 942 markets):
    #   BTC Thu  -0.164%/d  -> penalty -8
    #   ETH (top10 proxy)   -> penalty -10
    #   ALT Thu  -1.03%/d, apenas 9% positivos -> penalty -15
    $thuPenalty = switch ($tier) {
        "btc"   { -8 }
        "eth"   { -10 }
        "alt"   { -15 }
        default { -8 }
    }

    $dowAdj = switch ($dow) {
        "Monday"    {  8 }   # MELHOR dia (institucional retorna, lift-off)
        "Tuesday"   {  2 }
        "Wednesday" {  5 }
        "Thursday"  { $thuPenalty }
        "Friday"    { -2 }
        "Saturday"  { -5 }   # fim de semana: liquidez baixa
        "Sunday"    { -3 }
        default     {  0 }
    }

    # ── Ajuste por periodo mensal ─────────────────────────────────────────────
    # Primeiros 5 dias: fluxo de capital novo (salarios, alocacoes fundos)
    # Semana de vencimento de futuros (3a sexta, ~15-21): mais volatilidade
    # Fim de mes (28-31): fechamento de posicoes, rebalanceamento

    $monthAdj = if ($dom -le 5) {
        5    # influxo de capital no inicio do mes
    } elseif ($dom -ge 15 -and $dom -le 21) {
        3    # semana de vencimento futuros CME
    } elseif ($dom -ge 28) {
        -3   # fim de mes: fechamentos e rebalanceamentos
    } else {
        0
    }

    # ── Ajuste sazonalidade anual ─────────────────────────────────────────────
    # Jan/Out: historicamente fortes em crypto (bull sazonais)
    # Ago/Set: "setembro de crypto" geralmente fraco
    # Abr: pos-halving momentum historico

    $seasonAdj = switch ($month) {
        1  {  5 }   # janeiro: re-alocacoes anuais
        4  {  5 }   # abril: pos-halving sazonalidade
        10 {  5 }   # outubro: "Uptober"
        11 {  3 }   # novembro: rally historico
        8  { -3 }   # agosto: lento pre-setembro
        9  { -5 }   # setembro: historicamente o pior mes crypto
        default { 0 }
    }

    # ── Score de qualidade do momento (0-100) ─────────────────────────────────
    $windowScore = switch ($window) {
        "PRIME"   { 85 }
        "GOOD"    { 70 }
        "NEUTRAL" { 50 }
        "SLOW"    { 30 }
    }
    $momentScore = [math]::Max(0, [math]::Min(100, $windowScore + $dowAdj + $monthAdj + $seasonAdj))

    # ── Ajuste no score minimo de trade ──────────────────────────────────────
    # Em horario SLOW: exige score mais alto (mercado fino = mais ruido)
    # Em horario PRIME: barra ligeiramente menor (liquidez confirma sinal)

    $scoreAdj = switch ($window) {
        "PRIME"   { -3 }   # barra cai 3 pontos
        "GOOD"    {  0 }
        "NEUTRAL" {  3 }   # barra sobe 3 pontos
        "SLOW"    {  8 }   # barra sobe 8 pontos — exige sinal mais forte
    }
    # Fins de semana adicionam 5 pontos extra ao bar
    if ($dow -in "Saturday","Sunday") { $scoreAdj += 5 }

    # ── Intervalo de scan recomendado (retornado ao scheduler) ───────────────
    $scanIntervalMin = switch ($window) {
        "PRIME"   { 15 }
        "GOOD"    { 30 }
        "NEUTRAL" { 60 }
        "SLOW"    { 120 }
    }

    # DAILY_CYCLE_MODE override: backtest 2026-05-17 mostrou edge real em daily,
    # nao em hourly. Quando ativado, forca 1 cycle/dia (1440min) e window=DAILY.
    if ($global:DAILY_CYCLE_MODE) {
        $window = "DAILY"
        $scanIntervalMin = 1440
        $scoreAdj = 0   # sem penalty de janela; daily ja eh trend-day
    }

    return [PSCustomObject]@{
        window          = $window          # PRIME | GOOD | NEUTRAL | SLOW
        momentScore     = $momentScore     # 0-100: qualidade do momento
        scoreAdjustment = $scoreAdj        # pontos a SOMAR no SCORE_MINIMO
        scanIntervalMin = $scanIntervalMin # intervalo recomendado para scheduler
        marketTier      = $tier            # btc | eth | alt
        hour            = $hour
        dayOfWeek       = $dow.ToString()
        dayOfMonth      = $dom
        month           = $month
        reasons         = @(
            "Janela: $window ($hour`hBRT)"
            "DiaSem: $($dow.ToString()) (adj=$dowAdj)"
            "DiaMes: $dom (adj=$monthAdj)"
            "Mes: $month (adj=$seasonAdj)"
        )
    }
}

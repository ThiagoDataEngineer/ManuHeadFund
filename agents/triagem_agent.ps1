# triagem_agent.ps1 -- Drone Batedor (gratuito): classifica candidato em tier A/B/C/D
# Dot-source: . (Join-Path $PSScriptRoot "triagem_agent.ps1")
#
# Contrato:
#   Invoke-Triagem -Market <string> -Context <PSCustomObject>
#     Context = @{ scanner; prescreen; macro; seasonal }
#       scanner.score          (0-100)
#       macro.macro_bias       (BULLISH | NEUTRAL | BEARISH)
#       seasonal.dayOfWeek     (Monday..Sunday)
#       seasonal.marketTier    (btc | eth | alt)
#       seasonal.momentScore   (0-100)
#
# Flags configuraveis (config.local.ps1 ou config.ps1):
#   $SKIP_THURSDAY_ALTS  (default $false)  -- quando $true, Thursday+alt forca Tier D.
#     Wave 2 (2026-05-14): rebaixado a flag opcional para destravar paper trade.
#     Calibracao 14y "Skip Thursday = 3.5x B&H" virou penalidade leve (sem veto)
#     a menos que o usuario re-ative explicitamente.
#
#   Retorna [PSCustomObject]@{
#       tier             = A | B | C | D
#       razao            = string nao-vazia
#       score_predicted  = 0-100 int
#       flags            = array de strings
#       knowledge_cited  = array de strings (formato "source.md:tag")
#       latency_ms       = numerico
#   }
#
# Design:
#   1. Tier deterministico via regras (rule-first, LLM-augmented).
#   2. Tags de knowledge retrieval derivadas do contexto.
#   3. Groq (free) usado para razao + flags com fallback robusto.
#   4. Tracking via -Agent "triagem" propagado para Invoke-GroqJson.

# Dependencias: assume que knowledge_retriever.ps1 e lib_claude.ps1 ja foram dot-sourceados
# (ou que Get-RelevantKnowledge / Invoke-GroqJson estao definidas).

# Dias favoraveis (calibracao empirica 14y BTC: Mon/Tue/Wed positivos)
$TRIAGEM_DOW_FAVORAVEL = @("Monday","Tuesday","Wednesday","Thursday","Friday")  # 2026-07-09 FIX: Allow Thu/Fri (penalidade soft vs hard block)


function _Get-CtxField {
    param($Context, [string]$Path, $Default = $null)
    try {
        $parts = $Path -split '\.'
        $cur = $Context
        foreach ($p in $parts) {
            if ($null -eq $cur) { return $Default }
            $cur = $cur.$p
        }
        if ($null -eq $cur) { return $Default }
        return $cur
    } catch {
        return $Default
    }
}


function Get-TriagemThresholds {
    # Retorna @{D; B; A} com cutoffs do Tier.
    # Default (compat antigo): D=50, B=60, A=75 (escala 0-100 teorica).
    # Override OPT-IN via $global:TRIAGEM_THRESHOLDS = @{D=15; B=25; A=40}
    # para escala empirica do scanner (|change|*log10(vol/1000), range real 5-35).
    # Validacao: hashtable, valores em 1..100, ordem D<B<A. Falhas -> fallback default.
    [CmdletBinding()]
    param()
    $default = @{ D = 50; B = 60; A = 75 }
    $override = $null
    if (Test-Path variable:global:TRIAGEM_THRESHOLDS) {
        $override = $global:TRIAGEM_THRESHOLDS
    }
    if ($null -eq $override) { return $default }
    if ($override -isnot [hashtable]) { return $default }

    # Mistura override + default (override pode ser parcial)
    $merged = @{ D = $default.D; B = $default.B; A = $default.A }
    foreach ($key in @('D','B','A')) {
        if ($override.ContainsKey($key)) {
            $v = $override[$key]
            $parsed = 0
            if ([int]::TryParse([string]$v, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 100) {
                $merged[$key] = $parsed
            } else {
                # Valor invalido neste campo -> mantem default desse campo
            }
        }
    }
    # Coerencia D < B < A; senao fallback total
    if (-not ($merged.D -lt $merged.B -and $merged.B -lt $merged.A)) {
        return $default
    }
    return $merged
}


function _Compute-Tier {
    param(
        [int]$Score,
        [string]$MacroBias,
        [string]$DayOfWeek,
        [string]$MarketTier
    )
    # Flag opcional (default $false): Thursday+alt vira veto rigido.
    # Lookup global -> permite override por test/config.local.ps1.
    $skipThuAlt = $false
    try {
        if ($null -ne (Get-Variable -Name SKIP_THURSDAY_ALTS -Scope Global -ErrorAction SilentlyContinue)) {
            $skipThuAlt = [bool]$global:SKIP_THURSDAY_ALTS
        }
    } catch { $skipThuAlt = $false }

    $thursdayAlt = ($DayOfWeek -eq "Thursday" -and $MarketTier -eq "alt")
    if ($thursdayAlt -and $skipThuAlt) { return "D" }
    # Sem o veto, Thursday+alt vira penalidade leve no DoW favoravel (nao Tier A).

    # Thresholds dinamicos (default 50/60/75, override OPT-IN via $global:TRIAGEM_THRESHOLDS).
    $th = Get-TriagemThresholds

    if ($Score -lt $th.D)    { return "D" }
    if ($MacroBias -eq "BEARISH") {
        if ($Score -lt $th.B) { return "D" }
        return "C"
    }
    $dowFavoravel = ($TRIAGEM_DOW_FAVORAVEL -contains $DayOfWeek)
    $macroFavoravel = ($MacroBias -eq "BULLISH" -or $MacroBias -eq "NEUTRAL")
    # 2026-06-03 FIX: macro BEARISH nao bloqueia Tier A se score muito alto (per-pair override).
    # Antes: BEARISH sempre retornava C. Agora: BEARISH com score >= A threshold -> pode ser A (se DoW/regime forem).
    # Mantém conservadorismo: exige DoW favorável + sem Thursday+alt penalty.
    # Thursday+alt nao chega a Tier A nem com score alto (penalidade leve)
    if ($Score -ge $th.A -and $dowFavoravel -and -not $thursdayAlt) { return "A" }
    if ($Score -ge $th.B -and ($macroFavoravel -or ($Score -ge 100)))  { return "B" }
    return "C"
}


function _Compute-RegimeFromContext {
    # v3 2026-05-16 BUG ARQUITETURAL FIX:
    # Antes: regime era macro-BTC → todos pares ficavam BULL_WEAK quando BTC sideways
    # → SHORT em alts caindo -10% era vetado (anti-trend vs macro BTC).
    # 6+ trades SHORT lucrativos hoje perdidos por isso.
    #
    # Agora: PAIR_CHANGE_24H domina regime do PAR. Macro é tie-breaker secundário.
    # Sistema agora detecta BUSDT -13% como BEAR_STRONG (independente de BTC macro).
    #
    # 2026-05-21 HYBRID FIX:
    # Backtest STRUCTURAL_BREAK BULL_WEAK+LONG=-0.37R foi calculado com regime semantics
    # (price>SMA200 + ADX<=25) -- DIFERENTE da triagem (change_24h + macro fallback).
    # Sistema vetava BTC consolidando intraday como "BULL_WEAK" mesmo o ativo NAO estando
    # na condicao backtest. Quando tech data (EMA200+ADX) disponivel, usar semantics
    # backtest-compat. Senao fallback ao change_24h legacy.
    #
    # 2026-06-03 PUMP FAKE FIX (Opção 1):
    # Change +112% SEM validacao técnica = pump fake em bear estrutural.
    # Com tech data (EMA200+ADX+PDI/NDI): validar BULL_STRONG antes de retornar.
    # - Se preço ABAIXO EMA200: pump fake -> BEAR_WEAK
    # - Se preço ACIMA EMA200 MAS ADX<=25: bounce sem força -> BULL_WEAK
    # - Se preço ACIMA EMA200 MAS NDI>PDI + ADX>25: pump em downtrend -> BEAR_STRONG
    #
    # Regras (por par):
    #   change >= +15%  -> BULL_STRONG (IFF confirmação técnica; senão BEAR_WEAK/BULL_WEAK)
    #   change >= +5%   -> BULL_WEAK ou TRANSITION_UP (se macro bullish)
    #   change >= +2%   -> TRANSITION_UP ou SIDEWAYS
    #   change ±2%      -> SIDEWAYS
    #   change <= -2%   -> BEAR_WEAK
    #   change <= -8%   -> BEAR_STRONG
    #   change <= -20%  -> CAPITULATION
    param(
        [int]$Score,
        [string]$MacroBias,
        [double]$PairChange24h = 0.0,
        # HYBRID 2026-05-21 — backtest-compat semantics quando tech data disponivel
        [Nullable[double]]$CurrentPrice = $null,
        [Nullable[double]]$Ema200       = $null,
        [Nullable[double]]$Adx          = $null,
        [Nullable[double]]$Pdi          = $null,
        [Nullable[double]]$Ndi          = $null
    )

    # Helper: verificar se tech data disponível
    $hasTechData = ($null -ne $CurrentPrice -and $null -ne $Ema200 -and $Ema200 -gt 0 -and `
                    $null -ne $Adx -and $null -ne $Pdi -and $null -ne $Ndi)

    # Pair-specific dominates (regras change_24h fortes, mas com pump fake detection)
    if ($PairChange24h -ge 15) {
        # PUMP FAKE DETECTION: change +15%+ MAS validar tech
        if ($hasTechData) {
            $price  = [double]$CurrentPrice
            $ema200 = [double]$Ema200
            $adx    = [double]$Adx
            $pdi    = [double]$Pdi
            $ndi    = [double]$Ndi

            # Pump fake: pump (+112%) MAS abaixo EMA200 = continuação de downtrend
            if ($price -lt $ema200) { return "BEAR_WEAK" }

            # Pump acima EMA200 MAS sem força (ADX baixo) = bounce
            if ($adx -le 25) { return "BULL_WEAK" }

            # Pump acima EMA200 + ADX forte MAS downtrend (NDI>PDI) = sucker's pump
            if ($ndi -gt $pdi) { return "BEAR_STRONG" }

            # Pump validado: acima EMA200 + ADX>25 + uptrend (PDI>NDI)
            return "BULL_STRONG"
        }
        # Sem tech data: legacy (retorna BULL_STRONG direto)
        return "BULL_STRONG"
    }

    # Regras negativas (downtrend) — não requerem pump fake detection
    if ($PairChange24h -le -20) { return "CAPITULATION" }
    if ($PairChange24h -le -8)  { return "BEAR_STRONG" }
    if ($PairChange24h -le -2)  { return "BEAR_WEAK" }

    # Ranges positivos moderados (+5 a +15%)
    if ($PairChange24h -ge 5) {
        if ($hasTechData) {
            $price  = [double]$CurrentPrice
            $ema200 = [double]$Ema200
            $adx    = [double]$Adx
            $pdi    = [double]$Pdi
            $ndi    = [double]$Ndi
            # Tech validation: validação técnica BULL_STRONG
            if ($price -lt $ema200) { return "TRANSITION_UP" }  # pump fake: abaixo EMA
            if ($adx -le 25) { return "BULL_WEAK" }             # sem força: ADX baixo
            if ($ndi -gt $pdi) { return "BEAR_WEAK" }           # downtrend: NDI>PDI
            # Confirmado: acima EMA200 + ADX>25 + uptrend (PDI>NDI)
            return "BULL_STRONG"
        }
        # Legacy: macro driven
        if ($MacroBias -eq "BULLISH") { return "BULL_STRONG" }
        return "BULL_WEAK"
    }

    if ($PairChange24h -ge 2)  { return "TRANSITION_UP" }
    if ($PairChange24h -le -1) { return "TRANSITION_DOWN" }

    # Sideways range (-1 a +2%) — zona AMBIGUA:
    # HYBRID 2026-05-21: se tech data disponivel, classificar com semantics backtest.
    # Senao fallback legacy (que tinha bug de marcar BULLISH macro como BULL_WEAK
    # invariavelmente, ativando blacklist STRUCTURAL_BREAK).
    if ($null -ne $CurrentPrice -and $null -ne $Ema200 -and $Ema200 -gt 0 -and `
        $null -ne $Adx -and $null -ne $Pdi -and $null -ne $Ndi) {
        $price  = [double]$CurrentPrice
        $ema200 = [double]$Ema200
        $adx    = [double]$Adx
        $pdi    = [double]$Pdi
        $ndi    = [double]$Ndi

        # Strict backtest semantics
        if ($price -lt $ema200) {
            # Below EMA200 -> BEAR (acompanha macro structural)
            if ($adx -gt 25 -and $ndi -gt $pdi) { return "BEAR_STRONG" }
            return "BEAR_WEAK"
        }
        # Price >= EMA200
        if ($adx -gt 25 -and $pdi -gt $ndi) {
            return "BULL_STRONG"
        }
        # Price >= EMA200 mas ADX fraco / direcao indefinida
        # Backtest semantics: BULL_WEAK (mantem blacklist STRUCTURAL_BREAK).
        # NOTE: esta eh a condicao legitima onde -0.37R historicamente acontece.
        return "BULL_WEAK"
    }

    # Fallback legacy (sem tech data) — comportamento anterior preservado.
    switch ($MacroBias) {
        "BULLISH" { return "BULL_WEAK" }
        "BEARISH" { return "BEAR_WEAK" }
        default   { return "SIDEWAYS" }
    }
}


function _Compute-DirectionFromRegime {
    # BULL_*               -> LONG
    # BEAR_* / CAPITULATION / TRANSITION_DOWN -> SHORT
    # TRANSITION_UP / SIDEWAYS / desconhecido -> LONG (default)
    param([string]$Regime)
    if ($Regime -like "BULL_*")          { return "LONG" }
    if ($Regime -like "BEAR_*")          { return "SHORT" }
    if ($Regime -eq "CAPITULATION")      { return "SHORT" }
    if ($Regime -eq "TRANSITION_DOWN")   { return "SHORT" }
    return "LONG"
}


function _Derive-Tags {
    param([string]$MacroBias, [string]$DayOfWeek, [string]$MarketTier, [int]$Score)
    $tags = New-Object System.Collections.ArrayList
    switch ($MacroBias) {
        "BEARISH"  { $null = $tags.Add("bear"); $null = $tags.Add("macro_bear") }
        "BULLISH"  { $null = $tags.Add("bull"); $null = $tags.Add("macro_bull") }
        default    { $null = $tags.Add("neutral") }
    }
    if ($DayOfWeek -eq "Thursday") { $null = $tags.Add("thursday") }
    if ($MarketTier -eq "alt")     { $null = $tags.Add("altcoin"); $null = $tags.Add("micro") }
    if ($Score -lt 50)             { $null = $tags.Add("risk"); $null = $tags.Add("prudencia") }
    if ($Score -ge 80)             { $null = $tags.Add("convicao"); $null = $tags.Add("livermore") }
    return $tags.ToArray()
}


function _Default-Razao {
    param([string]$Tier, [int]$Score, [string]$MacroBias, [string]$DayOfWeek, [string]$MarketTier)
    switch ($Tier) {
        "A" { return "Tier A: score $Score com macro $MacroBias e $DayOfWeek favoravel" }
        "B" { return "Tier B: score $Score com macro $MacroBias dentro de banda neutra" }
        "C" { return "Tier C: score $Score insuficiente ou macro $MacroBias contrario" }
        "D" {
            if ($DayOfWeek -eq "Thursday" -and $MarketTier -eq "alt") {
                return "Tier D: quinta-feira em altcoin (DoW empirico -1.03%/d, 9% positivos)"
            }
            return "Tier D: score $Score muito baixo ou macro $MacroBias fortemente contrario"
        }
        default { return "Tier indefinido para score $Score" }
    }
}


function Invoke-Triagem {
    param(
        [string]$Market,
        [PSCustomObject]$Context
    )

    $start = Get-Date

    # ── 1. Extrair contexto com defaults seguros ──────────────────────────────
    $score      = [int](_Get-CtxField $Context "scanner.score" 50)
    $macroBias  = [string](_Get-CtxField $Context "macro.macro_bias" "NEUTRAL")
    $dow        = [string](_Get-CtxField $Context "seasonal.dayOfWeek" "Wednesday")
    $tier_mkt   = [string](_Get-CtxField $Context "seasonal.marketTier" "btc")
    $momentSc   = [int](_Get-CtxField $Context "seasonal.momentScore" 50)

    # ── 2. Calcular tier deterministico ───────────────────────────────────────
    $tier = _Compute-Tier -Score $score -MacroBias $macroBias -DayOfWeek $dow -MarketTier $tier_mkt

    # ── 2b. Regime + direction (Wave 2.5 -- consumido pelo whitelist gate) ────
    # v3 2026-05-16: passar pair change_24h para regime per-pair (não macro-only)
    # 2026-05-21 HYBRID: fetch tech data (EMA200+ADX+PDI+NDI) para semantics backtest-compat.
    # Sem tech data -> fallback ao change_24h legacy.
    $pairChange24h = 0.0
    try {
        # Compatibilidade: aceita scanner.change (nested) ou pair_change_24h (top-level)
        if ($null -ne $Context.pair_change_24h) {
            $pairChange24h = [double]$Context.pair_change_24h
        } elseif ($null -ne $Context.scanner.change) {
            $pairChange24h = [double]$Context.scanner.change
        }
    } catch {}

    $hyCurrentPrice = $null; $hyEma200 = $null
    $hyAdx = $null; $hyPdi = $null; $hyNdi = $null

    # 2026-06-03: Accept tech data from Context (testability) OR fetch via Get-TechData (prod)
    # Priority: Context.tech > Context.{flat} > Get-TechData API
    # Context.tech aceita PSCustomObject OR hashtable (testability)
    try {
        # Path 1: Nested Context.tech (PSCustomObject ou hashtable)
        if ($null -ne $Context.tech) {
            $tech = $Context.tech
            if ($tech -is [PSCustomObject]) {
                if ($tech.PSObject.Properties['current_price']) { $hyCurrentPrice = [double]$tech.current_price }
                if ($tech.PSObject.Properties['ema200']) { $hyEma200 = [double]$tech.ema200 }
                if ($tech.PSObject.Properties['adx']) { $hyAdx = [double]$tech.adx }
                if ($tech.PSObject.Properties['pdi']) { $hyPdi = [double]$tech.pdi }
                if ($tech.PSObject.Properties['ndi']) { $hyNdi = [double]$tech.ndi }
            } elseif ($tech -is [Hashtable]) {
                if ($tech.ContainsKey('current_price')) { $hyCurrentPrice = [double]$tech['current_price'] }
                if ($tech.ContainsKey('ema200')) { $hyEma200 = [double]$tech['ema200'] }
                if ($tech.ContainsKey('adx')) { $hyAdx = [double]$tech['adx'] }
                if ($tech.ContainsKey('pdi')) { $hyPdi = [double]$tech['pdi'] }
                if ($tech.ContainsKey('ndi')) { $hyNdi = [double]$tech['ndi'] }
            }
        }
        # Path 2: Flat Context top-level
        if ($null -ne $Context.current_price -and -not $hyCurrentPrice) { $hyCurrentPrice = [double]$Context.current_price }
        if ($null -ne $Context.ema200 -and -not $hyEma200) { $hyEma200 = [double]$Context.ema200 }
        if ($null -ne $Context.adx -and -not $hyAdx) { $hyAdx = [double]$Context.adx }
        if ($null -ne $Context.pdi -and -not $hyPdi) { $hyPdi = [double]$Context.pdi }
        if ($null -ne $Context.ndi -and -not $hyNdi) { $hyNdi = [double]$Context.ndi }
    } catch {}

    # Path 3: Fetch via Get-TechData API (production)
    try {
        if ((-not $hyEma200 -or -not $hyAdx) -and (Get-Command Get-TechData -ErrorAction SilentlyContinue)) {
            $td = Get-TechData -Market $Market -ErrorAction SilentlyContinue
            if ($td) {
                $tfRef = if ($td.tf1d) { $td.tf1d } else { $td.tf1h }
                if ($tfRef) {
                    if ($tfRef.PSObject.Properties['ema200'] -and -not $hyEma200) { $hyEma200 = [double]$tfRef.ema200 }
                    if ($tfRef.PSObject.Properties['adx'] -and -not $hyAdx) {
                        $hyAdx = [double]$tfRef.adx.adx
                        $hyPdi = [double]$tfRef.adx.pdi
                        $hyNdi = [double]$tfRef.adx.ndi
                    }
                    if ($tfRef.PSObject.Properties['close'] -and -not $hyCurrentPrice) { $hyCurrentPrice = [double]$tfRef.close }
                }
                # Price preferencial vem do tf1h close (mais recente)
                if ($td.tf1h -and $td.tf1h.PSObject.Properties['close']) {
                    $hyCurrentPrice = [double]$td.tf1h.close
                }
            }
        }
    } catch {}

    $regime    = _Compute-RegimeFromContext -Score $score -MacroBias $macroBias -PairChange24h $pairChange24h `
                    -CurrentPrice $hyCurrentPrice -Ema200 $hyEma200 -Adx $hyAdx -Pdi $hyPdi -Ndi $hyNdi

    # 2026-06-08: BIDIRECIONAL -- avalia LONG e SHORT, detecta bear/bull traps por confluencia.
    # Carrega lib central (defensivo) se ainda nao disponivel no escopo.
    if (-not (Get-Command Resolve-TradeDirection -ErrorAction SilentlyContinue)) {
        $__bidirLib = Join-Path $PSScriptRoot "lib_bidirectional_direction.ps1"
        if (Test-Path $__bidirLib) { . $__bidirLib }
    }
    $direction = $null
    $directionMeta = $null
    if (Get-Command Resolve-TradeDirection -ErrorAction SilentlyContinue) {
        try {
            $directionMeta = Resolve-TradeDirection -Regime $regime `
                -Change24h ([double]$pairChange24h) `
                -Pdi (if ($null -ne $hyPdi) { [double]$hyPdi } else { 0 }) `
                -Ndi (if ($null -ne $hyNdi) { [double]$hyNdi } else { 0 }) `
                -Adx (if ($null -ne $hyAdx) { [double]$hyAdx } else { 0 }) `
                -CurrentPrice (if ($null -ne $hyCurrentPrice) { [double]$hyCurrentPrice } else { 0 }) `
                -Ema200 (if ($null -ne $hyEma200) { [double]$hyEma200 } else { 0 })
            $direction = $directionMeta.direction
            if ($directionMeta.source -ne "regime") {
                Write-Host "  [Triagem BIDIR] $Market $($directionMeta.source): $($directionMeta.reason)" -ForegroundColor Magenta
            }
        } catch {
            $direction = $null
        }
    }
    # Fallback legado: regime puro (se lib indisponivel ou erro)
    if (-not $direction) { $direction = _Compute-DirectionFromRegime -Regime $regime }

    # 2026-06-08: CONSUMO DO APRENDIZADO -- ajusta conviction pelo historico real.
    # Carrega learned_multipliers.json (job periodico) e aplica multiplier por
    # (source,direction,regime). Sem dados confiaveis -> neutro (nao altera).
    if ($directionMeta -and (Get-Command Apply-LearnedConviction -ErrorAction SilentlyContinue)) {
        try {
            $statPath = Join-Path $global:JOURNAL_DIR "learned_multipliers.json"
            $learned = Get-LearnedStats -Path $statPath
            if (@($learned).Count -gt 0) {
                $baseConv = [int]$directionMeta.conviction
                $adjConv  = Apply-LearnedConviction -BaseConviction $baseConv -Stats $learned `
                    -Source $directionMeta.source -Direction $direction -Regime $regime
                if ($adjConv -ne $baseConv) {
                    Write-Host "  [Triagem LEARN] $Market conviction $baseConv -> $adjConv (historico $($directionMeta.source)|$direction|$regime)" -ForegroundColor DarkCyan
                    $directionMeta.conviction = $adjConv
                }
            }
        } catch { }
    }

    # ── 3. Knowledge retrieval para enriquecer prompt ─────────────────────────
    $tags = _Derive-Tags -MacroBias $macroBias -DayOfWeek $dow -MarketTier $tier_mkt -Score $score
    $kbChunks = @()
    try {
        $kbChunks = Get-RelevantKnowledge -Tags $tags -MaxChunks 2
        if ($null -eq $kbChunks) { $kbChunks = @() }
    } catch {
        $kbChunks = @()
    }
    $kbCited = @()
    foreach ($c in $kbChunks) {
        $kbCited += "$($c.source):$($c.tag)"
    }

    # ── 4. Montar payload para Groq (razao + flags enriquecidos) ──────────────
    $kbText = ""
    foreach ($c in $kbChunks) {
        $kbText += "`n--- $($c.source) [$($c.tag)] ---`n$($c.text)`n"
    }
    if ([string]::IsNullOrWhiteSpace($kbText)) { $kbText = "(sem knowledge match)" }

    $userPayload = @"
Market: $Market
ScannerScore: $score
MacroBias: $macroBias
DayOfWeek: $dow
MarketTier: $tier_mkt
SeasonalMomentScore: $momentSc
TierDeterministico: $tier

Knowledge relevante:
$kbText

Retorne JSON com chaves: razao (frase curta sobre o setup), flags (array de strings curtas), score_predicted (0-100 ajustado).
"@

    $systemPrompt = @"
Voce e um analista quant da escola Lopez de Prado / Markowitz / Renaissance Technologies.
Seu papel: triagem estatistica RAPIDA (Drone Batedor) — separa setups com edge mensuravel
de ruido sem viés narrativo. Sem fé. Sem story. Só métricas.

Frameworks que voce aplica em cada setup:
- DSR (Deflated Sharpe Ratio) — se setup nao passa rigor cross-period, eh ruido
- Triple barrier method — entry/stop/target deve ter R:R >= 3
- Meta-labeling — confluencia de >= 3 fatores independentes
- Volatility-targeted sizing — ATR-aware
- Anti-fade rules: RSI extremo SOZINHO NAO eh sinal (Lopez de Prado §17)

Sua DECISAO de tier (output):
- Tier A: score quantitativo TOP-DECIL + macro alinhado + DoW favoravel
  (raríssimo — só setups com edge claro cross-period)
- Tier B: score quartil 75+ + macro neutro/alinhado
- Tier C: score mediano, sem catalisador claro
- Tier D: ruido — abortar sem custo

Output JSON: razao (1 frase tecnica, sem floreio), flags (0-4 strings: ex
macro_aligned, dow_favoravel, oversold_extreme, low_volume, hit_target_freq_low),
score_predicted (0-100 — score quantitativo PREDIZIDO baseado em historico).

Responda APENAS JSON valido (sem markdown).
"@

    # ── 5. Chamar Groq com fallback robusto ───────────────────────────────────
    $razao           = $null
    $flags           = @()
    $scorePredicted  = $score

    try {
        # Cascade Triagem 2026-05-16: Gemini primary -> Groq fallback.
        # Triagem é classificação tier (baixa criticidade), free tier suficiente.
        if (Get-Command Invoke-TriagemCascade -ErrorAction SilentlyContinue) {
            $raw = Invoke-TriagemCascade -SystemPrompt $systemPrompt -UserContent $userPayload `
                -MaxTokens 400 -Temperature 0.3 -Agent "triagem"
            $resp = $null
            if ($raw) {
                try {
                    $cleaned = $raw -replace '```json\s*','' -replace '```\s*','' -replace '^\s+','' -replace '\s+$',''
                    $resp = $cleaned | ConvertFrom-Json
                } catch { $resp = $null }
            }
        } else {
            $resp = Invoke-GroqJson `
                -SystemPrompt $systemPrompt `
                -UserContent $userPayload `
                -Model "llama-3.3-70b-versatile" `
                -MaxTokens 400 `
                -Temperature 0.3 `
                -MaxRetries 2 `
                -Agent "triagem"
        }

        if ($resp) {
            if ($resp.razao) { $razao = [string]$resp.razao }
            if ($resp.flags) {
                $flagsRaw = $resp.flags
                if ($flagsRaw -is [array]) {
                    $flags = @($flagsRaw | ForEach-Object { [string]$_ })
                } elseif ($flagsRaw -is [string]) {
                    $flags = @($flagsRaw)
                }
            }
            if ($null -ne $resp.score_predicted) {
                $sp = 0
                if ([int]::TryParse([string]$resp.score_predicted, [ref]$sp)) {
                    if ($sp -ge 0 -and $sp -le 100) { $scorePredicted = $sp }
                }
            }
        }
    } catch {
        # silent fallback
    }

    if ([string]::IsNullOrWhiteSpace($razao)) {
        $razao = _Default-Razao -Tier $tier -Score $score -MacroBias $macroBias -DayOfWeek $dow -MarketTier $tier_mkt
    }

    $latency = [int]((Get-Date) - $start).TotalMilliseconds

    return [PSCustomObject]@{
        tier             = $tier
        razao            = $razao
        score_predicted  = $scorePredicted
        flags            = @($flags)
        knowledge_cited  = @($kbCited)
        latency_ms       = $latency
        regime           = $regime
        direction        = $direction
        # 2026-06-08: expoe metadados bidirecionais p/ signal snapshot (aprendizado)
        direction_source = if ($directionMeta) { $directionMeta.source } else { "regime" }
        signals_long     = if ($directionMeta) { [int]$directionMeta.signals_long } else { 0 }
        signals_short    = if ($directionMeta) { [int]$directionMeta.signals_short } else { 0 }
        conviction       = if ($directionMeta) { [int]$directionMeta.conviction } else { 0 }
    }
}

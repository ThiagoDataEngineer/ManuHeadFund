# lib_stop_loss_calibration_study.ps1
# Estudo de evolução: Stop Loss dedicado por moeda (não % fixo)
#
# OBJETIVO: Substituir SL% hardcoded (-8%) por sistema inteligente que:
#   1. Considera volatilidade individual (ATR)
#   2. Adapta por regime (BEAR_STRONG = mais espaço)
#   3. Usa gráficos (wick típico, close vs high/low)
#   4. Valida via backtest (menos false positives)
#
# FÓRMULAS CANDIDATAS:
#   A. ATR-based (simples)
#   B. ATR + Wick percentile (robusto)
#   C. Regime-aware ATR (adaptivo)
#   D. Hybrid (gráfico + ATR validation)

# ============================================================================
# FÓRMULA A: ATR-Based (Simples, implementável agora)
# ============================================================================
# Conceito: SL = Entry - (N * ATR_14_daily)
#
# Parâmetros:
#   ATR_14_daily = volatilidade típica de 14 dias
#   N = multiplier (2.0-3.0 recomendado)
#
# Vantagens:
#   ✓ Adaptado ao ativo automaticamente
#   ✓ Simples de implementar
#   ✓ Código já existe em lib_atr_stop.ps1
#
# Desvantagens:
#   ✗ Não considera gráfico real (wick observado)
#   ✗ Pode ser ainda apertado em extremos

function Get-SLByATR {
    <#
    .SYNOPSIS
    Calcula Stop Loss baseado em ATR.

    .PARAMETER Entry
    Preço de entrada

    .PARAMETER ATR14Daily
    ATR(14) do gráfico diário (absolute, não %)

    .PARAMETER Direction
    'long' ou 'short'

    .PARAMETER Multiplier
    Fator de risco (2.0 = conservador, 3.0 = espaçoso)

    .EXAMPLE
    Get-SLByATR -Entry 69.10 -ATR14Daily 8.5 -Direction "long" -Multiplier 2.5
    # CRCLX: Entry 69.10, ATR 8.5 → SL = 69.10 - (2.5*8.5) = 47.95 (≈ -30%)
    #>
    param(
        [double]$Entry,
        [double]$ATR14Daily,
        [ValidateSet("long","short")][string]$Direction = "long",
        [double]$Multiplier = 2.5
    )

    $offset = $ATR14Daily * $Multiplier
    if ($Direction -eq "long") {
        return $Entry - $offset
    } else {
        return $Entry + $offset
    }
}

# ============================================================================
# FÓRMULA B: ATR + Wick Percentile (Robusto, 1-2 semanas)
# ============================================================================
# Conceito: Usa histórico de wicks (H-L) para encontrar "break point"
#
# Algoritmo:
#   1. Fetch últimas 100 velas D1
#   2. Calcular wick% = (High - Low) / Close * 100 para cada vela
#   3. Encontrar P95 (95º percentil) = wick máximo "normal" (5% outlier)
#   4. SL = Entry - (P95 * 1.2)  # 20% buffer por segurança
#
# Vantagens:
#   ✓ Baseado em gráfico real (não assume distribuição)
#   ✓ Captura comportamento específico do ativo
#   ✓ Reduz false positives (apenas 5% de wicks quebram SL)
#
# Desvantagens:
#   ✗ Requer mais dados (100 velas)
#   ✗ Precisa validação em produção

function Get-SLByWickPercentile {
    <#
    .SYNOPSIS
    Calcula SL usando histórico de wicks (High - Low).

    .PARAMETER Entry
    Preço de entrada

    .PARAMETER Candles
    Array de candles { high, low, close }

    .PARAMETER Percentile
    Usar qual percentil de wick (default 95 = top 5%)

    .PARAMETER BufferFactor
    Multiplicador de segurança (default 1.2 = +20%)

    .EXAMPLE
    $candles = @( @{high=70; low=65; close=68}, ... )
    Get-SLByWickPercentile -Entry 69 -Candles $candles -Percentile 95
    # CRCLX wicks: [1%, 2%, 3%, ..., 15%, 18%, 20%] → P95=18%
    # SL = 69 - (69 * 0.18 * 1.2) = 69 - 14.9 = 54.1 (≈ -22%)
    #>
    param(
        [double]$Entry,
        [PSCustomObject[]]$Candles,
        [int]$Percentile = 95,
        [double]$BufferFactor = 1.2
    )

    if (-not $Candles -or $Candles.Count -lt 10) {
        return 0  # Fallback
    }

    $wickPercents = @()
    foreach ($c in $Candles) {
        if ($c.close -gt 0) {
            $wickPct = (($c.high - $c.low) / $c.close) * 100
            $wickPercents += $wickPct
        }
    }

    $wickPercents = $wickPercents | Sort-Object
    $index = [math]::Floor(($Percentile / 100) * $wickPercents.Count) - 1
    $p95Wick = if ($index -ge 0 -and $index -lt $wickPercents.Count) { $wickPercents[$index] } else { 5.0 }

    $slPercent = $p95Wick * $BufferFactor
    return $Entry * (1 - ($slPercent / 100))
}

# ============================================================================
# FÓRMULA C: Regime-Aware ATR (Adaptivo, implementável agora)
# ============================================================================
# Conceito: SL = Entry - (ATR * N * REGIME_MULTIPLIER)
#
# Regime Multipliers:
#   BEAR_WEAK:    × 1.0  (espaço normal)
#   BEAR_STRONG:  × 1.3  (espaço +30% por segurança)
#   BULL_WEAK:    × 0.9  (reduz, mais confiança)
#   BULL_STRONG:  × 0.8  (reduz, alta confiança)
#
# Vantagens:
#   ✓ Adapta automático ao regime
#   ✓ Implementação simples (apenas multiplica)
#   ✓ Evita false positives em BEAR_STRONG
#
# Exemplo CRCLX em BEAR_STRONG:
#   Entry: 69.10
#   ATR(14): 8.5
#   N: 2.5
#   Regime: BEAR_STRONG (×1.3)
#   SL = 69.10 - (8.5 * 2.5 * 1.3) = 69.10 - 27.625 = 41.475 (≈ -40%)

function Get-SLByRegimeAwareBATR {
    <#
    .SYNOPSIS
    ATR com ajuste por regime.

    .PARAMETER Entry
    Preço de entrada

    .PARAMETER ATR14Daily
    ATR(14) diário

    .PARAMETER Direction
    'long' ou 'short'

    .PARAMETER Regime
    BEAR_WEAK, BEAR_STRONG, BULL_WEAK, BULL_STRONG

    .PARAMETER BaseMultiplier
    Multiplicador base (default 2.5)
    #>
    param(
        [double]$Entry,
        [double]$ATR14Daily,
        [ValidateSet("long","short")][string]$Direction = "long",
        [ValidateSet("BEAR_WEAK","BEAR_STRONG","BULL_WEAK","BULL_STRONG")][string]$Regime = "BEAR_WEAK",
        [double]$BaseMultiplier = 2.5
    )

    $regimeMultipliers = @{
        "BEAR_WEAK"    = 1.0
        "BEAR_STRONG"  = 1.3
        "BULL_WEAK"    = 0.9
        "BULL_STRONG"  = 0.8
    }

    $regimeMult = $regimeMultipliers[$Regime]
    $finalMult = $BaseMultiplier * $regimeMult
    $offset = $ATR14Daily * $finalMult

    if ($Direction -eq "long") {
        return $Entry - $offset
    } else {
        return $Entry + $offset
    }
}

# ============================================================================
# FÓRMULA D: Hybrid (Gráfico + ATR Validation, final 2-3 semanas)
# ============================================================================
# Conceito: Combine histórico de gráfico com ATR como cross-validation
#
# Algoritmo:
#   1. Calcular SL via Fórmula B (wick percentile)
#   2. Calcular SL via Fórmula C (regime-aware ATR)
#   3. Usar MÁXIMO dos dois (mais seguro)
#   4. Validar: P(wick > SL) < 5%
#
# Vantagens:
#   ✓ Combina gráfico + automático
#   ✓ Máxima segurança (não hit por wick)
#   ✓ Regime-aware
#
# Desvantagens:
#   ✗ Mais complexo, mais computação

function Get-SLByHybrid {
    param(
        [double]$Entry,
        [double]$ATR14Daily,
        [PSCustomObject[]]$Candles,
        [ValidateSet("long","short")][string]$Direction = "long",
        [string]$Regime = "BEAR_WEAK",
        [double]$BaseMultiplier = 2.5
    )

    $slByATR = Get-SLByRegimeAwareBATR -Entry $Entry -ATR14Daily $ATR14Daily `
                                      -Direction $Direction -Regime $Regime `
                                      -BaseMultiplier $BaseMultiplier

    $slByWick = Get-SLByWickPercentile -Entry $Entry -Candles $Candles -Percentile 95

    # Para LONG: queremos SL mais baixo (mais seguro)
    # Para SHORT: queremos SL mais alto (mais seguro)
    if ($Direction -eq "long") {
        return [math]::Min($slByATR, $slByWick)  # Menor = mais seguro
    } else {
        return [math]::Max($slByATR, $slByWick)  # Maior = mais seguro
    }
}

# ============================================================================
# CONFIG POR MOEDA (Seu input via gráficos)
# ============================================================================
# Estrutura: Cada moeda tem seu próprio perfil
#
# Campos:
#   base_sl_pct: Fallback % se dados insuficientes
#   method: ATR | WICK | REGIME_ATR | HYBRID
#   atr_multiplier: Multiplicador base (2.0-3.0)
#   wick_percentile: Qual percentil (90-99)
#   regime_multiplier: Ajuste por regime (0.8-1.5)
#   description: Nota do gráfico (wick típico, vol, etc)

$STOP_LOSS_PER_ASSET_CONFIG = @{
    "BTCUSDT" = @{
        base_sl_pct        = -4.0
        method             = "REGIME_ATR"
        atr_multiplier     = 2.0
        wick_percentile    = 95
        regime_multiplier  = 1.0
        description        = "Macro stable, wick típ ±1-2%, leverage 10X → tight SL preserva margin"
        leverage           = 10
        note               = "Isolated mode, crítico não hit"
    }

    "CRCLXUSDT" = @{
        base_sl_pct        = -25.0
        method             = "HYBRID"
        atr_multiplier     = 2.5
        wick_percentile    = 95
        regime_multiplier  = 1.2
        description        = "Microcap, wick típ -10-15% normal, pump-fade, volatility extrema"
        leverage           = 3
        note               = "Use Hybrid (gráfico + ATR), não ATR só"
    }

    "DYDXUSDT" = @{
        base_sl_pct        = -16.0
        method             = "WICK"
        atr_multiplier     = 2.5
        wick_percentile    = 95
        regime_multiplier  = 1.2
        description        = "Microcap vol, wick típ -12-18%, defi-sensitive"
        leverage           = 3
        note               = "Track P95 wick, revalidar monthly"
    }

    "LRCUSDT" = @{
        base_sl_pct        = -20.0
        method             = "HYBRID"
        atr_multiplier     = 3.0
        wick_percentile    = 95
        regime_multiplier  = 1.3
        description        = "Extreme microcap, wick típ -15-25%, mais loose SL"
        leverage           = 3
        note               = "P95 or ATR×3, whichever is safer. Regime×1.3 em BEAR_STRONG"
    }

    "LDOUSDT" = @{
        base_sl_pct        = -10.0
        method             = "REGIME_ATR"
        atr_multiplier     = 2.2
        wick_percentile    = 90
        regime_multiplier  = 1.1
        description        = "Bluechip-ish, wick típ -6-8%, mais estável"
        leverage           = 3
        note               = "ATR straightforward, menos volatilidade que microcaps"
    }

    "PYTHUSDT" = @{
        base_sl_pct        = -14.0
        method             = "HYBRID"
        atr_multiplier     = 2.5
        wick_percentile    = 95
        regime_multiplier  = 1.2
        description        = "Microcap oracle, wick típ -10-12%, news-sensitive"
        leverage           = 3
        note               = "Monitor news impact on wicks, adjust P95 if needed"
    }

    "WAVESUSDT" = @{
        base_sl_pct        = -12.0
        method             = "REGIME_ATR"
        atr_multiplier     = 2.3
        wick_percentile    = 92
        regime_multiplier  = 1.15
        description        = "Medium vol, wick típ -8-10%, blockchain layer"
        leverage           = 3
        note               = "Stable, ATR sufficient, avoid over-optimization"
    }

    "SOLUSDT" = @{
        base_sl_pct        = 8.0   # SHORT: + é acima entry
        method             = "REGIME_ATR"
        atr_multiplier     = 2.0
        wick_percentile    = 92
        regime_multiplier  = 1.1
        is_short           = $true
        description        = "Macro, wick típ +6-8% (SHORT context), inflation hedge"
        leverage           = 5
        note               = "SHORT: wick sobe quando shorting, SL acima entry"
    }

    "WLDUSDT" = @{
        base_sl_pct        = 2.5    # SHORT: tight, low vol
        method             = "REGIME_ATR"
        atr_multiplier     = 1.8
        wick_percentile    = 90
        regime_multiplier  = 1.0
        is_short           = $true
        description        = "LOW volatility SHORT, wick típ +2-4%, gaming token"
        leverage           = 3
        note               = "Tight SL ok (low vol), watch for pump spikes"
    }

    "XRPUSDT" = @{
        base_sl_pct        = 1.5    # SHORT: CRÍTICO, preserve 0.5-1% margin
        method             = "REGIME_ATR"
        atr_multiplier     = 1.5
        wick_percentile    = 90
        regime_multiplier  = 1.0
        is_short           = $true
        leverage           = 50
        note               = "CRITICAL 50X, SL must preserve margin (liq 1.0894 vs entry 1.0788 = 0.98% dist)"
    }
}

# ============================================================================
# RECOMENDAÇÃO IMPLEMENTAÇÃO
# ============================================================================
#
# FASE 1 (hoje-2h): Deploy Fórmula C (Regime-Aware ATR)
#   • Mais simples, já temos lib_atr_stop.ps1
#   • Valida via backtest (últimas 100 trades)
#   • Ganho esperado: Win rate 30% → 40%
#
# FASE 2 (1 semana): Você valida gráficos + deploy Fórmula B (Wick)
#   • Para cada moeda, confirma wick típico
#   • Atualiza $STOP_LOSS_PER_ASSET_CONFIG["PAIR"].wick_percentile
#   • Ganho esperado: Win rate 40% → 45%
#
# FASE 3 (2 semanas): Deploy Fórmula D (Hybrid)
#   • Combina gráfico + ATR
#   • Máxima confiabilidade
#   • Ganho esperado: Win rate 45% → 50%+
#
# CRITICAL PATHS:
#   • XRPUSDT: Deploy TODAY (50X, liq risk)
#   • BTCUSDT: Deploy TODAY (10X, margin tight)
#   • CRCLX, LRC, DYDX: Deploy Fórmula B/Hybrid (microcaps, vol extrema)
#
# VALIDATION:
#   • Backtest: Última 100 trades com novo SL → count % wicks vs closures
#   • Live: Monitor "stops hit" vs "positions closed" ratio
#   •Expected: Wicks hit should be <5% (vs current ~40%)

# Export list (comentado 2026-07-09: Export-ModuleMember quebra dot-source; lista orfa causava parse error)
# (    'Get-SLByATR',
#    'Get-SLByWickPercentile',
#    'Get-SLByRegimeAwareBATR',
#    'Get-SLByHybrid'
# )




# lib_bidirectional_direction.ps1 -- Resolucao de direcao BIDIRECIONAL
# 2026-06-08: fonte unica de verdade p/ Triagem -> Mesa -> Mentor avaliarem LONG e SHORT.
#
# Problema que resolve: direcao era PURAMENTE regime-driven (BEAR->SHORT, BULL->LONG),
# ignorando reversoes. Bear traps (reversao de alta em bear) e bull traps (reversao de
# baixa em bull) tinham direcao forcada errada -> Mentor vetava "TORI SHORT e resistencia
# contra LONG" em vez de operar o SHORT.
#
# Design: FUNCAO PURA (testavel sem I/O). Fail-safe: precisa 2+ sinais concordando p/
# reverter o baseline do regime (1 sinal ruidoso NAO vira trade contra-tendencia).
#
# Sinais avaliados (cada um vota LONG | SHORT | NEUTRAL):
#   1. DI directional (PDI vs NDI) -- so conta se ADX>=20 (tendencia real, nao range)
#   2. Momentum (change24h) -- |change| >= 5% e significativo
#   3. Estrutura (price vs EMA200) -- bias estrutural de longo prazo

# ─────────────────────────────────────────────────────────────────────────────
# _DirectionFromRegime (PURA) -- baseline mono-direcional do regime.
# Identico ao legado _Compute-DirectionFromRegime (triagem) -- centralizado aqui.
# ─────────────────────────────────────────────────────────────────────────────
function _DirectionFromRegime {
    param([string]$Regime)
    if ($Regime -like "BULL_*")        { return "LONG" }
    if ($Regime -like "BEAR_*")        { return "SHORT" }
    if ($Regime -eq "CAPITULATION")    { return "SHORT" }
    if ($Regime -eq "TRANSITION_DOWN") { return "SHORT" }
    return "LONG"  # TRANSITION_UP / SIDEWAYS / desconhecido
}

# ─────────────────────────────────────────────────────────────────────────────
# Resolve-TradeDirection (PURA) -- decide direcao avaliando AMBOS sentidos.
# Output: { direction; source; conviction; signals_long; signals_short; reason }
#   source = "regime" | "bear_trap_reversal" | "bull_trap_reversal"
# ─────────────────────────────────────────────────────────────────────────────
function Resolve-TradeDirection {
    param(
        [string]$Regime,
        [double]$Change24h   = 0,
        [double]$Pdi         = 0,
        [double]$Ndi         = 0,
        [double]$Adx         = 0,
        [double]$CurrentPrice = 0,
        [double]$Ema200      = 0,
        [double]$MomentumThreshold = 5.0,  # % minimo p/ momentum contar
        [double]$AdxThreshold      = 20.0  # ADX minimo p/ DI contar (tendencia vs range)
    )

    $baseline = _DirectionFromRegime -Regime $Regime

    # ── Coleta votos dos 3 sinais (LONG | SHORT | NEUTRAL) ──
    # 1. DI directional -- so vale com tendencia (ADX>=threshold)
    $diVote = "NEUTRAL"
    if ($Adx -ge $AdxThreshold -and $Pdi -gt 0 -and $Ndi -gt 0) {
        if ($Pdi -gt $Ndi) { $diVote = "LONG" } elseif ($Ndi -gt $Pdi) { $diVote = "SHORT" }
    }

    # 2. Momentum -- change24h significativo
    $momVote = "NEUTRAL"
    if ($Change24h -ge $MomentumThreshold)      { $momVote = "LONG" }
    elseif ($Change24h -le (-$MomentumThreshold)) { $momVote = "SHORT" }

    # 3. Estrutura -- price vs EMA200 (so se ambos disponiveis)
    $structVote = "NEUTRAL"
    if ($CurrentPrice -gt 0 -and $Ema200 -gt 0) {
        if ($CurrentPrice -gt $Ema200) { $structVote = "LONG" } else { $structVote = "SHORT" }
    }

    $votes = @($diVote, $momVote, $structVote)
    $longVotes  = @($votes | Where-Object { $_ -eq "LONG" }).Count
    $shortVotes = @($votes | Where-Object { $_ -eq "SHORT" }).Count

    # ── Decisao: reverte baseline SO se 2+ sinais na direcao oposta ──
    $opposite      = if ($baseline -eq "LONG") { "SHORT" } else { "LONG" }
    $oppositeVotes = if ($baseline -eq "LONG") { $shortVotes } else { $longVotes }

    if ($oppositeVotes -ge 2) {
        $direction  = $opposite
        $source     = if ($baseline -eq "SHORT") { "bear_trap_reversal" } else { "bull_trap_reversal" }
        $conviction = [math]::Min(100, $oppositeVotes * 33 + 1)
        $trapName   = if ($source -eq "bear_trap_reversal") { "BEAR TRAP" } else { "BULL TRAP" }
        $reason     = "$trapName detectado: $oppositeVotes/3 sinais $opposite contra regime $Regime (DI=$diVote mom=$momVote struct=$structVote) -> reverte para $opposite"
    } else {
        $direction  = $baseline
        $source     = "regime"
        $alignVotes = if ($baseline -eq "LONG") { $longVotes } else { $shortVotes }
        $conviction = [math]::Min(100, 40 + $alignVotes * 20)
        $reason     = "Segue regime $Regime -> $baseline ($alignVotes/3 sinais alinhados; oposto $oppositeVotes insuficiente p/ reverter)"
    }

    return [PSCustomObject]@{
        direction     = $direction
        source        = $source
        conviction    = $conviction
        signals_long  = $longVotes
        signals_short = $shortVotes
        baseline      = $baseline
        reason        = $reason
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Resolve-MentorDirection (PURA) -- precedencia da direcao que chega ao Mentor.
# Ordem: explicito > Mesa(consenso tecnico) > Triagem(bidirecional c/ trap) > LONG.
# Fecha o gap do "LONG default cego": quando Mesa nao tem consenso, usa a direcao
# bidirecional da Triagem (que ja considera bear/bull traps) em vez de LONG fixo.
# ─────────────────────────────────────────────────────────────────────────────
function Resolve-MentorDirection {
    param(
        [string]$ExplicitDirection = "",
        [string]$MesaSignal        = "",
        [string]$TriagemDirection  = ""
    )
    if ($ExplicitDirection -in @("LONG","SHORT")) { return $ExplicitDirection }
    if ($MesaSignal       -in @("LONG","SHORT")) { return $MesaSignal }
    if ($TriagemDirection -in @("LONG","SHORT")) { return $TriagemDirection }
    return "LONG"
}

"""
signal_generator.py — TechAgent bar-a-bar sobre dados históricos
Regra crítica: bar[i] só usa candles[0..i] — ZERO lookahead bias.
Gera sinais COMPRA/VENDA/NEUTRO e persiste em backtest_signals.

Uso:
    python signal_generator.py --market BTCUSDT --period 1hour \
                               --start 2025-04-01 --end 2025-05-01
"""
import argparse
import os
import warnings
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from indicators import ema, rsi, atr, macd, bollinger, adx
from metrics import classify_regime

MIN_CANDLES = 35          # mínimo para MACD (26+9)
ATR_STOP_MULT = 2.0       # stop = entrada ± 2×ATR
RR_DEFAULT = 5.0          # alvo = entrada ± 5× risco (alinhado $RR_MINIMO config.ps1)
SCORE_THRESHOLD = 65.0    # score mínimo para gerar sinal acionável (alinhado config.ps1)
SMA200_PERIOD = 200       # regime filter: sideways via SMA200

# ── Regime-direction filter (paridade com agents/lib_operational_whitelist.ps1) ──
# Ref: memory/project_regime_matrix_14y_findings.md
#      memory/project_operational_whitelist_v2.md
VALID_REGIMES = (
    "BULL_STRONG", "BULL_WEAK", "SIDEWAYS", "TRANSITION_UP",
    "TRANSITION_DOWN", "BEAR_WEAK", "BEAR_STRONG", "CAPITULATION",
)

# Permissive: bloqueia apenas direção contra o regime (basic safety)
ALLOWED_PERMISSIVE = {
    "COMPRA": ("BULL_STRONG", "BULL_WEAK", "TRANSITION_UP"),
    "VENDA":  ("BEAR_STRONG", "BEAR_WEAK", "TRANSITION_DOWN", "CAPITULATION"),
}

# Strict v2: somente regimes com edge validado cross-period
# BULL_STRONG+LONG (+0.39R holdout), TRANSITION_UP+LONG+Mon BRT (+0.98R holdout)
# SHORT removido (0 regimes com edge cross-period)
# BULL_WEAK+LONG removido (STRUCTURAL_BREAK holdout, -0.37R em 2025)


_PHASE_ALLOWS_BULL_WEAK = {"phase_1_bull", "phase_4_recovery"}


def apply_regime_filter(
    signal: str,
    regime: Optional[str],
    mode: str = "off",
    day_of_week_brt: int = -1,
    halving_phase: Optional[str] = None,
    trendline_soft_passes: Optional[bool] = None,
) -> Tuple[str, str]:
    """
    Aplica filtro regime-direção sobre sinal já gerado.

    Args:
        signal: COMPRA | VENDA | NEUTRO
        regime: um dos 8 canônicos (ou None → no-op)
        mode: 'off' (default, backwards compat) | 'permissive' | 'strict_v2'
        day_of_week_brt: 0=Sun..6=Sat (BRT). -1 = desconhecido.

    Returns:
        (signal_final, razao_string). Nunca lança exceção.

    Modos:
        off         → não filtra (backwards compat default)
        permissive  → bloqueia LONG em BEAR_* e SHORT em BULL_*
        strict_v2   → whitelist v2: BULL_STRONG+LONG, TRANSITION_UP+LONG+Mon BRT
    """
    # NEUTRO passa por qualquer modo
    if signal == "NEUTRO":
        return signal, "filter_off"

    if mode == "off" or regime is None:
        return signal, "filter_off"

    # Regime inválido (fora dos 8 canônicos) → passa com warning, não força filter
    if regime not in VALID_REGIMES:
        warnings.warn(
            f"apply_regime_filter: regime inválido '{regime}' "
            f"(esperado um de {VALID_REGIMES}) — passando sinal sem filtrar.",
            stacklevel=2,
        )
        return signal, f"filter_passed:invalid_regime:{regime}"

    if mode == "permissive":
        allowed = ALLOWED_PERMISSIVE.get(signal)
        if allowed is not None and regime not in allowed:
            return "NEUTRO", f"regime_filter:permissive:{regime}_blocks_{signal}"
        return signal, "filter_passed"

    if mode == "strict_v2":
        if signal == "COMPRA":
            if regime == "BULL_STRONG":
                return signal, "v2_bull_strong_long"
            if regime == "TRANSITION_UP" and day_of_week_brt == 1:
                return signal, "v2_transition_up_mon"
            return "NEUTRO", f"regime_filter:strict_v2:{regime}_+_LONG_blocked"
        if signal == "VENDA":
            return "NEUTRO", "regime_filter:strict_v2:SHORT_disabled"
        return signal, "filter_passed"

    if mode == "strict_v3":
        # v3: LONG mantém v2 + SHORT habilitado em BEAR_*/CAPITULATION/TRANSITION_DOWN
        # 2026-05-19: BULL_WEAK LONG conditional (phase + trendline.soft 5-15deg)
        if signal == "COMPRA":
            if regime == "BULL_STRONG":
                return signal, "v3_bull_strong_long"
            if regime == "TRANSITION_UP" and day_of_week_brt == 1:
                return signal, "v3_transition_up_mon_long"
            if regime == "BULL_WEAK":
                if halving_phase is None or trendline_soft_passes is None:
                    return "NEUTRO", "regime_filter:strict_v3:BULL_WEAK_needs_phase_and_trendline"
                if halving_phase not in _PHASE_ALLOWS_BULL_WEAK:
                    return "NEUTRO", f"regime_filter:strict_v3:BULL_WEAK_phase_{halving_phase}_blocked"
                if not trendline_soft_passes:
                    return "NEUTRO", "regime_filter:strict_v3:BULL_WEAK_trendline_soft_failed"
                return signal, f"v3_bull_weak_long_{halving_phase}_trendline_aplus"
            return "NEUTRO", f"regime_filter:strict_v3:{regime}_+_LONG_blocked"
        if signal == "VENDA":
            if regime in ("BEAR_STRONG", "CAPITULATION", "TRANSITION_DOWN"):
                return signal, f"v3_{regime.lower()}_short"
            return "NEUTRO", f"regime_filter:strict_v3:{regime}_+_SHORT_blocked"
        return signal, "filter_passed"

    # Modo desconhecido → no-op defensivo (não bloqueia)
    warnings.warn(
        f"apply_regime_filter: mode desconhecido '{mode}' — passando sinal sem filtrar.",
        stacklevel=2,
    )
    return signal, f"filter_passed:unknown_mode:{mode}"


@dataclass
class SignalResult:
    signal: str           # COMPRA | VENDA | NEUTRO
    score: float          # 0-100
    entry_price: float
    stop_loss: float
    take_profit: float
    atr: float
    indicators: Dict = field(default_factory=dict)

    @property
    def rr_ratio(self) -> float:
        risk = abs(self.entry_price - self.stop_loss)
        reward = abs(self.take_profit - self.entry_price)
        return reward / risk if risk > 0 else 0.0

    @property
    def is_actionable(self) -> bool:
        return self.signal in ("COMPRA", "VENDA") and self.rr_ratio >= 2.0


def calc_stop_atr(candles: List[Dict], direction: str, multiplier: float = ATR_STOP_MULT) -> float:
    closes = [c["close"] for c in candles]
    atr_val = atr(candles, period=14)
    entry = closes[-1]
    if direction == "LONG":
        return entry - multiplier * atr_val
    return entry + multiplier * atr_val


def calc_target(entry: float, stop: float, direction: str, rr: float = RR_DEFAULT) -> float:
    risk = abs(entry - stop)
    if direction == "LONG":
        return entry + rr * risk
    return entry - rr * risk


def generate_signal(
    candles: List[Dict],
    regime: Optional[str] = None,
    regime_filter_mode: str = "off",
    day_of_week_brt: int = -1,
    halving_phase: Optional[str] = None,
    trendline_soft_passes: Optional[bool] = None,
) -> SignalResult:
    """
    Gera sinal para o último bar da série.
    Usa apenas os candles fornecidos — nunca olha além deles.

    Args:
        candles: lista de candles OHLCV (apenas [0..i], zero lookahead)
        regime: regime detectado externamente (opcional; um dos 8 canônicos)
        regime_filter_mode: 'off' (default) | 'permissive' | 'strict_v2'
        day_of_week_brt: 0=Sun..6=Sat (BRT); usado por strict_v2 para TRANSITION_UP

    Backwards compat: sem kwargs → comportamento original preservado.
    """
    entry = candles[-1]["close"] if candles else 0.0
    neutral = SignalResult(
        signal="NEUTRO", score=50.0,
        entry_price=entry,
        stop_loss=entry * 0.98,
        take_profit=entry * 1.06,
        atr=0.0, indicators={},
    )

    if len(candles) < MIN_CANDLES:
        return neutral

    closes = [c["close"] for c in candles]
    score_bullish = 0
    score_bearish = 0
    indicators = {}
    max_points = 0

    # ── Trend state (usado para evitar fade de tendencia em RSI/BB) ──────────
    # Ref: knowledge/INDICATORS_REFERENCE.md:96-99 (RSI alto em trend = forca)
    # Ref: knowledge/INDICATORS_REFERENCE.md:173-175 (BB walking em trend != reversao)
    trend_dir = "flat"
    try:
        _adx_pre = adx(candles, period=14)
        _ema9_pre = ema(closes, 9)
        _ema21_pre = ema(closes, 21)
        if _adx_pre["adx"] > 25:
            if _ema9_pre > _ema21_pre and _adx_pre["pdi"] > _adx_pre["ndi"]:
                trend_dir = "up"
            elif _ema9_pre < _ema21_pre and _adx_pre["ndi"] > _adx_pre["pdi"]:
                trend_dir = "down"
    except Exception:
        pass
    indicators["trend_dir"] = trend_dir

    # ── EMA Cross (9/21) ────────────────────────────────────────────────────
    try:
        ema9  = ema(closes, 9)
        ema21 = ema(closes, 21)
        ema50 = ema(closes[-50:] if len(closes) >= 50 else closes, min(50, len(closes)))
        indicators["ema9"]  = round(ema9, 4)
        indicators["ema21"] = round(ema21, 4)
        if ema9 > ema21:
            score_bullish += 15
            indicators["ema_cross"] = "bullish"
        elif ema9 < ema21:
            score_bearish += 15
            indicators["ema_cross"] = "bearish"
        max_points += 15
        # preço acima de EMA50
        if entry > ema50:
            score_bullish += 10
            indicators["above_ema50"] = True
        else:
            score_bearish += 10
            indicators["above_ema50"] = False
        max_points += 10
    except Exception:
        pass

    # ── RSI ─────────────────────────────────────────────────────────────────
    # KB fix: em trend forte (ADX>25 + EMA9/21 alinhado + DI confirma), RSI extremo
    # nao e reversao — e forca. Usar zonas 80/20 em vez de 65/35 nesse caso.
    # Ref: knowledge/INDICATORS_REFERENCE.md:96-99
    try:
        rsi_val = rsi(closes, 14)
        indicators["rsi"] = round(rsi_val, 1)
        if trend_dir == "up":
            # Em uptrend: RSI alto = continuacao; so vira bear se >80 (extremo real)
            if rsi_val > 80:
                score_bearish += 20
                indicators["rsi_zone"] = "exhaustion_up"
            else:
                score_bullish += 20
                indicators["rsi_zone"] = "trend_up_strength"
        elif trend_dir == "down":
            # Em downtrend: RSI baixo = continuacao; so vira bull se <20 (extremo real)
            if rsi_val < 20:
                score_bullish += 20
                indicators["rsi_zone"] = "exhaustion_down"
            else:
                score_bearish += 20
                indicators["rsi_zone"] = "trend_down_strength"
        else:
            # Sem trend forte: usa zonas classicas 35/65 (mean reversion valido)
            if rsi_val < 35:
                score_bullish += 20
                indicators["rsi_zone"] = "oversold"
            elif rsi_val > 65:
                score_bearish += 20
                indicators["rsi_zone"] = "overbought"
            else:
                if rsi_val > 50:
                    score_bullish += 8
                else:
                    score_bearish += 8
                indicators["rsi_zone"] = "neutral"
        max_points += 20
    except Exception:
        pass

    # ── MACD ────────────────────────────────────────────────────────────────
    try:
        m = macd(closes)
        indicators["macd_hist"] = round(m["histogram"], 4)
        if m["histogram"] > 0:
            score_bullish += 15
            indicators["macd_signal"] = "bullish"
        else:
            score_bearish += 15
            indicators["macd_signal"] = "bearish"
        max_points += 15
    except Exception:
        pass

    # ── Bollinger Bands ──────────────────────────────────────────────────────
    # KB fix: "Walking the bands" em trend forte != reversao. Em uptrend, tocar
    # banda superior e continuacao; so vira bear quando trend = flat.
    # Ref: knowledge/INDICATORS_REFERENCE.md:173-175
    try:
        bb = bollinger(closes[-20:] if len(closes) >= 20 else closes, period=min(20, len(closes)))
        indicators["bb_upper"] = round(bb["upper"], 4)
        indicators["bb_lower"] = round(bb["lower"], 4)
        if entry <= bb["lower"]:
            if trend_dir == "down":
                score_bearish += 15  # walking lower band em downtrend = continuacao
                indicators["bb_position"] = "walking_lower"
            else:
                score_bullish += 15
                indicators["bb_position"] = "below_lower"
        elif entry >= bb["upper"]:
            if trend_dir == "up":
                score_bullish += 15  # walking upper band em uptrend = continuacao
                indicators["bb_position"] = "walking_upper"
            else:
                score_bearish += 15
                indicators["bb_position"] = "above_upper"
        else:
            mid = bb["middle"]
            if entry > mid:
                score_bullish += 5
            else:
                score_bearish += 5
            indicators["bb_position"] = "inside"
        max_points += 15
    except Exception:
        pass

    # ── ADX (força da tendência) ─────────────────────────────────────────────
    try:
        adx_res = adx(candles, period=14)
        indicators["adx"] = round(adx_res["adx"], 1)
        if adx_res["adx"] > 25:
            if adx_res["pdi"] > adx_res["ndi"]:
                score_bullish += 15
                indicators["adx_trend"] = "strong_up"
            else:
                score_bearish += 15
                indicators["adx_trend"] = "strong_down"
        else:
            indicators["adx_trend"] = "weak"
        max_points += 15
    except Exception:
        pass

    # ── Volume (acima da média = confirmação) ────────────────────────────────
    try:
        vols = [c["volume"] for c in candles[-20:]]
        avg_vol = sum(vols[:-1]) / max(len(vols) - 1, 1)
        cur_vol = vols[-1]
        indicators["vol_ratio"] = round(cur_vol / avg_vol, 2) if avg_vol > 0 else 1.0
        if cur_vol > avg_vol * 1.3:
            indicators["vol_confirm"] = True
            # volume alto confirma a direção dominante
            if score_bullish > score_bearish:
                score_bullish += 10
            else:
                score_bearish += 10
        max_points += 10
    except Exception:
        pass

    # ── Score normalizado 0-100 ──────────────────────────────────────────────
    if max_points == 0:
        return neutral

    bull_score = (score_bullish / max_points) * 100
    bear_score = (score_bearish / max_points) * 100

    # Define direção e score
    if bull_score >= SCORE_THRESHOLD and bull_score > bear_score:
        direction = "LONG"
        signal = "COMPRA"
        score = bull_score
    elif bear_score >= SCORE_THRESHOLD and bear_score > bull_score:
        direction = "SHORT"
        signal = "VENDA"
        score = bear_score
    else:
        direction = "LONG" if bull_score >= bear_score else "SHORT"
        signal = "NEUTRO"
        score = max(bull_score, bear_score)

    # ── Stop e Alvo ──────────────────────────────────────────────────────────
    try:
        atr_val = atr(candles, period=14)
    except Exception:
        atr_val = entry * 0.01

    stop = calc_stop_atr(candles, direction, ATR_STOP_MULT)
    take_profit = calc_target(entry, stop, direction, RR_DEFAULT)

    # ── Regime-direction filter (opt-in via kwargs; default off = backwards compat) ──
    if regime_filter_mode != "off" and regime is not None:
        filtered_signal, filter_reason = apply_regime_filter(
            signal, regime, mode=regime_filter_mode, day_of_week_brt=day_of_week_brt,
            halving_phase=halving_phase, trendline_soft_passes=trendline_soft_passes,
        )
        indicators["regime_filter_reason"] = filter_reason
        if filtered_signal != signal:
            signal = filtered_signal  # tipicamente NEUTRO

    return SignalResult(
        signal=signal,
        score=round(score, 1),
        entry_price=entry,
        stop_loss=round(stop, 6),
        take_profit=round(take_profit, 6),
        atr=round(atr_val, 6),
        indicators=indicators,
    )


def _regime_for_window(window: List[Dict]) -> str:
    """Classifica regime da última barra via SMA200. Retorna 'sideways' se < 200 candles."""
    if len(window) < SMA200_PERIOD:
        return "sideways"
    closes = [c["close"] for c in window[-SMA200_PERIOD:]]
    sma200 = sum(closes) / SMA200_PERIOD
    return classify_regime(window[-1]["close"], sma200)


class SignalGenerator:
    def __init__(self, db, min_candles: int = MIN_CANDLES, score_threshold: float = SCORE_THRESHOLD,
                 filter_sideways: bool = False):
        self.db = db
        self.min_candles = min_candles
        self.score_threshold = score_threshold
        self.filter_sideways = filter_sideways

    FLUSH_SIZE = 500  # bulk insert a cada N sinais

    def run(self, market: str, period: str, date_from: str, date_to: str) -> int:
        candles = self.db.get_candles(market, period, date_from, date_to)
        if not candles:
            return 0

        stored = 0
        skipped_sideways = 0
        total = len(candles)
        buffer: List[Dict] = []

        # Flush assíncrono: envia batch para Supabase em background enquanto compute continua
        executor = ThreadPoolExecutor(max_workers=2)

        def _flush_async():
            if buffer:
                batch = list(buffer)
                buffer.clear()
                executor.submit(self.db.insert_signals_bulk, batch)

        for i in range(self.min_candles, total):
            # Janela limitada a 200 candles — suficiente para SMA200 + todos os indicadores
            # Zero lookahead mantido: só usa candles[0..i]
            window = candles[max(0, i - SMA200_PERIOD + 1):i + 1]

            if self.filter_sideways:
                regime = _regime_for_window(window)
                if regime == "sideways":
                    skipped_sideways += 1
                    continue

            result = generate_signal(window)

            if not result.is_actionable:
                continue

            buffer.append({
                "market": market,
                "period": period,
                "bar_ts": candles[i]["ts"],
                "signal": result.signal,
                "score": result.score,
                "entry_price": result.entry_price,
                "stop_loss": result.stop_loss,
                "take_profit": result.take_profit,
                "atr": result.atr,
                "indicators": result.indicators,
            })
            stored += 1

            if len(buffer) >= self.FLUSH_SIZE:
                _flush_async()

            if stored % 500 == 0 or i == total - 1:
                pct = int(i / total * 100)
                print(f"  {market} {period} [{pct:3d}%] bar {i}/{total} — sinais: {stored}", flush=True)

        _flush_async()
        executor.shutdown(wait=True)  # aguarda último flush antes de retornar

        sideways_msg = f" ({skipped_sideways} bars sideways filtrados)" if self.filter_sideways else ""
        print(f"  {market} {period} concluído — {stored} sinais de {total - self.min_candles} bars analisados{sideways_msg}")
        return stored


def main():
    parser = argparse.ArgumentParser(description="Gera sinais históricos do TechAgent → Supabase")
    parser.add_argument("--market", default="BTCUSDT")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    parser.add_argument("--threshold", type=float, default=SCORE_THRESHOLD)
    parser.add_argument("--filter-sideways", action="store_true", default=False,
                        help="Nao gerar sinais em regime sideways (SMA200)")
    parser.add_argument("--clear", action="store_true", default=False,
                        help="Limpar sinais e trades existentes antes de gerar")
    args = parser.parse_args()

    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    if args.clear:
        print(f"Limpando sinais e trades de {args.market} {args.period}...")
        db.clear_signals(args.market, args.period)
        db.clear_trades(args.market, args.period)

    gen = SignalGenerator(db=db, score_threshold=args.threshold, filter_sideways=args.filter_sideways)
    print(f"\nGerando sinais {args.market} {args.period} de {args.start} ate {args.end}...")
    count = gen.run(args.market, args.period, args.start, args.end)
    print(f"\nConcluido. {count} sinais armazenados.")


if __name__ == "__main__":
    main()

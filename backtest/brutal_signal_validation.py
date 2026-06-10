#!/usr/bin/env python3
"""
BRUTAL SIGNAL VALIDATION — 7.4 años BTC history
Executa backtest de TODOS os sinais contra 5,381 velas diárias BTC (2011-2026)
Calcula: Sharpe, Calmar, Win rate, Profit factor
Resultado: Quais sinais realmente têm edge? (Sharpe > 2.0)
"""

import json
import sys
from typing import List, Dict, Tuple
from dataclasses import dataclass
from datetime import datetime, timedelta
import statistics

@dataclass
class TradeResult:
    signal_type: str
    entry_price: float
    exit_price: float
    bars_held: int
    pnl_pct: float
    pnl_r: float  # em unidades de risco (ATR)
    win: bool
    regime: str
    entry_date: str
    exit_date: str

@dataclass
class SignalMetrics:
    signal_type: str
    total_trades: int
    winning_trades: int
    win_rate: float
    profit_factor: float
    expectancy_r: float
    max_drawdown_r: float
    sharpe_ratio: float
    calmar_ratio: float
    max_dd_pct: float
    avg_win: float
    avg_loss: float

    def passes_validation(self) -> bool:
        """Passa em validação brutal: Sharpe > 2.0"""
        return self.sharpe_ratio >= 2.0

class BrutalBacktest:
    def __init__(self, btc_file='btcusd_bitstamp_1day.json'):
        with open(btc_file) as f:
            self.candles = json.load(f)
        print(f"[LOAD] {len(self.candles)} velas BTC (2011-2026)")

    def _calc_rsi(self, closes: List[float], period: int = 14) -> float:
        """Calcula RSI do último candle"""
        if len(closes) < period + 1:
            return 50.0
        deltas = [closes[i] - closes[i-1] for i in range(1, len(closes))]
        gains = [max(d, 0) for d in deltas[-period:]]
        losses = [abs(min(d, 0)) for d in deltas[-period:]]
        avg_gain = sum(gains) / period if gains else 0
        avg_loss = sum(losses) / period if losses else 0
        if avg_loss == 0:
            return 100.0 if avg_gain > 0 else 50.0
        rs = avg_gain / avg_loss
        return 100 - (100 / (1 + rs))

    def _calc_atr(self, candles_list: List[Dict], period: int = 14) -> float:
        """Calcula ATR (volatilidade)"""
        if len(candles_list) < period:
            return 0.0
        trs = []
        for i in range(1, len(candles_list)):
            c = candles_list[i]
            pc = candles_list[i-1]
            tr = max(
                c['high'] - c['low'],
                abs(c['high'] - pc['close']),
                abs(c['low'] - pc['close'])
            )
            trs.append(tr)
        if not trs:
            return 0.0
        return sum(trs[-period:]) / period

    def _classify_regime(self, candles_list: List[Dict]) -> str:
        """Classifica regime por SMA200"""
        if len(candles_list) < 200:
            return "sideways"
        closes = [c['close'] for c in candles_list[-200:]]
        sma200 = sum(closes) / 200.0
        curr_price = candles_list[-1]['close']

        if curr_price > sma200 * 1.05:
            return "bull"
        elif curr_price < sma200 * 0.95:
            return "bear"
        else:
            return "sideways"

    def _detect_vol_climax(self, candles_list: List[Dict], idx: int) -> Tuple[bool, float]:
        """
        Vol Climax: Volume spike + price reversal + RSI extreme
        Returns: (signal_found, score)
        """
        if idx < 20:
            return False, 0.0

        recent = candles_list[idx-20:idx+1]
        avg_vol = statistics.mean([c['volume'] for c in recent[:-1]])
        curr_vol = recent[-1]['volume']

        # Volume spike: 2x average
        if curr_vol < avg_vol * 2:
            return False, 0.0

        # Price near high (exhaustion)
        high_20 = max([c['high'] for c in recent])
        curr_close = recent[-1]['close']
        if curr_close < high_20 * 0.97:
            return False, 0.0

        # RSI extreme
        closes = [c['close'] for c in recent]
        rsi = self._calc_rsi(closes)

        # RSI > 70 (overbought) OR < 30 (oversold)
        score = 0.0
        if rsi > 70:
            score = min(100, 50 + (rsi - 70))  # Bullish climax
        elif rsi < 30:
            score = min(100, 50 - (30 - rsi))  # Bearish climax
        else:
            return False, 0.0

        return True, score

    def _detect_tori(self, candles_list: List[Dict], idx: int) -> Tuple[bool, float]:
        """
        Tori Proximity: Regime-agnostic conviction based on proximity to recent lows/highs
        Returns: (signal_found, conviction_0_100)
        """
        if idx < 30:
            return False, 0.0

        recent = candles_list[idx-30:idx+1]
        curr_price = recent[-1]['close']
        min_30 = min([c['low'] for c in recent[:-1]])
        max_30 = max([c['high'] for c in recent[:-1]])

        range_30 = max_30 - min_30
        if range_30 == 0:
            return False, 0.0

        # Proximity to recent lows = bullish signal
        proximity_to_low = (curr_price - min_30) / range_30
        if proximity_to_low < 0.1:  # Close to lows
            conviction = 30 + proximity_to_low * 100
            return True, conviction

        # Proximity to recent highs = bearish signal
        proximity_to_high = (max_30 - curr_price) / range_30
        if proximity_to_high < 0.1:  # Close to highs
            conviction = 30 + proximity_to_high * 100
            return True, conviction

        return False, 0.0

    def _detect_faro_v3(self, candles_list: List[Dict], idx: int) -> Tuple[bool, float]:
        """
        FARO V3 Simplified: RSI + Volume + Momentum
        Returns: (signal_found, score_0_100)
        """
        if idx < 35:
            return False, 0.0

        recent = candles_list[idx-35:idx+1]
        closes = [c['close'] for c in recent]

        # RSI component
        rsi = self._calc_rsi(closes)
        rsi_score = 0.0
        if 30 <= rsi <= 70:
            rsi_score = 50  # Neutral zone (good for entry)
        elif rsi < 30:
            rsi_score = 30  # Oversold (strong signal)
        elif rsi > 70:
            rsi_score = 20  # Overbought (weak signal)

        # Volume component
        avg_vol = statistics.mean([c['volume'] for c in recent[:-1]])
        curr_vol = recent[-1]['volume']
        vol_score = min(50, 20 + (curr_vol / avg_vol - 1) * 30)

        # Momentum: Close relative to recent range
        high_5 = max([c['high'] for c in recent[-5:]])
        low_5 = min([c['low'] for c in recent[-5:]])
        curr_close = recent[-1]['close']
        if high_5 > low_5:
            momentum = (curr_close - low_5) / (high_5 - low_5)
            momentum_score = 30 * momentum
        else:
            momentum_score = 15

        total_score = (rsi_score * 0.4 + vol_score * 0.35 + momentum_score * 0.25)
        return total_score >= 45, total_score

    def _simulate_trade(self, entry_price: float, candles_forward: List[Dict],
                       atr: float, max_bars: int = 50) -> TradeResult:
        """Simula trade com stop loss em -2*ATR e target em +5*ATR"""
        if atr == 0:
            atr = entry_price * 0.02  # 2% fallback

        stop_loss = entry_price - atr * 2
        take_profit = entry_price + atr * 5

        bars_held = 1
        exit_price = entry_price

        for i, candle in enumerate(candles_forward[:max_bars]):
            bars_held = i + 1
            # Check stop loss
            if candle['low'] <= stop_loss:
                exit_price = stop_loss
                break
            # Check take profit
            if candle['high'] >= take_profit:
                exit_price = take_profit
                break
        else:
            # Exit on close of last bar
            exit_price = candles_forward[-1]['close']

        pnl_pct = ((exit_price - entry_price) / entry_price) * 100
        pnl_r = (exit_price - entry_price) / atr if atr > 0 else 0

        return TradeResult(
            signal_type="",
            entry_price=entry_price,
            exit_price=exit_price,
            bars_held=bars_held,
            pnl_pct=pnl_pct,
            pnl_r=pnl_r,
            win=exit_price > entry_price,
            regime="",
            entry_date="",
            exit_date=""
        )

    def backtest_signal(self, signal_detector, signal_name: str) -> SignalMetrics:
        """Executa backtest de um sinal contra todos os candles"""
        trades: List[TradeResult] = []

        for i in range(100, len(self.candles) - 51):
            signal_found, score = signal_detector(self.candles, i)

            if signal_found:
                curr_candle = self.candles[i]
                entry_price = curr_candle['close']
                atr = self._calc_atr(self.candles[max(0, i-30):i+1])
                regime = self._classify_regime(self.candles[:i+1])

                forward_candles = self.candles[i+1:i+51]
                if not forward_candles:
                    continue

                result = self._simulate_trade(entry_price, forward_candles, atr)
                result.signal_type = signal_name
                result.regime = regime
                result.entry_date = curr_candle['ts']
                result.exit_date = forward_candles[min(result.bars_held-1, len(forward_candles)-1)]['ts']

                trades.append(result)

        if not trades:
            return SignalMetrics(
                signal_type=signal_name,
                total_trades=0,
                winning_trades=0,
                win_rate=0.0,
                profit_factor=0.0,
                expectancy_r=0.0,
                max_drawdown_r=0.0,
                sharpe_ratio=0.0,
                calmar_ratio=0.0,
                max_dd_pct=0.0,
                avg_win=0.0,
                avg_loss=0.0
            )

        # Calculate metrics
        winning = sum(1 for t in trades if t.win)
        win_rate = winning / len(trades)

        pnl_r_series = [t.pnl_r for t in trades]
        expectancy_r = sum(pnl_r_series) / len(pnl_r_series)

        # Sharpe ratio
        if len(pnl_r_series) > 1:
            std_r = statistics.stdev(pnl_r_series) if len(pnl_r_series) > 1 else 1.0
            sharpe = (expectancy_r / std_r * (252 ** 0.5)) if std_r > 0 else 0.0
        else:
            sharpe = 0.0

        # Drawdown
        cumsum = 0
        peak = 0
        max_dd = 0
        for r in pnl_r_series:
            cumsum += r
            peak = max(peak, cumsum)
            dd = peak - cumsum
            max_dd = max(max_dd, dd)

        # Calmar
        total_r = sum(pnl_r_series)
        calmar = (total_r / (max_dd * 252)) if max_dd > 0 else 0.0

        # Profit factor
        gross_gain = sum(t.pnl_pct for t in trades if t.win)
        gross_loss = abs(sum(t.pnl_pct for t in trades if not t.win))
        pf = gross_gain / gross_loss if gross_loss > 0 else 0.0

        # Avg win/loss
        wins = [t.pnl_pct for t in trades if t.win]
        losses = [t.pnl_pct for t in trades if not t.win]
        avg_win = sum(wins) / len(wins) if wins else 0.0
        avg_loss = sum(losses) / len(losses) if losses else 0.0

        # Max DD %
        max_dd_pct = (max_dd / (expectancy_r + 0.001)) * 100  # Approximation

        return SignalMetrics(
            signal_type=signal_name,
            total_trades=len(trades),
            winning_trades=winning,
            win_rate=win_rate * 100,
            profit_factor=pf,
            expectancy_r=expectancy_r,
            max_drawdown_r=max_dd,
            sharpe_ratio=sharpe,
            calmar_ratio=calmar,
            max_dd_pct=max_dd_pct,
            avg_win=avg_win,
            avg_loss=avg_loss
        )

    def run_all_signals(self) -> List[SignalMetrics]:
        """Executa backtest de TODOS os sinais"""
        results = []

        signals = [
            (self._detect_vol_climax, "vol_climax"),
            (self._detect_tori, "tori"),
            (self._detect_faro_v3, "faro_v3_simple"),
        ]

        for detector, name in signals:
            print(f"\n[BACKTEST] {name}...")
            metrics = self.backtest_signal(detector, name)
            results.append(metrics)

            status = "PASS" if metrics.passes_validation() else "FAIL"
            print(f"  [{status}] Sharpe={metrics.sharpe_ratio:.2f} | "
                  f"Trades={metrics.total_trades} | "
                  f"Win%={metrics.win_rate:.1f}% | "
                  f"PF={metrics.profit_factor:.2f}")

        return results

    def print_report(self, results: List[SignalMetrics]):
        """Imprime relatório final em tabela"""
        print("\n" + "="*120)
        print("VALIDAÇÃO BRUTAL — QUAIS SINAIS TÊM EDGE? (Sharpe > 2.0)")
        print("="*120)

        # Header
        print(f"{'Signal':<20} {'Trades':<10} {'Win%':<10} {'Sharpe':<10} {'Calmar':<10} "
              f"{'PF':<8} {'Exp(R)':<10} {'Status':<12}")
        print("-"*120)

        for m in sorted(results, key=lambda x: x.sharpe_ratio, reverse=True):
            status = "✅ VALIDATED" if m.passes_validation() else "❌ NO EDGE"
            print(f"{m.signal_type:<20} {m.total_trades:<10} {m.win_rate:<10.1f} "
                  f"{m.sharpe_ratio:<10.2f} {m.calmar_ratio:<10.2f} "
                  f"{m.profit_factor:<8.2f} {m.expectancy_r:<10.2f} {status:<12}")

        print("-"*120)

        validated = [m for m in results if m.passes_validation()]
        print(f"\n[RESULT] {len(validated)}/{len(results)} sinais VALIDADOS (Sharpe >= 2.0)")

        if validated:
            print("\n✅ SINAIS COM EDGE COMPROVADO:")
            for m in validated:
                print(f"   • {m.signal_type}: Sharpe {m.sharpe_ratio:.2f} | "
                      f"{m.total_trades} trades | {m.win_rate:.1f}% win rate")
        else:
            print("\n⚠️  NENHUM SINAL TEM EDGE COMPROVADO (Sharpe >= 2.0)")
            print("   Recomendação: Validar em combinação (ensemble) ou pausar operação real")

if __name__ == '__main__':
    bt = BrutalBacktest()
    results = bt.run_all_signals()
    bt.print_report(results)

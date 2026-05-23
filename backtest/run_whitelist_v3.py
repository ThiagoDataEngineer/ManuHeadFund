"""run_whitelist_v3.py — Re-validar whitelist v3 (LONG+SHORT) com triple barrier."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(ROOT_DIR))

from entries_cache import detect_entries  # noqa: E402
from simulate_from_entries import simulate_from_entries  # noqa: E402
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity  # noqa: E402
from metrics_pct_returns import (  # noqa: E402
    sharpe_from_daily_returns,
    psr_from_daily_returns,
    dsr_from_daily_returns,
)
from walk_forward_purged import walk_forward_evaluate  # noqa: E402
from constants import (  # noqa: E402
    RISK_PCT_PER_TRADE,
    SIMONS_N_TRIALS_DEFAULT, SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD, PSR_THRESHOLD,
    TB_MAX_BARS, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)

JOURNAL_DIR = ROOT_DIR / "journal"


def load_candles(asset: str):
    if asset == "xrp":
        from run_simons_gate_xrp import load_xrp_candles
        return load_xrp_candles()
    if asset == "btc":
        from db import Database
        return Database().get_candles("BTCUSD", "1hour",
                                       "2014-01-01T00:00:00", "2025-05-01T00:00:00")
    raise ValueError(f"asset desconhecido: {asset}")


def simulate_with_direction(entries, all_dicts, stop_atr, target_atr) -> list:
    """Adapter: simulate_from_entries lendo direction de cada entry."""
    trades = []
    from triple_barrier_simulator import simulate_trade
    for e in entries:
        sim = simulate_trade(
            entry_idx=e["idx"],
            candles=all_dicts,
            direction=e["direction"],
            atr_value=e["atr_at_entry"],
            stop_atr=stop_atr,
            target_atr=target_atr,
            max_bars=TB_MAX_BARS,
            fee_pct=TB_FEE_TAKER_PCT,
            slippage_pct=TB_SLIPPAGE_PCT,
        )
        if sim["exit_reason"] == "invalid":
            continue
        trades.append({
            "entry_ts": e["entry_ts"],
            "regime": e["regime"],
            "direction": e["direction"],
            "result_r": round(sim["result_r"], 4),
            "exit_reason": sim["exit_reason"],
            "holding_bars": sim["holding_bars"],
            "entry_price": round(e["entry_price"], 6),
            "atr_at_entry": round(e["atr_at_entry"], 6),
        })
    return trades


def evaluate(trades) -> dict:
    if not trades or len(trades) < 30:
        return {"valid": False, "n_trades": len(trades)}
    eq = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30:
        return {"valid": False, "n_returns": len(rets)}
    sharpe = sharpe_from_daily_returns(rets)
    psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(rets, n_trials=SIMONS_N_TRIALS_DEFAULT,
                                  sharpe_benchmark=0.0,
                                  sample_variance_sharpes=SIMONS_SAMPLE_VAR)
    mean_r = sum(t["result_r"] for t in trades) / len(trades)
    win = sum(1 for t in trades if t["result_r"] > 0) / len(trades) * 100
    dates = sorted(eq.keys())
    long_n = sum(1 for t in trades if t["direction"] == "LONG")
    short_n = len(trades) - long_n
    return {
        "valid": True,
        "n_trades": len(trades),
        "n_long": long_n,
        "n_short": short_n,
        "n_days": len(eq),
        "sharpe": round(sharpe, 4),
        "psr": round(psr, 4),
        "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4),
        "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
        "decision": ("PASS" if (sharpe > 0 and dsr >= DSR_THRESHOLD and
                                  psr >= PSR_THRESHOLD) else "FAIL"),
    }


def main(asset: str):
    print("=" * 72)
    print(f"WHITELIST v3 (LONG+SHORT) — Triple barrier — {asset.upper()}")
    print("=" * 72)

    cache = JOURNAL_DIR / f"entries_v3_cache_{asset}_2026_05_17.json"
    ad_path = JOURNAL_DIR / f"all_dicts_{asset}_2026_05_17.json"

    if cache.exists() and ad_path.exists():
        with open(cache, "r", encoding="utf-8") as f:
            entries = json.load(f)
        with open(ad_path, "r", encoding="utf-8") as f:
            all_dicts = json.load(f)
        print(f"[load] {len(entries)} v3 entries cached")
    else:
        candles = load_candles(asset)
        print(f"[load] {len(candles)} candles {asset}")
        entries, all_dicts = detect_entries(
            candles, bars_per_day=24, label=f"{asset}_v3",
            whitelist_mode="strict_v3",
            test_signals=("COMPRA", "VENDA"),
        )
        with open(cache, "w", encoding="utf-8") as f:
            json.dump(entries, f)
        if not ad_path.exists():
            with open(ad_path, "w", encoding="utf-8") as f:
                json.dump(all_dicts, f)
        print(f"[save] {cache.name}")

    n_long = sum(1 for e in entries if e["direction"] == "LONG")
    n_short = sum(1 for e in entries if e["direction"] == "SHORT")
    print(f"[entries] LONG={n_long} SHORT={n_short} total={len(entries)}")

    # Distribuição regime para SHORTs
    regime_short = {}
    for e in entries:
        if e["direction"] == "SHORT":
            regime_short[e["regime"]] = regime_short.get(e["regime"], 0) + 1
    print(f"[short_regimes] {regime_short}")

    # Configs prioritárias: defaults + best XRP grid
    CONFIGS = [
        ("default_1_5", 1.0, 5.0),
        ("best_grid_2_5", 2.0, 5.0),
        ("balanced_1.5_3", 1.5, 3.0),
    ]
    out_all = []
    for label, s, t in CONFIGS:
        print(f"\n=== {label} (stop={s} target={t}) ===")
        trades = simulate_with_direction(entries, all_dicts, s, t)
        m = evaluate(trades)
        for k, v in m.items():
            print(f"  {k}: {v}")
        # Walk-forward
        if m.get("valid"):
            wf = walk_forward_evaluate(trades, k=5, embargo_days=7,
                                        risk_pct=RISK_PCT_PER_TRADE)
            print(f"  WF verdict: {wf['verdict']}")
            print(f"  WF OOS: mean={wf['oos_summary']['mean_test_sharpe']} "
                  f"positive={wf['oos_summary']['positive_sharpe_folds']}/{wf['oos_summary']['total_folds']}")
            out_all.append({"label": label, "stop_atr": s, "target_atr": t,
                             "metrics": m, "walk_forward": wf})
        else:
            out_all.append({"label": label, "stop_atr": s, "target_atr": t,
                             "metrics": m})

    out_json = JOURNAL_DIR / f"whitelist_v3_{asset}_2026_05_17.json"
    out_obj = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asset": asset.upper(),
        "whitelist": "v3_long_short",
        "n_entries": {"long": n_long, "short": n_short, "total": len(entries)},
        "short_regimes": regime_short,
        "results": out_all,
    }
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(out_obj, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_json.name}")


if __name__ == "__main__":
    asset = sys.argv[1] if len(sys.argv) > 1 else "xrp"
    main(asset)

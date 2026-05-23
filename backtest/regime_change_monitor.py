"""
regime_change_monitor.py -- Detecta mudancas de regime BTC e dispara re-validation.

Rodando pelo cron weekly OU manualmente:
1. Pega BTC kline daily atual
2. Compute regime (BULL_STRONG/WEAK, SIDEWAYS, BEAR_WEAK/STRONG, TRANSITION)
3. Compara com regime stored em journal/regime_state.json
4. Se mudou + magnitude relevante -> output flag pra cron disparar:
   - weekly_revalidation (re-checa whitelist)
   - weekly_discovery (procura novos candidatos)
   - Telegram alerta user

Output: journal/regime_state.json {
   timestamp, prev_regime, current_regime, changed: bool,
   trigger_actions: [list]
}
"""
from __future__ import annotations

import json, sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
STATE_PATH = ROOT / "journal" / "regime_state.json"


def fetch_btc_kline(n=210):
    url = f"https://api.coinex.com/v2/spot/kline?market=BTCUSDT&period=1day&limit={n}"
    try:
        with urlopen(Request(url, headers={"User-Agent":"rc/1"}), timeout=15) as r:
            d = json.loads(r.read().decode("utf-8"))
            return d.get("data") or []
    except Exception as e:
        print(f"  err fetch: {e}")
        return []


def compute_btc_regime(klines):
    if len(klines) < 200: return None
    closes = [float(k["close"]) for k in klines]
    sma200 = sum(closes[-200:]) / 200
    cur = closes[-1]
    dist = (cur - sma200) / sma200
    mom20 = (cur - closes[-20]) / closes[-20] if closes[-20] > 0 else 0
    if   dist > 0.20 and mom20 > 0.10:   return "BULL_STRONG"
    elif dist > 0    and mom20 > 0:       return "BULL_WEAK"
    elif dist < -0.20 and mom20 < -0.10:  return "BEAR_STRONG"
    elif dist < 0    and mom20 < 0:       return "BEAR_WEAK"
    elif abs(dist) < 0.05:                 return "SIDEWAYS"
    else:                                    return "TRANSITION"


def load_prev_state():
    if not STATE_PATH.exists(): return None
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as f: return json.load(f)
    except: return None


def save_state(state):
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


# Transitions consideradas "relevantes" (forcam re-validation)
SIGNIFICANT_TRANSITIONS = {
    # de bull -> bear (ou vice-versa) sempre relevante
    ("BULL_STRONG","BEAR_WEAK"), ("BULL_STRONG","BEAR_STRONG"),
    ("BULL_WEAK","BEAR_WEAK"), ("BULL_WEAK","BEAR_STRONG"),
    ("BEAR_STRONG","BULL_WEAK"), ("BEAR_STRONG","BULL_STRONG"),
    ("BEAR_WEAK","BULL_WEAK"), ("BEAR_WEAK","BULL_STRONG"),
    # transition para zonas decisivas
    ("SIDEWAYS","BULL_STRONG"), ("SIDEWAYS","BEAR_STRONG"),
    ("TRANSITION","BULL_STRONG"), ("TRANSITION","BEAR_STRONG"),
}


def is_significant_change(prev_regime, cur_regime):
    if not prev_regime or prev_regime == cur_regime: return False
    return (prev_regime, cur_regime) in SIGNIFICANT_TRANSITIONS


def main():
    print("=" * 70)
    print("Regime Change Monitor (BTC)")
    print("=" * 70)
    kl = fetch_btc_kline()
    if not kl:
        print("[err] sem kline"); return
    current = compute_btc_regime(kl)
    print(f"  current regime: {current}")
    prev_state = load_prev_state()
    prev_regime = prev_state.get("current_regime") if prev_state else None
    print(f"  prev regime: {prev_regime}")
    changed = is_significant_change(prev_regime, current)
    actions = []
    if changed:
        actions = ["trigger_revalidation", "trigger_discovery", "telegram_alert"]
        print(f"  >>> REGIME CHANGE DETECTED: {prev_regime} -> {current}")
        print(f"  >>> Actions to trigger: {actions}")
    else:
        print(f"  no significant change")
    state = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "current_regime": current,
        "prev_regime": prev_regime,
        "changed": changed,
        "trigger_actions": actions,
    }
    save_state(state)
    print(f"\n[save] regime_state.json")
    # Exit code: 0 normal, 7 if change detected (cron pode usar)
    if changed: sys.exit(7)


if __name__ == "__main__":
    main()

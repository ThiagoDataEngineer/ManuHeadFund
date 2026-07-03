# universe_tf_study.py — Estudo multi-timeframe do universo CoinEx (4h e 1h)
# 2026-07-03: evolucao do universe_pump_study (diario). Perguntas:
#   1. A lei de dissipacao (fade the pump) vale em 4h e 1h?
#   2. ANATOMIA do pump diario em 1h: hora de inicio, duracao ate pico,
#      janela de entrada LONG e de SHORT
#   3. Assinatura PRE-ignicao nas horas anteriores (o que o FARO deveria ler)
#   4. Hora do dia: pumps concentram em algum horario?
#
# Uso:
#   python backtest/universe_tf_study.py collect4h   # 4h x 720 (=120d) todos os pares
#   python backtest/universe_tf_study.py collect1h   # 1h x 1000 (=41d) pares c/ pump recente
#   python backtest/universe_tf_study.py law         # lei de dissipacao em 4h e 1h
#   python backtest/universe_tf_study.py anatomy     # anatomia intraday dos pumps

import sys
import time
import json
import urllib.request
from pathlib import Path

BASE = "https://api.coinex.com/v2"
DATA = Path(__file__).parent / "data"
DATA.mkdir(exist_ok=True)
CSV_4H = DATA / "universe_4h.csv"
CSV_1H = DATA / "universe_1h.csv"
CSV_1D = DATA / "universe_daily.csv"


def get_json(url, retries=3):
    for i in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                return json.loads(r.read().decode())
        except Exception:
            if i == retries - 1:
                return None
            time.sleep(1.0 * (i + 1))
    return None


def list_pairs(min_vol=1000):
    r = get_json(f"{BASE}/spot/ticker")
    out = []
    for t in r["data"]:
        m = t.get("market", "")
        try:
            v = float(t.get("value", 0))
        except (TypeError, ValueError):
            v = 0
        if m.endswith("USDT") and v >= min_vol:
            out.append(m)
    return out


def collect_tf(pairs, period, limit, out_csv):
    rows = []
    t0 = time.time()
    for i, m in enumerate(pairs):
        r = get_json(f"{BASE}/spot/kline?market={m}&period={period}&limit={limit}")
        if r and r.get("code") == 0 and r.get("data"):
            for k in r["data"]:
                rows.append((m, int(k["created_at"]), k["open"], k["high"], k["low"], k["close"], k["value"]))
        if (i + 1) % 100 == 0:
            print(f"  {i+1}/{len(pairs)} ({time.time()-t0:.0f}s, {len(rows)} candles)")
        time.sleep(0.08)
    with open(out_csv, "w", encoding="utf-8") as f:
        f.write("market,ts,open,high,low,close,vol_usd\n")
        for row in rows:
            f.write(",".join(str(x) for x in row) + "\n")
    print(f"OK: {len(rows)} candles -> {out_csv}")


def collect4h():
    pairs = list_pairs()
    print(f"{len(pairs)} pares | 4h x 720 candles (120 dias)")
    collect_tf(pairs, "4hour", 720, CSV_4H)


def collect1h():
    # so pares que tiveram pump diario +20% nos ultimos 41 dias (dataset diario)
    import pandas as pd
    df = pd.read_csv(CSV_1D)
    df["date"] = pd.to_datetime(df["ts"], unit="ms")
    df["ret"] = (pd.to_numeric(df["close"]) - pd.to_numeric(df["open"])) / pd.to_numeric(df["open"]) * 100
    recent = df[df["date"] >= df["date"].max() - pd.Timedelta(days=41)]
    pumped = sorted(recent[recent["ret"] >= 20]["market"].unique())
    print(f"{len(pumped)} pares com pump +20% nos ultimos 41 dias | 1h x 1000")
    collect_tf(pumped, "1hour", 1000, CSV_1H)


def _load(csv):
    import pandas as pd
    df = pd.read_csv(csv)
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "close"])
    df = df[df["open"] > 0]
    df["dt"] = pd.to_datetime(df["ts"], unit="ms")
    df = df.sort_values(["market", "ts"]).reset_index(drop=True)
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
    return df


def law():
    """Lei de dissipacao em 4h e 1h: E[ret proximo candle | ret candle atual]"""
    import pandas as pd

    for name, csv, bins, labels in [
        ("4H", CSV_4H,
         [-100, -15, -10, -5, -2, 0, 2, 5, 10, 15, 25, 1000],
         ["<-15", "-15..-10", "-10..-5", "-5..-2", "-2..0", "0..2", "2..5", "5..10", "10..15", "15..25", ">25"]),
        ("1H", CSV_1H,
         [-100, -10, -5, -3, -1, 0, 1, 3, 5, 10, 20, 1000],
         ["<-10", "-10..-5", "-5..-3", "-3..-1", "-1..0", "0..1", "1..3", "3..5", "5..10", "10..20", ">20"]),
    ]:
        if not csv.exists():
            print(f"[{name}] sem dados ({csv.name}) — rode collect primeiro")
            continue
        df = _load(csv)
        g = df.groupby("market")
        df["ret_n1"] = g["ret"].shift(-1)
        df["vol_ma"] = g["vol_usd"].transform(lambda s: s.shift(1).rolling(20, min_periods=10).mean())
        d = df.dropna(subset=["ret_n1"])
        d = d[d["vol_ma"].fillna(0) * 6 >= 500]  # liquidez minima
        print(f"\n=== LEI DE DISSIPACAO {name} | n={len(d)} candles ===")
        d["rb"] = pd.cut(d["ret"], bins, labels=labels)
        tab = d.groupby("rb", observed=True)["ret_n1"].agg(["median", "mean", "count"])
        print(f"    {'ret candle':>10} | {'prox mediana':>12} | {'prox media':>10} | {'n':>7}")
        for k, r in tab.iterrows():
            print(f"    {k:>10} | {r['median']:>+11.2f}% | {r['mean']:>+9.2f}% | {int(r['count']):>7}")


def anatomy():
    """Anatomia 1h dos pumps: hora de inicio (UTC), rampa, pico, ressaca.
    Pump-hora = candle 1h com ret >= 10%."""
    import pandas as pd
    import numpy as np

    df = _load(CSV_1H)
    g = df.groupby("market")
    df["vol_ma24"] = g["vol_usd"].transform(lambda s: s.shift(1).rolling(24, min_periods=12).mean())
    df["v_ratio"] = (df["vol_usd"] / df["vol_ma24"].replace(0, np.nan)).clip(upper=100)
    df["hour"] = df["dt"].dt.hour  # UTC

    ign = df[(df["ret"] >= 10) & (df["v_ratio"] >= 3)].copy()
    print(f"=== ANATOMIA: {len(ign)} ignicoes 1h (ret>=10% e vol>=3x) em {ign['market'].nunique()} pares ===")

    # 1. hora do dia (UTC e BRT=UTC-3)
    print("\n── 1. HORA DA IGNICAO (contagem por hora UTC | BRT = UTC-3) ──")
    hc = ign.groupby("hour").size()
    mx = hc.max()
    for h in range(24):
        n = hc.get(h, 0)
        bar = "#" * int(n / mx * 30)
        print(f"    {h:02d} UTC ({(h-3)%24:02d} BRT): {n:>4} {bar}")

    # 2. o que acontece nas 6h ANTES da ignicao (assinatura pre-pump)
    print("\n── 2. AS 6 HORAS ANTES DA IGNICAO (mediana) vs candle normal ──")
    idx = df.set_index(["market", "ts"])
    feats = {"ret": [], "v_ratio": []}
    base_ret = df["ret"].median()
    base_vr = df["v_ratio"].median()
    for lag in range(1, 7):
        r = df.groupby("market")["ret"].shift(lag).reindex(ign.index)
        v = df.groupby("market")["v_ratio"].shift(lag).reindex(ign.index)
        feats["ret"].append(r.median())
        feats["v_ratio"].append(v.median())
    print(f"    hora:      H-6    H-5    H-4    H-3    H-2    H-1   | normal")
    print("    ret %:  " + "  ".join(f"{v:+5.2f}" for v in reversed(feats["ret"])) + f"  | {base_ret:+5.2f}")
    print("    vol x:  " + "  ".join(f"{v:5.2f}" for v in reversed(feats["v_ratio"])) + f"  | {base_vr:5.2f}")

    # 3. o que acontece DEPOIS da ignicao (rampa e ressaca, horas +1..+12)
    print("\n── 3. DEPOIS DA IGNICAO: retorno acumulado mediano (h+1..h+12) ──")
    cum = []
    for lag in range(1, 13):
        r = df.groupby("market")["ret"].shift(-lag).reindex(ign.index)
        cum.append(r)
    cum_df = pd.concat(cum, axis=1)
    cum_df.columns = [f"h{i}" for i in range(1, 13)]
    acc = cum_df.cumsum(axis=1)
    med = acc.median()
    pos = (acc > 0).mean() * 100
    print(f"    {'h+':>4} | {'ret acum mediana':>16} | {'% positivo':>10}")
    for i, c in enumerate(acc.columns, 1):
        print(f"    {i:>4} | {med[c]:>+15.2f}% | {pos[c]:>9.0f}%")

    # 4. continuacao: probabilidade de mais +10% apos ignicao
    nxt_high = df.groupby("market")["high"].shift(-1)
    close0 = ign["close"]
    up_next = ((nxt_high.reindex(ign.index) - close0) / close0 * 100)
    print(f"\n── 4. CONTINUACAO IMEDIATA (h+1) ──")
    print(f"    high de h+1 >= +5% acima do close da ignicao: {(up_next >= 5).mean()*100:.0f}% dos casos")
    print(f"    high de h+1 >= +10%: {(up_next >= 10).mean()*100:.0f}% | mediana do pico h+1: {up_next.median():+.1f}%")


CSV_15M = DATA / "universe_15m.csv"
CSV_30M = DATA / "universe_30m.csv"
CSV_1W = DATA / "universe_week.csv"
CSV_1D_FULL = DATA / "universe_daily_full.csv"


def _pumped_pairs():
    import pandas as pd
    df = pd.read_csv(CSV_1D)
    df["ret"] = (pd.to_numeric(df["close"]) - pd.to_numeric(df["open"])) / pd.to_numeric(df["open"]) * 100
    df["date"] = pd.to_datetime(df["ts"], unit="ms")
    recent = df[df["date"] >= df["date"].max() - pd.Timedelta(days=21)]
    return sorted(recent[recent["ret"] >= 15]["market"].unique())


def collectall():
    """Coleta os frames extras em serie: 15m, 30m (pares pumped), 1w e 1d-full (todos)."""
    pumped = _pumped_pairs()
    allp = list_pairs()
    print(f"[1/4] 15min x 1000 (~10d) em {len(pumped)} pares pumped...")
    collect_tf(pumped, "15min", 1000, CSV_15M)
    print(f"[2/4] 30min x 1000 (~21d) em {len(pumped)} pares pumped...")
    collect_tf(pumped, "30min", 1000, CSV_30M)
    print(f"[3/4] 1week x 1000 em {len(allp)} pares (historico completo)...")
    collect_tf(allp, "1week", 1000, CSV_1W)
    print(f"[4/4] 1day x 1000 (~2.7 anos) em {len(allp)} pares...")
    collect_tf(allp, "1day", 1000, CSV_1D_FULL)


def lawx():
    """Lei de dissipacao em TODOS os frames: 15m, 30m, 1h, 4h, 1d, 1w e agregados M/3M/6M/Y."""
    import pandas as pd

    frames = [
        ("15M", CSV_15M, [-100, -5, -3, -1, 0, 1, 3, 5, 10, 1000],
         ["<-5", "-5..-3", "-3..-1", "-1..0", "0..1", "1..3", "3..5", "5..10", ">10"]),
        ("30M", CSV_30M, [-100, -7, -4, -2, 0, 2, 4, 7, 15, 1000],
         ["<-7", "-7..-4", "-4..-2", "-2..0", "0..2", "2..4", "4..7", "7..15", ">15"]),
        ("1W", CSV_1W, [-100, -40, -25, -10, 0, 10, 25, 50, 100, 10000],
         ["<-40", "-40..-25", "-25..-10", "-10..0", "0..10", "10..25", "25..50", "50..100", ">100"]),
    ]
    for name, csv, bins, labels in frames:
        if not csv.exists():
            print(f"[{name}] sem dados")
            continue
        df = _load(csv)
        g = df.groupby("market")
        df["ret_n1"] = g["ret"].shift(-1)
        d = df.dropna(subset=["ret_n1"])
        d = d[d["vol_usd"] > 100]
        print(f"\n=== LEI {name} | n={len(d)} ===")
        d["rb"] = pd.cut(d["ret"], bins, labels=labels)
        tab = d.groupby("rb", observed=True)["ret_n1"].agg(["median", "mean", "count"])
        for k, r in tab.iterrows():
            print(f"    {k:>9} | median {r['median']:>+7.2f}% | mean {r['mean']:>+7.2f}% | n={int(r['count']):>7}")

    # agregados mensal/trimestral/semestral/anual a partir do daily_full
    if not CSV_1D_FULL.exists():
        print("\n[M/3M/6M/Y] sem daily_full")
        return
    df = _load(CSV_1D_FULL)
    df = df.set_index("dt")
    for name, rule, bins, labels in [
        ("MENSAL", "ME", [-100, -50, -30, -10, 0, 20, 50, 100, 100000],
         ["<-50", "-50..-30", "-30..-10", "-10..0", "0..20", "20..50", "50..100", ">100"]),
        ("TRIMESTRAL", "QE", [-100, -60, -30, 0, 50, 150, 100000],
         ["<-60", "-60..-30", "-30..0", "0..50", "50..150", ">150"]),
        ("SEMESTRAL", "2QE", [-100, -70, -30, 0, 100, 100000],
         ["<-70", "-70..-30", "-30..0", "0..100", ">100"]),
        ("ANUAL", "YE", [-100, -80, -40, 0, 200, 100000],
         ["<-80", "-80..-40", "-40..0", "0..200", ">200"]),
    ]:
        agg = df.groupby("market").resample(rule).agg(
            open=("open", "first"), close=("close", "last"), vol=("vol_usd", "sum")).dropna()
        agg = agg[agg["open"] > 0]
        agg["ret"] = (agg["close"] - agg["open"]) / agg["open"] * 100
        agg = agg.reset_index().sort_values(["market", "dt"])
        agg["ret_n1"] = agg.groupby("market")["ret"].shift(-1)
        d = agg.dropna(subset=["ret_n1"])
        d = d[d["vol"] > 1000]
        if len(d) < 50:
            print(f"\n=== LEI {name}: n={len(d)} (pouco) ===")
            continue
        print(f"\n=== LEI {name} | n={len(d)} periodos-par ===")
        d["rb"] = pd.cut(d["ret"], bins, labels=labels)
        tab = d.groupby("rb", observed=True)["ret_n1"].agg(["median", "mean", "count"])
        for k, r in tab.iterrows():
            print(f"    {k:>9} | median {r['median']:>+7.1f}% | mean {r['mean']:>+7.1f}% | n={int(r['count']):>6}")


def macro():
    """Visao macro: sazonalidade mensal (altseason?), drift do universo, MORTALIDADE."""
    import pandas as pd
    import numpy as np

    df = _load(CSV_1D_FULL)
    print(f"=== MACRO | {df['market'].nunique()} pares | {df['dt'].min().date()} -> {df['dt'].max().date()} ===")

    # 1. Sazonalidade mensal: retorno mediano do universo por MES calendario
    df["ym"] = df["dt"].dt.to_period("M")
    monthly = df.set_index("dt").groupby("market").resample("ME").agg(
        open=("open", "first"), close=("close", "last")).dropna()
    monthly = monthly[monthly["open"] > 0]
    monthly["ret"] = (monthly["close"] - monthly["open"]) / monthly["open"] * 100
    monthly = monthly.reset_index()
    monthly["month"] = monthly["dt"].dt.month
    monthly["year"] = monthly["dt"].dt.year
    print("\n── 1. SAZONALIDADE: retorno mensal MEDIANO do universo por mes (todos os anos) ──")
    ms = monthly.groupby("month")["ret"].agg(["median", "count"])
    for m, r in ms.iterrows():
        bar = "#" * int(abs(r["median"]))
        sign = "+" if r["median"] >= 0 else "-"
        print(f"    mes {m:02d}: {r['median']:>+6.1f}% {sign*0}{bar}  (n={int(r['count'])})")

    # 2. Drift por ano: quanto o universo rende por ano-mediano
    print("\n── 2. DRIFT ANUAL do universo (mediana do retorno mensal por ano) ──")
    ys = monthly.groupby("year")["ret"].agg(["median", "count"])
    for y, r in ys.iterrows():
        print(f"    {y}: mediana mensal {r['median']:>+6.1f}% (n={int(r['count'])})")

    # 3. MORTALIDADE: dos pares que existiam ha 12+ meses, quantos ainda tem volume?
    print("\n── 3. MORTALIDADE (survivorship) ──")
    last30 = df[df["dt"] >= df["dt"].max() - pd.Timedelta(days=30)]
    vol_now = last30.groupby("market")["vol_usd"].median()
    first_seen = df.groupby("market")["dt"].min()
    old = first_seen[first_seen <= df["dt"].max() - pd.Timedelta(days=365)].index
    if len(old) > 20:
        alive = (vol_now.reindex(old).fillna(0) >= 1000).mean() * 100
        dead = (vol_now.reindex(old).fillna(0) < 100).mean() * 100
        print(f"    pares listados ha 12+ meses: {len(old)}")
        print(f"    ainda 'vivos' (vol mediano 30d >= $1K): {alive:.0f}%")
        print(f"    'mortos' (vol < $100): {dead:.0f}%")
    # retorno de 12 meses dos antigos (o custo de holdar microcap)
    oned = df[df["market"].isin(old)]
    yr = oned.set_index("dt").groupby("market").resample("YE").agg(
        open=("open", "first"), close=("close", "last")).dropna()
    yr = yr[yr["open"] > 0]
    yr["ret"] = (yr["close"] - yr["open"]) / yr["open"] * 100
    if len(yr):
        print(f"    retorno ANUAL mediano dos pares 12m+: {yr['ret'].median():+.0f}% | % anos positivos: {(yr['ret']>0).mean()*100:.0f}%")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "law"
    {"collect4h": collect4h, "collect1h": collect1h, "law": law, "anatomy": anatomy,
     "collectall": collectall, "lawx": lawx, "macro": macro}[mode]()

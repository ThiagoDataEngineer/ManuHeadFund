# universe_pump_study.py — Estudo do comportamento de pumps no universo CoinEx
# 2026-07-03: análise exploratória PRÉ-recalibragem (pedido do usuário: estudar
# o universo antes de mexer em gates — existe padrão/sazonalidade nos pumps?)
#
# Fase 1 (coleta): klines 1d (120 dias) de todos os pares spot USDT
# Fase 2 (análise): pump-rate diário, clusters, correlação BTC, DoW, pós-pump D+1/D+2
#
# Uso:
#   python backtest/universe_pump_study.py collect   # baixa dados -> universe_daily.csv
#   python backtest/universe_pump_study.py analyze   # roda análise -> imprime relatório

import sys
import time
import json
import urllib.request
from pathlib import Path

BASE = "https://api.coinex.com/v2"
OUT_DIR = Path(__file__).parent / "data"
OUT_DIR.mkdir(exist_ok=True)
RAW_CSV = OUT_DIR / "universe_daily.csv"
DAYS = 120
MIN_VOL_USD = 1000  # exclui pares mortos


def get_json(url: str, retries: int = 3):
    for i in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                return json.loads(r.read().decode())
        except Exception:
            if i == retries - 1:
                return None
            time.sleep(1.0 * (i + 1))
    return None


def collect():
    print("[1/2] Listando pares spot USDT...")
    r = get_json(f"{BASE}/spot/ticker")
    if not r or r.get("code") != 0:
        print("ERRO ao listar tickers")
        sys.exit(1)
    pairs = []
    for t in r["data"]:
        m = t.get("market", "")
        if not m.endswith("USDT"):
            continue
        try:
            vol_usd = float(t.get("value", 0))
        except (TypeError, ValueError):
            vol_usd = 0
        if vol_usd >= MIN_VOL_USD:
            pairs.append(m)
    print(f"  {len(pairs)} pares USDT com vol >= ${MIN_VOL_USD}")

    print(f"[2/2] Baixando klines 1d x {DAYS} dias por par (rate ~10/s)...")
    rows = []
    t0 = time.time()
    for i, m in enumerate(pairs):
        r = get_json(f"{BASE}/spot/kline?market={m}&period=1day&limit={DAYS}")
        if r and r.get("code") == 0 and r.get("data"):
            for k in r["data"]:
                rows.append((
                    m,
                    int(k["created_at"]),
                    k["open"], k["high"], k["low"], k["close"], k["value"],
                ))
        if (i + 1) % 100 == 0:
            el = time.time() - t0
            print(f"  {i+1}/{len(pairs)} pares ({el:.0f}s, {len(rows)} candles)")
        time.sleep(0.08)  # ~12 req/s, abaixo do rate limit publico

    with open(RAW_CSV, "w", encoding="utf-8") as f:
        f.write("market,ts,open,high,low,close,vol_usd\n")
        for row in rows:
            f.write(",".join(str(x) for x in row) + "\n")
    print(f"OK: {len(rows)} candles de {len(pairs)} pares -> {RAW_CSV}")


def analyze():
    import pandas as pd
    import numpy as np

    df = pd.read_csv(RAW_CSV)
    df["date"] = pd.to_datetime(df["ts"], unit="ms").dt.date
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "close"])
    df = df[df["open"] > 0]
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100.0
    # retorno intradiário máximo (open -> high): o que um scalp de venda rápida capturaria
    df["ret_hi"] = (df["high"] - df["open"]) / df["open"] * 100.0

    n_days = df["date"].nunique()
    n_mkts = df["market"].nunique()
    print(f"=== UNIVERSO: {n_mkts} pares | {n_days} dias | {len(df)} candles ===\n")

    # ── 1. PUMP-RATE DIÁRIO ─────────────────────────────────────────────
    daily = df.groupby("date").agg(
        n_mkts=("market", "count"),
        p20=("ret", lambda s: int((s >= 20).sum())),
        p30=("ret", lambda s: int((s >= 30).sum())),
        p50=("ret", lambda s: int((s >= 50).sum())),
        d20=("ret", lambda s: int((s <= -20).sum())),
        med_ret=("ret", "median"),
    ).reset_index()
    daily["pump_rate"] = daily["p20"] / daily["n_mkts"] * 100

    print("── 1. PUMPS POR DIA (>=+20% | >=+30% | >=+50% open->close) ──")
    print(f"  Média/dia:   {daily['p20'].mean():.1f} | {daily['p30'].mean():.1f} | {daily['p50'].mean():.1f}")
    print(f"  Mediana/dia: {daily['p20'].median():.0f} | {daily['p30'].median():.0f} | {daily['p50'].median():.0f}")
    print(f"  Máximo/dia:  {daily['p20'].max()} | {daily['p30'].max()} | {daily['p50'].max()}")
    print(f"  Dias com ZERO pump +20%: {(daily['p20']==0).sum()}/{len(daily)}")
    print(f"  Dias com 10+ pumps +20%: {(daily['p20']>=10).sum()}/{len(daily)}")

    top5 = daily.nlargest(5, "p20")[["date", "p20", "p30", "p50", "med_ret"]]
    print("\n  TOP 5 dias de pump:")
    for _, r in top5.iterrows():
        print(f"    {r['date']}  +20%:{r['p20']:>3}  +30%:{r['p30']:>3}  +50%:{r['p50']:>3}  mediana universo: {r['med_ret']:+.1f}%")

    # ── 2. CLUSTERS: pump hoje prevê pump amanhã? ───────────────────────
    s = daily.sort_values("date")["p20"]
    ac1 = s.autocorr(lag=1)
    ac2 = s.autocorr(lag=2)
    ac7 = s.autocorr(lag=7)
    print(f"\n── 2. CLUSTERING (autocorrelação do n_pumps diário) ──")
    print(f"  lag 1d: {ac1:+.2f} | lag 2d: {ac2:+.2f} | lag 7d: {ac7:+.2f}")
    print(f"  ({'CLUSTERIZA — dias de pump vêm em ondas' if ac1 > 0.3 else 'fraco/sem cluster — pumps ~independentes dia a dia'})")

    # ── 3. CORRELAÇÃO COM BTC ───────────────────────────────────────────
    btc = df[df["market"] == "BTCUSDT"][["date", "ret"]].rename(columns={"ret": "btc_ret"})
    m = daily.merge(btc, on="date", how="inner")
    if len(m) > 10:
        c_same = m["p20"].corr(m["btc_ret"])
        m["btc_prev"] = m["btc_ret"].shift(1)
        c_lag = m["p20"].iloc[1:].corr(m["btc_prev"].iloc[1:])
        print(f"\n── 3. BTC vs PUMP-RATE ──")
        print(f"  corr(n_pumps, BTC ret mesmo dia): {c_same:+.2f}")
        print(f"  corr(n_pumps, BTC ret dia anterior): {c_lag:+.2f}")
        up = m[m["btc_ret"] > 1]["p20"].mean()
        flat = m[m["btc_ret"].abs() <= 1]["p20"].mean()
        dn = m[m["btc_ret"] < -1]["p20"].mean()
        print(f"  pumps/dia quando BTC: sobe>1%: {up:.1f} | lateral ±1%: {flat:.1f} | cai>1%: {dn:.1f}")

    # ── 4. DIA DA SEMANA ────────────────────────────────────────────────
    daily["dow"] = pd.to_datetime(daily["date"].astype(str)).dt.day_name()
    dow = daily.groupby("dow")["p20"].mean().reindex(
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
    print("\n── 4. SAZONALIDADE — pumps médios por dia da semana ──")
    for d, v in dow.items():
        bar = "#" * int(v * 2)
        print(f"  {d[:3]}: {v:5.1f}  {bar}")

    # ── 5. PÓS-PUMP: continuação ou reversão? (D+1, D+2) ────────────────
    df_s = df.sort_values(["market", "date"]).reset_index(drop=True)
    df_s["ret_d1"] = df_s.groupby("market")["ret"].shift(-1)
    df_s["ret_d2"] = df_s.groupby("market")["ret"].shift(-2)
    df_s["rethi_d1"] = df_s.groupby("market")["ret_hi"].shift(-1)
    pumps = df_s[(df_s["ret"] >= 20) & df_s["ret_d1"].notna()]
    print(f"\n── 5. O QUE ACONTECE DEPOIS de um pump +20%? (n={len(pumps)}) ──")
    print(f"  D+1 mediana:    {pumps['ret_d1'].median():+.1f}%  (média {pumps['ret_d1'].mean():+.1f}%)")
    print(f"  D+1 sobe mais:  {(pumps['ret_d1']>0).mean()*100:.0f}% dos casos")
    print(f"  D+1 cai >=10%:  {(pumps['ret_d1']<=-10).mean()*100:.0f}% dos casos")
    print(f"  D+1 high>=+10% (janela p/ venda rápida intraday): {(pumps['rethi_d1']>=10).mean()*100:.0f}% dos casos")
    p2 = pumps[pumps["ret_d2"].notna()]
    print(f"  D+2 mediana:    {p2['ret_d2'].median():+.1f}%")
    # SHORT do topo: pump +30% -> retorno D+1
    big = df_s[(df_s["ret"] >= 30) & df_s["ret_d1"].notna()]
    print(f"\n  Pumps >=+30% (n={len(big)}): D+1 mediana {big['ret_d1'].median():+.1f}% | cai em {(big['ret_d1']<0).mean()*100:.0f}% dos casos")

    # ── 6. TAMANHO DO UNIVERSO PUMPÁVEL por faixa de volume ─────────────
    volband = df.copy()
    volband["band"] = pd.cut(volband["vol_usd"],
                             [0, 10_000, 50_000, 500_000, 5_000_000, np.inf],
                             labels=["<10K", "10-50K", "50-500K", "0.5-5M", ">5M"])
    bb = volband.groupby("band", observed=True).agg(
        candles=("ret", "count"),
        pct_pump20=("ret", lambda s: (s >= 20).mean() * 100),
        pct_dump20=("ret", lambda s: (s <= -20).mean() * 100),
    )
    print("\n── 6. ONDE os pumps acontecem (faixa de volume 24h do dia) ──")
    print(f"  {'faixa':>8} | {'candles':>8} | {'% dias +20%':>11} | {'% dias -20%':>11}")
    for band, r in bb.iterrows():
        print(f"  {band:>8} | {int(r['candles']):>8} | {r['pct_pump20']:>10.2f}% | {r['pct_dump20']:>10.2f}%")

    daily.to_csv(OUT_DIR / "daily_pump_rate.csv", index=False)
    print(f"\nSérie diária salva: {OUT_DIR / 'daily_pump_rate.csv'}")


def fingerprint():
    """Fase 3: o que os dias D-3..D-1 tem em comum ANTES de pump (+20%) e dump (-20%)?
    Compara features da vespera contra baseline e mede LIFT de probabilidade."""
    import pandas as pd
    import numpy as np

    df = pd.read_csv(RAW_CSV)
    df["date"] = pd.to_datetime(df["ts"], unit="ms")
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "close", "high", "low"])
    df = df[df["open"] > 0].sort_values(["market", "date"]).reset_index(drop=True)

    g = df.groupby("market")
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
    df["range_pct"] = (df["high"] - df["low"]) / df["open"] * 100
    rng = (df["high"] - df["low"])
    df["clv"] = np.where(rng > 0, (df["close"] - df["low"]) / rng, 0.5)  # 1=fechou no topo
    df["upwick"] = (df["high"] - df[["open", "close"]].max(axis=1)) / df["open"] * 100

    # janela de referencia D-7..D-2 (média movel deslocada)
    df["vol_ma5"] = g["vol_usd"].transform(lambda s: s.shift(2).rolling(5, min_periods=3).mean())
    df["range_ma5"] = g["range_pct"].transform(lambda s: s.shift(2).rolling(5, min_periods=3).mean())

    # features da VESPERA (D-1) para prever D0
    df["v_ratio"] = (g["vol_usd"].shift(1) / df["vol_ma5"].replace(0, np.nan)).clip(upper=50)
    df["v_accel"] = (g["vol_usd"].shift(1) / g["vol_usd"].shift(2).replace(0, np.nan)).clip(upper=50)
    df["r1"] = g["ret"].shift(1)
    df["r3"] = g["ret"].shift(1) + g["ret"].shift(2) + g["ret"].shift(3)
    df["clv1"] = g["clv"].shift(1)
    df["compress"] = (g["range_pct"].shift(1) / df["range_ma5"].replace(0, np.nan)).clip(upper=20)
    df["upwick1"] = g["upwick"].shift(1)
    df["vol1"] = g["vol_usd"].shift(1)

    df["pump"] = df["ret"] >= 20
    df["dump"] = df["ret"] <= -20

    d = df.dropna(subset=["v_ratio", "r1", "clv1", "compress", "vol1"])
    d = d[d["vol1"] >= 3000]  # liquidez minima da vespera (operavel)
    base_p = d["pump"].mean() * 100
    base_d = d["dump"].mean() * 100
    print(f"=== FINGERPRINT D-1 -> D0 | amostra {len(d)} dias-par (vol vespera >= $3K) ===")
    print(f"Base rate: PUMP +20% = {base_p:.2f}%   DUMP -20% = {base_d:.2f}%\n")

    feats = ["v_ratio", "v_accel", "r1", "r3", "clv1", "compress", "upwick1"]
    print("── MEDIANA das features na VESPERA: pump-eve vs dump-eve vs normal ──")
    print(f"  {'feature':>9} | {'pre-PUMP':>9} | {'pre-DUMP':>9} | {'normal':>9}")
    pe = d[d["pump"]]
    de = d[d["dump"]]
    nn = d[~d["pump"] & ~d["dump"]]
    for f in feats:
        print(f"  {f:>9} | {pe[f].median():>9.2f} | {de[f].median():>9.2f} | {nn[f].median():>9.2f}")

    # LIFT univariado por quintil
    print("\n── LIFT univariado: P(evento D0 | quintil da feature D-1) / base ──")
    for f in feats:
        try:
            d["q"] = pd.qcut(d[f], 5, labels=False, duplicates="drop")
        except ValueError:
            continue
        liftp = d.groupby("q")["pump"].mean() * 100 / base_p
        liftd = d.groupby("q")["dump"].mean() * 100 / base_d
        lp = " ".join(f"{v:4.1f}" for v in liftp)
        ld = " ".join(f"{v:4.1f}" for v in liftd)
        print(f"  {f:>9}: PUMP [{lp}]  DUMP [{ld}]  (quintis baixo->alto)")

    # REGRAS COMBINADAS candidatas
    print("\n── REGRAS COMBINADAS (P(evento) e lift vs base) ──")
    rules_pump = [
        ("vol 3x + subiu 5-20% ontem + fechou no topo",
         (d.v_ratio >= 3) & d.r1.between(5, 20) & (d.clv1 >= 0.7)),
        ("vol 5x + range expandindo 2x",
         (d.v_ratio >= 5) & (d.compress >= 2)),
        ("compressao (range<0.6x) + vol subindo (accel>1.5)",
         (d.compress <= 0.6) & (d.v_accel >= 1.5)),
        ("3d acumulado +10..+30% + vol 2x (onda em curso)",
         d.r3.between(10, 30) & (d.v_ratio >= 2)),
        ("pump ontem +20..50% (chase — controle)",
         d.r1.between(20, 50)),
    ]
    rules_dump = [
        ("pump ontem >=30% (short do topo)", d.r1 >= 30),
        ("pump ontem >=20% + upwick >=5% (rejeicao)",
         (d.r1 >= 20) & (d.upwick1 >= 5)),
        ("pump ontem >=20% + fechou fraco (clv<0.4)",
         (d.r1 >= 20) & (d.clv1 <= 0.4)),
        ("2 dias caindo (r3<-15%) + vol 2x (cascata)",
         (d.r3 <= -15) & (d.v_ratio >= 2)),
        ("upwick >=8% ontem (exaustao)", d.upwick1 >= 8),
    ]
    print("  PUMP (long/spot pre-entrada):")
    for name, mask in rules_pump:
        sub = d[mask]
        if len(sub) < 30:
            print(f"    {name:>52}: n={len(sub)} (amostra pequena)")
            continue
        p = sub["pump"].mean() * 100
        med = sub["ret"].median()
        print(f"    {name:>52}: n={len(sub):>5} P(pump)={p:4.1f}% lift={p/base_p:4.1f}x | ret D0 mediana {med:+.1f}%")
    print("  DUMP (short pre-entrada):")
    for name, mask in rules_dump:
        sub = d[mask]
        if len(sub) < 30:
            print(f"    {name:>52}: n={len(sub)} (amostra pequena)")
            continue
        p = sub["dump"].mean() * 100
        med = sub["ret"].median()
        print(f"    {name:>52}: n={len(sub):>5} P(dump)={p:4.1f}% lift={p/base_d:4.1f}x | ret D0 mediana {med:+.1f}%")


def trend():
    """Fase 4: TENDENCIA (proxy diaria de trendline/Tori) cruzada com pump/dump.
    Pergunta-chave: pump +30% em DOWNTREND reverte mais que em UPTREND?
    Define se Tori entra como peso, hard filter ou nao entra no sinal pos-pump."""
    import pandas as pd
    import numpy as np

    df = pd.read_csv(RAW_CSV)
    df["date"] = pd.to_datetime(df["ts"], unit="ms")
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "close"])
    df = df[df["open"] > 0].sort_values(["market", "date"]).reset_index(drop=True)

    g = df.groupby("market")
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
    df["ema20"] = g["close"].transform(lambda s: s.ewm(span=20, min_periods=15).mean())
    df["ema50"] = g["close"].transform(lambda s: s.ewm(span=50, min_periods=30).mean())
    df["ema20_slope"] = g["ema20"].transform(lambda s: (s / s.shift(5) - 1) * 100)

    # Classe de tendencia na VESPERA (D-1), como o app veria antes de decidir
    close1 = g["close"].shift(1)
    ema20_1 = g["ema20"].shift(1)
    ema50_1 = g["ema50"].shift(1)
    slope1 = g["ema20_slope"].shift(1)
    df["trend"] = np.select(
        [
            (close1 > ema20_1) & (ema20_1 > ema50_1) & (slope1 > 0),
            (close1 < ema20_1) & (ema20_1 < ema50_1) & (slope1 < 0),
        ],
        ["UPTREND", "DOWNTREND"],
        default="NEUTRO",
    )
    df["r1"] = g["ret"].shift(1)
    df["ret_d1"] = g["ret"].shift(-1)
    df["high_d1"] = g["high"].shift(-1)
    df["open_d1"] = g["open"].shift(-1)
    df["upwick"] = (df["high"] - df[["open", "close"]].max(axis=1)) / df["open"] * 100
    df["vol1"] = g["vol_usd"].shift(1)

    d = df.dropna(subset=["trend", "r1", "ret_d1"])
    d = d[d["vol1"] >= 3000]

    dist = d["trend"].value_counts(normalize=True) * 100
    print(f"=== TENDENCIA (proxy EMA20/50 diaria) x PUMP/DUMP | n={len(d)} ===")
    print("Distribuicao do universo: " + " | ".join(f"{k}: {v:.0f}%" for k, v in dist.items()))

    # ── A. SHORT pos-pump: o edge muda por tendencia? ──────────────────
    print("\n── A. POS-PUMP (ontem +30%): retorno de HOJE por tendencia ──")
    print(f"  {'tendencia':>10} | {'n':>5} | {'mediana D0':>10} | {'cai%':>5} | {'dump -20%':>9} | {'sobe +10% (risco short)':>12}")
    pp = d[d["r1"] >= 30]
    for t in ["DOWNTREND", "NEUTRO", "UPTREND"]:
        s = pp[pp["trend"] == t]
        if len(s) < 20:
            print(f"  {t:>10} | n={len(s)} (pequeno)")
            continue
        print(f"  {t:>10} | {len(s):>5} | {s['ret'].median():>+9.1f}% | {(s['ret']<0).mean()*100:>4.0f}% | {(s['ret']<=-20).mean()*100:>8.1f}% | {(s['ret']>=10).mean()*100:>11.1f}%")

    print("\n  (pump ontem 20-30% — sinal mais fraco)")
    pp2 = d[d["r1"].between(20, 30)]
    for t in ["DOWNTREND", "NEUTRO", "UPTREND"]:
        s = pp2[pp2["trend"] == t]
        if len(s) < 20:
            continue
        print(f"  {t:>10} | {len(s):>5} | {s['ret'].median():>+9.1f}% | {(s['ret']<0).mean()*100:>4.0f}% | {(s['ret']<=-20).mean()*100:>8.1f}% | {(s['ret']>=10).mean()*100:>11.1f}%")

    # ── B. LONG: pump nasce mais em qual tendencia? e continua? ────────
    print("\n── B. PUMPS +20% de HOJE: em qual tendencia nasceram? ──")
    pumps = d[d["ret"] >= 20]
    base_by_t = d.groupby("trend")["ret"].apply(lambda s: (s >= 20).mean() * 100)
    for t in ["UPTREND", "NEUTRO", "DOWNTREND"]:
        n_t = (pumps["trend"] == t).sum()
        rate = base_by_t.get(t, 0)
        cont = pumps[pumps["trend"] == t]["ret_d1"]
        med_d1 = cont.median() if len(cont) > 10 else float("nan")
        print(f"  {t:>10}: {n_t:>4} pumps | P(pump)={rate:.2f}% | D+1 mediana {med_d1:+.1f}%")

    # ── C. Bear rally classico (BEAR_MARKET 4.3): rally em downtrend ───
    print("\n── C. SETUP CANONICO BEAR 4.3: rally 15%+ ONTEM em DOWNTREND + upwick ──")
    ups1 = g["upwick"].shift(1)
    d2 = d.copy()
    d2["upwick1"] = ups1.reindex(d2.index)
    canon = d2[(d2["trend"] == "DOWNTREND") & (d2["r1"] >= 15) & (d2["upwick1"] >= 3)]
    if len(canon) >= 30:
        print(f"  n={len(canon)} | D0 mediana {canon['ret'].median():+.1f}% | cai {(canon['ret']<0).mean()*100:.0f}% | dump-20 {(canon['ret']<=-20).mean()*100:.1f}%")
    else:
        print(f"  n={len(canon)} (amostra pequena)")


def formula():
    """Fase 5: extrair a FORMA FUNCIONAL do comportamento do universo.
    1. W(t): temperatura de pump do universo (EWMA) e seu poder preditivo
    2. Curva de resposta E[ret D+1 | ret D0] — a lei de mean-reversion do par
    3. Curva de resposta ao volume
    4. Interacao: reversao pos-pump muda conforme W(t)?
    5. Regressao linear interpretavel -> coeficientes da formula S_short/S_long"""
    import pandas as pd
    import numpy as np

    df = pd.read_csv(RAW_CSV)
    df["date"] = pd.to_datetime(df["ts"], unit="ms")
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "close", "high", "low"])
    df = df[df["open"] > 0].sort_values(["market", "date"]).reset_index(drop=True)

    g = df.groupby("market")
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
    df["ret_d1"] = g["ret"].shift(-1)
    df["upwick"] = (df["high"] - df[["open", "close"]].max(axis=1)) / df["open"] * 100
    df["vol_ma5"] = g["vol_usd"].transform(lambda s: s.shift(1).rolling(5, min_periods=3).mean())
    df["v_ratio"] = (df["vol_usd"] / df["vol_ma5"].replace(0, np.nan)).clip(upper=50)
    df["r3prev"] = g["ret"].shift(1).rolling(3, min_periods=3).sum().reset_index(drop=True)

    d = df.dropna(subset=["ret_d1", "v_ratio"])
    d = d[d["vol_usd"] >= 3000]

    # ── 1. W(t): TEMPERATURA DO UNIVERSO ────────────────────────────────
    daily = df.groupby(df["date"].dt.date).agg(
        n=("market", "count"), p20=("ret", lambda s: (s >= 20).sum()))
    daily["rate"] = daily["p20"] / daily["n"] * 100
    # W = EWMA 2 dias do pump-rate (meia-vida ~ AC observada 0.6)
    daily["W"] = daily["rate"].ewm(halflife=2).mean()
    daily["rate_next"] = daily["rate"].shift(-1)
    dd = daily.dropna()
    print("=== 1. W(t) — TEMPERATURA DE PUMP DO UNIVERSO ===")
    print("    W(t) = EWMA(halflife=2d) do pump-rate diario (%% de pares +20%)")
    q = pd.qcut(dd["W"], 4, labels=["W frio", "W morno", "W quente", "W FERVENDO"])
    tab = dd.groupby(q, observed=True)["rate_next"].agg(["mean", "median", "count"])
    print(f"    corr(W(t), pump_rate(t+1)) = {dd['W'].corr(dd['rate_next']):+.2f}")
    for k, r in tab.iterrows():
        print(f"    {k:>12}: pump-rate AMANHA media {r['mean']:.2f}% (mediana {r['median']:.2f}%, n={int(r['count'])})")

    # ── 2. CURVA DE MEAN-REVERSION: E[ret D+1 | ret D0] ────────────────
    print("\n=== 2. CURVA DE RESPOSTA: E[ret amanha | ret hoje] (a lei do par) ===")
    bins = [-100, -30, -20, -10, -5, 0, 5, 10, 20, 30, 50, 1000]
    labels = ["<-30", "-30..-20", "-20..-10", "-10..-5", "-5..0", "0..5", "5..10", "10..20", "20..30", "30..50", ">50"]
    d["rb"] = pd.cut(d["ret"], bins, labels=labels)
    tab2 = d.groupby("rb", observed=True)["ret_d1"].agg(["median", "mean", "count"])
    print(f"    {'ret hoje':>9} | {'D+1 mediana':>11} | {'D+1 media':>9} | {'n':>6}")
    for k, r in tab2.iterrows():
        print(f"    {k:>9} | {r['median']:>+10.1f}% | {r['mean']:>+8.1f}% | {int(r['count']):>6}")

    # ── 3. CURVA DE VOLUME: E[ret D+1 | v_ratio D0] ────────────────────
    print("\n=== 3. CURVA DE RESPOSTA AO VOLUME: E[ret amanha | vol_ratio hoje] ===")
    vb = pd.cut(d["v_ratio"], [0, 0.5, 1, 2, 3, 5, 10, 100], labels=["<0.5x", "0.5-1x", "1-2x", "2-3x", "3-5x", "5-10x", ">10x"])
    tab3 = d.groupby(vb, observed=True)["ret_d1"].agg(["median", "count"])
    for k, r in tab3.iterrows():
        print(f"    vol {k:>7}: D+1 mediana {r['median']:>+5.1f}%  (n={int(r['count'])})")

    # ── 4. INTERACAO: reversao pos-pump x W(t) ──────────────────────────
    print("\n=== 4. INTERACAO: pos-pump (+30%) reverte igual em onda alta? ===")
    wmap = daily["W"].to_dict()
    d["W"] = d["date"].dt.date.map(wmap)
    pp = d[(d["ret"] >= 30) & d["W"].notna()]
    wq = pd.qcut(pp["W"], 3, labels=["W baixo", "W medio", "W alto"])
    tab4 = pp.groupby(wq, observed=True)["ret_d1"].agg(["median", "count"])
    tab4["cai"] = pp.groupby(wq, observed=True)["ret_d1"].apply(lambda s: (s < 0).mean() * 100)
    for k, r in tab4.iterrows():
        print(f"    {k:>8}: D+1 mediana {r['median']:>+5.1f}% | cai {r['cai']:.0f}% (n={int(r['count'])})")

    # ── 5. REGRESSAO INTERPRETAVEL: coeficientes da formula ────────────
    print("\n=== 5. FORMULA (OLS interpretavel sobre ret D+1, em %) ===")
    X = pd.DataFrame({
        "ext_pump": d["ret"].clip(lower=0) / 10,          # extensao de alta (por 10pp)
        "ext_dump": (-d["ret"]).clip(lower=0) / 10,        # extensao de queda (por 10pp)
        "upwick": d["upwick"].clip(0, 30) / 10,            # rejeicao (por 10pp)
        "vol_x": np.log1p(d["v_ratio"]),                   # volume (log)
        "W": (d["W"] - d["W"].mean()) / d["W"].std(),      # temperatura universo (z)
    })
    y = d["ret_d1"].clip(-50, 50)
    ok = X.notna().all(axis=1) & y.notna()
    Xo, yo = X[ok], y[ok]
    Xm = np.column_stack([np.ones(len(Xo)), Xo.values])
    beta, *_ = np.linalg.lstsq(Xm, yo.values, rcond=None)
    names = ["intercepto"] + list(Xo.columns)
    print("    E[ret D+1] =")
    for n, b in zip(names, beta):
        print(f"      {b:+.2f}  x {n}")
    pred = Xm @ beta
    ss_res = ((yo - pred) ** 2).sum()
    ss_tot = ((yo - yo.mean()) ** 2).sum()
    print(f"    R2 = {1 - ss_res/ss_tot:.3f} (n={len(yo)})")
    print("\n    Leitura: coeficiente de ext_pump = quanto cada +10pp de pump de hoje")
    print("    subtrai do retorno esperado de amanha. upwick idem. W>0 = onda alta.")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "analyze"
    if mode == "collect":
        collect()
    elif mode == "fingerprint":
        fingerprint()
    elif mode == "trend":
        trend()
    elif mode == "formula":
        formula()
    else:
        analyze()

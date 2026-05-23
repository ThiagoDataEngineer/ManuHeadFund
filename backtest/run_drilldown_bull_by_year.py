"""Runner: carrega trades BTCUSD do Supabase, executa drilldown, salva JSON."""
import os
import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from drilldown_bull_by_year import (
    build_drilldown_report, validate_schema, TRAIN_YEARS, HOLDOUT_YEARS,
)
from regime_direction_matrix import _load_trades_paginated
from regime_8state_classifier import reclassify_trades_8state
from db import Database


def _load_candles_paginated(market, period, start, end):
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    out = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*&market=eq.{market}&period=eq.{period}"
            f"&ts=gte.{start}&ts=lte.{end}"
            f"&order=ts.asc&limit={page}&offset={offset}"
        )
        rows = db._get("candles", params)
        out.extend(rows)
        if len(rows) < page:
            break
        offset += page
    return out


def main():
    print("Carregando trades BTCUSD 2014-2025 do Supabase...", flush=True)
    trades = _load_trades_paginated("BTCUSD", "2014-01-01", "2025-12-31")
    print(f"  -> {len(trades)} trades totais")

    print("Carregando candles BTCUSD 1hour para reclassificacao 8-state...", flush=True)
    candles = _load_candles_paginated("BTCUSD", "1hour", "2014-01-01", "2025-12-31")
    print(f"  -> {len(candles)} candles")

    print("Reclassificando trades para 8 regimes...", flush=True)
    trades = reclassify_trades_8state(trades, candles)
    from collections import Counter
    print(f"  -> Distribuicao apos reclass: {dict(Counter(t.get('regime') for t in trades))}")

    # Split train / holdout
    def year_of(t):
        ts = t.get("entry_ts", "")
        try:
            return int(str(ts)[:4])
        except (ValueError, TypeError):
            return None

    train_trades = [t for t in trades if year_of(t) in TRAIN_YEARS]
    holdout_trades = [t for t in trades if year_of(t) in HOLDOUT_YEARS]
    print(f"  -> Train (2014-2022): {len(train_trades)}")
    print(f"  -> Holdout (2023-2025): {len(holdout_trades)}")

    report = build_drilldown_report(train_trades, holdout_trades)
    assert validate_schema(report)

    out = Path(__file__).parent.parent / "journal" / "task2b_drilldown_bull_by_year.json"
    out.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print(f"\nSalvo: {out}")

    # Resumo
    print("\n" + "=" * 90)
    print("DRILLDOWN — BULL_STRONG e BULL_WEAK por ano (holdout 2023-2025)")
    print("=" * 90)
    print(f"\nTrain baseline aggregate (2014-2022):")
    for reg, m in report["train_baseline_aggregate"].items():
        print(f"  {reg:<13}: n={m['trades']:>5} exp={m['exp']:+.3f}R pf={m['pf']:.2f} wr={m['wr']:.1f}%")

    print(f"\nMetricas holdout por ano:")
    for year_str, regs in report["metricas_por_ano"].items():
        print(f"  {year_str}:")
        for reg, data in regs.items():
            d = data["delta_vs_train"]
            print(f"    {reg:<13}: n={data['trades']:>4} exp={data['exp']:+.3f}R "
                  f"pf={data['pf']:.2f} wr={data['wr']:.1f}% | delta_exp={d['delta_exp']:+.3f}R")

    print(f"\nDiagnostico por regime:")
    for reg, diag in report.get("diagnostico_por_regime", {}).items():
        print(f"  {reg}: {diag}")

    print(f"\nAno pior: {report['ano_pior']}")
    print(f"Razao:    {report['razao']}")
    print(f"\nPadrao trades perdedores:")
    print(f"  {report['padrao_trades_perdedores']}")
    print(f"\nDIAGNOSTICO FINAL: {report['diagnostico']}")
    print("=" * 90)


if __name__ == "__main__":
    main()

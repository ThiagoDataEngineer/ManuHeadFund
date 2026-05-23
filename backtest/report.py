"""
report.py — Relatório HTML de backtest com benchmarking por regime
Entrada: run_row (dict do backtest_runs) + RegimeBreakdown
Saída:   string HTML + arquivo opcional

Uso standalone:
    python report.py --run-id 1   (lê do Supabase e gera report.html)
"""
import argparse
import os
from typing import Optional

from metrics import BacktestMetrics, RegimeBreakdown

# ── Metas institucionais Tier 3 ───────────────────────────────────────────────

THRESHOLDS = {
    "win_rate":      {"min": 45.0, "ok": 55.0},
    "expectancy_r":  {"min": 0.3,  "ok": 0.5},
    "profit_factor": {"min": 1.5,  "ok": 2.0},
    "max_drawdown":  {"min": 20.0, "ok": 10.0, "lower_is_better": True},
    "sharpe_ratio":  {"min": 1.0,  "ok": 1.5},
}

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
       background: #0f1117; color: #e2e8f0; padding: 2rem; }
h1   { font-size: 1.4rem; color: #60a5fa; margin-bottom: 0.3rem; }
.sub { color: #64748b; font-size: 0.85rem; margin-bottom: 2rem; }
h2   { font-size: 1rem; color: #94a3b8; margin: 1.5rem 0 0.6rem; text-transform: uppercase;
       letter-spacing: 0.05em; }
table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
th    { text-align: left; padding: 0.5rem 0.75rem; color: #64748b;
        border-bottom: 1px solid #1e293b; font-weight: 500; }
td    { padding: 0.5rem 0.75rem; border-bottom: 1px solid #1e293b; }
tr:last-child td { border-bottom: none; }
.num  { text-align: right; font-variant-numeric: tabular-nums; }
.pass { color: #34d399; font-weight: 600; }
.warn { color: #fbbf24; }
.fail { color: #f87171; }
.regime-bull     { color: #60a5fa; }
.regime-bear     { color: #f87171; }
.regime-sideways { color: #94a3b8; }
.section { background: #1e293b; border-radius: 0.5rem; padding: 1rem; margin-bottom: 1rem; }
.badge-pass { background: #064e3b; color: #34d399; padding: 0.1rem 0.5rem;
              border-radius: 9999px; font-size: 0.75rem; margin-left: 0.5rem; }
.badge-fail { background: #450a0a; color: #f87171; padding: 0.1rem 0.5rem;
              border-radius: 9999px; font-size: 0.75rem; margin-left: 0.5rem; }
"""


def _grade(key: str, value: float) -> str:
    """Retorna classe CSS para o valor de uma métrica."""
    t = THRESHOLDS.get(key)
    if t is None:
        return ""
    lower = t.get("lower_is_better", False)
    if lower:
        if value <= t["ok"]:
            return "pass"
        if value <= t["min"]:
            return "warn"
        return "fail"
    else:
        if value >= t["ok"]:
            return "pass"
        if value >= t["min"]:
            return "warn"
        return "fail"


def _threshold_row(key: str, label: str, value: float, fmt: str) -> str:
    cls = _grade(key, value)
    t = THRESHOLDS.get(key, {})
    badge = f'<span class="badge-pass">✓ ok</span>' if cls == "pass" else \
            f'<span class="badge-fail">✗ fail</span>' if cls == "fail" else \
            f'<span class="badge-fail">⚠ warn</span>'
    lower = t.get("lower_is_better", False)
    ref = f"min {'≤' if lower else '≥'} {t.get('min')}  |  ok {'≤' if lower else '≥'} {t.get('ok')}"
    return (f"<tr><td>{label}</td>"
            f'<td class="num {cls}">{value:{fmt}}</td>'
            f'<td class="num" style="color:#475569;font-size:0.8rem">{ref}</td>'
            f"<td>{badge}</td></tr>")


def _regime_section(label: str, cls: str, m: Optional[BacktestMetrics]) -> str:
    if m is None:
        return (f'<tr><td class="{cls}">{label}</td>'
                f'<td class="num" style="color:#475569" colspan="4">sem trades</td></tr>')
    exp_cls = "pass" if m.expectancy_r > 0.3 else ("warn" if m.expectancy_r > 0 else "fail")
    wr_cls  = "pass" if m.win_rate > 55 else ("warn" if m.win_rate > 45 else "fail")
    return (f'<tr>'
            f'<td class="{cls}">{label}</td>'
            f'<td class="num">{m.total_trades}</td>'
            f'<td class="num {wr_cls}">{m.win_rate:.1f}%</td>'
            f'<td class="num {exp_cls}">{m.expectancy_r:+.3f}R</td>'
            f'<td class="num">{m.sharpe_ratio:.2f}</td>'
            f'</tr>')


def generate_html_report(
    run: dict,
    regime: RegimeBreakdown,
    output_path: Optional[str] = "backtest_report.html",
) -> str:
    market    = run.get("market", "—")
    period    = run.get("period", "—")
    d_from    = run.get("date_from", "—")
    d_to      = run.get("date_to", "—")
    capital   = run.get("capital_initial", 1000.0)
    total_t   = run.get("total_trades", 0)
    win_t     = run.get("winning_trades", 0)
    wr        = float(run.get("win_rate", 0))
    exp_r     = float(run.get("expectancy_r", 0))
    pf        = float(run.get("profit_factor") or 0)
    dd        = float(run.get("max_drawdown", 0))
    sharpe    = float(run.get("sharpe_ratio", 0))

    counts = regime.regime_counts

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Backtest — {market} {period}</title>
<style>{CSS}</style>
</head>
<body>

<h1>Backtest — {market} {period}</h1>
<p class="sub">{d_from} → {d_to} &nbsp;|&nbsp; Capital: ${capital:,.0f}</p>

<div class="section">
<h2>Resultado Combinado</h2>
<table>
<tr><th>Métrica</th><th class="num">Valor</th><th class="num">Referência Tier 3</th><th></th></tr>
{_threshold_row("win_rate",      "Win Rate",      wr,     ".1f") .replace(f"{wr:.1f}", f"{wr:.1f}%")}
{_threshold_row("expectancy_r",  "Expectancy",    exp_r,  "+.3f").replace(f"{exp_r:+.3f}", f"{exp_r:+.3f}R")}
{_threshold_row("profit_factor", "Profit Factor", pf,     ".2f")}
{_threshold_row("max_drawdown",  "Max Drawdown",  dd,     ".2f") .replace(f"{dd:.2f}", f"{dd:.2f}R")}
{_threshold_row("sharpe_ratio",  "Sharpe Ratio",  sharpe, ".3f")}
<tr><td>Total Trades</td>
    <td class="num">{total_t} ({win_t} wins)</td>
    <td class="num" style="color:#475569;font-size:0.8rem">min ≥ 10/mês para significância</td>
    <td></td></tr>
</table>
</div>

<div class="section">
<h2>Benchmarking por Regime (SMA200)</h2>
<p style="color:#475569;font-size:0.82rem;margin-bottom:0.75rem">
  bull: close &gt; SMA200×1.02 &nbsp;|&nbsp;
  bear: close &lt; SMA200×0.98 &nbsp;|&nbsp;
  sideways: dentro da banda &nbsp;|&nbsp;
  Edge real: bear.expectancy &gt; +0.30R
</p>
<table>
<tr><th>Regime</th><th class="num">Trades</th><th class="num">Win Rate</th>
    <th class="num">Expectancy</th><th class="num">Sharpe</th></tr>
{_regime_section("BULL",     "regime-bull",     regime.bull)}
{_regime_section("BEAR",     "regime-bear",     regime.bear)}
{_regime_section("SIDEWAYS", "regime-sideways", regime.sideways)}
</table>
</div>

<p style="color:#334155;font-size:0.75rem;margin-top:1rem">
  Gerado por backtest_runner.py — CoinEx AI Agent
</p>

</body>
</html>"""

    if output_path:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html)

    return html

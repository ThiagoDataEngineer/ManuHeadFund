"""
paper_trade_audit.py -- Auditor de logs paper trade DryRun.

Funcoes puras (testaveis):
  parse_trade_line(line) -> dict | None
  parse_paper_trade_log(path) -> List[dict]
  filter_signals_by_regime_direction(signals, regime, direction) -> List[dict]
  count_transition_up_mon_long(signals, since_date='2023-01-01') -> dict
  aggregate_by_regime_direction(signals) -> dict
  identify_abort_reasons(signals) -> List[dict]
  find_data_gaps(signals, expected_regimes) -> List[dict]

Formatos aceitos:
  v1.5 (lib_trade_logger.ps1, 2026-05-15 EUREKA A):
    [HH:MM:SS] [TRADE] MARKET: DECISION regime=X direction=Y
      scanner_score=S1 score_predicted=S2 tier=T consensus=C razao=...
  v1.0 (lib_trade_logger.ps1, pre-2026-05-15):
    [HH:MM:SS] [TRADE] MARKET: DECISION regime=X direction=Y score=Z
      tier=T consensus=C razao=...
  LEGACY (scan_master.ps1 pre-2026-05-14):
    [HH:MM:SS] [TRADE] Orchestrator MARKET: DECISION score=N sinal=X regime=R direction=D
Campos opcionais: score, scanner_score, score_predicted, sinal, regime,
direction, tier, consensus, razao. Valor "-" eh interpretado como None.

Compat: dict de saida sempre inclui chaves 'score', 'scanner_score',
'score_predicted'. Em formato v1.0/legacy, scanner_score=None e score_predicted
mapeia para score (que ja era LLM-gerado pre-fix).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Sequence


# ──────────────────────────────────────────────────────────────────────────────
# Parsers
# ──────────────────────────────────────────────────────────────────────────────

# Novo formato (lib_trade_logger.ps1):
#   [HH:MM:SS] [TRADE] MARKET: DECISION regime=X direction=Y score=Z tier=T consensus=C razao=...
# Legacy:
#   [HH:MM:SS] [TRADE] Orchestrator MARKET: DECISION score=N sinal=X ...
# A regex aceita "Orchestrator " opcional para back-compat com logs antigos.
_TRADE_RE = re.compile(
    r"\[(?P<ts>\d{2}:\d{2}:\d{2})\]\s*"
    r"\[TRADE\]\s+(?:Orchestrator\s+)?(?P<market>\S+):\s+(?P<decision>\S+)"
    r"(?P<tail>.*)"
)

# MASTER CYCLE  HH:MM dd/mm  WINDOW  momento=NN/100
_MASTER_RE = re.compile(
    r"MASTER\s+CYCLE\s+(?P<time>\d{2}:\d{2})\s+(?P<date>\d{2}/\d{2})\s+"
    r"(?P<window>\S+)\s+momento=(?P<momento>\d+)/100"
)

# Decisao V6 (linha antes do TRADE) -- pode ter razao=
_V6_RE = re.compile(
    r"\[V6\]\s+Decisao:\s+(?P<decision>\S+)"
    r"(?:.*?razao=(?P<razao>\S+))?"
)


def _parse_kv_tail(tail: str) -> Dict[str, str]:
    """Extrai pares chave=valor de tail (ex: 'score=82 sinal=COMPRA regime=UP_MON').

    Caso especial: 'razao=...' eh o ultimo campo do novo formato e pode conter
    espacos (texto livre escapado). Capturamos tudo apos 'razao=' ate fim da linha.
    """
    out: Dict[str, str] = {}

    # Trata 'razao=' como tail-livre se aparecer (ultimo campo no novo formato)
    razao_match = re.search(r"\brazao=(.*)$", tail)
    razao_str = None
    scan_tail = tail
    if razao_match:
        razao_str = razao_match.group(1).strip()
        scan_tail = tail[: razao_match.start()]

    for m in re.finditer(r"(\w+)=([^\s]*)", scan_tail):
        key = m.group(1).lower()
        val = m.group(2)
        out[key] = val

    if razao_str is not None:
        out["razao"] = razao_str
    return out


def parse_trade_line(line: str) -> Optional[Dict]:
    """Parse uma linha de TRADE. Retorna dict ou None se nao for TRADE."""
    if not line or not line.strip():
        return None
    m = _TRADE_RE.search(line)
    if not m:
        return None
    tail = m.group("tail") or ""
    kv = _parse_kv_tail(tail)

    def _maybe_int(v: str) -> Optional[int]:
        if v == "" or v is None:
            return None
        try:
            return int(v)
        except ValueError:
            try:
                return int(float(v))
            except ValueError:
                return None

    def _none_if_empty_or_dash(v):
        if v is None or v == "" or v == "-":
            return None
        return v

    # v1.5: scanner_score + score_predicted separados; v1.0/legacy: score
    scanner_raw = kv.get("scanner_score")
    predicted_raw = kv.get("score_predicted")
    score_raw = kv.get("score")  # legacy

    def _parse_score(raw):
        if raw in (None, "", "-"):
            return None
        return _maybe_int(raw)

    scanner_score = _parse_score(scanner_raw)
    score_predicted = _parse_score(predicted_raw)

    # Compat: campo legado 'score' eh:
    #  - v1.5: igual a score_predicted (preserva semantica antiga: o numero exibido era LLM)
    #  - v1.0/legacy: o proprio campo score=
    if score_predicted is not None or scanner_score is not None:
        # Formato v1.5 detectado
        score = score_predicted
    else:
        score = _parse_score(score_raw)

    sinal = _none_if_empty_or_dash(kv.get("sinal"))
    regime = _none_if_empty_or_dash(kv.get("regime"))
    direction = _none_if_empty_or_dash(kv.get("direction"))
    tier = _none_if_empty_or_dash(kv.get("tier"))
    consensus = _none_if_empty_or_dash(kv.get("consensus"))
    razao = _none_if_empty_or_dash(kv.get("razao"))

    return {
        "timestamp": m.group("ts"),
        "market": m.group("market"),
        "decision": m.group("decision"),
        "score": score,
        "scanner_score": scanner_score,
        "score_predicted": score_predicted,
        "sinal": sinal,
        "regime": regime,
        "direction": direction,
        "tier": tier,
        "consensus": consensus,
        "razao": razao,
        "timezone": None,
    }


def parse_paper_trade_log(path: str) -> List[Dict]:
    """Parseia arquivo de log inteiro. Associa cada TRADE com seu MASTER CYCLE
    e razao do V6 imediatamente anterior, quando disponivel.
    """
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception:
        return []
    if not lines:
        return []

    signals: List[Dict] = []
    current_cycle: Optional[Dict] = None
    pending_v6_razao: Optional[str] = None

    # Tenta deduzir data atual (UTC) -- usaremos para preencher 'date'
    fallback_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    for raw in lines:
        line = raw.rstrip("\n")

        m_master = _MASTER_RE.search(line)
        if m_master:
            dt_str = m_master.group("date")  # 'dd/mm'
            try:
                day, month = dt_str.split("/")
                current_cycle = {
                    "cycle_window": m_master.group("window"),
                    "cycle_momento": int(m_master.group("momento")),
                    "cycle_date": f"{datetime.now().year:04d}-{int(month):02d}-{int(day):02d}",
                }
            except Exception:
                current_cycle = {
                    "cycle_window": m_master.group("window"),
                    "cycle_momento": int(m_master.group("momento")),
                    "cycle_date": fallback_date,
                }
            pending_v6_razao = None
            continue

        m_v6 = _V6_RE.search(line)
        if m_v6:
            pending_v6_razao = m_v6.group("razao")
            continue

        trade = parse_trade_line(line)
        if trade:
            if current_cycle:
                trade.update(current_cycle)
                trade["date"] = current_cycle.get("cycle_date", fallback_date)
            else:
                trade["cycle_window"] = None
                trade["cycle_momento"] = None
                trade["date"] = fallback_date
            if not trade.get("razao") and pending_v6_razao:
                trade["razao"] = pending_v6_razao
            pending_v6_razao = None
            signals.append(trade)
    return signals


# ──────────────────────────────────────────────────────────────────────────────
# Filtros + agregacoes
# ──────────────────────────────────────────────────────────────────────────────

def filter_signals_by_regime_direction(
    signals: Sequence[Dict],
    regime: str,
    direction: str,
) -> List[Dict]:
    return [
        s for s in signals
        if s.get("regime") == regime and s.get("direction") == direction
    ]


def count_transition_up_mon_long(
    signals: Sequence[Dict],
    since_date: str = "2023-01-01",
    expected_target: int = 30,
) -> Dict:
    """Conta sinais UP_MON + LONG desde since_date. Reporta gap para expected_target."""
    try:
        cutoff = datetime.fromisoformat(since_date).date()
    except ValueError:
        cutoff = datetime(2023, 1, 1).date()

    matching: List[Dict] = []
    for s in signals:
        if s.get("regime") != "UP_MON" or s.get("direction") != "LONG":
            continue
        d_str = s.get("date") or ""
        try:
            d = datetime.fromisoformat(d_str).date()
        except ValueError:
            continue
        if d >= cutoff:
            matching.append(s)

    executed = sum(1 for s in matching if s.get("decision") == "EXECUTAR")
    total = len(matching)
    gap = max(0, expected_target - total)
    return {
        "count_total": total,
        "count_executed": executed,
        "since_date": since_date,
        "expected_target": expected_target,
        "gap_to_30": gap,
    }


def aggregate_by_regime_direction(signals: Sequence[Dict]) -> Dict[str, Dict]:
    """Bucket por (regime, direction). Sinais sem campos viram UNKNOWN|UNKNOWN."""
    buckets: Dict[str, Dict] = {}
    for s in signals:
        regime = s.get("regime") or "UNKNOWN"
        direction = s.get("direction") or "UNKNOWN"
        key = f"{regime}|{direction}"
        if key not in buckets:
            buckets[key] = {"total": 0, "executed": 0, "aborted": 0, "other": 0}
        buckets[key]["total"] += 1
        decision = s.get("decision") or ""
        if decision == "EXECUTAR":
            buckets[key]["executed"] += 1
        elif decision == "ABORTAR":
            buckets[key]["aborted"] += 1
        else:
            buckets[key]["other"] += 1
    return buckets


def identify_abort_reasons(signals: Sequence[Dict], top_n: int = 5) -> List[Dict]:
    """Top N razoes de ABORTAR. 'unspecified' quando sem campo razao."""
    counter: Counter = Counter()
    for s in signals:
        if s.get("decision") != "ABORTAR":
            continue
        reason = s.get("razao") or "unspecified"
        counter[reason] += 1
    return [{"reason": r, "count": c} for r, c in counter.most_common(top_n)]


def find_data_gaps(signals: Sequence[Dict], expected_regimes: Sequence[str]) -> List[Dict]:
    """Lista regimes esperados que NAO aparecem nos sinais."""
    observed = {s.get("regime") for s in signals if s.get("regime")}
    gaps: List[Dict] = []
    for r in expected_regimes:
        if r not in observed:
            gaps.append({"regime": r, "reason": "not_observed_in_log"})
    return gaps


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

DEFAULT_LOG_PATH = (
    "C:/Users/thiag/AppData/Local/Temp/claude/c--Users-thiag-Coinex-AI-USER-API/"
    "4bae7014-4ca9-426b-bfe6-068d90f3d64f/tasks/bbnclvt9g.output"
)

DEFAULT_EXPECTED_REGIMES = [
    "UP_MON", "UP_WK", "UP_DAY",
    "NEUTRAL",
    "DOWN_DAY", "DOWN_WK", "DOWN_MON",
    "RANGE",
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", default=DEFAULT_LOG_PATH)
    parser.add_argument("--output", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "paper_trade_audit_2026_05_14.json"
    ))
    args = parser.parse_args()

    print(f"[1/5] Parseando log: {args.log}", flush=True)
    signals = parse_paper_trade_log(args.log)
    print(f"  total_signals={len(signals)}", flush=True)

    executed = sum(1 for s in signals if s.get("decision") == "EXECUTAR")
    print(f"  total_executed={executed}", flush=True)

    print("[2/5] Agregando por regime|direction...", flush=True)
    agg = aggregate_by_regime_direction(signals)
    for k, v in sorted(agg.items()):
        print(f"  {k}: total={v['total']} executed={v['executed']} aborted={v['aborted']}", flush=True)

    print("[3/5] UP_MON LONG transition count...", flush=True)
    trans = count_transition_up_mon_long(signals, since_date="2023-01-01")
    print(f"  {trans}", flush=True)

    print("[4/5] Top abort reasons...", flush=True)
    reasons = identify_abort_reasons(signals, top_n=5)
    for r in reasons:
        print(f"  {r['reason']}: {r['count']}", flush=True)

    print("[5/5] Gaps de regime esperados...", flush=True)
    gaps = find_data_gaps(signals, DEFAULT_EXPECTED_REGIMES)
    for g in gaps:
        print(f"  missing: {g['regime']}", flush=True)

    honest_note = (
        "Log bbnclvt9g (DryRun 14/05/2026, 5h+ ininterrupto) NAO emite "
        "regime/direction nos TRADE entries -- todos os signals viram UNKNOWN|UNKNOWN. "
        "Decisoes V6 vieram com score/sinal vazios (ABORTAR generalizado). "
        "Para validar UP_MON LONG transitions, signal_generator/orchestrator precisam "
        "log estruturado com regime+direction antes do paper trade go-live."
    )

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "log_path": args.log,
        "total_signals": len(signals),
        "total_executed": executed,
        "breakdown_by_regime_direction": agg,
        "transition_up_mon_long_count": trans,
        "top_5_abort_reasons": reasons,
        "regime_data_gaps": gaps,
        "honest_note": honest_note,
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n[OK] saved: {args.output}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""
tier_a_flag_tracker.py -- Auto-demote rule pra repeated FLAG drawdown.

Hipotese: se mesmo market FLAGGED N dias consecutivos, setup quebrado.
Acao: proporr demote no Telegram pro user decidir (nao auto-demote).

State em journal/tier_a_flag_history.jsonl (append-only).
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STATE_PATH = ROOT / "journal" / "tier_a_flag_history.jsonl"


def record_flags(flagged: List[str], critical: List[str],
                 state_path: Optional[str] = None) -> None:
    """Append event de flags do dia ao jsonl."""
    path = state_path or str(DEFAULT_STATE_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    event = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "flagged": list(flagged or []),
        "critical": list(critical or []),
    }
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


def _load_history(state_path: str) -> List[dict]:
    if not os.path.exists(state_path):
        return []
    out = []
    with open(state_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    out.sort(key=lambda e: e.get("ts", ""))
    return out


def get_flag_streak(market: str, state_path: Optional[str] = None) -> int:
    """Retorna numero de eventos consecutivos (do mais recente pra tras) onde market esta FLAG ou CRITICAL."""
    path = state_path or str(DEFAULT_STATE_PATH)
    history = _load_history(path)
    if not history:
        return 0
    streak = 0
    for event in reversed(history):
        is_flagged = market in event.get("flagged", []) or market in event.get("critical", [])
        if is_flagged:
            streak += 1
        else:
            break
    return streak


def get_demote_candidates(state_path: Optional[str] = None,
                          threshold: int = 3) -> List[str]:
    """Retorna lista de markets com streak >= threshold."""
    path = state_path or str(DEFAULT_STATE_PATH)
    history = _load_history(path)
    if not history:
        return []
    # Coleta todos os markets que ja apareceram FLAG/CRITICAL
    all_markets = set()
    for event in history:
        all_markets.update(event.get("flagged", []))
        all_markets.update(event.get("critical", []))
    candidates = []
    for m in sorted(all_markets):
        if get_flag_streak(m, state_path=path) >= threshold:
            candidates.append(m)
    return candidates


def format_demote_proposal(candidates: List[str], threshold: int = 3) -> Optional[str]:
    """Formata mensagem Telegram com candidatos a demote."""
    if not candidates:
        return None
    lines = [
        f"<b>Demote proposto Tier A LIVE</b>",
        "",
        f"Markets FLAGGED >= {threshold} dias consecutivos:",
    ]
    for m in candidates:
        lines.append(f"  - {m}")
    lines.extend([
        "",
        "Resposta sugerida:",
        "  - <code>/demote MARKET</code> = move pra OBSERVATION",
        "  - <code>/keep MARKET</code> = manter Tier A (reset streak)",
        "  - Ignorar = nada acontece, alerta segue diariamente",
    ])
    return "\n".join(lines)

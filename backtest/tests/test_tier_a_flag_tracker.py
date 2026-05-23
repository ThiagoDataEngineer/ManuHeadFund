"""
test_tier_a_flag_tracker.py -- TDD para auto-demote rule de FLAG drawdown.

Hipotese: se mesmo market FLAGGED N dias consecutivos = setup quebrado,
          propor demote pro user decidir (Telegram).
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from tier_a_flag_tracker import (  # noqa: E402
    record_flags,
    get_flag_streak,
    get_demote_candidates,
    format_demote_proposal,
)


@pytest.fixture
def tmp_state():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as f:
        path = f.name
    yield path
    if os.path.exists(path):
        os.unlink(path)


class TestRecordFlags:
    def test_appends_event_to_jsonl(self, tmp_state):
        record_flags(["PENDLEUSDT", "INJUSDT"], [], state_path=tmp_state)
        with open(tmp_state) as f:
            lines = [json.loads(l) for l in f if l.strip()]
        assert len(lines) == 1
        assert "PENDLEUSDT" in lines[0]["flagged"]
        assert "INJUSDT" in lines[0]["flagged"]
        assert lines[0]["critical"] == []
        assert "ts" in lines[0]

    def test_multiple_calls_append(self, tmp_state):
        record_flags(["A"], [], state_path=tmp_state)
        record_flags(["A", "B"], [], state_path=tmp_state)
        with open(tmp_state) as f:
            lines = [json.loads(l) for l in f if l.strip()]
        assert len(lines) == 2


class TestGetFlagStreak:
    def test_zero_if_no_history(self, tmp_state):
        assert get_flag_streak("XYZ", state_path=tmp_state) == 0

    def test_streak_3_consecutive(self, tmp_state):
        # 3 dias seguidos FLAG
        for d in range(3):
            ts = datetime.now(timezone.utc) - timedelta(days=2-d)
            event = {"ts": ts.isoformat(), "flagged": ["XYZ"], "critical": []}
            with open(tmp_state, "a") as f:
                f.write(json.dumps(event) + "\n")
        assert get_flag_streak("XYZ", state_path=tmp_state) == 3

    def test_streak_breaks_when_not_flagged(self, tmp_state):
        # Dia 1: FLAG, Dia 2: OK (nao aparece), Dia 3: FLAG
        events = [
            {"ts": (datetime.now(timezone.utc) - timedelta(days=2)).isoformat(),
             "flagged": ["XYZ"], "critical": []},
            {"ts": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
             "flagged": [], "critical": []},  # streak quebrado
            {"ts": datetime.now(timezone.utc).isoformat(),
             "flagged": ["XYZ"], "critical": []},
        ]
        with open(tmp_state, "w") as f:
            for e in events:
                f.write(json.dumps(e) + "\n")
        # Streak atual = 1 (so o ultimo)
        assert get_flag_streak("XYZ", state_path=tmp_state) == 1


class TestGetDemoteCandidates:
    def test_empty_when_no_streaks(self, tmp_state):
        record_flags(["A"], [], state_path=tmp_state)
        assert get_demote_candidates(state_path=tmp_state, threshold=3) == []

    def test_returns_market_with_3_streak(self, tmp_state):
        for d in range(3):
            ts = datetime.now(timezone.utc) - timedelta(days=2-d)
            event = {"ts": ts.isoformat(), "flagged": ["PENDLE"], "critical": []}
            with open(tmp_state, "a") as f:
                f.write(json.dumps(event) + "\n")
        cands = get_demote_candidates(state_path=tmp_state, threshold=3)
        assert "PENDLE" in cands

    def test_critical_also_counts(self, tmp_state):
        # Mix de FLAG + CRITICAL = ambos contam pra streak
        events = [
            {"ts": (datetime.now(timezone.utc) - timedelta(days=2)).isoformat(),
             "flagged": ["X"], "critical": []},
            {"ts": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
             "flagged": [], "critical": ["X"]},
            {"ts": datetime.now(timezone.utc).isoformat(),
             "flagged": ["X"], "critical": []},
        ]
        with open(tmp_state, "w") as f:
            for e in events:
                f.write(json.dumps(e) + "\n")
        cands = get_demote_candidates(state_path=tmp_state, threshold=3)
        assert "X" in cands


class TestFormatDemoteProposal:
    def test_returns_string_with_markets(self):
        msg = format_demote_proposal(["PENDLEUSDT", "INJUSDT"], threshold=3)
        assert "PENDLEUSDT" in msg
        assert "INJUSDT" in msg
        assert "3" in msg  # threshold

    def test_empty_list_returns_none(self):
        msg = format_demote_proposal([], threshold=3)
        assert msg is None or msg == ""

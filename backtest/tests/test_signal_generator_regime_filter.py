"""
TDD strict — regime-direction filter em signal_generator.py
Paridade Python com agents/lib_operational_whitelist.ps1 (camada PowerShell).

Mapeamento canônico (8 regimes):
  BULL_STRONG, BULL_WEAK, SIDEWAYS, TRANSITION_UP,
  TRANSITION_DOWN, BEAR_WEAK, BEAR_STRONG, CAPITULATION

Modos:
  off          → não filtra (default, backwards compat)
  permissive   → bloqueia contra-regime (LONG em BEAR_*, SHORT em BULL_*)
  strict_v2    → whitelist v2: BULL_STRONG+LONG, TRANSITION_UP+LONG+Mon BRT only

Ref: memory/project_regime_matrix_14y_findings.md
     agents/lib_operational_whitelist.ps1 (28 tests Pester)
"""
import pytest
from signal_generator import apply_regime_filter


# ── 1. Backwards compat (default off) ────────────────────────────────────────

def test_filter_off_by_default_passes_long_in_bear():
    """Default mode='off' não filtra — sinal sai como antes (backwards compat)."""
    signal, reason = apply_regime_filter("COMPRA", "BEAR_STRONG")
    assert signal == "COMPRA"
    assert reason == "filter_off"


def test_filter_off_explicit_passes_short_in_bull():
    signal, reason = apply_regime_filter("VENDA", "BULL_STRONG", mode="off")
    assert signal == "VENDA"
    assert reason == "filter_off"


# ── 2. Permissive mode: bloqueia contra-regime ───────────────────────────────

def test_permissive_blocks_long_in_bear_weak():
    signal, reason = apply_regime_filter("COMPRA", "BEAR_WEAK", mode="permissive")
    assert signal == "NEUTRO"
    assert "BEAR_WEAK" in reason
    assert "COMPRA" in reason
    assert reason.startswith("regime_filter:permissive:")


def test_permissive_blocks_long_in_bear_strong():
    signal, reason = apply_regime_filter("COMPRA", "BEAR_STRONG", mode="permissive")
    assert signal == "NEUTRO"
    assert "BEAR_STRONG" in reason


def test_permissive_blocks_short_in_bull_strong():
    signal, reason = apply_regime_filter("VENDA", "BULL_STRONG", mode="permissive")
    assert signal == "NEUTRO"
    assert "BULL_STRONG" in reason
    assert "VENDA" in reason


def test_permissive_blocks_short_in_bull_weak():
    signal, reason = apply_regime_filter("VENDA", "BULL_WEAK", mode="permissive")
    assert signal == "NEUTRO"
    assert "BULL_WEAK" in reason


# ── 3. Permissive mode: permite alinhados ────────────────────────────────────

def test_permissive_allows_long_in_bull_strong():
    signal, reason = apply_regime_filter("COMPRA", "BULL_STRONG", mode="permissive")
    assert signal == "COMPRA"
    assert reason == "filter_passed"


def test_permissive_allows_long_in_bull_weak():
    signal, reason = apply_regime_filter("COMPRA", "BULL_WEAK", mode="permissive")
    assert signal == "COMPRA"


def test_permissive_allows_long_in_transition_up():
    signal, reason = apply_regime_filter("COMPRA", "TRANSITION_UP", mode="permissive")
    assert signal == "COMPRA"


def test_permissive_allows_short_in_bear_strong():
    signal, reason = apply_regime_filter("VENDA", "BEAR_STRONG", mode="permissive")
    assert signal == "VENDA"


def test_permissive_allows_short_in_bear_weak():
    signal, reason = apply_regime_filter("VENDA", "BEAR_WEAK", mode="permissive")
    assert signal == "VENDA"


# ── 4. Strict v2: BULL_STRONG+LONG e TRANSITION_UP+Mon+LONG only ─────────────

def test_strict_v2_allows_bull_strong_long():
    signal, reason = apply_regime_filter("COMPRA", "BULL_STRONG", mode="strict_v2")
    assert signal == "COMPRA"
    assert reason == "v2_bull_strong_long"


def test_strict_v2_allows_transition_up_long_only_on_monday():
    signal, reason = apply_regime_filter(
        "COMPRA", "TRANSITION_UP", mode="strict_v2", day_of_week_brt=1
    )
    assert signal == "COMPRA"
    assert reason == "v2_transition_up_mon"


def test_strict_v2_blocks_transition_up_long_not_monday():
    """DoW != 1 (BRT) bloqueia TRANSITION_UP em modo strict_v2."""
    for dow in [0, 2, 3, 4, 5, 6]:
        signal, reason = apply_regime_filter(
            "COMPRA", "TRANSITION_UP", mode="strict_v2", day_of_week_brt=dow
        )
        assert signal == "NEUTRO", f"DoW={dow} deveria bloquear, mas passou"
        assert "strict_v2" in reason


# ── 5. Strict v2: bloqueia BULL_WEAK+LONG (structural break holdout) ─────────

def test_strict_v2_blocks_bull_weak_long():
    """BULL_WEAK+LONG é blacklist no v2 (STRUCTURAL_BREAK holdout, -0.37R 2025)."""
    signal, reason = apply_regime_filter("COMPRA", "BULL_WEAK", mode="strict_v2")
    assert signal == "NEUTRO"
    assert "BULL_WEAK" in reason
    assert "strict_v2" in reason


# ── 6. Strict v2: SHORT desabilitado completo ────────────────────────────────

def test_strict_v2_blocks_short_in_all_regimes():
    """SHORT não tem edge cross-period em nenhum regime (0/8)."""
    for regime in [
        "BULL_STRONG", "BULL_WEAK", "SIDEWAYS", "TRANSITION_UP",
        "TRANSITION_DOWN", "BEAR_WEAK", "BEAR_STRONG", "CAPITULATION",
    ]:
        signal, reason = apply_regime_filter("VENDA", regime, mode="strict_v2")
        assert signal == "NEUTRO", f"SHORT em {regime} deveria ser bloqueado em v2"
        assert "SHORT_disabled" in reason


# ── 7. SIDEWAYS bloqueia em ambos os modos ───────────────────────────────────

def test_sideways_blocks_long_permissive():
    """SIDEWAYS não está na whitelist de LONG em modo permissive."""
    signal, reason = apply_regime_filter("COMPRA", "SIDEWAYS", mode="permissive")
    assert signal == "NEUTRO"
    assert "SIDEWAYS" in reason


def test_sideways_blocks_long_strict_v2():
    signal, reason = apply_regime_filter("COMPRA", "SIDEWAYS", mode="strict_v2")
    assert signal == "NEUTRO"


# ── 8. TRANSITION_DOWN bloqueia LONG em ambos ────────────────────────────────

def test_transition_down_blocks_long_permissive():
    signal, reason = apply_regime_filter("COMPRA", "TRANSITION_DOWN", mode="permissive")
    assert signal == "NEUTRO"


def test_transition_down_blocks_long_strict_v2():
    signal, reason = apply_regime_filter("COMPRA", "TRANSITION_DOWN", mode="strict_v2")
    assert signal == "NEUTRO"


# ── 9. NEUTRO de entrada passa sem alteração ─────────────────────────────────

def test_neutro_passes_through_any_mode():
    """Se sinal já é NEUTRO, filtro não muda nada."""
    for mode in ["off", "permissive", "strict_v2"]:
        signal, _ = apply_regime_filter("NEUTRO", "BEAR_STRONG", mode=mode)
        assert signal == "NEUTRO"


# ── 10. Filter retorna NEUTRO (não exception) + razão explícita ──────────────

def test_filter_never_raises_returns_neutro_with_reason():
    """Bloqueio sempre retorna ('NEUTRO', razão_string) — nunca exception."""
    signal, reason = apply_regime_filter("COMPRA", "BEAR_STRONG", mode="permissive")
    assert isinstance(signal, str)
    assert isinstance(reason, str)
    assert len(reason) > 0
    assert signal == "NEUTRO"


# ── 11. Edge: regime=None → sinal passa (não força filter) ───────────────────

def test_regime_none_passes_signal_unchanged():
    signal, reason = apply_regime_filter("COMPRA", None, mode="permissive")
    assert signal == "COMPRA"
    assert reason == "filter_off"


def test_regime_none_passes_short_unchanged_strict_v2():
    signal, reason = apply_regime_filter("VENDA", None, mode="strict_v2")
    assert signal == "VENDA"


# ── 12. Edge: regime inválido (fora dos 8 canônicos) → passa com warning ─────

def test_invalid_regime_passes_with_warning(recwarn):
    signal, reason = apply_regime_filter("COMPRA", "MOON_PHASE", mode="permissive")
    assert signal == "COMPRA"
    assert "invalid_regime" in reason or "warning" in reason.lower()


def test_invalid_regime_strict_v2_also_passes():
    signal, _ = apply_regime_filter("COMPRA", "FAKE_REGIME", mode="strict_v2")
    assert signal == "COMPRA"


# ── Bonus: generate_signal aceita regime_filter_mode (integração) ────────────

def test_generate_signal_accepts_regime_filter_kwargs():
    """API pública mantida — kwargs opcionais não quebram caller existente."""
    from signal_generator import generate_signal
    # 50 candles flat
    candles = [
        {"ts": "2025-01-01", "open": 100.0, "high": 101.0, "low": 99.0,
         "close": 100.0 + i * 0.1, "volume": 100.0}
        for i in range(50)
    ]
    # Sem kwargs → comportamento antigo
    r1 = generate_signal(candles)
    # Com kwargs (default off → mesmo resultado)
    r2 = generate_signal(candles, regime="BEAR_STRONG", regime_filter_mode="off")
    assert r1.signal == r2.signal

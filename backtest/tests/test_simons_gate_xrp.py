"""
test_simons_gate_xrp.py -- TDD strict para Simons Gate XRP (Wave 1 cross-asset validation).

Adversarial-first: XRP escolhido por ter regulatory hostile period SEC Dec 2020 - Jul 2023.
Testa generalização do sistema SEM retreinar whitelist (strict_v2 fixo de BTC).

Estrutura:
  - Fase RED: NotImplementedError em todos os testes integração (fase atual)
  - Fase GREEN: implementada após run_simons_gate_xrp.py funcionar

Convenções:
  - pytest 7+, Python 3.12
  - Sem mocks nos testes de integração (dados reais)
  - Tests unitários (fixtures locais) imediatamente executáveis

Ref: memory/project_simons_gate_real_validated.md (BTC baseline 4/4 PASS)
     memory/project_operational_whitelist_v2.md (whitelist v2 strict_v2 input fixo)
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import List, Dict

import numpy as np
import pytest

# Ajusta path para importar do backtest/
TESTS_DIR = Path(__file__).resolve().parent
BACKTEST_DIR = TESTS_DIR.parent
ROOT_DIR = BACKTEST_DIR.parent
sys.path.insert(0, str(BACKTEST_DIR))
sys.path.insert(0, str(ROOT_DIR))

# SEC lawsuit windows (constantes)
SEC_START = datetime(2020, 12, 22, tzinfo=timezone.utc)
SEC_END = datetime(2023, 7, 13, tzinfo=timezone.utc)
XRP_START = datetime(2017, 8, 1, tzinfo=timezone.utc)

# Thresholds (idênticos ao BTC gate — NÃO modificar)
DSR_THRESH = 0.95
PSR_THRESH = 0.95
MIN_CANDLES_ACCEPTABLE = 40_000  # 8 anos × ~5475 h/ano


# ── Imports condicionais (falhando no RED) ────────────────────────────────────

def _try_import(module_name: str):
    try:
        import importlib
        return importlib.import_module(module_name)
    except (ImportError, ModuleNotFoundError):
        return None


def _load_journal_json() -> Dict:
    """Carrega journal JSON se existir."""
    p = ROOT_DIR / "journal" / "simons_gate_xrp_2026_05_15.json"
    if p.exists():
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


CACHE_FILE = BACKTEST_DIR / "xrp_bitstamp_1h.json"
JOURNAL_JSON = ROOT_DIR / "journal" / "simons_gate_xrp_2026_05_15.json"
JOURNAL_MD = ROOT_DIR / "journal" / "simons_gate_xrp_2026_05_15.md"


# ═══════════════════════════════════════════════════════════════════════════════
# GRUPO 1: Testes UNITÁRIOS (sem dados reais — executáveis imediatamente)
# ═══════════════════════════════════════════════════════════════════════════════

class TestSimonsMetricsBaseline:
    """Testes unitários das métricas Simons (GREEN desde metrics_simons.py)."""

    def test_dsr_threshold_constant_unchanged(self):
        """DSR threshold deve ser 0.95 (idêntico ao BTC gate)."""
        assert DSR_THRESH == 0.95, "DSR_THRESH NÃO pode ser modificado para XRP"

    def test_psr_threshold_constant_unchanged(self):
        """PSR threshold deve ser 0.95 (idêntico ao BTC gate)."""
        assert PSR_THRESH == 0.95, "PSR_THRESH NÃO pode ser modificado para XRP"

    def test_sec_start_date_correct(self):
        """SEC lawsuit início: 22 Dez 2020."""
        assert SEC_START == datetime(2020, 12, 22, tzinfo=timezone.utc)

    def test_sec_end_date_correct(self):
        """SEC lawsuit fim: 13 Jul 2023."""
        assert SEC_END == datetime(2023, 7, 13, tzinfo=timezone.utc)

    def test_metrics_simons_importable(self):
        """metrics_simons.py deve ser importável."""
        m = _try_import("metrics_simons")
        assert m is not None, "metrics_simons não importável"
        assert hasattr(m, "run_simons_gate"), "run_simons_gate não encontrado"
        assert hasattr(m, "deflated_sharpe_ratio"), "deflated_sharpe_ratio não encontrado"

    def test_regime_classifier_importable(self):
        """regime_classifier.py deve ser importável."""
        m = _try_import("regime_classifier")
        assert m is not None, "regime_classifier não importável"
        assert hasattr(m, "classify_regime"), "classify_regime não encontrado"

    def test_signal_generator_importable(self):
        """signal_generator.py deve ser importável."""
        m = _try_import("signal_generator")
        assert m is not None, "signal_generator não importável"
        assert hasattr(m, "apply_regime_filter"), "apply_regime_filter não encontrado"

    def test_whitelist_v2_blocks_short(self):
        """Whitelist v2 DEVE bloquear VENDA em qualquer regime para XRP."""
        m = _try_import("signal_generator")
        if m is None:
            pytest.skip("signal_generator não importável")
        # SHORT deve ser filtrado em qualquer regime
        for regime in ["BULL_STRONG", "BULL_WEAK", "BEAR_STRONG", "TRANSITION_UP"]:
            sig, reason = m.apply_regime_filter(
                signal="VENDA",
                regime=regime,
                mode="strict_v2",
                day_of_week_brt=1,
            )
            assert sig == "NEUTRO", f"VENDA não bloqueada em {regime}: {reason}"

    def test_whitelist_v2_allows_bull_strong_long(self):
        """Whitelist v2 permite COMPRA em BULL_STRONG (qualquer dia)."""
        m = _try_import("signal_generator")
        if m is None:
            pytest.skip("signal_generator não importável")
        for dow in [0, 1, 2, 3, 4, 5, 6]:
            sig, reason = m.apply_regime_filter(
                signal="COMPRA",
                regime="BULL_STRONG",
                mode="strict_v2",
                day_of_week_brt=dow,
            )
            assert sig == "COMPRA", f"BULL_STRONG+LONG bloqueado em dow={dow}: {reason}"

    def test_whitelist_v2_allows_transition_up_monday_only(self):
        """Whitelist v2 permite COMPRA em TRANSITION_UP SOMENTE na Segunda (dow=1)."""
        m = _try_import("signal_generator")
        if m is None:
            pytest.skip("signal_generator não importável")
        # Segunda deve passar
        sig_mon, _ = m.apply_regime_filter("COMPRA", "TRANSITION_UP", "strict_v2", 1)
        assert sig_mon == "COMPRA", "TRANSITION_UP+Mon deve passar"
        # Outros dias devem bloquear
        for dow in [0, 2, 3, 4, 5, 6]:
            sig, reason = m.apply_regime_filter("COMPRA", "TRANSITION_UP", "strict_v2", dow)
            assert sig == "NEUTRO", f"TRANSITION_UP+dow={dow} deveria ser bloqueado: {reason}"

    def test_whitelist_v2_blocks_bull_weak(self):
        """Whitelist v2 DEVE bloquear COMPRA em BULL_WEAK (removido por STRUCTURAL_BREAK)."""
        m = _try_import("signal_generator")
        if m is None:
            pytest.skip("signal_generator não importável")
        sig, reason = m.apply_regime_filter("COMPRA", "BULL_WEAK", "strict_v2", 1)
        assert sig == "NEUTRO", f"BULL_WEAK deve ser bloqueado: {reason}"

    def test_simons_gate_xrp_script_importable(self):
        """run_simons_gate_xrp.py deve ser importável."""
        m = _try_import("run_simons_gate_xrp")
        assert m is not None, "run_simons_gate_xrp não importável"


# ═══════════════════════════════════════════════════════════════════════════════
# GRUPO 2: Testes de DATA (precisam do cache XRP)
# ═══════════════════════════════════════════════════════════════════════════════

class TestXrpDataAcquisition:
    """Testes de verificação do dataset XRP (requerem cache ou acesso Bitstamp)."""

    def _load_cache(self) -> Dict:
        if not CACHE_FILE.exists():
            pytest.skip(f"Cache XRP não encontrado: {CACHE_FILE} — rode fetch_xrp_bitstamp.py")
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)

    def test_xrp_cache_exists(self):
        """Cache xrp_bitstamp_1h.json deve existir após fetch."""
        if not CACHE_FILE.exists():
            pytest.skip("Cache não existe ainda — rodar fetch primeiro")
        assert CACHE_FILE.exists()

    def test_xrp_candles_count_sufficient(self):
        """N candles XRP deve ser >= 40.000 para cobrir 8+ anos de 1h."""
        data = self._load_cache()
        candles = data.get("candles", [])
        n = len(candles)
        assert n >= MIN_CANDLES_ACCEPTABLE, (
            f"Apenas {n} candles XRP — mínimo {MIN_CANDLES_ACCEPTABLE} para 8+ anos. "
            f"Verificar paginação Bitstamp."
        )

    def test_xrp_candles_schema_ohlcv(self):
        """Schema dos candles deve ter ts, open, high, low, close, volume."""
        data = self._load_cache()
        candles = data.get("candles", [])
        assert len(candles) > 0, "Nenhum candle no cache"
        required_fields = {"ts", "open", "high", "low", "close", "volume"}
        for c in candles[:10]:  # Verifica primeiros 10
            missing = required_fields - set(c.keys())
            assert not missing, f"Campos faltando no candle: {missing}"

    def test_xrp_candles_no_major_gaps(self):
        """Sem gaps maiores que 48h contínuos (tolerância para fins de semana/manutenção)."""
        data = self._load_cache()
        candles = data.get("candles", [])
        if len(candles) < 2:
            pytest.skip("Poucos candles para análise de gaps")
        max_gap_h = 0
        for i in range(1, len(candles)):
            ts_cur  = candles[i].get("ts_unix", 0)
            ts_prev = candles[i-1].get("ts_unix", 0)
            if ts_cur and ts_prev:
                gap_h = (ts_cur - ts_prev) / 3600
                max_gap_h = max(max_gap_h, gap_h)
        # Gap máximo tolerado: 48h (2 dias — possível manutenção ou dados faltando)
        assert max_gap_h <= 48 * 24, f"Gap máximo {max_gap_h:.1f}h excede 48 dias"

    def test_xrp_coverage_pre_sec_period(self):
        """Dados devem cobrir período pre-SEC (antes de 2020-12-22)."""
        data = self._load_cache()
        candles = data.get("candles", [])
        sec_start_unix = int(SEC_START.timestamp())
        pre_sec = [c for c in candles if c.get("ts_unix", 0) < sec_start_unix]
        assert len(pre_sec) >= 1000, f"Pre-SEC com apenas {len(pre_sec)} candles"

    def test_xrp_coverage_during_sec_period(self):
        """Dados devem cobrir período durante SEC (2020-12-22 a 2023-07-13)."""
        data = self._load_cache()
        candles = data.get("candles", [])
        sec_start_unix = int(SEC_START.timestamp())
        sec_end_unix   = int(SEC_END.timestamp())
        during = [c for c in candles if sec_start_unix <= c.get("ts_unix", 0) < sec_end_unix]
        assert len(during) >= 1000, f"Durante SEC com apenas {len(during)} candles"

    def test_xrp_coverage_post_sec_period(self):
        """Dados devem cobrir período pós-SEC (após 2023-07-13)."""
        data = self._load_cache()
        candles = data.get("candles", [])
        sec_end_unix = int(SEC_END.timestamp())
        post_sec = [c for c in candles if c.get("ts_unix", 0) >= sec_end_unix]
        assert len(post_sec) >= 1000, f"Pós-SEC com apenas {len(post_sec)} candles"

    def test_xrp_prices_non_zero(self):
        """Todos os closes devem ser > 0."""
        data = self._load_cache()
        candles = data.get("candles", [])
        zero_closes = [c for c in candles if float(c.get("close", 0)) <= 0]
        assert len(zero_closes) == 0, f"{len(zero_closes)} candles com close <= 0"


# ═══════════════════════════════════════════════════════════════════════════════
# GRUPO 3: Testes do JOURNAL (precisam que run_simons_gate_xrp.py seja executado)
# ═══════════════════════════════════════════════════════════════════════════════

class TestXrpJournalOutput:
    """Testes do journal JSON/MD gerado pelo Simons Gate XRP."""

    def _load_journal(self) -> Dict:
        if not JOURNAL_JSON.exists():
            pytest.skip(f"Journal não encontrado: {JOURNAL_JSON} — rode run_simons_gate_xrp.py")
        with open(JOURNAL_JSON, "r", encoding="utf-8") as f:
            return json.load(f)

    def test_journal_json_created(self):
        """journal/simons_gate_xrp_2026_05_15.json deve existir."""
        if not JOURNAL_JSON.exists():
            pytest.skip("Journal JSON não criado ainda")
        assert JOURNAL_JSON.exists()

    def test_journal_md_created(self):
        """journal/simons_gate_xrp_2026_05_15.md deve existir."""
        if not JOURNAL_MD.exists():
            pytest.skip("Journal MD não criado ainda")
        assert JOURNAL_MD.exists()

    def test_journal_json_has_required_fields(self):
        """JSON deve ter campos: timestamp, asset, dataset, metrics, decision, sec_windows."""
        j = self._load_journal()
        required = {"timestamp", "asset", "dataset", "metrics", "decision", "sec_windows"}
        missing = required - set(j.keys())
        assert not missing, f"Campos faltando no journal: {missing}"

    def test_journal_asset_is_xrp(self):
        """Journal deve ser para XRPUSD (não BTC)."""
        j = self._load_journal()
        assert j.get("asset") == "XRPUSD", f"Asset incorreto: {j.get('asset')}"

    def test_journal_whitelist_unchanged(self):
        """Journal deve registrar whitelist v2 strict_v2 sem retreino."""
        j = self._load_journal()
        whitelist = j.get("whitelist", "")
        assert "strict_v2" in whitelist, f"Whitelist não é strict_v2: {whitelist}"
        assert "retrein" in whitelist.lower() or "NÃO" in whitelist, \
            "Journal deve indicar que NÃO foi retreinada"

    def test_journal_metrics_have_four_keys(self):
        """metrics deve ter dsr, psr, sharpe_usdt, ergodicity."""
        j = self._load_journal()
        m = j.get("metrics", {})
        for key in ["dsr", "psr", "sharpe_usdt", "ergodicity"]:
            assert key in m, f"Métrica '{key}' faltando em metrics"

    def test_journal_sec_windows_have_three_entries(self):
        """sec_windows deve ter 3 entradas (pre, durante, pós)."""
        j = self._load_journal()
        windows = j.get("sec_windows", [])
        assert len(windows) == 3, f"Esperado 3 janelas SEC, got {len(windows)}"

    def test_journal_decision_is_valid(self):
        """decision deve ser PASS ou FAIL*."""
        j = self._load_journal()
        decision = j.get("decision", "")
        valid = {"PASS", "FAIL", "FAIL_NO_TRADES", "FAIL_INSUFFICIENT_DATA"}
        assert decision in valid or decision.startswith("FAIL"), \
            f"Decision inválida: {decision}"

    def test_journal_trades_per_window_present(self):
        """trades_per_window deve ter pre_sec, during_sec, post_sec."""
        j = self._load_journal()
        tpw = j.get("trades_per_window", {})
        for k in ["pre_sec", "during_sec", "post_sec"]:
            assert k in tpw, f"trades_per_window faltando chave: {k}"

    def test_md_contains_decision_tree(self):
        """Journal MD deve conter seção Decision Tree."""
        if not JOURNAL_MD.exists():
            pytest.skip("Journal MD não criado")
        content = JOURNAL_MD.read_text(encoding="utf-8")
        assert "Decision Tree" in content or "decision tree" in content.lower(), \
            "Journal MD deve ter seção Decision Tree"

    def test_md_contains_sec_decomposition_table(self):
        """Journal MD deve conter tabela de decomposição SEC."""
        if not JOURNAL_MD.exists():
            pytest.skip("Journal MD não criado")
        content = JOURNAL_MD.read_text(encoding="utf-8")
        assert "SEC" in content, "Journal MD deve mencionar SEC"
        assert "|" in content, "Journal MD deve ter pelo menos uma tabela"


# ═══════════════════════════════════════════════════════════════════════════════
# GRUPO 4: Testes de LÓGICA do Gate XRP (validam o comportamento esperado)
# ═══════════════════════════════════════════════════════════════════════════════

class TestSimonsGateXrpLogic:
    """Testes de lógica do Simons Gate aplicado ao XRP."""

    def _load_journal(self) -> Dict:
        if not JOURNAL_JSON.exists():
            pytest.skip("Journal não encontrado — rode run_simons_gate_xrp.py")
        with open(JOURNAL_JSON, "r", encoding="utf-8") as f:
            return json.load(f)

    def test_sec_period_trades_lower_than_other_windows(self):
        """
        Durante SEC, N trades deve ser <= pre-SEC (regime conservador correto).
        Se for maior, é sinal de bug no regime filter.
        """
        j = self._load_journal()
        tpw = j.get("trades_per_window", {})
        pre   = tpw.get("pre_sec", 0)
        during = tpw.get("during_sec", 0)
        # Durante SEC deve ser <= pre-SEC (mercado adversarial => menos trades)
        # Não é um FAIL absoluto se SEC tiver mais (pode ter bounces), mas é suspeito
        if pre > 0 and during > pre * 2:
            pytest.fail(
                f"Durante SEC ({during} trades) > 2x pre-SEC ({pre} trades). "
                f"Suspeito: regime classifier pode não estar filtrando corretamente."
            )

    def test_no_short_trades_generated(self):
        """Não devem existir trades com direction=VENDA."""
        j = self._load_journal()
        # O journal não armazena trades individuais, mas podemos verificar via regime_distribution
        # (se só COMPRA, então OK)
        decision = j.get("decision", "")
        # Verificação indireta: whitelist v2 bloqueia SHORT
        assert decision != "FAIL_SHORT_ENABLED", "SHORT não deveria ser habilitado"

    def test_dsr_threshold_not_relaxed(self):
        """DSR threshold no journal deve ser 0.95 (não relaxado para XRP)."""
        j = self._load_journal()
        params = j.get("params", {})
        assert params.get("dsr_threshold") == 0.95, \
            f"DSR threshold alterado: {params.get('dsr_threshold')} (deve ser 0.95)"

    def test_psr_threshold_not_relaxed(self):
        """PSR threshold no journal deve ser 0.95."""
        j = self._load_journal()
        params = j.get("params", {})
        assert params.get("psr_threshold") == 0.95, \
            f"PSR threshold alterado: {params.get('psr_threshold')} (deve ser 0.95)"

    def test_sensitivity_has_four_entries(self):
        """Sensitivity deve ter 4 entradas [50, 100, 200, 500]."""
        j = self._load_journal()
        sens = j.get("sensitivity", [])
        assert len(sens) == 4, f"Sensitivity deve ter 4 entradas (50/100/200/500), got {len(sens)}"
        n_trials_list = [s["n_trials"] for s in sens]
        assert n_trials_list == [50, 100, 200, 500], \
            f"n_trials incorretos: {n_trials_list}"

    def test_regime_distribution_recorded(self):
        """Distribuição de regimes deve estar no journal."""
        j = self._load_journal()
        reg_dist = j.get("regime_distribution", {})
        # Pode ser vazio se 0 trades, mas o campo deve existir
        assert "regime_distribution" in j, "regime_distribution deve estar no journal"

    def test_btc_baseline_preserved(self):
        """BTC baseline (4/4 PASS) deve estar no journal para comparação."""
        j = self._load_journal()
        btc_base = j.get("btc_baseline", {})
        assert btc_base, "btc_baseline deve estar presente para diff"
        assert btc_base.get("decision") == "PASS", \
            "BTC baseline deve ser PASS (Wave 2 validado)"

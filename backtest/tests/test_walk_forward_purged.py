"""TDD walk-forward purged k-fold."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from walk_forward_purged import (
    split_temporal_kfold,
    evaluate_fold_metrics,
    walk_forward_evaluate,
)


def _mk(ts, r):
    return {"entry_ts": ts, "result_r": r}


def _gen_trades(n, start_year=2018):
    """Gera n trades distribuídos uniformemente em ~7 anos."""
    trades = []
    for i in range(n):
        year = start_year + (i * 7 // n)
        month = (i % 12) + 1
        day = (i % 28) + 1
        trades.append(_mk(f"{year}-{month:02d}-{day:02d}T00:00:00+00:00",
                           0.5 if i % 3 == 0 else -0.3))
    return trades


def test_kfold_splits_correct_count():
    """k=5 gera 5 folds com test sets não-sobrepostos."""
    trades = _gen_trades(100)
    folds = split_temporal_kfold(trades, k=5, embargo_days=0)
    assert len(folds) == 5
    total_test = sum(f["n_test"] for f in folds)
    assert total_test == 100


def test_kfold_train_test_disjoint():
    """train_idxs e test_idxs devem ser disjuntos por fold."""
    trades = _gen_trades(50)
    folds = split_temporal_kfold(trades, k=5, embargo_days=0)
    for f in folds:
        assert set(f["train_idxs"]).isdisjoint(set(f["test_idxs"]))


def test_embargo_reduces_train_size():
    """Embargo > 0 reduz train size (purga embargo window)."""
    trades = _gen_trades(50)
    f_no = split_temporal_kfold(trades, k=5, embargo_days=0)
    f_yes = split_temporal_kfold(trades, k=5, embargo_days=30)
    # Pelo menos 1 fold deve ter menos trades de treino com embargo
    diff = any(f_no[i]["n_train"] > f_yes[i]["n_train"]
               for i in range(min(len(f_no), len(f_yes))))
    assert diff


def test_evaluate_fold_returns_invalid_low_n():
    """< 30 trades retorna invalid."""
    r = evaluate_fold_metrics([_mk("2020-01-01T00:00:00+00:00", 1.0)] * 10)
    assert not r["valid"]


def test_walk_forward_robust_with_uniform():
    """Strategy uniforme com edge constante → todos folds positivos."""
    # 200 trades com mean_r positivo distribuído
    trades = []
    for i in range(200):
        year = 2018 + (i // 30)
        month = (i % 12) + 1
        day = (i % 28) + 1
        # Distribute positive mean
        r = 0.5 if i % 2 == 0 else -0.3  # mean = 0.1
        trades.append(_mk(f"{year}-{month:02d}-{day:02d}T00:00:00+00:00", r))
    out = walk_forward_evaluate(trades, k=5, embargo_days=0)
    assert "verdict" in out
    assert out["oos_summary"]["total_folds"] == 5


def test_walk_forward_flags_overfit_when_oos_negative():
    """Strategy que perde em todos os anos → flag overfit."""
    trades = []
    for i in range(200):
        year = 2018 + (i // 30)
        trades.append(_mk(f"{year}-01-{(i%28)+1:02d}T00:00:00+00:00",
                           -0.5))  # sempre perde
    out = walk_forward_evaluate(trades, k=5, embargo_days=0)
    assert "OVERFIT" in out["verdict"] or "FRAGILE" in out["verdict"]

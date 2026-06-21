# Trailing Policy — Walk-Forward Validation (2026-06-21)

> Profissionalização do trailing. Framework: harness puro de replay + motor de
> políticas por tipo + reversão-vs-manter + validação walk-forward pareada.
> **Veredicto: edge do RUNNER é REAL mas CONDICIONAL à tendência. NÃO ativar
> live incondicionalmente. Gate por uptrend/regime.**

## Metodologia

- **Dados:** 149 ativos CoinEx, daily, ~1000 candles cada (2023-08 → 2026-06).
- **Entradas:** LONG sintéticas a cada 40 barras (janelas não-sobrepostas, hold 30),
  stop inicial = 2×ATR. As MESMAS entradas rodam em todas as políticas →
  comparação **pareada** isola o efeito da SAÍDA (controla qualidade da entrada).
- **Métrica:** delta R pareado (candidate − atual) por entrada; bootstrap CI 95%.
- **Veredicto:** ROBUST só se o CI inteiro > 0. FRÁGIL se cruza 0. PIOR se < 0.

## Resultado 1 — full history (3130 entradas pareadas)

| Política | avg_R | win% | total_R |
|---|---|---|---|
| atual (baseline) | 0.054 | 38.6 | 168.8 |
| scalp | 0.058 | 41.0 | 179.9 |
| swing_long | 0.088 | 38.8 | 275.8 |
| **runner** | **0.286** | 32.8 | **893.6** |

| Candidate vs atual | delta | CI 95% | Veredicto |
|---|---|---|---|
| scalp | +0.0035 | [−0.022, +0.028] | FRÁGIL |
| swing_long | +0.0342 | [+0.011, +0.059] | ROBUST |
| runner | +0.2316 | [+0.151, +0.316] | ROBUST |

Block bootstrap **por ativo** (respeita correlação intra-ativo, 149 blocos):
runner [+0.157, +0.307] ROBUST; swing_long [+0.014, +0.057] ROBUST.

## Resultado 2 — split temporal (REPROVOU o full-history)

| | ERA1 (antiga ~bull) | ERA2 (recente ~bear) |
|---|---|---|
| runner vs atual | +0.553 ROBUST | **−0.102 PIOR** |
| swing_long vs atual | +0.113 ROBUST | −0.036 PIOR |

O CI sólido do full-history era **inteiramente puxado pela era de bull**. Na era
recente (regime corrente BEAR_WEAK) o runner **perde** pro trailing atual. Clássico
overfit a regime — exatamente o que a memória `realidade_dura` / Branch A
("h20 lift inflado por cluster day") manda procurar.

## Resultado 3 — driver real é TENDÊNCIA (não tempo)

Bucket por tendência na entrada (close vs SMA50):

| Bucket | n | runner Δ vs atual | CI 95% | Veredicto | avg_R atual→runner |
|---|---|---|---|---|---|
| UPTREND (close>SMA50) | 1219 | **+0.183** | [+0.070, +0.308] | ROBUST | 0.16 → 0.34 |
| DOWNTREND (close<SMA50) | 1795 | **−0.111** | [−0.163, −0.053] | PIOR | −0.114 → −0.225 |

A era recente reprovou porque tem mais entradas em downtrend. O driver é a
tendência, não o calendário.

## Conclusão acionável

1. **Runner (trail largo, deixa correr) é edge REAL em uptrend** (+0.18R, ~2× avg_R)
   e **prejuízo em downtrend** (dobra a perda). Deve ser **gated**.
2. `Resolve-ExitPolicyGated` (puro, TDD) encoda o gate: LONG + uptrend + regime
   não-bear → runner; resto → política atual.
3. **Regime corrente = BEAR_WEAK → o gate mantém o trailing ATUAL** (correto).
   O upgrade só "liga" quando o mercado virar uptrend/bull confirmado.
4. **Pré-LIVE ainda pendente:** isto é tudo IN-SAMPLE (mesmo histórico). Falta
   forward-test real (paper 1-3 meses) antes de plugar no money-path
   (`Update-AllTrailingStops` / `Invoke-ExitIntelligence`). NÃO foi wired no
   live nesta rodada — by design, sob dinheiro real + bear.

## Libs (zero LLM, 100% TDD — 36 testes)

- `lib_exit_backtest.ps1` (9) — Invoke-ExitReplay / Get-ExitReplayStats
- `lib_trailing_policy.ps1` (17) — Resolve-ExitPolicy / Get-ExitDecision / Resolve-ExitPolicyGated
- `lib_trailing_baseline.ps1` (4) — Get-CandlesFromFile / Invoke-BaselineComparison
- `lib_trailing_walkforward.ps1` (6) — Invoke-WalkForwardExit / Get-PairedDelta / Get-PairedDeltaBlocked

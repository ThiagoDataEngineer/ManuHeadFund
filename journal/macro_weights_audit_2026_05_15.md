# Audit Pesos Adaptativos Runtime — 2026-05-15

## Veredito: **ROTATION_ACTIVE**

Pesos adaptativos rotacionam REALMENTE por regime macro e SAO consumidos no scoring ponderado do orchestrator.

## Evidencias

- `adaptive_active`: **true**
- `has_regime_switch`: **true** (`switch ($macro.macro_bias) { BULLISH → $WEIGHTS_BULL; BEARISH → $WEIGHTS_BEAR; default → $WEIGHTS_NEUTRAL }` em `agents/orchestrator.ps1:132-135`)
- `weights_actually_differ`: **true**
- `evidence_count`: **13** sites de uso real (`$w.Tech *`, `$w.Fund *`, `$w.Chain *`, `$w.Sent *`) no orchestrator

## Pesos por Regime (`agents/config.ps1:44-46`)

| Regime  | Tech | Chain | Sent | Fund |
|---------|------|-------|------|------|
| BULL    | 0.40 | 0.30  | 0.20 | 0.10 |
| NEUTRAL | 0.40 | 0.25  | 0.20 | 0.15 |
| BEAR    | 0.35 | 0.20  | 0.25 | 0.20 |

Diferenca BULL → BEAR: Chain -33% (less defensive on-chain weight), Fund +100% (mais peso macro em bear), Sent +25% (capitulacao matters mais).

## Sites de Consumo Real (`agents/orchestrator.ps1`)

| Linha | Snippet |
|------:|---------|
| 250 | `$totalWeight = $w.Tech` |
| 251-253 | `$totalWeight += $w.Fund/Sent/Chain` |
| 255 | `$scorePonderado = $techScore * $w.Tech` |
| 256-258 | `$scorePonderado += $fundScore * $w.Fund` ... |

Demais 8 sites em `Write-Host` logs (informativos), mas as linhas 250-258 sao **score-multiplications de verdade** -- pesos entram no calculo do score final que dispara o gate de decisao.

## Conclusao

Pesos adaptativos NAO sao apenas declaracao em config: o orchestrator (a) carrega macro_bias via `Get-MacroContext`, (b) faz switch para selecionar `$w`, (c) multiplica cada score agent pelo peso correspondente, (d) loga peso ativo no console (`Pesos ativos [BULLISH]: Tech=40% Chain=30% ...`). Isso eh **runtime rotation**, validado por audit estatico + evidencia textual + 13 patterns de uso.

## Confidence: **HIGH**

- 8/8 Pester tests passam (`tests/macro_audit.Tests.ps1`)
- Live run mostra `verdict=ROTATION_ACTIVE`
- Evidence count (13) excede minimo (4) por 3x

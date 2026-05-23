# Mentor E4 — alpha_vs_btc Field & Audit (2026-05-22)

> Pattern: doc-alongside-TDD. Esta evolução implementa medição da regra-ouro #13
> ("altcoin precisa BATER BTC") que estava invisível no pipeline.

## Objetivo

Computar e expor **alpha_vs_btc** = trade_return − BTC_return (mesma holding window)
para todo trade fechado. Sem isto, regra-ouro #13 (CLAUDE.md:189) é declarativa
mas não verificável empiricamente.

## Motivação

`CLAUDE.md` rule #13: "altcoin precisa BATER BTC (após fees+slippage) pra justificar
exposição vs simplesmente holdar BTC". Pipeline atual registra `pnl_usd` e `pnl_pct`
mas **NÃO alpha_vs_btc**. Possível cenário invisível: alts ganhando dinheiro mas
PERDENDO consistently pra BTC hold equivalent.

Sem audit, não saberíamos. Tauric calcula alpha desde v0.2.0.

## Design

### Compute-AlphaVsBtc (core function)

```powershell
$r = Compute-AlphaVsBtc -Market "ETHUSDT" `
       -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" `
       -TradeReturnPct 10.0
# Returns: { alpha_vs_btc=5.0, btc_return_pct=5.0, valid=$true }
```

Decisões:
- **BTC trade auto-detect**: Market="BTCUSDT" ou "BTCUSD" → alpha=0 sempre, skip lookup
- **Fail-soft**: se BTC cache miss, retorna `valid=$false` + `alpha_vs_btc=$null`. NÃO bloqueia close
- **Daily granularity**: UTC date-based (não tick precision). Suficiente pra alpha calc
- **Cache file**: `journal/btc_daily_close_cache.json` formato `{ "YYYY-MM-DD": close }`

### Get-AlphaNegativeRate (audit aggregator)

```powershell
$r = Get-AlphaNegativeRate -Alphas @($a1, $a2, ...) -MinSampleSize 20 -AlertThresholdPct 60
# Returns: { n, negative_count, negative_rate_pct, alert, reason, threshold_pct }
```

- **MinSampleSize 20**: skip se n<20 (statistical confidence)
- **AlertThresholdPct 60%**: rate >= 60% sobre N>=20 → alert
- **Reason explícito**: "pipeline alt-trades losing to BTC (13/20 = 65%)" ou "insufficient_sample"

### Audit script: scripts/audit_alpha_negative_rate.ps1

Lê `journal/gem_trades.csv` + `journal/journal.csv`, extrai todas alphas, chama `Get-AlphaNegativeRate`. Se ALERT, optional `-SendTelegram` envia notificação.

Output:
```
=== Alpha vs BTC Audit ===
  Source: gem_trades.csv (47 total rows)
  Source: journal.csv (12 total rows)

  Trades audited: 59
  Trades with alpha_vs_btc computed: 23

=== Result ===
  n: 23, Negative count: 15, Negative rate: 65.2%
  ALERT TRIGGERED
```

### Wire deferred (intencional)

Wire em `Close-Trade` (journal.ps1) + `gem_executor.ps1` close path NÃO foi feito
nesta evolução. Razão: requires schema migration (adding column to existing CSV).
Risco: corromper journal histórico. Decisão segura: lib + audit prontos, mas wire
fica como **follow-up explícito** quando user confirmar:
1. Backup full journal
2. Migration script append-column-if-missing
3. Update Close-Trade hooks 1x

Audit script já funciona com dados parciais — quando wire vier, trades novos vão ter alpha e audit funciona incrementalmente.

## TDD Coverage

`tests/lib_alpha_vs_btc.Tests.ps1` — **18/18 PASS**:

| Group | Tests | Coverage |
|---|---|---|
| Get-BtcDailyClose | 3 | Cache miss/hit/corrupt |
| Set-BtcDailyClose | 2 | Create + preserve other entries |
| Compute-AlphaVsBtc | 5 | BTC auto-detect + alt positive/negative alpha + fail-soft cases |
| Get-AlphaNegativeRate | 4 | Insufficient sample + alert/no alert + custom threshold |
| Property: alpha + btc = trade | 1 | Mathematical invariant cross multiple trade returns |
| Property: determinism | 1 | Same input → same output |

## Design decisions

1. **Lib + audit separately deployable**: lib pode ser dot-sourced em testes/análises sem precisar wire em Close-Trade. Audit script lê whatever está disponível.

2. **Fail-soft no Compute-AlphaVsBtc**: NÃO blockar close de trade se BTC cache miss. `alpha_vs_btc=null` é OK — audit script skipa nulls.

3. **Daily granularity, não intraday**: alpha calc tolerante a precisão minutal. Daily UTC é "close-to-close" como índices.

4. **Cache write/read separation**: Set-BtcDailyClose pra refresh externa (poderia ser cron). Get-BtcDailyClose só leitura. Permite cache ser populado por job separado sem hot-path dependency.

5. **Wire deferred (não auto)**: schema migration risk é real. Wire fica como follow-up explícito.

## Forward links

- **Mentor E3 (Reflection)**: vai usar `alpha_vs_btc` para gerar lessons "alt under-performed BTC, lesson: stricter BTC-core gate"
- **Future cron** `CoinExBtcCacheRefresh` daily: pre-populate cache pra alpha calc não falhe em close hot-path
- **Future cron** `CoinExAlphaAudit` weekly: roda `audit_alpha_negative_rate.ps1` automaticamente

## Skill insight permanente

> **"Métrica que valida regra-ouro deve ser AUTOMÁTICA, não opcional"**.
>
> Regra-ouro só é regra se for verificável continuamente. Se medição é manual,
> regra vira aspiração. CLAUDE.md tinha #13 "altcoin BATE BTC" há meses; sem
> `alpha_vs_btc` field, regra era retórica não código.
>
> Application: TODO regra de filosofia operacional deve ter (a) métrica corresponding
> (b) audit automático com alert threshold (c) documentação ligando regra → métrica.

## Artefatos

- Código: [agents/lib_alpha_vs_btc.ps1](../../agents/lib_alpha_vs_btc.ps1)
- TDD: [tests/lib_alpha_vs_btc.Tests.ps1](../../tests/lib_alpha_vs_btc.Tests.ps1) (18 PASS)
- Audit: [scripts/audit_alpha_negative_rate.ps1](../../scripts/audit_alpha_negative_rate.ps1)
- Doc: este arquivo

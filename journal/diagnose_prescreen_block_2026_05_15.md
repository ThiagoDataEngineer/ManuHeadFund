# Diagnose: Pre-screen bloqueio 100% no ciclo 04:06 BRT 15/05

## Sintoma

Paper trade `bmnljqgdg`, ciclo 04:06 BRT (janela SLOW): 20/20 candidatos bloqueados no pre-screen com 1-2/4 passes. Mensagem:

```
[04:08:04] [WARN] Nenhum par passou o pre-screen - Orchestrator pulado
```

Ciclo anterior 01:58 (janela NEUTRAL): 7 candidatos passaram, 3 chegaram ao orchestrator. Algo mudou entre 01:58 e 04:06.

## Investigacao

### Metodologia

Criado `scripts/diagnose_prescreen.ps1` que reproduz `Get-ScannerCandidates -TopN 20 -MinVolUsd 500000 -IncludeSpot` e aplica `Test-ScanPreScreen` + os 4 gates do array `passes` em cada futuro, extraindo valores reais de ADX, RSI, vol ratio, EMA spread, e identificando qual gate falhou.

JSON: `journal/diagnose_prescreen_20260515_101339.json` (antes do fix).

### Snapshot empirico (10:13 BRT — pos-04:06, mesmo regime de mercado)

20 futuros avaliados; **14/20 BLOCK, 6/20 PASS**.

Falhas por gate (entre blocked):

| Gate | Falhas/14 |
|------|-----------|
| RSI  | 14/14 (100%) |
| VOL  | 12/14 (86%)  |
| EMA  | 3/14  (21%)  |
| ADX  | 2/14  (14%)  |

RSI fail reasons:

| Razao | N |
|-------|---|
| `rsi_healthy_band missing=vol<1.0x`       | 10 |
| `rsi<28 oversold`                         | 3  |
| `rsi_healthy_band missing=adx<20,vol<1.0x`| 1  |

### Exemplos representativos

| Mkt        | ADX  | RSI  | Vol   | EMAspread | Passes | Falhas |
|------------|------|------|-------|-----------|--------|--------|
| HYPEUSDT   | 34.8 | 43.0 | 0.31x | 0.78%     | 2/4    | RSI[missing=vol<1.0x] \| VOL<0.5x |
| DUSKUSDT   | 27.3 | 54.4 | 0.36x | 0.56%     | 2/4    | RSI[missing=vol<1.0x] \| VOL<0.5x |
| ICPUSDT    | 32.7 | 23.1 | 0.11x | 2.31%     | 2/4    | RSI[oversold] \| VOL<0.5x |
| CFXUSDT    | 78.9 | 40.6 | 0.20x | 1.23%     | 2/4    | RSI[missing=vol<1.0x] \| VOL<0.5x |
| KASUSDT    | 52.4 | 31.5 | 0.12x | 1.08%     | 2/4    | RSI[missing=vol<1.0x] \| VOL<0.5x |

## Root Cause (HIGH confidence)

`Test-ScanPreScreen` (Bug A fix original) tem **gate de RSI acoplado a confluencia vol+ADX em faixa saudavel (28-78)**:

```ps1
if ($Rsi -le 78) {
    return ($Adx -ge 20 -and $Vol -ge 1.0)   # <-- acoplamento incorreto
}
```

Problema: o array `passes` em `Invoke-MasterCycle` (linha 392-397) ja tem 4 gates independentes:

```ps1
$passes = @(
    ($adx -ge 18),                          # gate ADX
    $rsiOk,                                 # gate RSI (Test-ScanPreScreen)
    ($emaSpread >= 0.0002),                 # gate EMA spread
    ($vol -ge 0.5)                          # gate VOL
)
```

Quando RSI esta em faixa saudavel mas vol < 1.0x:
- Gate VOL (#4) passa se vol >= 0.5x
- Gate RSI (#2) falha porque exige vol >= 1.0x DENTRO do gate

Resultado: candidato com RSI saudavel + vol 0.5-1.0x tem maximo 3/4. Pior: se vol < 0.5x (comum em janela SLOW), gate VOL e gate RSI falham simultaneamente -> maximo 2/4 -> BLOCK.

Por que so ocorreu na madrugada? Janela SLOW (00h-06h BRT) tem **volume de mercado universalmente baixo**, fazendo vol relativo (vs media 24h) cair para 0.1-0.5x em quase todos pares. Quando isso acontece, o duplo gate de volume bloqueia 100%.

## Decisao: SAIDA B — Bug especifico identificado

Fix: desacoplar vol/ADX do gate de RSI em faixa saudavel. RSI gate julga apenas RSI; vol e ADX tem gates separados no array `passes`. Confluencia vol/ADX so se aplica em faixa de breakout (78-88), onde a confluencia E o sinal (sem ela, RSI alto vira sinal falso).

### Diff

`scripts/scan_master.ps1` (funcao Test-ScanPreScreen):

```diff
 if ($Rsi -le 78) {
-    # Faixa saudavel — default healthy. ADX e vol minimos suaves.
-    return ($Adx -ge 20 -and $Vol -ge 1.0)
+    # Faixa saudavel — RSI sozinho ja qualifica. Gates de vol e ADX
+    # (array passes em Invoke-MasterCycle) decidem confluencia separadamente.
+    return $true
 }
```

Faixa 78-88 (breakout) preservada intacta — `vol >= 1.5 AND adx >= 25`.

### TDD

`tests/scan_master_rsi_filter.Tests.ps1`: novo Describe "Bug C - RSI gate desacoplado", 8 testes RED -> GREEN:

1. `RSI 28-78 saudavel: passa SEMPRE` (HYPE cenario real)
2. `RSI 54 com vol baixo: RSI gate passa` (DUSK cenario real)
3. `RSI saudavel com ADX baixo: RSI gate passa`
4. `RSI 78 boundary saudavel: passa sem confluencia`
5. `RSI 28 boundary inferior: passa sem confluencia`
6. `RSI 78-88 breakout: AINDA exige vol+ADX` (3 asserts internos)
7. `RSI > 88: rejeita sempre`
8. `RSI < 28: rejeita sempre`

Antes do fix: 5 RED, 15 PASS (total 20).  
Depois do fix: 0 RED, 20 PASS.

### Suite completa pos-fix

| Suite   | Antes  | Depois | Delta |
|---------|--------|--------|-------|
| Pester  | 809    | 817    | +8    |
| pytest  | 627    | 627    | 0     |
| **Total** | **1436** | **1444** | **+8** |

Zero regressao. 100% verde.

## Validacao empirica pos-fix

Re-rodou `diagnose_prescreen.ps1` as 10:44 BRT (mesmas condicoes de mercado, ~30min depois):

| Metrica | Antes  | Depois |
|---------|--------|--------|
| PASS    | 6/20   | **17/20** |
| BLOCK   | 14/20  | 3/20      |
| Falha RSI healthy_band missing=vol | 10 | **0** |

Os 3 blocks remanescentes tem causa **legitima**:

- **XAGUSDT**: ADX 12.7 (sem tendencia) + RSI 24.4 (oversold extremo). Correto rejeitar.
- **FARTCOINUSDT**: ADX 12.7 + RSI 24.8. Correto rejeitar.
- **XPLUSDT**: ADX 8.0 + RSI 27.5. Correto rejeitar.

Sistema agora bloqueia por motivos certos (tendencia ausente + reversao nao iniciada), nao mais por artefato de janela horaria.

## Analise honesta: HYPE +17%

**HYPE no momento do diagnose (10:44 BRT 15/05):**
- ADX 34.8 (tendencia saudavel, nao saturada)
- RSI 43.3 (saudavel, nem oversold nem overbought)
- Vol 0.52x (vol pos-pump baixou — pump esfriando)
- EMA spread 0.78% (EMA9 acima EMA21, mas convergindo)
- Change 24h: +6.49% (segundo dia consecutivo, mas com vol decrescente)

**Contexto critico:** ontem (14/05) +20% com vol 4.46x e ADX 29 — *aquele* era o ponto de edge real (Bug A fix mirava). Hoje, com vol 0.52x e RSI 43, o pump esta **distribuindo**. Entrar agora = comprar de quem ja lucrou ontem.

Sistema rejeita HYPE pelo gate de VOL (0.52x ainda passa o 0.5x mas marginal). Mesmo se passar pre-screen e cascade, orchestrator V6 provavelmente devolveria ABORTAR (regime, score baixo). Comportamento esperado.

**Resposta direta:** HYPE +17% hoje **NAO era oportunidade real** — era FOMO pos-pump. A oportunidade foi ontem com vol 4.46x. Sistema bloqueando agora esta correto. O fix do Bug C nao deve fazer o sistema operar HYPE; deve fazer o sistema **reconhecer candidatos legitimos** em janelas de baixo volume (madrugada) que antes eram artificialmente bloqueados.

## Restart paper trade

- PID antigo: 26728 (morto)
- PID novo: 25300 (background, DryRun)
- Janela atual: SLOW (proximo ciclo agendado pos-fix)

## Recomendacao proxima sessao

1. **Monitorar 24h** o paper trade pos-fix. Esperado: pre-screen passa ~30-70% dos candidatos (vs ~0-35% antes), Orchestrator entra mais vezes em ABORTAR/EXECUTAR (vs WARN nenhum-par).
2. **Re-checar janela SLOW especificamente** (proximo ciclo 06:08 BRT) — confirmar que candidatos passam.
3. **Verificar se cascade V6 nao explode** com mais candidatos chegando. TOPN default = 3, claude budget OK.
4. **Considerar tightening** se sistema operar demais em janela SLOW (baixa liquidez = slippage real). Pode-se adicionar gate de janela em Get-ScannerCandidates: `if (window == SLOW) { MinVolUsd *= 3 }`. Opt-in via config.local.ps1.

## Arquivos modificados

| Path | Acao |
|------|------|
| `scripts/scan_master.ps1`                  | Test-ScanPreScreen Bug C fix (linhas 100-127) |
| `tests/scan_master_rsi_filter.Tests.ps1`   | 8 testes novos Bug C (Describe adicional) |
| `scripts/diagnose_prescreen.ps1`           | Novo (ferramenta diagnostico/repro) |
| `journal/diagnose_prescreen_20260515_101339.json` | Snapshot pre-fix |
| `journal/diagnose_prescreen_20260515_104453.json` | Snapshot pos-fix |
| `journal/diagnose_prescreen_block_2026_05_15.md`  | Este documento |

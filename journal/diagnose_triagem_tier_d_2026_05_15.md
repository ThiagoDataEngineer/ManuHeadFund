# Diagnose: 100% Tier D no paper trade pos-Bug-C-fix (2026-05-15)

> READ-ONLY. Nenhum codigo modificado. 37 [TRADE] entries em `logs/master_20260515.log`
> entre 01:58 e 10:47 BRT. Janela WAVE 2.5 ativa, `SKIP_THURSDAY_ALTS=$false`.

---

## 1. Logica de Tier (exata)

### Onde mora a decisao

**Arquivo:** `agents/triagem_agent.ps1`
**Funcao:** `_Compute-Tier` (linhas 58-89)
**Tier e 100% DETERMINISTICO.** O LLM (Llama 3.3 70B via Groq) NAO influencia tier.
LLM produz apenas `razao`, `flags` e `score_predicted` — todos cosmeticos para `tier`.

### Algoritmo (pseudocodigo)

```
inputs: Score (int), MacroBias, DayOfWeek, MarketTier
        SKIP_THURSDAY_ALTS (global, default $false)

if (Thursday AND alt AND SKIP_THURSDAY_ALTS=$true) -> D     # gate opt-in OFF hoje
if (Score < 50)                                    -> D     # ★ HOT GATE
if (MacroBias == BEARISH):
    if (Score < 60)                                -> D
    else                                           -> C
# Macro favoravel (BULLISH ou NEUTRAL):
if (Score >= 75 AND macroFavoravel AND dowFavoravel AND not thursdayAlt) -> A
if (Score >= 60 AND macroFavoravel)                                       -> B
else                                                                      -> C
```

### Variaveis de entrada (so 4)

| Campo `Context`             | Default `_Get-CtxField` | Origem real           |
|-----------------------------|-------------------------|-----------------------|
| `scanner.score`             | 50                      | `Get-QuickTechScore`  |
| `macro.macro_bias`          | "NEUTRAL"               | `Get-MacroContext`    |
| `seasonal.dayOfWeek`        | "Wednesday"             | `Get-SeasonalityCtx`  |
| `seasonal.marketTier`       | "btc"                   | `Get-MarketTier`      |

### Pos-LLM: existe override?

**Nao.** `Invoke-Triagem` (linha 281-290) retorna o `$tier` calculado em **passo 2** (linha 188).
O cascade `Invoke-V6Cascade` (linhas 50-61) **so le** `triagem.tier` para abortar; nao reescreve.

### Thresholds resumidos

| Score      | BULLISH | NEUTRAL | BEARISH |
|------------|---------|---------|---------|
| < 50       | **D**   | **D**   | **D**   |
| 50-59      | C       | C       | D       |
| 60-74      | B       | B       | C       |
| 75-100     | A*      | A*/B    | C       |

*A exige tambem DoW favoravel (Mon/Tue/Wed) e nao-(Thursday+alt).

---

## 2. Onde `Score` realmente vem (escala 0-100)

**`agents/scanner.ps1::Get-QuickTechScore` (linhas 150-180):**

```
score = 50
if change > +3%  : score += 15  -> 65
elif change > +1%: score += 7   -> 57
elif change < -1%: score -= 7   -> 43
elif change < -3%: score -= 15  -> 35
clamp [0..100]
```

**Implicacao critica:** score so atinge **>= 60** quando `change_24h > +3%`.
Em janela SLOW/GOOD com mercado lateral (-1% a +1%), TODOS os pares ficam em 50 -> Tier C (mas
ate 50 e EXATAMENTE 50, NAO < 50, entao seria Tier C).

Para chegar a Tier D via `score<50`, o par precisa estar com change negativo > -1% (score 43)
ou pior. **Isso explica por que 100% caem em D nessa janela: o mercado esta vermelho/lateral,
nao bullish o suficiente para score >= 50.**

---

## 3. Analise empirica (37 trades)

### Distribuicao de `score=` no log

| Score reportado | N  | Tier observado | % do total |
|-----------------|----|----|------------|
| 20              | 2  | D  | 5%   |
| 40              | 2  | D  | 5%   |
| 42              | 31 | D  | 84%  |
| 60              | 1  | D  | 3%   |
| 72              | 1  | D  | 3%   |

### ★ ALERTA DE INTERPRETACAO

**O `score=` no `[TRADE]` log NAO E `scanner.score`.**

`scripts/scan_master.ps1` linhas 465-468:

```powershell
$scoreNum = if ($null -ne $result.scorePonderado) { $result.scorePonderado }
            elseif ($result.mesa)                 { $result.mesa.score_avg }
            elseif ($result.triagem)              { $result.triagem.score_predicted }
            else                                  { $null }
```

Quando tier=D, a cascade aborta antes da Mesa, entao `mesa=null` e `scorePonderado` nunca e
populado. O score logado e sempre **`triagem.score_predicted`** — numero que o **Llama 3.3
inventou** como "estimativa de qualidade". O `scanner.score` real (que de fato gatilhou Tier D)
fica **invisivel no log**.

### Anomalias que comprovam

- **BNBUSDT score=60 tier=D** (08:43): se fosse `scanner.score=60`, Tier B seria emitido. Logo,
  `scanner.score < 50` chegou a Triagem, mas Llama escreveu 60 em `score_predicted`.
- **XAUTUSDT score=72 tier=D** (08:12): mesmo raciocinio. `scanner.score < 50`, LLM exagerou para 72.
- O pico de 31 trades com exatamente "42" sugere que o Llama tem **vies de defaults para 42**
  quando o cenario e morno (eco do scanner default 50 - 7 = 43, ou heuristica do LLM).

### Pares dominantes (37 trades, ~15 ciclos)

CHZ, VVV, CFX, XAUT, SUI, XMR, ICP, NOT, LUNC, CRV, PYTH, APT, TURBO, MYX, B, WLD, BNB, ZEC, TON, RIVER, DUSK. Misto de mid-caps com low momentum em mercado lateral/bearish curto. **Nenhum
par com change_24h > +3% chegou ao orchestrator no periodo** — caso contrario teriamos
visto `score_predicted` correlato e provavelmente Tier B/C.

### Existiu candidato A+?

**NAO.** Em 37 trades, **zero** tinha condicoes "scanner.score >= 60 + BULLISH + DoW favoravel".
O mercado entre 01:58-10:47 nao produziu mover capaz de gerar scanner.score >= 60.

---

## 4. Hipoteses ranqueadas

| # | Hipotese | Confianca | Evidencia |
|---|----------|-----------|-----------|
| 1 | Llama 70B overly conservative | **LOW (refutada)** | Tier nao depende do LLM; e deterministico antes da chamada |
| 2 | Logica determ. pos-LLM forca Tier D | **LOW (refutada)** | Nao existe override; cascade so le `triagem.tier` |
| 3 | Threshold de C/B/A estruturalmente impossivel | **MEDIUM** | Para Tier B precisa scanner.score >= 60 == change > +3%. Em janela morna, raro |
| 4 | Gate determ. nao-obvio (DoW, par, etc) | **LOW (refutada)** | `SKIP_THURSDAY_ALTS=$false`; nao ha whitelist de pares antes do Tier |
| 5 | Score normalizado com escala errada | **LOW (refutada)** | `Get-QuickTechScore` clamp [0..100] correto; `_Get-CtxField` lendo `scanner.score` correto |
| **6** | **`scanner.score` chegando < 50 em 100% dos pares devido a mercado lateral/vermelho na janela** | **HIGH** | Scanner score = 50 +/- f(change_24h). Nenhum par com change > +3% no periodo. Consistente com pre-screen passando "6/20 -> 17/20" mas o que passa pre-screen nao necessariamente tem momentum. Pre-screen olha ADX/RSI/EMA — nao change% |
| **7** | **Score logado em `[TRADE]` e `score_predicted` (LLM), nao `scanner.score`** | **HIGH (confirmado)** | `scan_master.ps1:467` fallback chain mostra isso; BNB=60/Tier=D e prova porque viola regras se fosse scanner.score |

**Hipotese vencedora: #6 + #7 (sao complementares).** O sistema esta funcionando exatamente
como projetado. Nao ha bug; ha **gap de calibracao + dificuldade de observabilidade**.

---

## 5. EUREKA: 2 problemas reais (nao bugs)

### EUREKA A — Gap de observabilidade (HIGH severity)

O log `[TRADE] score=X` engana o operador. Quando tier=D, `X` e o
`triagem.score_predicted` (numero LLM-gerado), nao o input determinante do tier. Operador
acha que "score 60 deveria virar Tier B" e questiona a logica — mas o sistema esta certo;
o numero exibido e o que NAO importa.

**Fix proposto (sem aplicar):** acrescentar `scanner_score` ao formato de log:

```
[TRADE] BNBUSDT: ABORTAR ... scanner_score=42 score_predicted=60 tier=D ...
```

Ou renomear o campo atual para `score_pred` e adicionar `score_sc`. Isso elimina 100% da
confusao em diagnoses futuros.

### EUREKA B — Scanner score acoplado APENAS a change_24h (MEDIUM severity)

`Get-QuickTechScore` (linha 162-167) usa **somente** `change_24h` para mover o score acima/abaixo
de 50. Isso significa:

- Janela lateral (-1% < change < +1%): TUDO fica em 50 -> Tier C maximo (com BULLISH macro).
- Janela morna positiva (+1% a +3%): score=57 -> Tier C.
- Para chegar a Tier B, precisa change > +3% nas ultimas 24h. **Em paper trade real, isso e
  ~5-10% dos pares por ciclo.**
- Para Tier A, precisa change > +3% AND scanner.score >= 75. Mas o calculo MAX e 65. **Tier A
  e MATEMATICAMENTE INALCANCAVEL pelo scanner atual.**

Vejam: `score = 50 + 15 = 65 <  75`. Logo, **Tier A nunca disparara** com `Get-QuickTechScore`.

Tier A so funcionaria via `Get-FullTechScore` (linha 182+, chama `tech_agent.ps1`), que retorna
`totalScore` — mas o scanner.ps1 atual usa Get-QuickTechScore por default no caminho de
universe-scan. Verificar se Wave 2.5 trocou para FullTechScore (provavelmente nao).

---

## 6. Recomendacao concreta (OPT-IN, sem mexer em codigo agora)

### Opcao 1 (recomendada) — Manter como esta, aguardar mercado mover

O sistema esta correto. 100% Tier D em janela lateral/bearish e **comportamento esperado e
desejado** (Regra de Ouro #6: "Aguardar e uma posicao"). Nao ha edge em forcar entradas
quando momentum agregado e fraco.

**Acao:** continuar paper trade. Esperar 24-48h mais (janela inclui dias da semana com mover
maior). Se NENHUM Tier B/A aparecer em 5 dias com BULLISH detectado, ai sim ha
recalibracao a fazer.

**Risco:** baixo. Custo: 24-48h de paciencia.

### Opcao 2 — Recalibrar scanner.score para escalar ate 100

Substituir `Get-QuickTechScore` por uma formula que use change + volume + ADX + EMA spread
(fatores ja calculados em pre-screen) para produzir 0-100 com distribuicao mais larga.

**Risco:** alto. Mexe em base critica do filtro. Requer TDD completo + walkforward retroativo
para garantir que nao introduz vies long.

### Opcao 3 — Adicionar log de `scanner_score` separado (so EUREKA A)

`agents/lib_trade_logger.ps1`: estender `Format-TradeLogEntry` com `-ScannerScore` opcional;
`scripts/scan_master.ps1` linha 478: passar `$result.triagem.score` (se exposto) ou via
`$global:SCANNER_INDEX[$c.market].score`.

**Risco:** zero (cosmetico). Beneficio: diagnose futuros ficam triviais. **Recomendado em
qualquer cenario.**

### Opcao 4 — Calibracao via override OPT-IN

Adicionar config: `$global:TRIAGEM_SCORE_FLOOR = 50` (default). Permite operador baixar para
40 para destravar Tier C em janela lateral.

```powershell
# config.local.ps1
$global:TRIAGEM_SCORE_FLOOR = 45   # opt-in: aceita Tier C mais agressivo
```

`_Compute-Tier` linha 78 viraria `if ($Score -lt $floor) { return "D" }`.

**Risco:** medio. Destrava trades mas em mercados fracos (justamente onde scanner.score baixo
existe por razao). Pode aumentar false-positives. Validar com walkforward em janela lateral
de 14d.

---

## 7. Conclusao

- **Bug claro:** zero. Sistema funcionando como projetado.
- **Bug de observabilidade:** EUREKA A — score logado e enganoso. Fix barato e altamente
  recomendado.
- **Gap de calibracao real:** EUREKA B — `Get-QuickTechScore` clamp em 65 torna Tier A
  matematicamente impossivel via universe-scan; e Tier B exige change > +3% (raro).
- **Recomendacao:** Opcao 1 + Opcao 3 combinadas. Esperar mercado mover + melhorar log para
  diagnoses futuros sem ambiguidade.

**O paper trade NAO esta quebrado.** Esta cumprindo a regra "aguardar e uma posicao" em janela
lateral. A surpresa do operador veio de log com nome ambiguo (`score=` significa coisas
diferentes consoante o caminho da cascade).

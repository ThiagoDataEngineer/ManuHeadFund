# Cascade 100% Tier D — Diagnose Definitivo (2026-05-15)

## TL;DR

Cascade V6 fica 100% em Tier D **não por bug de calibração mas por escala incompatível** entre o que o scanner produz e o que a Triagem espera.

| Componente | Range observado | Threshold consumidor |
|---|---|---|
| `Score-Ticker` em `Get-ScannerCandidates` (scan_master.ps1:212-228) | **0-50 típico** (`|change%| × log10(vol/1000)`) | — |
| `$global:SCANNER_INDEX[market].score` | mesmos 0-50 | — |
| `scanInfo.score` → orchestrator → Triagem `_Compute-Tier` | mesmos 0-50 | **Tier D < 50, A >= 75** |

**Conclusão:** Formula score top out em ~35 na universidade atual (mainstream markets, regime SIDEWAYS). Triagem exige >=50 para escapar Tier D. **Matematicamente impossível** com a escala atual.

---

## Cadeia de Score (rastreada)

1. `scan_master.ps1:398` chama `Get-ScannerCandidates` (definida no mesmo arquivo, linha 204).
2. `Score-Ticker` (linha 212-228) computa:
   ```
   score = |change_24h%| × log10(volume_usd / 1000)
   ```
3. Top-20 indexado em `$global:SCANNER_INDEX[market] = { score, change, volume }`.
4. Pre-screen filtra por ADX/RSI/EMA/vol → candidatos.
5. Ordenação por `compScore` (composite `vol*0.4 + |mom|*0.3 + adxH*0.3`) seleciona top-N.
6. Para cada top, `scan_master.ps1:534` passa `$scanInfo.score = $sr.score` (do SCANNER_INDEX) ao orchestrator.
7. `Invoke-OrchestratorV6` propaga via `Context.scanner_score`.
8. Triagem `_Compute-Tier` (triagem_agent.ps1:78-88):
   ```
   if ($Score -lt 50)  { return "D" }
   if (BEARISH && Score<60) { return "D" }
   if (Score>=75 && macro+dow OK) { return "A" }
   if (Score>=60 && macroOK)      { return "B" }
   return "C"
   ```

## Por que falsamente identifiquei "clamp 65→85" como solução

`Get-QuickTechScore` em `scanner.ps1:186` tinha clamp em 65 (fórmula `50 ± 15` × `change > 3%`). EUREKA B (memory `project_triagem_diagnose_eurekas_2026_05_15.md`) introduziu override 65→85. **Mas essa função NÃO É USADA no pipeline live**: scan_master usa `Get-ScannerCandidates` (formula log10), não `Get-QuickTechScore`. Eu fiz a alteração no caminho errado.

## Distribuição real observada (logs hoje)

| Market | scanner_score | Tier |
|---|---|---|
| FFUSDT | 32.62-33.65 | D |
| MYXUSDT | 24.22-25.69 | D |
| TURBOUSDT | 24.57-25.56 | D |
| WIFUSDT | 22.65-22.91 | D |
| XAGUSDT | 29.30-29.38 | D |
| ENAUSDT | 25.70-26.28 | D |
| TONUSDT | 28.78 | D |
| WLDUSDT | 24.67-25.22 | D |

Range observado: **22-34**. Nenhum >50 em 4+ ciclos.

## Fix proposto (Opção 2 — recalibrar Triagem para escala real)

Em vez de tentar inflar o score (mascararia o problema), recalibrar Triagem thresholds para a escala empírica do scanner:

```powershell
# triagem_agent.ps1:78-88 — escala calibrada para log10×change formula
# Range empírico observado: 22-34 (universal CoinEx, regime SIDEWAYS/BULL_WEAK)
# Movers fortes 1x/semana podem chegar a 50-80.
if ($Score -lt 15)  { return "D" }    # ruído puro
if ($MacroBias -eq "BEARISH") {
    if ($Score -lt 25) { return "D" }
    return "C"
}
# ...
if ($Score -ge 40 -and $macroFavoravel -and $dowFavoravel -and -not $thursdayAlt) { return "A" }
if ($Score -ge 25 -and $macroFavoravel) { return "B" }
return "C"
```

**Risco:** Tier B/A passam a ser alcançáveis → cascade ativa PORTEIRO/MESA/GENERAL → custo Anthropic incremental (~$0.005-0.05/ciclo).

**Reversibilidade:** Override `$global:TRIAGEM_THRESHOLDS = @{D=15; B=25; A=40}` em config.local.ps1, default mantém valores antigos. Opt-in.

**Validação obrigatória:**
- Adicionar tests pra novo override (8-10 testes TDD)
- Rodar suite Pester completa
- Em 24h: paper trade audit confirmando cascade ativou ≥1× sem aprovação espúria

## Decisão pendente do usuário

- **A) Aplicar fix com OPT-IN override** (recomendado — reversível)
- **B) Aplicar fix hardcoded** (mais simples mas reversibilidade requer revert commit)
- **C) Adiar — coletar mais 24h de paper trade pra confirmar distribuição em outros regimes**

## Anexo — Bug STORJUSDT (Task C, em diagnose)

`Orchestrator STORJUSDT erro: argumento 'Path' nulo` é recorrente em todo ciclo onde STORJ está nos candidatos. Hipóteses ativas:
1. STORJ é GEM (score 85 detectado, único gem hoje) → gem_executor pode estar tentando logar em path null
2. STORJ sub-dollar (~$0.30) → precisão decimal pode estar quebrando alguma função `-Path` em CoinEx-PlacedOrder/Add-LadderTrack

Instrumentação inserida em `scripts/scan_master.ps1:597-606` (catch com stack trace). Próximo ciclo do paper trade (PID 9708) deve capturar stack trace exato. Fix vai depender do path identificado.

---

Gerado em 2026-05-15 ~19:00 BRT durante diagnose Task B + Task C.

# SPEC: TORI LONG SWEEP (regime-aware) — gem_loop.ps1

> Escrita 2026-07-15 para implementação por agente executor. Toda âncora de
> linha refere-se ao commit `9e977ce`. Se as linhas mudaram, buscar pelos
> textos-âncora citados.

## Contexto (por quê)

O `gem_loop.ps1` tem 3 fontes de candidatos: triggers, `Invoke-GemScan`
(DISCOVERY, momentum-LONG genérico) e o **TORI SHORT SWEEP** (linhas
320-372, âncora: comentário `── TORI SHORT SWEEP (2026-07-09)`). Não existe
sweep LONG equivalente: quando o mercado está subindo em massa (medido
2026-07-15: 87% do universo futures positivo em 24h), o sistema gasta
ciclos propondo SHORTs que os quality gates vetam (corretamente), e não
propõe os LONGs que o momento pede. O detector Tori JÁ suporta LONG
(`Test-ToriConfluence -SetupType "LONG"` — ver
`agents/lib_tori_confluence_detector.ps1` linhas 120 e 279).

## Objetivo

Adicionar um **TORI LONG SWEEP** em `scripts/gem_loop.ps1`, espelhando o
SHORT sweep existente, **gated pelo cenário BTC ao vivo** (regime-aware):
só roda quando `Get-MarketScenario` retorna `allow_long = $true` — o mesmo
critério que o gate do executor usa, então zero candidato desperdiçado.

## Mudanças exatas

### 1. `scripts/gem_loop.ps1` — inserir novo bloco

**Local:** imediatamente APÓS o fechamento do bloco TORI SHORT SWEEP
(após a linha com `Write-GemLog "WARN" "tori short sweep failed...` e seu
`}` de fechamento — âncora: a linha `$gems = @($triggerGems) + @($gemsFromScan) + @($toriShortGems)`).
Inserir ANTES dessa linha `$gems = ...`.

**Código a inserir** (seguir EXATAMENTE este shape — é espelho do SHORT
sweep com as diferenças anotadas):

```powershell
        # ── TORI LONG SWEEP (2026-07-15): 4a fonte de candidatos ───────────────
        # Espelho do SHORT sweep acima, para o lado LONG. Regime-aware: so roda
        # quando Get-MarketScenario permite LONG (allow_long=true: BULL/
        # CAPITULACAO/UNKNOWN) -- mesmo criterio do gate 1c do executor, entao
        # nenhum candidato e gerado apenas para ser bloqueado no cenario.
        # Universo: config/long_universe.json (git-tracked, acessivel na nuvem),
        # tier A_LIVE. Cap 3/ciclo. Executor re-roda TODOS os gates.
        $toriLongGems = @()
        if (-not (Get-Command Get-MarketScenario -ErrorAction SilentlyContinue)) {
            $projRoot2 = Split-Path $global:JOURNAL_DIR -Parent
            $msPath = Join-Path (Join-Path $projRoot2 "agents") "lib_market_scenario.ps1"
            if (Test-Path $msPath) { . $msPath }
        }
        if ((Get-Command Test-ToriConfluence -ErrorAction SilentlyContinue) -and
            (Get-Command Get-MarketScenario -ErrorAction SilentlyContinue)) {
            try {
                $scenSweep = Get-MarketScenario
                if ($scenSweep -and $scenSweep.allow_long) {
                    $luPath = Join-Path (Split-Path $global:JOURNAL_DIR -Parent) "config/long_universe.json"
                    if (Test-Path $luPath) {
                        $lu = Get-Content $luPath -Raw | ConvertFrom-Json
                        $luMarkets = @($lu.markets | Where-Object { $_.tier -eq "A_LIVE" } | ForEach-Object { $_.market })
                        foreach ($m in $luMarkets) {
                            $tc = $null
                            try { $tc = Test-ToriConfluence -Market $m -SetupType "LONG" -TimeframeMinutes 60 -TimeoutSeconds 6 } catch {}
                            if ($tc -and $tc.allows) {
                                $toriLongGems += [PSCustomObject]@{
                                    market     = $m
                                    score      = [int]$tc.confluence_score
                                    mode       = "TORI_LONG"
                                    direction  = "LONG"
                                    conviction = [int]$tc.confluence_score
                                    signal     = ("tori:" + (@($tc.signals_fired) -join '+'))
                                    sizing     = [PSCustomObject]@{ sizing_pct = 0.02 }
                                }
                                Write-GemLog "TORI_LONG" "$m confluence=$($tc.confluence_score) signals=$(@($tc.signals_fired) -join '+')"
                            }
                        }
                        if ($toriLongGems.Count -gt 3) {
                            $toriLongGems = @($toriLongGems | Sort-Object { [int]$_.score } -Descending | Select-Object -First 3)
                        }
                        if ($toriLongGems.Count -gt 0) {
                            Write-GemLog "INFO" "Tori LONG sweep: $($toriLongGems.Count) candidato(s) >=80 no A_LIVE (cenario=$($scenSweep.scenario))"
                        }
                    }
                } else {
                    Write-GemLog "INFO" "Tori LONG sweep: skip (cenario=$($scenSweep.scenario) allow_long=false)"
                }
            } catch {
                Write-GemLog "WARN" "tori long sweep failed (non-critical): $($_.Exception.Message)"
            }
        }
```

### 2. Mesma função — incluir na agregação

Alterar a linha:
```powershell
$gems = @($triggerGems) + @($gemsFromScan) + @($toriShortGems)
```
para:
```powershell
$gems = @($triggerGems) + @($gemsFromScan) + @($toriShortGems) + @($toriLongGems)
```

## Regras INEGOCIÁVEIS (lições de incidentes reais deste repo)

1. **PS 5.1 compat**: NUNCA usar `??`, `?:` ternário, `?.`  — quebram parse
   e a lib inteira morre em silêncio no dot-source. Validar com
   `[System.Management.Automation.Language.Parser]::ParseFile()` ANTES de
   qualquer commit (o pre-commit hook também valida, não burlar).
2. **NUNCA usar sed/regex-replace em massa** para editar o arquivo — edição
   pontual apenas (incidente 2026-07-14: sed corrompeu 25 linhas e derrubou
   a nuvem por 2h).
3. **PSCustomObject, não hashtable** para os gems — o executor lê
   `.direction` via PSObject em pontos legados (comentário no SHORT sweep,
   bug real de 2026-07-09 em que direction de hashtable era ignorada e tudo
   virava LONG).
4. **Fail-soft**: todo o bloco dentro de try/catch com WARN não-crítico —
   uma falha no sweep NUNCA pode derrubar o ciclo do gem_loop.
5. **Não tocar no SHORT sweep existente** — nenhuma linha dele muda.
6. **Não inventar dependência nova**: usar apenas `Test-ToriConfluence`,
   `Get-MarketScenario`, `Write-GemLog` e `config/long_universe.json`, todos
   já existentes.

## Validação obrigatória (nesta ordem)

1. `[System.Management.Automation.Language.Parser]::ParseFile()` em
   `scripts/gem_loop.ps1` → 0 erros.
2. Rodar Pester (Pester 3.4 do repo, sintaxe `Invoke-Pester -Script`):
   `tests/lib_market_scenario.Tests.ps1` e qualquer teste com "gem_loop" no
   nome se existir → resultado IGUAL ao baseline (rodar antes E depois; a
   comparação antes/depois é a prova de não-regressão, não o número
   absoluto — há falhas pré-existentes conhecidas no repo).
3. Mostrar o diff completo (`git diff scripts/gem_loop.ps1`) no relatório
   final.
4. NÃO commitar nem push — entregar o diff aplicado no working tree para
   revisão.

## Critério de sucesso

- Bloco novo presente entre o SHORT sweep e a linha `$gems = ...`, com
  `$toriLongGems` agregado.
- Parse PS5.1 limpo; Pester igual ao baseline.
- Comportamento: em cenário BULL/CAPITULACAO, até 3 candidatos LONG
  (mode=TORI_LONG, confluence>=threshold do detector) entram na esteira; em
  NEUTRO/BEAR, log de skip explícito e zero candidatos (sem custo).

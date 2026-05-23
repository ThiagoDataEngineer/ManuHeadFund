# Gate Safety Audit — fail-closed compliance

> Criado 2026-05-19 PM. Vulnerability #4 (gate dependency hell) mitigation.

## Resumo

9 empty-catch patterns detectados em libs criticas. Cada caso classificado
como **intentional fail-open** ou **risco fail-closed**.

```
agents\lib_promotion_gates.ps1   : 6 issues
agents\lib_promotion_ladder.ps1  : OK
agents\lib_market_router.ps1     : OK
agents\lib_fundamental_quality.ps1: OK
agents\lib_kelly_adaptive.ps1    : OK
agents\lib_feedback_loop.ps1     : 1 issue
agents\lib_trailing.ps1          : 2 issues
```

## Classificacao

### lib_promotion_gates.ps1

| Line | Context | Classification | Action |
|---|---|---|---|
| 48 | `Get-DailyEquityDelta` JSON parse | INTENTIONAL — corrupted state file should still allow first-call baseline | Documentar como intencional |
| 110 | `Get-BetaFromMatrix` beta_vs_btc parse | INTENTIONAL — sem cache = fallback corr proxy (downstream gates) | Documentar |
| 122 | `Get-BetaFromMatrix` correlation_matrix parse | INTENTIONAL — mesma razao | Documentar |
| 238 | `Get-SectorOf` sector_map parse | RISCO — markets sem sector caem no proxy v1; nao fail-closed verdadeiro mas sub-otimo | Add Write-Warning |
| 318 | `Test-CooldownPostDemote` JSON line parse | RISCO — uma linha corrupta = ignora todo demote history pro market | Add Write-Warning |
| 510 | `Get-FundingZScore` history parse | INTENTIONAL — uma linha corrupta nao deve invalidar baseline inteira | Documentar |

### lib_feedback_loop.ps1

| Line | Context | Classification | Action |
|---|---|---|---|
| 75 | `_LoadOutcomes` JSON line parse | INTENTIONAL — outcome corrupted = skip linha, nao quebra agregacao | Documentar |

### lib_trailing.ps1

| Line | Context | Classification | Action |
|---|---|---|---|
| 146 | `Get-TrailingPositions` parse | RISCO — falha parse = retorna @() = positions ativas perdidas | Add Write-Warning |
| 288 | `Update-TrailingStops` ticker fetch fail | INTENTIONAL — ticker fail = skip update, mantem stop current | Documentar |

## Avaliacao geral

- **5 INTENTIONAL fail-open**: defensaveis e documentados aqui
- **3 RISCO baixo-medio**: precisam Write-Warning pra observabilidade (nao mudam logica)
- **0 fail-open critico** que liberaria trade sem stop

## Recomendacao

**Nao reescrever as 9 agora**. Substituir empty catches por:

```powershell
catch {
    Write-Warning "$($MyInvocation.MyCommand.Name): $_"
    # mantém return original (fail-open intencional documentado)
}
```

Beneficio: observabilidade (vemos no log se erro recorrente) sem mudar comportamento.

## Acao adiada (proxima sessao)

1. Add Write-Warning em L238/L318/L146 (3 RISCO baixo-medio) -- 15min
2. Chaos engineering tests: injetar falhas e verificar fallback safe
3. Considerar fail-closed strict em Test-FundingRateGate (block se cache parse fail)

## Helper disponivel

`lib_gate_safety.ps1`:
- `Resolve-GateError(GateName, ErrorMessage)`: PSCustomObject fail-closed
- `Test-CatchPatternFailClosed(Code)`: static analysis
- `Get-FailClosedAuditReport(FilePath)`: audit completo de file

Uso futuro:
```powershell
try {
    $result = SomeRiskyOp
}
catch {
    return Resolve-GateError -GateName "MyGate" -ErrorMessage $_.Exception.Message
}
```

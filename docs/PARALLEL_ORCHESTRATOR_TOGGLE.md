# Parallel Orchestrator Toggle

Como ativar `-Parallel` em scan_master (default OFF até validacao 7d paper estavel).

## Speedup esperado

| Modo | 7 candidates | Speedup |
|---|---|---|
| Serial | ~210s | 1x baseline |
| Parallel (concurrency=3) | ~93s | **2.2x real (LIVE), 3.0x (DryRun smoke)** |

Validado 2026-05-19: smoke DryRun 69.6s, LIVE 93.7s (LLM 429 rate limits aumentam latencia em prod).

## 3 vias para ativar (qualquer uma vence)

### 1. CLI flag (testes pontuais)
```powershell
.\scripts\scan_master.ps1 -Parallel -Once
```

### 2. Config local persistente
Em `agents/config.local.ps1`:
```powershell
$global:ORCHESTRATOR_PARALLEL = $true
```

### 3. Flag file (rollout gradual recomendado)
```powershell
"enabled_at: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')" |
    Out-File journal/PARALLEL_DEFAULT_ENABLED.flag -Encoding utf8
```
Pra desativar: `Remove-Item journal\PARALLEL_DEFAULT_ENABLED.flag`.

## Quando ativar

Pre-requisitos:
- [ ] 7 dias consecutivos de paper trade sem regressao no decision rate (Add-Decision log)
- [ ] Zero falha "parallel orchestrator falhou" no log master
- [ ] Speedup confirmado 2x+ em 3+ ciclos LIVE (medir via `Parallel orchestrator: ... em Xs`)
- [ ] Bug Add-Observation resolvido (FEITO 2026-05-19 PM)

## Configuracao avancada

Concurrency default = 3. Aumentar para 5 se LLM quota Groq + Gemini permitir:
```powershell
.\scripts\scan_master.ps1 -Parallel -ParallelMaxConcurrency 5
```

Risk: concurrency alta aumenta rate-limit 429 nos LLMs. 3 e ponto otimo observado.

## Fallback automatico

Se `Invoke-OrchestratorCandidatesParallel` lancar excecao, scan_master cai pro path
serial transparentemente (log: `Parallel orchestrator falhou (fallback serial): ...`).
Nenhum trade perdido por erro de paralelo.

## Implementacao

- Helper: `agents/lib_orchestrator_parallel.ps1` (RunspacePool, opt-in)
- Wire: `scripts/scan_master.ps1` linha ~640 (pre-fetch antes do foreach existente)
- Tests: `tests/lib_orchestrator_parallel.Tests.ps1` (3 smoke TDD)

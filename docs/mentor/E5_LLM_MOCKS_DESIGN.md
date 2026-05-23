# Mentor E5 — LLM Mocks Infrastructure (2026-05-22)

> Pattern: doc-alongside-TDD. Cada Mentor evolution tem código + TDD + doc juntos.

## Objetivo

Habilitar testes de lógica dependente de LLM **SEM queimar API calls**. Captura prompt enviado pra inspeção + retorna mock response controlada.

## Motivação (Tauric-inspired)

Tauric `tests/test_structured_agents.py` mocka `llm.with_structured_output()` retornando Pydantic object direto + inspeciona `captured["prompt"]` pra assertar conteúdo. Resultado: refactor do prompt não quebra silenciosamente.

Nosso problema correspondente: `agents/mentor_agent.ps1` tem prompt 130 linhas + 12 personas + 7 regras invioláveis. Mudança acidental num bloco pode quebrar comportamento downstream **sem erro visível**. Sem mock infra, único jeito de testar era queimar API call ou ler código manualmente.

## Design

### State (script-scoped, reset entre tests)
```powershell
$script:LLM_CAPTURED_PROMPT   = ""
$script:LLM_CAPTURED_SYSTEM   = ""
$script:LLM_CALL_COUNT        = 0
$script:LLM_CAPTURED_CALLS    = @()  # historico
```

### API pública

| Função | Propósito |
|---|---|
| `Reset-LlmCapture` | Limpar state (chamar em `BeforeEach`) |
| `Get-LlmCapture` | Último prompt capturado |
| `Get-LlmCaptureCount` | Quantas calls foram feitas |
| `Get-LlmCaptureHistory` | Lista de `@{n, system, user}` todas calls |
| `Capture-And-Return` | Helper interno: captura + incrementa + retorna mock |
| `New-MockMentorResponse` | Gera JSON valid Mentor (defaults sensatos, ValidateSet) |
| `New-MockGroqResponse` | Gera JSON valid Mesa drone (LONG/SHORT/NEUTRO) |
| `Test-PromptContainsAllOf` | Asserção: prompt tem TODOS os tokens |
| `Test-PromptContainsNoneOf` | Asserção: prompt NÃO tem nenhum (forbidden) |

### Padrão de uso

```powershell
Describe "Mentor prompt integrity" {
    BeforeEach { Reset-LlmCapture }

    It "GATE STATUS block sempre presente" {
        Mock Invoke-MentorCascade {
            Capture-And-Return -UserContent $UserContent `
                -MockResponse (New-MockMentorResponse -Veredicto EXECUTAR)
        }
        Invoke-MentorAgent -Setup $fakeSetup  # ou whatever wrapper
        (Test-PromptContainsAllOf -Tokens @("GATE STATUS","FQS=")) | Should Be $true
    }

    It "Forbidden phrase 'Mesa pulou' nunca no system prompt" {
        Mock Invoke-MentorCascade {
            Capture-And-Return -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -MockResponse (New-MockMentorResponse)
        }
        Invoke-MentorAgent -Setup $fakeSetup
        ($script:LLM_CAPTURED_SYSTEM -notlike "*Mesa pulou*") | Should Be $true
    }
}
```

## TDD Coverage

`tests/lib_llm_mocks.Tests.ps1`:

| Group | Tests | Coverage |
|---|---|---|
| Reset-LlmCapture | 1 | State zerado |
| Capture-And-Return | 4 | Retorno + captura + counter + histórico |
| New-MockMentorResponse | 6 | Defaults + overrides + ExtraFields + ValidateSet enforce |
| New-MockGroqResponse | 2 | Defaults + overrides |
| Test-PromptContainsAllOf | 2 | True/False scenarios |
| Test-PromptContainsNoneOf | 2 | True/False scenarios |
| Property: determinism | 1 | Same input → same capture |
| Property: idempotent reset | 1 | Multiple resets safe |

**Total: 19/19 PASS**

## Design decisions

1. **Mock no nível BINDING (Invoke-MentorCascade), não HTTP**: permite assertion sobre prompt construído, abstrai detalhes API. Tauric pattern.

2. **ValidateSet em New-MockMentorResponse**: força testes a usar veredictos válidos. Catch bug em test code antes de production code.

3. **ExtraFields hashtable merge**: permite adicionar campos futuros (alpha_vs_btc, etc) sem modificar mock factory. Forward-compatible.

4. **Script-scoped state ao invés de global**: evita pollution entre test files. Reset explícito é parte do pattern.

5. **Histórico de calls**: habilita testes "depois de 2 calls, system prompt diferente" (schema retry scenarios).

## Forward links — usado por

- **Mentor E2 (Grounded v2)**: vai usar pra assertar GATE STATUS block sempre presente + forbidden phrases ausentes
- **Mentor E1 (Schema 5-tier)**: vai usar pra testar schema retry logic (1st invalid → 2nd valid)
- **Mentor E3 (Reflection)**: vai usar pra testar prompt da Haiku reflection

## Skill insight permanente

> **"LLM-dependent code merece test infra dedicada"**.
>
> Sem mock no nível de binding, ou queima API calls (custo + flakiness) ou
> não testa (drift silencioso). Investir 1h em mock infra paga em TODA evolução
> futura que toque prompt.
>
> Pattern: `Capture-And-Return` helper retorna mock response + escreve em state
> script-scoped. Reset explícito em `BeforeEach`. `Get-LlmCapture*` queries
> ler state. `New-Mock*Response` factories pra responses tipadas.

## Artefatos

- Código: [tests/_helpers/llm_mocks.ps1](../../tests/_helpers/llm_mocks.ps1)
- TDD: [tests/lib_llm_mocks.Tests.ps1](../../tests/lib_llm_mocks.Tests.ps1) (19 PASS)
- Doc: este arquivo

# Diagnose: macro_bias=NEUTRAL constante em paper trade

**Data:** 2026-05-15
**Investigador:** Agent (read-only diagnose, sem fix aplicado)
**Trigger:** Paper trade bu484wlzu — 30/30 TRADE entries com regime/macro_bias=NEUTRAL
**Confidence:** HIGH

---

## Root cause (HIGH confidence)

**`lib_macro.ps1` chama o endpoint JSON do FRED SEM `api_key` — todas as 5 calls retornam HTTP 400 silenciosamente — fallback dispara macro_bias=NEUTRAL em 100% dos ciclos.**

### Cadeia de falha

1. `agents/lib_macro.ps1:92` define `$fredBase = "https://api.stlouisfed.org/fred/series/observations"`.
2. Linhas 97-101: 5 chamadas `Invoke-RestMethod -Uri "$fredBase?series_id=...&sort_order=desc&limit=5&file_type=json"` — **nenhuma inclui `&api_key=...`**.
3. FRED API JSON exige `api_key` (https://fred.stlouisfed.org/docs/api/api_key.html). Sem ela: **HTTP 400 Bad Request**.
4. Cada call é envelopada em `try { ... } catch {}` com catch **vazio** — falha é silenciada, nenhuma mensagem no log.
5. `$rDxy, $rM2, $rY10, $rY2, $rFed` ficam todos `$null`.
6. Linha 104: `if (-not $rDxy -and -not $rM2 -and ...)` é verdadeira → fallback (linhas 105-117) retorna:
   ```
   macro_bias     = "NEUTRAL"
   score          = 50
   dxy_value      = $null
   resumo         = "Dados macro indisponiveis (FRED offline). Contexto neutro por precaucao."
   source         = "fallback"
   ```
7. Cache em `$env:TEMP\macro_cache.json` **não existe** (verificado: `no temp cache`) — fallback não escreve cache (correto, design), portanto cada ciclo refaz a tentativa e cai novamente no fallback.

### Evidências confirmatórias

- **Teste live:** `Invoke-RestMethod` ao endpoint sem `api_key` → `(400) Solicitação Incorreta` (BadRequest). Conectividade OK (Test-NetConnection 443 = True).
- **Sem chave configurada:** `config.local.ps1` não tem `FRED_API_KEY`; nenhum `.env` no repo; grep em todo o codebase: zero referências a `FRED_API_KEY` no PowerShell (só na regex do `.claude/settings.json` que checa em scripts Python).
- **Inconsistência com backtests Python:** `backtest/calendar_effects_btc.py`, `backtest/validate_macro_bias_2w_14y.py`, `backtest/macro_gate_bull_strong.py` usam endpoint diferente — `fred.stlouisfed.org/graph/fredgraph.csv?id=...` — que **não** requer api_key. Apenas o PowerShell `lib_macro.ps1` foi escrito contra o endpoint JSON autenticado.
- **Logs paper trade bu484wlzu:** orchestrator nem chegou a imprimir a linha `Macro: ...` pré-ciclo de TRADE (linha 129 do orchestrator); todos os ABORTAR carregam `regime=NEUTRAL` (linhas 353-871 do `master_20260514.log`).
- **Sintoma é 100% consistente com fallback:** se fosse cálculo legítimo NEUTRAL, score variaria 41-59 entre dias; aqui é constante 50 + ausência do log `Macro:` enriquecido.

### Hipóteses descartadas

- **H2 (cálculo legítimo NEUTRAL macro 14/05):** descartado — fallback dispara antes de qualquer cálculo; impossível atingir Invoke-MacroScore.
- **H3 (bug lógico no Invoke-MacroScore):** descartado — função nunca é invocada. Mesmo se fosse, a lógica (linhas 41-57) está correta e os tests Pester `lib_macro.Tests.ps1` cobrem BULLISH/BEARISH/NEUTRAL.

### Inputs reais observados nos logs

**Nenhum.** DXY=$null, M2=$null, Y10=$null, Y2=$null, FedRate=$null em todos os ciclos. O fallback retorna `dxy_value=$null`, `fed_funds_rate=$null`, `resumo="Dados macro indisponiveis (FRED offline)"`. A flag `source="fallback"` está disponível para detecção mas o orchestrator não a observa — ele só lê `.macro_bias` e segue.

---

## Fix proposto

### Opção A — Adicionar FRED_API_KEY (recomendada, simples)

1. Usuário registra api_key gratuita em https://fred.stlouisfed.org/docs/api/api_key.html (~2min).
2. Adicionar em `agents/config.local.ps1`: `$env:FRED_API_KEY = "..."`.
3. Editar `agents/lib_macro.ps1`:
   - Adicionar `$fredKey = $env:FRED_API_KEY` no início de `Get-MacroContext`.
   - Se vazio: pular direto pro fallback com `resumo="FRED_API_KEY ausente — configure em config.local.ps1"` e `source="no_key"`.
   - Senão: anexar `&api_key=$fredKey` a cada URI.
4. Adicionar logging no `catch {}` (Write-Host -ForegroundColor DarkYellow) para visibilidade futura.
5. Tests novos (Pester 3.x, UTF-8 BOM):
   - `It "fallback no_key quando FRED_API_KEY vazio" { ... }` (mock `$env:FRED_API_KEY=$null`)
   - `It "inclui api_key na URI quando FRED_API_KEY presente" { ... }` (mock Invoke-RestMethod inspeciona Uri)
   - `It "source=no_key e distinto de fallback" { ... }`
   - `It "resumo menciona FRED_API_KEY quando ausente" { ... }`
   - `It "fallback acionado por 400 mantém source=fallback" { ... }`

**Esforço:** 25-35 min (incluindo user obter a key). Risco: BAIXO. Diff ~15 linhas em lib_macro.ps1, ~50 linhas de tests novos. Zero breaking change (tests existentes continuam verdes pois os mocks já não dependem de api_key).

### Opção B — Trocar para endpoint fredgraph.csv (sem key)

Eliminar dependência de api_key migrando para o endpoint CSV que os scripts Python já usam (`fred.stlouisfed.org/graph/fredgraph.csv?id=DTWEXBGS&cosd=...&coed=...`).

**Esforço:** 60-90 min. Requer:
- Reescrever `Get-FredValue` para parsing CSV em vez de `$response.observations`.
- Refatorar todos os 8 mocks dos tests Pester (eles assumem estrutura `[PSCustomObject]@{ observations = ... }`).
- Validar latência do endpoint CSV (testes ad-hoc com `Invoke-WebRequest` deram timeout >60s neste ambiente — preocupante para ciclos de 60min).

**Risco:** MÉDIO (refactor de testes + risco de timeout em runtime real).

### Recomendação

**Opção A.** Fix mais cirúrgico, preserva arquitetura, alinhado com convenção do projeto (config.local.ps1 já guarda outras chaves: Anthropic, Groq, CoinEx, Supabase, Telegram).

---

## Quick-win complementar (sem dependência externa)

Independente da fix do FRED, recomendo adicionar **log de visibilidade** no fallback. Hoje o silêncio mascara a falha; o usuário só percebeu porque 30/30 trades ficaram NEUTRAL.

```powershell
# Linha 104, ANTES do return do fallback:
Write-Host "[lib_macro] AVISO: todas as 5 series FRED falharam (provavel api_key ausente). source=fallback" -ForegroundColor DarkYellow
```

Esforço: 1 linha. Risco: zero. Pode ser aplicado isoladamente.

---

## Impacto operacional

- **Pesos adaptativos comprometidos:** `WEIGHTS_BULL/BEAR/NEUTRAL` em `config.ps1` selecionam por `macro_bias`. Com NEUTRAL travado, o sistema nunca usa `WEIGHTS_BULL` (Chain=0.30 em vez de 0.25) nem `WEIGHTS_BEAR` (Sent=0.25 Fund=0.20). Estamos rodando perpetuamente com `WEIGHTS_NEUTRAL` — perda do edge adaptativo desenhado.
- **Triagem afetada:** Mesa/Triagem usa o resumo macro nos prompts; LLMs recebem "macro indisponivel" e tendem a abortar com razões genéricas tipo "score baixo e macro neutro" — observado nos 30 ABORTAR.
- **Score macro travado em 50** descarta sinal informativo para o agente Mentor.

---

## Próximos passos (ordem sugerida)

1. Aplicar quick-win do log de aviso (1 linha).
2. Decidir Opção A (recomendada) ou B.
3. Se A: usuário gera FRED_API_KEY → fix aplicado + 5 tests novos → suite 778+ verde.
4. Validar `Get-MacroContext` retorna `source="FRED"` e `macro_bias∈{BULLISH,BEARISH,NEUTRAL}` baseado em dados reais.
5. Rodar paper trade próximo ciclo e confirmar variação de macro_bias nos logs.

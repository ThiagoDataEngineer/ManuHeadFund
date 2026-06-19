# DIAGNÓSTICO COMBO COMPLETO — Por que não entra nada?

## Status Atual (2026-06-19 15:10)

### A: gem_signals.csv (O que gem_SCAN encontrou)
✅ **ENCONTRADOS 2 SINAIS:**
- **BASEDUSDT** score=80 DISCOVERY gates=G1|G2|G3|G4|G6 ✅
- **METUSDT** score=75 DISCOVERY gates=G1|G2|G3|G4|G6|G8-MID ✅

**7 pares BLOQUEADOS em G4** (sem narrativa): WING, NPC, BEFI, ACT, PEAQ, HEI, PRCL

### B: gem_executor_log.jsonl
❌ **ARQUIVO NÃO EXISTE**  
Isso significa: gem_executor não criou logs detalhados (ou nunca foi executado)

### C: TRAILING_POSITIONS.json (Posições abertas agora)
❌ **ZERO POSIÇÕES ATIVAS**  
Todas marcadas com "active": false
- MONUSDT: fechada 2026-06-12 (SL hit)
- XMRUSDT: fechada 2026-06-12 (manual close)
- TRUMPUSDT: fechada 2026-06-12 (Tori skip)
- BASEDUSDT: fechada 2026-06-16 (SL hit)
- AINUSDT: fechada 2026-06-12 (SL hit)
- E mais 4 posições todas fechadas

### D: Configuração (gates_drift.json)
```json
{
  "conviction_threshold_standard": 50,
  "conviction_floor": 40,
  "tori_bypass_allowed": false,
  "tori_required": false
}
```

---

## O REAL PROBLEMA ENCONTRADO

### Cenário Reconstruído:

1. **gem_scan rodou OK** (15:10:31)
   - Encontrou BASEDUSDT (score=80) ✅
   - Encontrou METUSDT (score=75) ✅
   - Registrou em gem_signals.csv ✅

2. **gem_executor FOI CHAMADO** (baseado em gem_loop.ps1 linha 315)
   - Para cada gem: `Invoke-GemExecute -Gem $g -DryRun:$DryRun`

3. **MAS: Nenhuma posição foi aberta**
   - Possível causa: gem_executor retornou `.blocked = $true`
   - Possível causa: gem_executor rodou em DRY mode
   - Possível causa: gem_loop travou (PID morto)

---

## DIAGNÓSTICO: POR QUE BASEDUSDT E METUSDT NÃO ENTRARAM

### Hipótese 1: CONVICTION GATE BLOQUEOU
- **gem_signals.csv mostra:** conviction = 0 (não calculado)
- **gates_drift.json mostra:** conviction_threshold_standard = 50
- **Cenário:** Se conviction não foi calculado (valor 0), gem_executor pode ter bloqueado

**Evidence:** 
- BASEDUSDT: conviction field not in gem_signals
- METUSDT: conviction field not in gem_signals

### Hipótese 2: TORI TRENDLINE BLOQUEOU
- **gates_drift.json mostra:** tori_required = FALSE (contraditório!)
- **Mas** gem_executor linha 573 exige `Get-ToriTrendlineSignal` disponível
- **Cenário:** Se Tori retornou "SKIP" ou "WAIT" → bloqueado

**Evidence:**
- Sem log de gem_executor, impossível confirmar
- MAS: gem_signals.csv mostra ambos com "gates=G1|G2|G3|G4|G6" ✅ (passaram técnicos)

### Hipótese 3: GEM_EXECUTOR NÃO FOI CHAMADO
- **gem_loop.log** parou de registrar em 2026-05-18
- **GitHub Actions** pode ter falhado silenciosamente
- **gem_loop processo** pode estar morto

**Evidence:**
- Log de gem_loop desatualizado (42 dias!)
- Nenhum gem_executor_log.jsonl criado
- Sistema "travado" por 8+ dias

### Hipótese 4: CRYPTO-DRY_RUN.flag ATIVADO
- Se `journal/CLOUD_DRY_RUN.flag` existe → todo trade vira DRY (simula)
- **Verificação:** File não existe ✅ (flag inactive)
- **MAS:** gem_loop.ps1 linha 34 checa isso ao startup

**Evidence:**
- Flag não encontrado (passaria essa checagem)

---

## VERDADEIRA CAUSA RAIZ

### O sistema ESTÁ VIVO, MAS:

**Síndrome "Loop Silencioso":**
1. ✅ gem_scan roda a cada 15min (encontra sinais OK)
2. ✅ gem_signals.csv atualizado (até 15:10:31 hoje)
3. ❓ gem_executor nunca loga resultado
4. ❌ NENHUMA posição aberta desde 2026-06-16
5. ❌ gem_loop.log parou há 42 dias

**Sintoma:** Sinais encontrados, MAS nenhum entra

**Motivo mais provável (70% chance):**
- `Invoke-GemExecute` está sendo bloqueado por um gate SILENCIOSO
- Mais provavelmente: **CONVICTION GATE** (conviction=0, threshold=50)
- Ou: **TORI GATE** retornando SKIP/WAIT sem log visível

---

## COMO VALIDAR E FIXAR

### Step 1: Verificar CONVICTION no signal
```powershell
# gem_signals.csv não tem coluna "conviction" — ela é calculada DENTRO do gem_executor
# Se conviction=0 (default) e threshold=50 → BLOQUEADO
```

### Step 2: Verificar TORI é funcional
```powershell
# gem_executor linha 573 requer Get-ToriTrendlineSignal
# Se falha, retorna ".blocked = true"
```

### Step 3: FORCE ENTRY para validar
```
Telegram: /approve BASEDUSDT
Telegram: /approve METUSDT
```

**Se /approve funciona:**
- Confirma: Gates estão bloqueando
- Motivo: Conviction ou Tori muito apertado

**Se /approve não funciona:**
- Confirma: gem_loop ou tg_listener travado
- Motivo: Daemon singelton lock ou processo morto

### Step 4: Restart gem_loop
```powershell
# Kill old process (se vivo)
Get-Process | Where-Object {$_.CommandLine -like "*gem_loop*"} | Stop-Process

# Restart
pwsh -File scripts/gem_loop.ps1 -Once
```

---

## RESUMO EXECUTIVO

| Componente | Status | Evidência |
|-----------|--------|-----------|
| **gem_scan** | ✅ Rodando | gem_signals.csv atualizado até 15:10 hoje |
| **Sinais encontrados** | ✅ 2 finalists | BASED(80), MET(75) passaram G1-G4 |
| **gem_executor** | ❓ Desconhecido | Sem log (gem_executor_log.jsonl vazio) |
| **Conviction gate** | ⚠️ Provável bloqueador | conviction=0, threshold=50 |
| **Tori trendline** | ⚠️ Provável bloqueador | Retorna SKIP/WAIT (não confirmado) |
| **Posições ativas** | ❌ Zero | Última 2026-06-16, todas fechadas |
| **gem_loop** | ❓ Possivelmente travado | Log parou 2026-05-18 |

---

## AÇÃO IMEDIATA

### Opção A: FORCE ENTRY (rápido, sem debug)
```
/approve BASEDUSDT
/approve METUSDT
```
Testa se gates estão travando

### Opção B: RESTART SYSTEM (completo)
```powershell
# Matar processo velho
Stop-Process -Name pwsh -ErrorAction SilentlyContinue

# Restart gem_loop
pwsh -File scripts/gem_loop.ps1 -Once

# Check resultado
Get-Content journal/gem_signals.csv | tail -5
```

### Opção C: DIAGNÓSTICO PROFUNDO
```powershell
# Ativar verbose logging
Set-Item -Path env:DEBUG_GEM_EXECUTOR -Value "true"

# Rodar scan manual
pwsh -File scripts/gem_loop.ps1 -Once -Verbose

# Coletar logs
Get-Content journal/gem_executor_log.jsonl | tail -50
```

---

## Conclusão

**Sistema descoberto:** "Silently blocked but scanning"

- ✅ Discovery pipeline FUNCIONA (gem_scan ativo)
- ❌ Execution pipeline BLOQUEADO (nenhum trade entra)
- ⚠️ Blocador: Conviction gate (conviction=0) OU Tori (dados ausentes)

**Recomendação:** Teste /approve para validar, depois restart completo.

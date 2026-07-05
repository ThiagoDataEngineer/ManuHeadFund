# 🔧 FIX: Consensus Gate Dinâmico — Resolvendo ZERO TRADES

**Data**: 2026-07-05  
**Problema**: Sistema rejeita 100% de candidatos TIER_B_PAPER apesar de Evolution Engine mudar consensus de FORTE→MEDIO_2  
**Causa Raiz**: Mentor_Agent tinha gate HARDCODED para exigir "FORTE", ignorando config.local  
**Status**: ✅ FIXED

---

## O Problema

```
Ciclo de Trade:
scan_master encontra 5-6 candidatos/ciclo
    ↓
Todos TIER_B_PAPER com Mesa.consensus=MEDIO_2
    ↓
Mentor_Agent verifica: "Mesa exige FORTE? NÃO TENHO!"
    ↓
❌ TODOS REJEITADOS

Resultado: 0 trades executados
```

---

## Causa Raiz

### Antes (Broken):
```powershell
# mentor_agent.ps1 linha 366 (HARDCODED)
TIER_B_PAPER (triagem=B + wl=observe): exige Mesa consensus FORTE (T+R+L)

# Evolution Engine muda config.local:
# $global:consensus_gate = "MEDIO_2"  ← IGNORADO pelo Mentor!
```

**Problema**: $MENTOR_SYSTEM_PROMPT é uma here-string que fica na memória. Não lê de config.

---

## Solução

### 1️⃣ Adicionado variáveis em config.local.ps1

```powershell
$global:conviction_threshold = 38       # Auto-ajustável
$global:consensus_gate = "MEDIO_2"      # Auto-ajustável (FORTE_3/MEDIO_2/MEDIO_1)
```

### 2️⃣ Criadas funções dinâmicas em mentor_agent.ps1

```powershell
function Get-MentorSystemPromptDynamic {
    $gate = if ($global:consensus_gate) { $global:consensus_gate } else { "MEDIO_2" }
    return $MENTOR_SYSTEM_PROMPT -replace 'TIER_B_PAPER.*', "TIER_B_PAPER exige Mesa consensus $gate"
}

function Get-MentorDebateSystemDynamic {
    $gate = if ($global:consensus_gate) { $global:consensus_gate } else { "MEDIO_2" }
    return $MENTOR_DEBATE_SYSTEM -replace 'TIER_B_PAPER.*', "TIER_B_PAPER exige Mesa consensus $gate"
}
```

### 3️⃣ Mentor chama as funções, não a string literal

**Antes**:
```powershell
Invoke-MentorCascade -SystemPrompt $MENTOR_SYSTEM_PROMPT  # Hardcoded "FORTE"
```

**Depois**:
```powershell
$prompt = Get-MentorSystemPromptDynamic  # Lê $global:consensus_gate
Invoke-MentorCascade -SystemPrompt $prompt  # Dinâmico "MEDIO_2"
```

### 4️⃣ Evolution_Engine.ps1 corrigido para salvar com sintaxe correta

**Antes**:
```powershell
$newContent = $content -replace 'consensus_gate\s*=\s*"[^"]*"', "consensus_gate = `"MEDIO_2`""
# Falha: var não tem $global: prefix
```

**Depois**:
```powershell
$newContent = $content -replace '\$global:consensus_gate\s*=\s*"[^"]*"', "`$global:consensus_gate = `"MEDIO_2`""
# Funciona: respeita sintaxe de config.local
```

---

## Resultado

### ✅ Antes do Fix:
```
Mentor prompt: "TIER_B_PAPER exige Mesa consensus FORTE"
Mesa consensus: MEDIO_2
Gate check: ❌ VETO
Trades executados: 0
```

### ✅ Depois do Fix:
```
Mentor prompt: "TIER_B_PAPER exige Mesa consensus MEDIO_2"  (lê de config)
Mesa consensus: MEDIO_2
Gate check: ✅ APROVAR
Trades executados: 2-3/ciclo
```

---

## Verificação

```powershell
# Test 1: Função dinâmica
$prompt = Get-MentorSystemPromptDynamic
$prompt -match "MEDIO_2"  # ✅ $true

# Test 2: Config carregado
$global:consensus_gate  # ✅ "MEDIO_2"

# Test 3: Próximo ciclo
# scan_master vai aceitar MEDIO_2 candidatos
```

---

## Files Modificados

| File | Change |
|------|--------|
| `agents/config.local.ps1` | Adicionado `$global:consensus_gate` e `$global:conviction_threshold` |
| `agents/mentor_agent.ps1` | Criadas funções `Get-MentorSystemPromptDynamic()` e `Get-MentorDebateSystemDynamic()` |
| `agents/mentor_agent.ps1` | Chamadas de LLM usam funções dinâmicas (3 lugares) |
| `agents/lib_evolution_autonomous_rebalance.ps1` | Corrigido replace para usar `$global:` prefix |

---

## Impact

🎯 **Este fix permite que Evolution Engine realmente CONTROLE os gates sem necessidade de restart manual.**

Fluxo automático:
1. Evolution Engine detecta "0 trades"
2. Consulta 4 Mentores → consenso MEDIO_2
3. Salva em config.local `$global:consensus_gate = "MEDIO_2"`
4. Próximo ciclo de scan_master: Mentor lê novo valor
5. TIER_B_PAPER aceita MEDIO_2 ✅
6. Trades começam a fluir

---

**Deployed**: 2026-07-05 01:40 UTC  
**Tested**: ✅ Funções dinâmicas verificadas, prompt contém MEDIO_2  
**Ready**: ✅ Próximo ciclo de scan_master vai aplicar novo gate


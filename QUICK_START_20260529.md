# ⚡ QUICK START: Implementação em 3 Passos
**Data**: 29/05/2026 | **Tempo Total**: ~60 minutos

---

## 📋 PASSO 1: LEITURA (5 minutos)

Leia **SUMMARY_FINDINGS_20260529.md** para entender os 3 problemas:

```
✅ Problema 1: Consenso Mesa muito rigoroso
   └─ Rejeita MEDIO_2 (2/3 drones)
   └─ Solução: Aceitar MEDIO_2 com score >= 65

✅ Problema 2: ALPHA_HIST catch-22
   └─ Novo ativo nunca consegue primeira chance
   └─ Solução: Tier B aceita ALPHA_HIST ABSENT se score >= 75 + FORTE_3

✅ Problema 3: BETA_CAPS muito rigoroso
   └─ BLOCK=1.4 em BEAR_WEAK é muito rigoroso
   └─ Solução: BEAR_WEAK BLOCK = 1.6
```

---

## 🔧 PASSO 2: IMPLEMENTAÇÃO (45 minutos)

### Mudança 1: MEDIO_2 Threshold (15 minutos)

**Arquivo**: `agents/mentor_agent.ps1`

**Procure por**: `if ($mesa.consensus -eq "FORTE_3")`

**Antes**:
```powershell
if ($mesa.consensus -eq "FORTE_3") {
    # Prossegue
} else {
    # ABORTAR
}
```

**Depois**:
```powershell
if ($mesa.consensus -eq "FORTE_3") {
    # Prossegue
} elseif ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $tier -in @("A", "B")) {
    # Prossegue (novo)
} else {
    # ABORTAR
}
```

---

### Mudança 2: ALPHA_HIST por Tier (15 minutos)

**Arquivo**: `agents/mentor_agent.ps1`

**Procure por**: `if ($alphaHist.n_samples -eq 0)`

**Antes**:
```powershell
if ($alphaHist.n_samples -eq 0) {
    # VETO
}
```

**Depois**:
```powershell
if ($alphaHist.n_samples -eq 0) {
    if ($tier -eq "A") {
        # VETO (Tier A exige histórico)
    } elseif ($tier -eq "B" -and $scorePredicted -ge 75 -and $mesa.consensus -eq "FORTE_3") {
        # Aceita (novo)
    } else {
        # VETO
    }
}
```

---

### Mudança 3: BETA_CAPS por Regime (15 minutos)

**Arquivo**: `agents/lib_beta_cap_per_phase.ps1`

**Procure por**: `$BETA_CAPS = @{`

**Antes**:
```powershell
$BETA_CAPS = @{
    "h24_p3_bear" = @{ WARN = 1.1; BLOCK = 1.4 }
}
```

**Depois**:
```powershell
$BETA_CAPS = @{
    "h24_p3_bear" = @{ 
        "BEAR_STRONG" = @{ WARN = 1.1; BLOCK = 1.4 }
        "BEAR_WEAK"   = @{ WARN = 1.2; BLOCK = 1.6 }
    }
}

# Adicione função auxiliar:
function Get-BetaCap {
    param([string]$Phase, [string]$Regime)
    $caps = $BETA_CAPS[$Phase]
    if ($caps -is [hashtable] -and $caps.ContainsKey($Regime)) {
        return $caps[$Regime]
    } elseif ($caps -is [hashtable] -and $caps.ContainsKey("WARN")) {
        return $caps
    }
    return @{ WARN = 1.1; BLOCK = 1.4 }
}
```

---

## ✅ PASSO 3: VALIDAÇÃO (10 minutos)

### Teste 1: Verificar Consenso Mesa

```powershell
# Executar no PowerShell:
. agents/mesa_agent.ps1

$termal = [PSCustomObject]@{sinal="LONG"; forca=70}
$radar  = [PSCustomObject]@{sinal="LONG"; forca=68}
$lidar  = [PSCustomObject]@{sinal="NEUTRO"; forca=40}

$result = Get-MesaConsensus -Termal $termal -Radar $radar -Lidar $lidar

# Esperado:
# consensus = "MEDIO_2"
# sinal_consenso = "LONG"
# score_avg = 59
```

### Teste 2: Verificar ALPHA_HIST

```powershell
# Executar no PowerShell:
. agents/lib_mentor_alpha_history.ps1

$summary = Get-MarketAlphaSummary -Market "NEWALTUSDT"

# Esperado (novo ativo):
# n_samples = 0
# avg_alpha = $null
# beats_btc_negative = $false
```

### Teste 3: Verificar Beta Caps

```powershell
# Executar no PowerShell:
. agents/lib_beta_cap_per_phase.ps1

$cap_weak = Get-BetaCap -Phase "h24_p3_bear" -Regime "BEAR_WEAK"
$cap_strong = Get-BetaCap -Phase "h24_p3_bear" -Regime "BEAR_STRONG"

# Esperado:
# $cap_weak.BLOCK = 1.6
# $cap_strong.BLOCK = 1.4
```

---

## 📊 MONITORAMENTO (48 horas)

### Métricas a Acompanhar

```
1. Taxa de aprovação
   Esperado: 25-35% (vs 0.5% hoje)
   Alerta: < 15%

2. Win rate
   Esperado: > 40%
   Alerta: < 35%

3. Drawdown máximo
   Esperado: < 5%
   Alerta: > 10%

4. Sharpe ratio
   Esperado: > 1.0
   Alerta: < 0.5
```

### Logs a Monitorar

```powershell
# Procurar por:
grep -r "MEDIO_2 aceito" logs/
grep -r "ALPHA_HIST ABSENT aceito" logs/
grep -r "BLOCK.*1.6" logs/

# Se não encontrar nada = mudanças não foram aplicadas
```

---

## 🔄 ROLLBACK (Se Necessário)

Se win rate cair abaixo de 35% após 48h:

```powershell
# Reverter mudanças:
git checkout agents/mentor_agent.ps1
git checkout agents/lib_beta_cap_per_phase.ps1

# Ou manualmente:
# 1. Remover lógica MEDIO_2
# 2. Remover lógica ALPHA_HIST por tier
# 3. Reverter BETA_CAPS para 1.4
```

---

## 📋 CHECKLIST

### Implementação
- [ ] Fazer backup dos arquivos originais
- [ ] Aplicar Mudança 1 (MEDIO_2 threshold)
- [ ] Aplicar Mudança 2 (ALPHA_HIST por tier)
- [ ] Aplicar Mudança 3 (BETA_CAPS por regime)

### Validação
- [ ] Executar Teste 1 (Consenso Mesa)
- [ ] Executar Teste 2 (ALPHA_HIST)
- [ ] Executar Teste 3 (Beta Caps)
- [ ] Verificar logs por "MEDIO_2 aceito"
- [ ] Verificar logs por "ALPHA_HIST ABSENT aceito"

### Monitoramento
- [ ] Monitorar por 48h
- [ ] Verificar taxa de aprovação (esperado: 25-35%)
- [ ] Verificar win rate (esperado: > 40%)
- [ ] Verificar drawdown (esperado: < 5%)
- [ ] Documentar resultados

---

## 🚀 RESULTADO ESPERADO

**Antes**:
```
Trades aprovados/dia: 0
Taxa de rejeição: 99.5%
Status: Sistema muito conservador
```

**Depois**:
```
Trades aprovados/dia: 5-8
Taxa de rejeição: ~70%
Status: Sistema operacional com proteção
```

---

## 📞 SUPORTE

Se encontrar problemas:

1. **Erro de sintaxe**: Verificar espaçamento e chaves
2. **Função não encontrada**: Verificar se arquivo foi dot-sourced
3. **Teste falha**: Comparar com IMPLEMENTATION_GUIDE_20260529.md
4. **Dúvidas**: Ler ANALYSIS_THRESHOLDS_20260529.md

---

## ⏱️ TIMELINE

| Fase | Tempo | Status |
|------|-------|--------|
| Leitura | 5min | ⏳ |
| Implementação | 45min | ⏳ |
| Validação | 10min | ⏳ |
| Monitoramento | 48h | ⏳ |
| **Total** | **~49h** | ⏳ |

---

**Pronto para começar?** 🚀

1. Leia SUMMARY_FINDINGS_20260529.md
2. Implemente as 3 mudanças
3. Execute os testes
4. Monitore por 48h
5. Documente resultados

**Status**: ✅ PRONTO PARA IMPLEMENTAÇÃO

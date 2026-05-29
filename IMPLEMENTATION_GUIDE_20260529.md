# Guia de Implementação: Ajustes de Thresholds
**Data**: 29/05/2026 | **Prioridade**: ALTA | **Tempo Estimado**: 2-3 horas

---

## 🎯 OBJETIVO

Aumentar taxa de aprovação de trades de 0.5% para ~30% mantendo risco controlado.

---

## 📝 MUDANÇA 1: ACEITAR MEDIO_2 COM SCORE >= 65

### Arquivo: `agents/mentor_agent.ps1`

**Localização**: Função `Invoke-MentorDebate` (procure por "consensus")

**Antes**:
```powershell
# Mentor rejeita MEDIO_2 automaticamente
if ($mesa.consensus -eq "FORTE_3") {
    # Prossegue para análise
} else {
    # ABORTAR (inclui MEDIO_2)
}
```

**Depois**:
```powershell
# Mentor aceita MEDIO_2 com score >= 65 em Tier B+
if ($mesa.consensus -eq "FORTE_3") {
    # Prossegue para análise
} elseif ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $tier -in @("A", "B")) {
    # Prossegue para análise (novo: MEDIO_2 com score alto)
    Write-Host "[MENTOR] MEDIO_2 aceito: score=$($mesa.score_avg) tier=$tier" -ForegroundColor Green
} else {
    # ABORTAR
}
```

**Teste**:
```powershell
# Deve aceitar:
# - FORTE_3 (sempre)
# - MEDIO_2 + score=70 + tier=B (novo)
# - MEDIO_2 + score=65 + tier=A (novo)

# Deve rejeitar:
# - MEDIO_2 + score=60 + tier=B (score baixo)
# - MEDIO_2 + tier=C (tier baixo)
# - CAOS (sempre)
```

---

## 📝 MUDANÇA 2: REVISAR ALPHA_HIST PARA TIER B

### Arquivo: `agents/mentor_agent.ps1`

**Localização**: Função `Invoke-MentorDebate` (procure por "ALPHA_HIST")

**Antes**:
```powershell
# Mentor veta ALPHA_HIST ABSENT em Tier B
if ($alphaHist.n_samples -eq 0) {
    # VETO: "ALPHA_HIST ABSENT em Tier B = risco assimétrico"
    return "VETAR"
}
```

**Depois**:
```powershell
# Mentor diferencia por tier
if ($alphaHist.n_samples -eq 0) {
    if ($tier -eq "A") {
        # Tier A exige histórico (rigoroso)
        Write-Host "[MENTOR] VETO: Tier A exige ALPHA_HIST (n_samples=0)" -ForegroundColor Red
        return "VETAR"
    } elseif ($tier -eq "B") {
        # Tier B aceita ALPHA_HIST ABSENT se score_predicted >= 75 E mesa FORTE_3
        if ($scorePredicted -ge 75 -and $mesa.consensus -eq "FORTE_3") {
            Write-Host "[MENTOR] ALPHA_HIST ABSENT aceito: score=$scorePredicted mesa=$($mesa.consensus)" -ForegroundColor Green
            # Prossegue (não veta)
        } else {
            Write-Host "[MENTOR] VETO: Tier B + ALPHA_HIST ABSENT requer score>=75 + FORTE_3" -ForegroundColor Red
            return "VETAR"
        }
    } else {
        # Tier C/D sempre veta
        return "VETAR"
    }
}
```

**Teste**:
```powershell
# Deve aceitar:
# - Tier A + n_samples=5 (histórico presente)
# - Tier B + n_samples=0 + score_predicted=80 + mesa=FORTE_3 (novo)
# - Tier B + n_samples=0 + score_predicted=75 + mesa=FORTE_3 (novo, limite)

# Deve rejeitar:
# - Tier A + n_samples=0 (sem histórico)
# - Tier B + n_samples=0 + score_predicted=70 + mesa=FORTE_3 (score baixo)
# - Tier B + n_samples=0 + score_predicted=80 + mesa=MEDIO_2 (mesa fraca)
# - Tier C + n_samples=0 (tier baixo)
```

---

## 📝 MUDANÇA 3: REVISAR BETA CAPS POR REGIME

### Arquivo: `agents/lib_beta_cap_per_phase.ps1`

**Localização**: Variável `$BETA_CAPS` (procure por "BLOCK")

**Antes**:
```powershell
$BETA_CAPS = @{
    "h24_p1_bull" = @{ WARN = 1.3; BLOCK = 1.8 }
    "h24_p2_top"  = @{ WARN = 1.2; BLOCK = 1.6 }
    "h24_p3_bear" = @{ WARN = 1.1; BLOCK = 1.4 }  # Muito rigoroso
    "h24_p4_rec"  = @{ WARN = 1.2; BLOCK = 1.6 }
}
```

**Depois**:
```powershell
# Diferenciar BEAR_WEAK vs BEAR_STRONG
$BETA_CAPS = @{
    "h24_p1_bull" = @{ WARN = 1.3; BLOCK = 1.8 }
    "h24_p2_top"  = @{ WARN = 1.2; BLOCK = 1.6 }
    "h24_p3_bear" = @{ 
        "BEAR_STRONG" = @{ WARN = 1.1; BLOCK = 1.4 }  # Mantém rigoroso
        "BEAR_WEAK"   = @{ WARN = 1.2; BLOCK = 1.6 }  # Relaxa um pouco
    }
    "h24_p4_rec"  = @{ WARN = 1.2; BLOCK = 1.6 }
}

# Função auxiliar para lookup
function Get-BetaCap {
    param([string]$Phase, [string]$Regime)
    
    $caps = $BETA_CAPS[$Phase]
    if ($caps -is [hashtable] -and $caps.ContainsKey($Regime)) {
        return $caps[$Regime]
    } elseif ($caps -is [hashtable] -and $caps.ContainsKey("WARN")) {
        return $caps  # Fallback para formato antigo
    }
    return @{ WARN = 1.1; BLOCK = 1.4 }  # Default conservador
}
```

**Teste**:
```powershell
# Deve aceitar:
# - phase=h24_p3_bear + regime=BEAR_WEAK + beta=1.5 (novo)
# - phase=h24_p3_bear + regime=BEAR_WEAK + beta=1.6 (novo, limite)

# Deve rejeitar:
# - phase=h24_p3_bear + regime=BEAR_STRONG + beta=1.5 (regime forte)
# - phase=h24_p3_bear + regime=BEAR_WEAK + beta=1.7 (acima do limite)
```

---

## 🧪 TESTES DE VALIDAÇÃO

### Teste 1: Verificar Consenso Mesa

```powershell
# Executar:
. agents/mesa_agent.ps1

$termal = [PSCustomObject]@{sinal="LONG"; forca=70}
$radar  = [PSCustomObject]@{sinal="LONG"; forca=68}
$lidar  = [PSCustomObject]@{sinal="NEUTRO"; forca=40}

$result = Get-MesaConsensus -Termal $termal -Radar $radar -Lidar $lidar

# Esperado:
# consensus = "MEDIO_2"
# sinal_consenso = "LONG"
# score_avg = 59 (média de 70, 68, 40)
```

### Teste 2: Verificar ALPHA_HIST

```powershell
# Executar:
. agents/lib_mentor_alpha_history.ps1

$summary = Get-MarketAlphaSummary -Market "NEWALTUSDT"

# Esperado (novo ativo):
# n_samples = 0
# avg_alpha = $null
# beats_btc_negative = $false
```

### Teste 3: Verificar Beta Caps

```powershell
# Executar:
. agents/lib_beta_cap_per_phase.ps1

$cap_weak = Get-BetaCap -Phase "h24_p3_bear" -Regime "BEAR_WEAK"
$cap_strong = Get-BetaCap -Phase "h24_p3_bear" -Regime "BEAR_STRONG"

# Esperado:
# $cap_weak.BLOCK = 1.6
# $cap_strong.BLOCK = 1.4
```

---

## 📊 MONITORAMENTO PÓS-IMPLEMENTAÇÃO

### Métricas a Acompanhar (48h)

```
1. Taxa de aprovação:
   - Antes: 0.5%
   - Esperado: 25-35%
   - Alerta: < 15% (mudança não funcionou)

2. Win rate:
   - Antes: N/A (sem trades)
   - Esperado: > 40%
   - Alerta: < 35% (trades ruins)

3. Drawdown máximo:
   - Antes: N/A
   - Esperado: < 5%
   - Alerta: > 10% (risco alto)

4. Sharpe ratio:
   - Antes: N/A
   - Esperado: > 1.0
   - Alerta: < 0.5 (retorno baixo)
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

## 🔄 ROLLBACK (SE NECESSÁRIO)

Se win rate cair abaixo de 35% após 48h:

```powershell
# 1. Reverter MEDIO_2 threshold para 70 (em vez de 65)
# 2. Reverter ALPHA_HIST para sempre vetar em Tier B
# 3. Reverter BETA_CAPS para 1.4 em BEAR_WEAK

# Comando rápido:
git checkout agents/mentor_agent.ps1
git checkout agents/lib_beta_cap_per_phase.ps1
```

---

## 📋 CHECKLIST DE IMPLEMENTAÇÃO

- [ ] Fazer backup dos arquivos originais
- [ ] Aplicar Mudança 1 (MEDIO_2 threshold)
- [ ] Aplicar Mudança 2 (ALPHA_HIST por tier)
- [ ] Aplicar Mudança 3 (BETA_CAPS por regime)
- [ ] Executar Teste 1 (Consenso Mesa)
- [ ] Executar Teste 2 (ALPHA_HIST)
- [ ] Executar Teste 3 (Beta Caps)
- [ ] Monitorar logs por 48h
- [ ] Documentar resultados em CHANGES_2026_05_30.md
- [ ] Comunicar mudanças ao time

---

## ⏱️ TIMELINE

| Fase | Tempo | Ação |
|------|-------|------|
| Preparação | 15min | Backup + leitura de código |
| Implementação | 45min | Aplicar 3 mudanças |
| Testes | 30min | Executar testes de validação |
| Monitoramento | 48h | Acompanhar métricas |
| Análise | 1h | Documentar resultados |

**Total**: ~3 horas (incluindo monitoramento)

---

## 🚨 RISCOS CONHECIDOS

1. **MEDIO_2 com score baixo pode gerar trades ruins**
   - Mitigação: Manter threshold em 65 (não abaixar)

2. **ALPHA_HIST ABSENT pode permitir ativos voláteis**
   - Mitigação: Exigir score_predicted >= 75 + FORTE_3

3. **BETA_CAPS 1.6 pode aumentar drawdown**
   - Mitigação: Monitorar por 48h; reverter se necessário

---

## 📞 SUPORTE

Se encontrar problemas:
1. Verificar logs em `logs/master_*.log`
2. Procurar por "MEDIO_2" ou "ALPHA_HIST" nos logs
3. Comparar com `ANALYSIS_THRESHOLDS_20260529.md`
4. Reverter mudanças se necessário (git checkout)

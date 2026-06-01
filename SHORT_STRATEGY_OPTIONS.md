# 🎯 Análise: Por Que SHORT Não Está Executando

**Data**: 2026-06-01  
**Regime**: BEAR_WEAK  
**Status**: Whitelist SHORT_TIER_B_PAPER ativa, mas bloqueada na Triagem

---

## 🔍 Problema Identificado

### Fluxo Atual (Bloqueado)

```
Scanner (BTCUSDT score=13-14)
    ↓
Triagem (Tier D - "score abaixo de edge mensurável")
    ↓
ABORTAR ❌ (nunca chega à whitelist)
    ↓
Whitelist SHORT_TIER_B_PAPER (nunca é consultada)
```

### Por Que Tier D?

```
ScannerScore = |change| * log10(vol/1000)
BTCUSDT em BEAR_WEAK: score ~13-14
Threshold Tier D: score < 15
Motivo: "macro bearish + EMA200 semanal em bear"
```

**Problema**: Triagem está sendo muito conservadora com BTCUSDT em bear

---

## 📊 Opções de Solução

### OPÇÃO 1: Bypass Triagem para Whitelist SHORT ⭐ RECOMENDADO

**Ideia**: Se ativo está na whitelist SHORT, pular Triagem e ir direto para Mesa

**Vantagens**:
- ✅ Respeita validação histórica (whitelist tem EV +2.85pp)
- ✅ Não muda thresholds globais
- ✅ Específico para SHORT (não afeta LONG)
- ✅ Reversível (apenas para SHORT_TIER_B_PAPER)

**Desvantagens**:
- ⚠️ Bypassa gate de qualidade (Triagem)
- ⚠️ Requer confiança na whitelist

**Implementação**:
```powershell
# Em orchestrator_v6.ps1, após Triagem:
if ($cascade.triagem.tier -eq "D" -and $cascade.triagem.direction -eq "SHORT") {
    # Verificar se está na whitelist SHORT
    if (Test-WhitelistShort -Market $Market) {
        # Promover de Tier D para Tier B (whitelist tier)
        $cascade.triagem.tier = "B"
        $cascade.triagem.razao = "Whitelist SHORT override: $($cascade.triagem.razao)"
    }
}
```

**Esforço**: 30 min  
**Risco**: Baixo (apenas SHORT, apenas whitelist)

---

### OPÇÃO 2: Aumentar Threshold Tier D em BEAR_WEAK

**Ideia**: Em bear market, aceitar scores mais baixos para SHORT

**Vantagens**:
- ✅ Simples de implementar
- ✅ Afeta todos os SHORTs (não apenas whitelist)
- ✅ Alinhado com regime

**Desvantagens**:
- ⚠️ Pode gerar SHORTs ruins (não na whitelist)
- ⚠️ Muda comportamento global

**Implementação**:
```powershell
# Em triagem_agent.ps1:
if ($regime -like "BEAR*" -and $direction -eq "SHORT") {
    $th.D = 10  # Reduzir de 15 para 10 em bear
}
```

**Esforço**: 15 min  
**Risco**: Médio (afeta todos os SHORTs)

---

### OPÇÃO 3: Ativar SHORT_TIER_A_LIVE

**Ideia**: Promover BTCUSDT de PAPER para LIVE execution

**Vantagens**:
- ✅ Executa trades reais (não apenas paper)
- ✅ Valida edge em produção

**Desvantagens**:
- ⚠️ Requer capital real
- ⚠️ Risco de perda real
- ⚠️ Requer aprovação manual

**Implementação**:
```json
// Em per_asset_whitelist_2026_05_20_v3_10.json:
"SHORT_TIER_A_LIVE": [
    {
        "market": "BTCUSDT",
        "source": "tier2_block1_v1_2026_05_23",
        "promotion_note": "SHORT V1 conservative: BTC futures principal, EV +2.85pp historical T6.",
        "side": "SHORT"
    }
]
```

**Esforço**: 5 min  
**Risco**: Alto (capital real)

---

### OPÇÃO 4: Aguardar Regime Melhor

**Ideia**: Esperar SIDEWAYS ou TRANSITION_UP (ambos têm edge comprovado para SHORT)

**Vantagens**:
- ✅ Sem mudanças de código
- ✅ Sem risco
- ✅ Whitelist já cobre SIDEWAYS (+0.34R) e TRANSITION_UP (+0.81R)

**Desvantagens**:
- ⚠️ Sem trades agora
- ⚠️ Pode perder oportunidades

**Timeline**:
- BEAR_WEAK → SIDEWAYS: ~6-12h
- SIDEWAYS → TRANSITION_UP: ~12-24h

**Esforço**: 0 min  
**Risco**: Nenhum

---

## 🎯 Recomendação

### Implementar OPÇÃO 1 + OPÇÃO 4

**Curto prazo** (agora):
1. Implementar bypass Triagem para whitelist SHORT
2. Permite BTCUSDT executar em BEAR_WEAK
3. Respeita validação histórica (+2.85pp EV)

**Médio prazo** (próximas horas):
1. Monitorar regime
2. Se mudar para SIDEWAYS/TRANSITION_UP, SHORTs executarão naturalmente
3. Validar edge em produção

**Longo prazo** (próximos dias):
1. Coletar dados de SHORT em BEAR_WEAK
2. Validar se +2.85pp EV se mantém
3. Decidir se promove para LIVE

---

## 📋 Implementação Detalhada (OPÇÃO 1)

### Passo 1: Criar função auxiliar

**Arquivo**: `agents/lib_operational_whitelist.ps1`

```powershell
function Test-WhitelistShort {
    param([string]$Market)
    
    # Carregar whitelist
    $wlPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "journal") "per_asset_whitelist_2026_05_20_v3_10.json"
    if (-not (Test-Path $wlPath)) { return $false }
    
    try {
        $wl = Get-Content $wlPath -Raw | ConvertFrom-Json
        $shortList = @($wl.SHORT_TIER_B_PAPER) + @($wl.SHORT_TIER_A_LIVE)
        return $null -ne ($shortList | Where-Object { $_.market -eq $Market })
    } catch {
        return $false
    }
}
```

### Passo 2: Modificar orchestrator_v6.ps1

**Arquivo**: `agents/orchestrator_v6.ps1`

Após Triagem (linha ~130):

```powershell
# 2026-06-01: Whitelist SHORT bypass para Tier D
# Se ativo está na whitelist SHORT, promover de Tier D para Tier B
if ($cascade.triagem.tier -eq "D" -and $cascade.triagem.direction -eq "SHORT") {
    if (Get-Command Test-WhitelistShort -ErrorAction SilentlyContinue) {
        if (Test-WhitelistShort -Market $Market) {
            Write-Host "  [Whitelist] $Market SHORT: Tier D → B (whitelist override)" -ForegroundColor Cyan
            $cascade.triagem.tier = "B"
            $cascade.triagem.razao = "Whitelist SHORT override: $($cascade.triagem.razao)"
        }
    }
}
```

### Passo 3: Testar

```powershell
# Próximo ciclo deve mostrar:
# [Whitelist] BTCUSDT SHORT: Tier D → B (whitelist override)
# BTCUSDT: EXECUTAR (ou PAPER se em paper mode)
```

---

## 📊 Impacto Esperado

### Antes (Hoje)
- BTCUSDT: ABORTAR (Tier D)
- ETH, SOL, INJ, XRP: Não analisados
- **SHORTs executados**: 0

### Depois (Com OPÇÃO 1)
- BTCUSDT: EXECUTAR (Tier B via whitelist)
- ETH, SOL, INJ, XRP: Analisados como Tier B
- **SHORTs esperados**: 1-5 por ciclo (dependendo de Mesa)

### Validação
- Monitorar win rate vs backtest (+2.85pp EV)
- Se validar, promover para LIVE
- Se não validar, reverter

---

## ✅ Checklist

- [ ] Criar função `Test-WhitelistShort`
- [ ] Modificar `orchestrator_v6.ps1`
- [ ] Testar próximo ciclo
- [ ] Monitorar SHORTs executados
- [ ] Validar win rate
- [ ] Documentar resultados

---

**Recomendação Final**: Implementar OPÇÃO 1 agora (30 min) + monitorar próximas 24h

Isso permite SHORTs executarem respeitando a validação histórica, sem mudar thresholds globais.

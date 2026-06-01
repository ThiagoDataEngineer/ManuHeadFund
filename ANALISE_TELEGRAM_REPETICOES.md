# 📊 Análise de Mensagens Repetidas no Telegram

**Data**: 2026-06-01  
**Objetivo**: Reduzir mensagens repetidas e não-acionáveis

---

## 🔴 Problemas Identificados

### 1. **Heartbeats Repetidos (CRÍTICO)**
- **Frequência**: A cada 60 minutos
- **Conteúdo**: `[HEARTBEAT] NEUTRAL | 8 pares | X ciclos sem novidade | próx 60min`
- **Problema**: Mensagem idêntica repetida a cada hora, sem ação necessária
- **Impacto**: Polui o chat com informação que você já sabe

**Arquivo**: `agents/lib_telegram.ps1` (linhas 708-750)

### 2. **PRE-SCREEN BLOQUEOU (MUITO FREQUENTE)**
- **Frequência**: A cada candidato bloqueado (5-10x por ciclo)
- **Conteúdo**: `[~] PRE-SCREEN BLOQUEOU MARKET_X - razão - nenhum custo AI`
- **Problema**: Você não pode fazer nada com isso; é apenas informação de debug
- **Impacto**: 50-100 mensagens por dia

**Arquivo**: `agents/orchestrator.ps1` (linhas 201-203)

### 3. **ABORTAR Repetido (MUITO FREQUENTE)**
- **Frequência**: A cada candidato abortado (10-20x por ciclo)
- **Conteúdo**: `ABORTAR - regime=BULL_WEAK - score=45`
- **Problema**: Você não pode fazer nada; é decisão automática do sistema
- **Impacto**: 100-200 mensagens por dia

**Arquivo**: `agents/orchestrator_v6.ps1` (linhas 760-768)

### 4. **Trailing Stop Updates (FREQUENTE)**
- **Frequência**: A cada atualização de stop (5-20x por ciclo)
- **Conteúdo**: `🔄 BTCUSDT LONG fase 1→2 stop 65000→65500`
- **Problema**: Você já vê isso no dashboard; mensagem redundante
- **Impacto**: 20-50 mensagens por dia

**Arquivo**: `agents/lib_trailing_adaptive.ps1` (linhas 343-347)

### 5. **Fase Transitions (FREQUENTE)**
- **Frequência**: A cada mudança de fase
- **Conteúdo**: `[Adaptive Trailing] BTCUSDT LONG fase 1→2`
- **Problema**: Redundante com trailing stop updates
- **Impacto**: 10-30 mensagens por dia

**Arquivo**: `agents/lib_trailing.ps1` (linhas 484-485)

### 6. **Layer Advisories (FREQUENTE)**
- **Frequência**: A cada layer decision
- **Conteúdo**: `[Layer4 ADVISORY] BTCUSDT LONG suggests HOLD`
- **Problema**: Você não pode fazer nada; é apenas advisory
- **Impacto**: 10-20 mensagens por dia

**Arquivo**: `agents/lib_layer4_tori_timestop.ps1` (linhas 320-326)

### 7. **Moon Bag Advisories (FREQUENTE)**
- **Frequência**: A cada moon bag decision
- **Conteúdo**: `[Layer5 ADVISORY] BTCUSDT LONG suggests HOLD`
- **Problema**: Você não pode fazer nada; é apenas advisory
- **Impacto**: 5-10 mensagens por dia

**Arquivo**: `agents/lib_moon_bag.ps1` (linhas 492-497)

---

## 📈 Estimativa de Redução

| Tipo | Antes/dia | Depois/dia | Redução |
|------|-----------|-----------|---------|
| Heartbeats | 24 | 2 | -92% |
| PRE-SCREEN | 75 | 0 | -100% |
| ABORTAR | 150 | 0 | -100% |
| Trailing Updates | 35 | 5 | -86% |
| Fase Transitions | 20 | 0 | -100% |
| Layer Advisories | 15 | 0 | -100% |
| Moon Bag Advisories | 8 | 0 | -100% |
| **TOTAL** | **327** | **7** | **-98%** |

---

## ✅ Solução Proposta

### Estratégia: Categorizar Mensagens por Importância

#### **TIER 1: CRÍTICO (Enviar Sempre)**
- ✅ Posição aberta (EXECUTAR)
- ✅ Posição fechada (STOP HIT, TP HIT)
- ✅ Liquidação próxima (MARGIN ALERT)
- ✅ Posição sem proteção (SL/TP faltando)
- ✅ Whale alert (>100 BTC)
- ✅ Erro crítico (LLM indisponível, API down)

#### **TIER 2: IMPORTANTE (Enviar com Dedup)**
- ⚠️ Gem aprovado (1x por gem)
- ⚠️ Promotion/Demotion (1x por market)
- ⚠️ Regime change (1x por mudança)
- ⚠️ Kelly sizing ativado (1x)

#### **TIER 3: INFORMATIVO (Enviar apenas em Dashboard)**
- ℹ️ Heartbeat (apenas 1x por 6h, não 1x por 1h)
- ℹ️ Trailing stop updates (apenas grandes mudanças, >5%)
- ℹ️ Fase transitions (apenas fase 1→final, não intermediárias)
- ℹ️ Layer advisories (apenas CLOSE, não HOLD)
- ℹ️ Moon bag advisories (apenas CLOSE, não HOLD)

#### **TIER 4: DEBUG (Nunca Enviar)**
- ❌ PRE-SCREEN BLOQUEOU
- ❌ ABORTAR (decisão automática)
- ❌ Triagem score
- ❌ Mesa consensus
- ❌ Mentor reasoning

---

## 🛠️ Implementação

### Passo 1: Criar Flag de Controle

**Arquivo**: `agents/config.local.ps1`

```powershell
# Telegram Message Filtering
$global:TELEGRAM_FILTER_MODE = "production"  # production | debug | verbose

# Tier 1: Sempre enviar
$global:TELEGRAM_SEND_CRITICAL = $true

# Tier 2: Enviar com dedup
$global:TELEGRAM_SEND_IMPORTANT = $true

# Tier 3: Enviar apenas em dashboard
$global:TELEGRAM_SEND_INFORMATIVE = $false

# Tier 4: Nunca enviar
$global:TELEGRAM_SEND_DEBUG = $false

# Heartbeat: reduzir de 1h para 6h
$global:TELEGRAM_HEARTBEAT_INTERVAL_MIN = 360  # 6 horas

# Trailing: enviar apenas mudanças >5%
$global:TELEGRAM_TRAILING_MIN_CHANGE_PCT = 5.0

# Layer: enviar apenas CLOSE, não HOLD
$global:TELEGRAM_LAYER_SEND_HOLD = $false
```

### Passo 2: Modificar Send-TelegramAlert

**Arquivo**: `agents/lib_telegram.ps1`

```powershell
function Send-TelegramAlert {
    param(
        [string]$Message,
        [string]$Tier = "CRITICAL"  # CRITICAL, IMPORTANT, INFORMATIVE, DEBUG
    )
    
    # Verificar se deve enviar baseado no tier
    switch ($Tier) {
        "CRITICAL" {
            if (-not $global:TELEGRAM_SEND_CRITICAL) { return }
        }
        "IMPORTANT" {
            if (-not $global:TELEGRAM_SEND_IMPORTANT) { return }
        }
        "INFORMATIVE" {
            if (-not $global:TELEGRAM_SEND_INFORMATIVE) { return }
        }
        "DEBUG" {
            if (-not $global:TELEGRAM_SEND_DEBUG) { return }
        }
    }
    
    # Enviar mensagem
    Telegram-SendMessage -Message $Message
}
```

### Passo 3: Atualizar Chamadas

**Exemplo 1: PRE-SCREEN BLOQUEOU (Remover)**

**Antes**:
```powershell
Send-TelegramAlert -Message "[~] PRE-SCREEN BLOQUEOU $Market..."
```

**Depois**:
```powershell
# Remover completamente ou enviar apenas em debug mode
if ($global:TELEGRAM_SEND_DEBUG) {
    Send-TelegramAlert -Message "[~] PRE-SCREEN BLOQUEOU $Market..." -Tier "DEBUG"
}
```

**Exemplo 2: Heartbeat (Aumentar Intervalo)**

**Antes**:
```powershell
Send-HeartbeatIfDue -IntervalMinutes 60
```

**Depois**:
```powershell
Send-HeartbeatIfDue -IntervalMinutes $global:TELEGRAM_HEARTBEAT_INTERVAL_MIN
```

**Exemplo 3: Trailing Stop (Filtrar Pequenas Mudanças)**

**Antes**:
```powershell
Send-TelegramAlert -Message "🔄 $($pos.market) stop $oldStop→$($calc.newStop)"
```

**Depois**:
```powershell
$changePct = [math]::Abs(($calc.newStop - $oldStop) / $oldStop * 100)
if ($changePct -ge $global:TELEGRAM_TRAILING_MIN_CHANGE_PCT) {
    Send-TelegramAlert -Message "🔄 $($pos.market) stop $oldStop→$($calc.newStop)" -Tier "INFORMATIVE"
}
```

**Exemplo 4: Layer Advisories (Enviar apenas CLOSE)**

**Antes**:
```powershell
Send-TelegramAlert -Message "[Layer4 ADVISORY] $($pos.market) suggests $($decision.action)"
```

**Depois**:
```powershell
if ($decision.action -eq "CLOSE" -or $global:TELEGRAM_LAYER_SEND_HOLD) {
    Send-TelegramAlert -Message "[Layer4 ADVISORY] $($pos.market) suggests $($decision.action)" -Tier "INFORMATIVE"
}
```

---

## 📋 Checklist de Implementação

- [ ] Criar flags em `config.local.ps1`
- [ ] Modificar `Send-TelegramAlert` para aceitar `Tier`
- [ ] Atualizar `orchestrator.ps1` (remover PRE-SCREEN)
- [ ] Atualizar `orchestrator_v6.ps1` (remover ABORTAR)
- [ ] Atualizar `lib_trailing_adaptive.ps1` (filtrar pequenas mudanças)
- [ ] Atualizar `lib_trailing.ps1` (filtrar pequenas mudanças)
- [ ] Atualizar `lib_layer4_tori_timestop.ps1` (enviar apenas CLOSE)
- [ ] Atualizar `lib_moon_bag.ps1` (enviar apenas CLOSE)
- [ ] Atualizar `lib_telegram.ps1` (aumentar heartbeat para 6h)
- [ ] Testar em modo debug
- [ ] Ativar em modo production

---

## 🎯 Resultado Esperado

**Antes**: 327 mensagens/dia (muitas repetidas e não-acionáveis)  
**Depois**: 7 mensagens/dia (apenas críticas e importantes)

**Redução**: 98% de mensagens desnecessárias

---

## 📞 Próximos Passos

1. Você quer que eu implemente essas mudanças?
2. Quer ajustar os thresholds (ex: heartbeat 6h vs 12h)?
3. Quer adicionar mais filtros (ex: apenas LONG, não SHORT)?


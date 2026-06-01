# 🚀 Plano de Implementação - Redução de Mensagens Telegram

**Data**: 2026-06-01  
**Objetivo**: Reduzir de 327 para 7 mensagens/dia (98% redução)  
**Tempo Estimado**: 2-3 horas

---

## 📋 Fase 1: Preparação (15 min)

### 1.1 Criar Arquivo de Configuração

**Arquivo**: `agents/config.telegram_filter.ps1`

```powershell
# ============================================================================
# Telegram Message Filtering Configuration
# ============================================================================

# Modo de operação
$global:TELEGRAM_FILTER_MODE = "production"  # production | debug | verbose

# ─────────────────────────────────────────────────────────────────────────
# TIER 1: CRÍTICO (Sempre enviar)
# ─────────────────────────────────────────────────────────────────────────
$global:TELEGRAM_SEND_CRITICAL = $true

# ─────────────────────────────────────────────────────────────────────────
# TIER 2: IMPORTANTE (Enviar com dedup)
# ─────────────────────────────────────────────────────────────────────────
$global:TELEGRAM_SEND_IMPORTANT = $true

# ─────────────────────────────────────────────────────────────────────────
# TIER 3: INFORMATIVO (Enviar apenas em dashboard)
# ─────────────────────────────────────────────────────────────────────────
$global:TELEGRAM_SEND_INFORMATIVE = $false

# ─────────────────────────────────────────────────────────────────────────
# TIER 4: DEBUG (Nunca enviar em production)
# ─────────────────────────────────────────────────────────────────────────
$global:TELEGRAM_SEND_DEBUG = $false

# ─────────────────────────────────────────────────────────────────────────
# Configurações Específicas
# ─────────────────────────────────────────────────────────────────────────

# Heartbeat: reduzir de 1h para 6h
$global:TELEGRAM_HEARTBEAT_INTERVAL_MIN = 360

# Trailing: enviar apenas mudanças >5%
$global:TELEGRAM_TRAILING_MIN_CHANGE_PCT = 5.0

# Layer: enviar apenas CLOSE, não HOLD
$global:TELEGRAM_LAYER_SEND_HOLD = $false

# Moon Bag: enviar apenas CLOSE, não HOLD
$global:TELEGRAM_MOON_BAG_SEND_HOLD = $false

# PRE-SCREEN: nunca enviar (debug only)
$global:TELEGRAM_SEND_PRESCREEN = $false

# ABORTAR: nunca enviar (debug only)
$global:TELEGRAM_SEND_ABORTAR = $false
```

### 1.2 Adicionar ao config.local.ps1

**Arquivo**: `agents/config.local.ps1`

```powershell
# Carregar configuração de filtro Telegram
. (Join-Path $PSScriptRoot "config.telegram_filter.ps1")
```

---

## 📋 Fase 2: Modificar lib_telegram.ps1 (30 min)

### 2.1 Adicionar Função de Filtro

**Adicionar após `Send-TelegramAlert`**:

```powershell
# ============================================================================
# Send-TelegramAlertFiltered - Envia com filtro por tier
# ============================================================================

function Send-TelegramAlertFiltered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CRITICAL", "IMPORTANT", "INFORMATIVE", "DEBUG")]
        [string]$Tier = "CRITICAL",
        
        [Parameter(Mandatory=$false)]
        [int]$DedupSeconds = 0,
        
        [Parameter(Mandatory=$false)]
        [string]$DedupStorePath = ""
    )
    
    # Verificar se deve enviar baseado no tier
    $shouldSend = switch ($Tier) {
        "CRITICAL"     { $global:TELEGRAM_SEND_CRITICAL }
        "IMPORTANT"    { $global:TELEGRAM_SEND_IMPORTANT }
        "INFORMATIVE"  { $global:TELEGRAM_SEND_INFORMATIVE }
        "DEBUG"        { $global:TELEGRAM_SEND_DEBUG }
        default        { $true }
    }
    
    if (-not $shouldSend) {
        Write-Verbose "[TELEGRAM] Mensagem $Tier filtrada (modo=$global:TELEGRAM_FILTER_MODE)"
        return [PSCustomObject]@{
            success = $true
            skipped = $true
            reason = "filtered_by_tier_$Tier"
        }
    }
    
    # Enviar com dedup se configurado
    if ($DedupSeconds -gt 0) {
        return Send-TelegramAlert -Message $Message -DedupSeconds $DedupSeconds -DedupStorePath $DedupStorePath
    } else {
        return Send-TelegramAlert -Message $Message
    }
}
```

### 2.2 Atualizar Heartbeat

**Modificar `Send-HeartbeatIfDue`**:

```powershell
function Send-HeartbeatIfDue {
    param(
        [string]$LastHeartbeatFile = "",
        [int]   $IntervalMinutes   = 60,  # ← Será sobrescrito por config
        [string]$Window            = "NEUTRAL",
        [int]   $NextMin           = 60,
        [string]$NextTime          = "",
        [int]   $WatchCount        = 0,
        [int]   $CyclesQuiet       = 0,
        [switch]$DryRun
    )
    
    if (-not $Enabled) { return $false }
    
    # ✨ NOVO: Usar intervalo da configuração
    $interval = if ($global:TELEGRAM_HEARTBEAT_INTERVAL_MIN) {
        $global:TELEGRAM_HEARTBEAT_INTERVAL_MIN
    } else {
        $IntervalMinutes
    }
    
    # Resto do código...
    $msg = Format-HeartbeatMessage `
        -Window $Window -NextMin $NextMin -NextTime $NextTime `
        -WatchCount $WatchCount -CyclesQuiet $CyclesQuiet -DryRun:$DryRun
    
    # ✨ NOVO: Usar Send-TelegramAlertFiltered com INFORMATIVE
    $hbDedupPath = Join-Path $PSScriptRoot "..\journal\tg_dedup_heartbeat.json"
    $result = Send-TelegramAlertFiltered -Message $msg -Tier "INFORMATIVE" `
        -DedupSeconds 3600 -DedupStorePath $hbDedupPath
    
    # Resto do código...
}
```

---

## 📋 Fase 3: Modificar orchestrator.ps1 (15 min)

### 3.1 Remover PRE-SCREEN BLOQUEOU

**Arquivo**: `agents/orchestrator.ps1` (linhas 201-203)

**Antes**:
```powershell
Write-Host "  [BLOQUEADO] Setup insuficiente — pipeline encerrado sem custo AI." -ForegroundColor Yellow
$tgMsg = "[~] PRE-SCREEN BLOQUEOU $Market`n$preMotivo`nNenhum custo AI gerado.`n$(Get-Date -Format 'HH:mm dd/MM/yy')"
Send-TelegramAlert -Message $tgMsg | Out-Null
```

**Depois**:
```powershell
Write-Host "  [BLOQUEADO] Setup insuficiente — pipeline encerrado sem custo AI." -ForegroundColor Yellow
# ✨ NOVO: Enviar apenas em debug mode
if ($global:TELEGRAM_SEND_PRESCREEN) {
    $tgMsg = "[~] PRE-SCREEN BLOQUEOU $Market`n$preMotivo`nNenhum custo AI gerado.`n$(Get-Date -Format 'HH:mm dd/MM/yy')"
    Send-TelegramAlertFiltered -Message $tgMsg -Tier "DEBUG" | Out-Null
}
```

---

## 📋 Fase 4: Modificar orchestrator_v6.ps1 (15 min)

### 4.1 Remover ABORTAR

**Arquivo**: `agents/orchestrator_v6.ps1` (linhas 760-768)

**Antes**:
```powershell
if ($cascade.telegramFire -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
    try {
        $decisaoTg = if ($DryRun) { "DRY_RUN_EXECUTAR" } else { $cascade.decisao }
        $msg = Format-TgEsquadraoResult -Market $Market -Triagem $cascade.triagem `
            -Mesa $cascade.mesa -Mentor $cascade.mentor -Decisao $decisaoTg
        Send-TelegramAlert -Message $msg | Out-Null
    } catch { Write-Host "  [TG] Falha envio: $_" -ForegroundColor DarkYellow }
}
```

**Depois**:
```powershell
if ($cascade.telegramFire -and (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue)) {
    try {
        $decisaoTg = if ($DryRun) { "DRY_RUN_EXECUTAR" } else { $cascade.decisao }
        
        # ✨ NOVO: Enviar apenas se EXECUTAR (não ABORTAR)
        if ($decisaoTg -eq "EXECUTAR" -or $decisaoTg -eq "DRY_RUN_EXECUTAR") {
            $msg = Format-TgEsquadraoResult -Market $Market -Triagem $cascade.triagem `
                -Mesa $cascade.mesa -Mentor $cascade.mentor -Decisao $decisaoTg
            Send-TelegramAlertFiltered -Message $msg -Tier "CRITICAL" | Out-Null
        } elseif ($global:TELEGRAM_SEND_DEBUG) {
            # Debug mode: enviar ABORTAR também
            $msg = Format-TgEsquadraoResult -Market $Market -Triagem $cascade.triagem `
                -Mesa $cascade.mesa -Mentor $cascade.mentor -Decisao $decisaoTg
            Send-TelegramAlertFiltered -Message $msg -Tier "DEBUG" | Out-Null
        }
    } catch { Write-Host "  [TG] Falha envio: $_" -ForegroundColor DarkYellow }
}
```

---

## 📋 Fase 5: Modificar lib_trailing_adaptive.ps1 (15 min)

### 5.1 Filtrar Pequenas Mudanças

**Arquivo**: `agents/lib_trailing_adaptive.ps1` (linhas 343-347)

**Antes**:
```powershell
$msg = "🔄 $($pos.market) $($pos.side) fase $oldPhase→$($pos.phase) ($($phaseLabel[$pos.phase])) stop $oldStop→$($calc.newStop) | regime=$regime"
Write-Host "  [Adaptive Trailing] $msg" -ForegroundColor Green
if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
    try { Send-TelegramAlert -Message $msg | Out-Null } catch { }
}
```

**Depois**:
```powershell
# ✨ NOVO: Calcular mudança percentual
$changePct = if ($oldStop -gt 0) {
    [math]::Abs(($calc.newStop - $oldStop) / $oldStop * 100)
} else {
    0
}

# ✨ NOVO: Enviar apenas se mudança > threshold
$minChange = if ($global:TELEGRAM_TRAILING_MIN_CHANGE_PCT) {
    $global:TELEGRAM_TRAILING_MIN_CHANGE_PCT
} else {
    5.0
}

if ($changePct -ge $minChange) {
    $msg = "🔄 $($pos.market) $($pos.side) fase $oldPhase→$($pos.phase) ($($phaseLabel[$pos.phase])) stop $oldStop→$($calc.newStop) | regime=$regime"
    Write-Host "  [Adaptive Trailing] $msg" -ForegroundColor Green
    if (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue) {
        try { Send-TelegramAlertFiltered -Message $msg -Tier "INFORMATIVE" | Out-Null } catch { }
    }
}
```

---

## 📋 Fase 6: Modificar lib_layer4_tori_timestop.ps1 (10 min)

### 6.1 Enviar Apenas CLOSE

**Arquivo**: `agents/lib_layer4_tori_timestop.ps1` (linhas 320-326)

**Antes**:
```powershell
if ($decision.action -ne "HOLD") {
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        try {
            $alertMsg = "[Layer4 ADVISORY] $($pos.market) $($pos.side) suggests: $($decision.action) (reason=$($decision.reason)). Manual action required - no auto-execute."
            Send-TelegramAlert -Message $alertMsg | Out-Null
        } catch { }
    }
}
```

**Depois**:
```powershell
# ✨ NOVO: Enviar apenas CLOSE, não HOLD
$sendLayer = $decision.action -eq "CLOSE" -or $global:TELEGRAM_LAYER_SEND_HOLD

if ($sendLayer -and (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue)) {
    try {
        $alertMsg = "[Layer4 ADVISORY] $($pos.market) $($pos.side) suggests: $($decision.action) (reason=$($decision.reason)). Manual action required - no auto-execute."
        Send-TelegramAlertFiltered -Message $alertMsg -Tier "INFORMATIVE" | Out-Null
    } catch { }
}
```

---

## 📋 Fase 7: Modificar lib_moon_bag.ps1 (10 min)

### 7.1 Enviar Apenas CLOSE

**Arquivo**: `agents/lib_moon_bag.ps1` (linhas 492-497, 516-520)

**Antes**:
```powershell
if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
    try {
        $msg = "[Layer5 ADVISORY] $($pos.market) $($pos.moonBagKind) $($pos.side) suggests $($decision.action) at $current. Manual action required."
        Send-TelegramAlert -Message $msg | Out-Null
    } catch { }
}
```

**Depois**:
```powershell
# ✨ NOVO: Enviar apenas CLOSE, não HOLD
$sendMoonBag = $decision.action -eq "CLOSE" -or $global:TELEGRAM_MOON_BAG_SEND_HOLD

if ($sendMoonBag -and (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue)) {
    try {
        $msg = "[Layer5 ADVISORY] $($pos.market) $($pos.moonBagKind) $($pos.side) suggests $($decision.action) at $current. Manual action required."
        Send-TelegramAlertFiltered -Message $msg -Tier "INFORMATIVE" | Out-Null
    } catch { }
}
```

---

## 📋 Fase 8: Testar (30 min)

### 8.1 Modo Debug

```powershell
# Em config.local.ps1
$global:TELEGRAM_FILTER_MODE = "debug"
$global:TELEGRAM_SEND_DEBUG = $true
$global:TELEGRAM_SEND_INFORMATIVE = $true
```

**Resultado**: Você verá TODAS as mensagens (incluindo debug)

### 8.2 Modo Production

```powershell
# Em config.local.ps1
$global:TELEGRAM_FILTER_MODE = "production"
$global:TELEGRAM_SEND_DEBUG = $false
$global:TELEGRAM_SEND_INFORMATIVE = $false
```

**Resultado**: Você verá apenas CRÍTICO e IMPORTANTE

### 8.3 Modo Verbose

```powershell
# Em config.local.ps1
$global:TELEGRAM_FILTER_MODE = "verbose"
$global:TELEGRAM_SEND_DEBUG = $false
$global:TELEGRAM_SEND_INFORMATIVE = $true
```

**Resultado**: Você verá CRÍTICO, IMPORTANTE e INFORMATIVO

---

## 📊 Resultado Esperado

### Antes (Production Atual)
```
[HEARTBEAT] NEUTRAL | 8 pares | 1 ciclo sem novidade | próx 60min
[~] PRE-SCREEN BLOQUEOU ETHUSDT - regime=BULL_WEAK - nenhum custo AI
[~] PRE-SCREEN BLOQUEOU SOLUSDT - regime=BULL_WEAK - nenhum custo AI
ABORTAR - BTCUSDT - regime=BULL_WEAK - score=45
ABORTAR - ETHUSDT - regime=BULL_WEAK - score=40
🔄 BTCUSDT LONG fase 1→2 stop 65000→65100
[Layer4 ADVISORY] BTCUSDT LONG suggests HOLD
[Layer5 ADVISORY] BTCUSDT LONG suggests HOLD
... (327 mensagens/dia)
```

### Depois (Production Otimizado)
```
✅ BTCUSDT LONG EXECUTAR | Score: 75 | Size: $500
✅ ETHUSDT LONG EXECUTAR | Score: 68 | Size: $300
🛑 BTCUSDT LONG STOP HIT @ 64500
🛑 ETHUSDT LONG TP HIT @ 2500
⚠️ BTCUSDT LONG liquidação próxima - margin adicionado +100 USDT
[HEARTBEAT] NEUTRAL | 8 pares | 6h sem novidade | próx 360min
... (7 mensagens/dia)
```

---

## ✅ Checklist de Implementação

- [ ] Criar `config.telegram_filter.ps1`
- [ ] Adicionar import em `config.local.ps1`
- [ ] Adicionar `Send-TelegramAlertFiltered` em `lib_telegram.ps1`
- [ ] Atualizar `Send-HeartbeatIfDue` em `lib_telegram.ps1`
- [ ] Modificar `orchestrator.ps1` (PRE-SCREEN)
- [ ] Modificar `orchestrator_v6.ps1` (ABORTAR)
- [ ] Modificar `lib_trailing_adaptive.ps1` (filtro de mudanças)
- [ ] Modificar `lib_layer4_tori_timestop.ps1` (apenas CLOSE)
- [ ] Modificar `lib_moon_bag.ps1` (apenas CLOSE)
- [ ] Testar em modo debug
- [ ] Testar em modo verbose
- [ ] Testar em modo production
- [ ] Fazer commit e push
- [ ] Reiniciar sistema

---

## 🎯 Tempo Total Estimado

- Fase 1 (Preparação): 15 min
- Fase 2 (lib_telegram): 30 min
- Fase 3 (orchestrator): 15 min
- Fase 4 (orchestrator_v6): 15 min
- Fase 5 (lib_trailing_adaptive): 15 min
- Fase 6 (lib_layer4): 10 min
- Fase 7 (lib_moon_bag): 10 min
- Fase 8 (Testes): 30 min

**Total**: ~2.5 horas

---

**Status**: Pronto para implementação


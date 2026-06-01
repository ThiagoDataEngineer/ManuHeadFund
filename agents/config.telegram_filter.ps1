# ============================================================================
# config.telegram_filter.ps1 - Telegram Message Filtering Configuration
# ============================================================================
# Objetivo: Reduzir ruído no Telegram filtrando mensagens por tier de importância
# Implementado: 2026-06-01
# Redução esperada: 327 → 7 mensagens/dia (98%)

# ─────────────────────────────────────────────────────────────────────────
# Modo de Operação
# ─────────────────────────────────────────────────────────────────────────
# production: Apenas CRÍTICO + IMPORTANTE (7 msg/dia)
# verbose:    CRÍTICO + IMPORTANTE + INFORMATIVO (50 msg/dia)
# debug:      Todas as mensagens (327 msg/dia)

$global:TELEGRAM_FILTER_MODE = "production"

# ─────────────────────────────────────────────────────────────────────────
# TIER 1: CRÍTICO (Sempre enviar)
# ─────────────────────────────────────────────────────────────────────────
# Posição aberta (EXECUTAR)
# Posição fechada (STOP HIT, TP HIT)
# Liquidação próxima
# Posição sem proteção
# Whale alert
# Erro crítico

$global:TELEGRAM_SEND_CRITICAL = $true

# ─────────────────────────────────────────────────────────────────────────
# TIER 2: IMPORTANTE (Enviar com dedup)
# ─────────────────────────────────────────────────────────────────────────
# Gem aprovado
# Promotion/Demotion
# Regime change
# Kelly sizing ativado
# Trailing updates (mudanças de stop/fase)
# Whale/Bacon alerts

$global:TELEGRAM_SEND_IMPORTANT = $true

# ─────────────────────────────────────────────────────────────────────────
# TIER 3: INFORMATIVO (Enviar apenas em verbose/debug)
# ─────────────────────────────────────────────────────────────────────────
# Heartbeat (1x por 6h, não 1x por 1h)
# Trailing updates (apenas >5% mudança)
# Fase transitions (apenas final)
# Layer advisories (apenas CLOSE)
# Moon bag advisories (apenas CLOSE)

$global:TELEGRAM_SEND_INFORMATIVE = if ($global:TELEGRAM_FILTER_MODE -eq "production") { $false } else { $true }

# ─────────────────────────────────────────────────────────────────────────
# TIER 4: DEBUG (Nunca enviar em production)
# ─────────────────────────────────────────────────────────────────────────
# PRE-SCREEN BLOQUEOU
# ABORTAR
# Triagem score
# Mesa consensus
# Mentor reasoning

$global:TELEGRAM_SEND_DEBUG = if ($global:TELEGRAM_FILTER_MODE -eq "debug") { $true } else { $false }

# ─────────────────────────────────────────────────────────────────────────
# Configurações Específicas
# ─────────────────────────────────────────────────────────────────────────

# Heartbeat: reduzir de 1h para 6h (360 minutos)
$global:TELEGRAM_HEARTBEAT_INTERVAL_MIN = 360

# Trailing: enviar apenas mudanças >5%
$global:TELEGRAM_TRAILING_MIN_CHANGE_PCT = 5.0

# Layer: enviar apenas CLOSE, não HOLD
$global:TELEGRAM_LAYER_SEND_HOLD = $false

# Moon Bag: enviar apenas CLOSE, não HOLD
$global:TELEGRAM_MOON_BAG_SEND_HOLD = $false

# PRE-SCREEN: nunca enviar em production
$global:TELEGRAM_SEND_PRESCREEN = if ($global:TELEGRAM_FILTER_MODE -eq "debug") { $true } else { $false }

# ABORTAR: nunca enviar em production
$global:TELEGRAM_SEND_ABORTAR = if ($global:TELEGRAM_FILTER_MODE -eq "debug") { $true } else { $false }

Write-Verbose "[TELEGRAM_FILTER] Modo=$global:TELEGRAM_FILTER_MODE | Critical=$global:TELEGRAM_SEND_CRITICAL | Important=$global:TELEGRAM_SEND_IMPORTANT | Informative=$global:TELEGRAM_SEND_INFORMATIVE | Debug=$global:TELEGRAM_SEND_DEBUG"

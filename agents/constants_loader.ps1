# constants_loader.ps1 — Single Source of Truth para constantes PowerShell
# Espelhado em docs/CONSTANTS.md (revisão 2026-05-16).
# Espelhado em backtest/constants.py (Python side).
#
# Uso:
#   . "$PSScriptRoot\constants_loader.ps1"
#   $RR_DEFAULT       # disponível como variável global
#   Get-Constant -Name "RR_DEFAULT"   # ou via função
#
# Adicione novas constantes AQUI, NÃO em arquivos individuais.
# State vivo (capital/fees/prices) NÃO está aqui — usar lib_coinex.ps1.

# ─────────────────────────────────────────────────────────────────────────────
# WORLD_FACT — imutáveis
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_HALVING_DATE_2024     = [DateTime]::new(2024, 4, 19)


# ─────────────────────────────────────────────────────────────────────────────
# BUSINESS_RULE — risk & sizing (espelha config.ps1)
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_RR_DEFAULT            = 5.0     # alinhado $RR_MINIMO/PREFERIDO config.ps1
$global:CONST_SCORE_THRESHOLD       = 65.0    # alinhado $SCORE_MINIMO config.ps1
$global:CONST_RISK_PCT_PER_TRADE    = 0.01
$global:CONST_MAX_OPEN_RISK_PCT     = 0.03
$global:CONST_MAX_LEVERAGE          = 5.0


# ─────────────────────────────────────────────────────────────────────────────
# REGIME classifier (espelha regime_classifier.py + regime_8state_classifier.py)
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_SMA200_PERIOD         = 200
$global:CONST_SIDEWAYS_BAND         = 0.02
$global:CONST_DIST_STRONG           = 0.15
$global:CONST_ADX_PERIOD            = 14
$global:CONST_ADX_STRONG_THRESHOLD  = 25.0
$global:CONST_CAPITULATION_THRESHOLD = 0.25


# ─────────────────────────────────────────────────────────────────────────────
# TRIAGEM thresholds (default; override via $global:TRIAGEM_THRESHOLDS)
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_TRIAGEM_TIER_D_DEFAULT = 50
$global:CONST_TRIAGEM_TIER_B_DEFAULT = 60
$global:CONST_TRIAGEM_TIER_A_DEFAULT = 75


# ─────────────────────────────────────────────────────────────────────────────
# GO_CRITERION (nomes explícitos pós DRIFT-2)
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_GO_POSITIVE_YEARS_PCT   = 70.0
$global:CONST_GO_POSITIVE_WINDOWS_PCT = 60.0
$global:CONST_GO_TOTAL_PF             = 1.5
$global:CONST_GO_LIVE_DD_THRESHOLD_R  = 20.0


# ─────────────────────────────────────────────────────────────────────────────
# SIMONS GATE
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_DSR_THRESHOLD         = 0.95
$global:CONST_PSR_THRESHOLD         = 0.95


# ─────────────────────────────────────────────────────────────────────────────
# TEST FIXTURES (mock values) — usar em testes pra evitar magic numbers
# Espelhar em backtest/constants.py seção TEST_FIXTURES
# ─────────────────────────────────────────────────────────────────────────────
$global:CONST_TEST_BTC_PRICE             = 60000.0
$global:CONST_TEST_ALT_PRICE_SUB_DOLLAR  = 0.5
$global:CONST_TEST_CAPITAL_USDT          = 1000.0
$global:CONST_TEST_RR_SCENARIO           = 5.0
$global:CONST_TEST_ATR_PCT               = 2.5
$global:CONST_TEST_CHANGE_24H_BULLISH    = 5.0
$global:CONST_TEST_CHANGE_24H_BEARISH    = -5.0


# ─────────────────────────────────────────────────────────────────────────────
# Function: Get-Constant — lookup explícito
# ─────────────────────────────────────────────────────────────────────────────
function Get-Constant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter()][object]$Default = $null
    )
    $varName = "CONST_$Name"
    $v = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
    if ($v) { return $v.Value }
    return $Default
}

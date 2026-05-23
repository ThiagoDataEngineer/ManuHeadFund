# lib_operational_whitelist.ps1 -- Whitelist operacional regime+direcao+DoW+mode
# Pester 3.x compativel. PS 5.1. UTF-8 BOM.
#
# Regras (ref: memory/project_operational_whitelist_v2.md):
#   PAPER (prioridade alta -> baixa):
#     (BULL_STRONG, LONG, *)              -> execute
#     (TRANSITION_UP, LONG, DoW=1 Monday) -> execute
#     (TRANSITION_UP, LONG, DoW!=1)       -> observe
#     (BULL_WEAK, LONG, *)                -> observe
#     (*, SHORT, *)                       -> observe   (coleta amostra)
#     (else)                              -> skip
#   LIVE:
#     (BULL_STRONG, LONG, *)              -> execute
#     (TRANSITION_UP, LONG, DoW=1)        -> execute
#     (else)                              -> skip
#
# DayOfWeekBRT: 0=Sunday, 1=Monday, ..., 6=Saturday (BRT/UTC-3).

$script:VALID_REGIMES = @(
    'BULL_STRONG','BULL_WEAK','SIDEWAYS','TRANSITION_UP',
    'TRANSITION_DOWN','BEAR_WEAK','BEAR_STRONG','CAPITULATION'
)
$script:VALID_DIRECTIONS = @('LONG','SHORT')
$script:VALID_MODES = @('paper','live')


function Test-RegimeDirectionAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Regime,
        [Parameter(Mandatory)] [string]$Direction,
        [Parameter(Mandatory)] [int]   $DayOfWeekBRT,
        [Parameter(Mandatory)] [string]$Mode
    )

    # Validacao defensiva
    if ($script:VALID_REGIMES -notcontains $Regime) {
        throw "Regime invalido: '$Regime'. Esperado um de: $($script:VALID_REGIMES -join ', ')"
    }
    if ($script:VALID_DIRECTIONS -notcontains $Direction) {
        throw "Direction invalida: '$Direction'. Esperado: LONG ou SHORT"
    }
    if ($DayOfWeekBRT -lt 0 -or $DayOfWeekBRT -gt 6) {
        throw "DayOfWeekBRT fora do range 0-6: $DayOfWeekBRT (0=Sunday, 1=Monday, ..., 6=Saturday)"
    }
    if ($script:VALID_MODES -notcontains $Mode) {
        throw "Mode invalido: '$Mode'. Esperado: paper ou live"
    }

    # Regra 1: BULL_STRONG + LONG -> execute em ambos os modos
    if ($Regime -eq 'BULL_STRONG' -and $Direction -eq 'LONG') {
        return [PSCustomObject]@{
            allowed = $true
            tier    = 'execute'
            reason  = 'BULL_STRONG + LONG (validated cross-period, edge +0.39R holdout)'
        }
    }

    # Regra 2: TRANSITION_UP + LONG + Monday (BRT) -> execute em ambos os modos
    if ($Regime -eq 'TRANSITION_UP' -and $Direction -eq 'LONG' -and $DayOfWeekBRT -eq 1) {
        return [PSCustomObject]@{
            allowed = $true
            tier    = 'execute'
            reason  = 'TRANSITION_UP + LONG + Monday BRT (+0.98R holdout, n=25, aguarda 5 trades para VIABLE)'
        }
    }

    # Regra 3: TRANSITION_UP + LONG + DoW!=1 -> observe (paper) | skip (live)
    if ($Regime -eq 'TRANSITION_UP' -and $Direction -eq 'LONG') {
        if ($Mode -eq 'paper') {
            return [PSCustomObject]@{
                allowed = $true
                tier    = 'observe'
                reason  = "TRANSITION_UP LONG fora da janela Monday BRT (DoW=$DayOfWeekBRT) -- paper observa, live nao"
            }
        }
        return [PSCustomObject]@{
            allowed = $false
            tier    = 'skip'
            reason  = "TRANSITION_UP LONG fora de Monday BRT (DoW=$DayOfWeekBRT) -- live exige DoW=1"
        }
    }

    # Regra 4: BULL_WEAK + LONG -> observe (paper) | observe (live, RE-VALIDATED 2026-05-23)
    # RE-VALIDATION 2026-05-23 (docs/backtest/BLACKLIST_BULL_WEAK_REVALIDATION.md):
    # 1127 signals 1y mostraram EV +2.08pp (vs hipotese 2025 -0.4R). Cross-phase 5/5 positive.
    # Action: convert live SKIP -> OBSERVE (paper tier defensiva). 30d forward
    # validation antes de promover live execution. Flag-gated rollback via env.
    if ($Regime -eq 'BULL_WEAK' -and $Direction -eq 'LONG') {
        if ($Mode -eq 'paper') {
            return [PSCustomObject]@{
                allowed = $true
                tier    = 'observe'
                reason  = 'BULL_WEAK LONG -- paper coleta para verificar se structural break e permanente'
            }
        }
        # Live mode: opt-out via env BULL_WEAK_LONG_SKIP=1 (rollback path)
        if ($env:BULL_WEAK_LONG_SKIP -eq '1') {
            return [PSCustomObject]@{
                allowed = $false
                tier    = 'skip'
                reason  = 'BULL_WEAK LONG -- live blacklist (env override rollback)'
            }
        }
        return [PSCustomObject]@{
            allowed = $true
            tier    = 'observe'
            reason  = 'BULL_WEAK LONG -- paper tier (re-validated 2026-05-23 +2.08pp EV, 1127 sigs/1y). Forward validation 30d.'
        }
    }

    # Regra 5 (v3 2026-05-16): SHORT bidirecional desde o início da estratégia.
    # Whitelist v2 strict_v2 (LONG-only) era restrição conservadora baseada em backtest
    # 14y BTCUSD, mas (1) ignora altcoin pump-dump pattern e (2) Bear 2022 já mostrava
    # +0.56R PF 2.10 (rejeitado por threshold cosmético dd_ratio<0.5).
    # v3 habilita SHORT live em regimes bearish + transition_down.
    if ($Direction -eq 'SHORT') {
        $bearishRegimes = @('BEAR_STRONG','BEAR_WEAK','CAPITULATION','TRANSITION_DOWN')
        if ($bearishRegimes -contains $Regime) {
            return [PSCustomObject]@{
                allowed = $true
                tier    = 'execute'
                reason  = "SHORT em $Regime (v3 bidirecional) -- regime bearish alinhado com direcao"
            }
        }
        # SIDEWAYS SHORT: observe paper (ainda risco em ranging), skip live
        if ($Regime -eq 'SIDEWAYS') {
            if ($Mode -eq 'paper') {
                return [PSCustomObject]@{
                    allowed = $true
                    tier    = 'observe'
                    reason  = "SHORT em SIDEWAYS -- paper observa, live exige bear regime"
                }
            }
            return [PSCustomObject]@{
                allowed = $false
                tier    = 'skip'
                reason  = "SHORT em SIDEWAYS -- live exige regime bearish confirmado"
            }
        }
        # BULL_* + SHORT = anti-trend perigoso, sempre skip
        return [PSCustomObject]@{
            allowed = $false
            tier    = 'skip'
            reason  = "SHORT em $Regime -- anti-trend (regime bullish), skip"
        }
    }

    # Regra 6: catch-all -> skip em ambos
    return [PSCustomObject]@{
        allowed = $false
        tier    = 'skip'
        reason  = "$Regime + $Direction nao esta na whitelist (avoid no 14y)"
    }
}

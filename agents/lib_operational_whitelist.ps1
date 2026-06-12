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

    # Regra 5 (v3 2026-05-16 + Block2 2026-05-28): SHORT bidirecional.
    # v3: SHORT live em regimes bearish + transition_down.
    # Block2 2026-05-28: adiciona SIDEWAYS e TRANSITION_UP com edge comprovado:
    #   SIDEWAYS + SHORT:       +0.34R PF 1.54 (18m dataset) -> execute paper, observe live
    #   TRANSITION_UP + SHORT:  +0.81R PF 2.60 (18m dataset, bounce failure) -> execute paper, observe live
    if ($Direction -eq 'SHORT') {
        $bearishRegimes = @('BEAR_STRONG','BEAR_WEAK','CAPITULATION','TRANSITION_DOWN')
        if ($bearishRegimes -contains $Regime) {
            return [PSCustomObject]@{
                allowed = $true
                tier    = 'execute'
                reason  = "SHORT em $Regime (v3 bidirecional) -- regime bearish alinhado com direcao"
            }
        }
        # SIDEWAYS SHORT: execute paper (edge +0.34R PF 1.54), observe live (aguarda 30d forward)
        if ($Regime -eq 'SIDEWAYS') {
            if ($Mode -eq 'paper') {
                return [PSCustomObject]@{
                    allowed = $true
                    tier    = 'execute'
                    reason  = "SHORT em SIDEWAYS -- paper execute (edge +0.34R PF 1.54, 18m dataset Block2 2026-05-28)"
                }
            }
            return [PSCustomObject]@{
                allowed = $true
                tier    = 'observe'
                reason  = "SHORT em SIDEWAYS -- live observe (aguarda 30d forward validation antes de execute)"
            }
        }
        # TRANSITION_UP + SHORT: bounce failure, execute paper (edge +0.81R PF 2.60), observe live
        if ($Regime -eq 'TRANSITION_UP') {
            if ($Mode -eq 'paper') {
                return [PSCustomObject]@{
                    allowed = $true
                    tier    = 'execute'
                    reason  = "SHORT em TRANSITION_UP -- paper execute (bounce failure +0.81R PF 2.60, 18m dataset Block2 2026-05-28)"
                }
            }
            return [PSCustomObject]@{
                allowed = $true
                tier    = 'observe'
                reason  = "SHORT em TRANSITION_UP -- live observe (aguarda 30d forward validation antes de execute)"
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


# ─────────────────────────────────────────────────────────────────────────────
# Test-WhitelistShort — Verifica se ativo está na whitelist SHORT
# ─────────────────────────────────────────────────────────────────────────────
# 2026-06-01: Função para bypass Triagem Tier D para SHORTs na whitelist
# Permite que SHORTs validados (EV +2.85pp) executem mesmo com score baixo
function Test-WhitelistShort {
    <#
    .SYNOPSIS
    Verifica se ativo está na whitelist SHORT (TIER_A_LIVE ou TIER_B_PAPER).
    
    .PARAMETER Market
    Par de trading (ex: BTCUSDT)
    
    .OUTPUTS
    [bool] $true se está na whitelist, $false caso contrário
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][string]$Market
    )

    try {
        # Carregar whitelist
        $wlPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "journal") "per_asset_whitelist_2026_05_20_v3_10.json"
        if (-not (Test-Path $wlPath)) {
            Write-Verbose "[Whitelist] Arquivo não encontrado: $wlPath"
            return $false
        }

        $wl = Get-Content $wlPath -Raw | ConvertFrom-Json
        
        # Verificar em ambas as listas
        $shortLists = @()
        if ($wl.PSObject.Properties['SHORT_TIER_A_LIVE']) {
            $shortLists += @($wl.SHORT_TIER_A_LIVE)
        }
        if ($wl.PSObject.Properties['SHORT_TIER_B_PAPER']) {
            $shortLists += @($wl.SHORT_TIER_B_PAPER)
        }

        # Procurar pelo market
        foreach ($list in $shortLists) {
            if ($null -ne ($list | Where-Object { $_.market -eq $Market })) {
                Write-Verbose "[Whitelist] $Market encontrado em SHORT whitelist"
                return $true
            }
        }

        Write-Verbose "[Whitelist] $Market NÃO encontrado em SHORT whitelist"
        return $false

    } catch {
        Write-Warning "[Whitelist] Erro ao verificar SHORT whitelist: $_"
        return $false
    }
}

# Exportada: Test-WhitelistShort

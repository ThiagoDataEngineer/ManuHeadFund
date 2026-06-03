# lib_exit_ladder.ps1 -- Multi TP/SL knowledge-driven templates
# Pester 3.x compatible
#
# Contrato:
#   Get-ExitLadder -TemplateId <string> [-Entry <decimal>] [-AtrValue <decimal>]
#   Returns PSCustomObject:
#     {
#       ladder_template_id: string
#       sl_levels: PSCustomObject[]  # { trigger, qty_pct, type }
#       tp_levels: PSCustomObject[]  # { trigger, qty_pct, type }
#       breakeven_after_tp: int      # move SL para break-even apos TP N (0=nunca)
#       notes: string
#     }
#
# Tipos de trigger:
#   price_pct  -> trigger eh % do entry (ex: TP1 a +50% = entry * 1.5)
#   atr_mult   -> trigger eh ATR * multiplicador (ex: SL a entry - ATR*1.5)
#   rr_multiple -> trigger eh entry + (entry - sl) * N (Risk:Reward N:1)

function Get-ExitLadder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('tori', 'melao_kelly', 'gem_runner', 'bull_strong_conservative')]
        [string] $TemplateId,

        [decimal] $Entry = 100,
        [decimal] $AtrValue = 0
    )

    switch ($TemplateId) {
        'tori'                       { return Get-LadderTemplate-Tori -Entry $Entry }
        'melao_kelly'                { return Get-LadderTemplate-MelaoKelly -Entry $Entry -AtrValue $AtrValue }
        'gem_runner'                 { return Get-LadderTemplate-GemRunner -Entry $Entry }
        'bull_strong_conservative'   { return Get-LadderTemplate-BullStrongConservative -Entry $Entry -AtrValue $AtrValue }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# TORI TRADES template
#
# Filosofia: T1/T2/T3 com break-even apos T1
# - TP1: +50% (recupera capital + lucro 50%)  / 30% size
# - TP2: +100% (dobra capital inicial)        / 30% size
# - TP3: +200% (runner sem limite)            / 40% size
# - SL inicial: -50%
# - Move SL para break-even (entry) apos TP1
# ────────────────────────────────────────────────────────────────────────────

function Get-LadderTemplate-Tori {
    param([decimal] $Entry = 100)

    return [PSCustomObject]@{
        ladder_template_id = 'tori'
        tp_levels = @(
            [PSCustomObject]@{
                trigger = 50
                qty_pct = 30
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 100
                qty_pct = 30
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 200
                qty_pct = 40
                type = 'price_pct'
            }
        )
        sl_levels = @(
            [PSCustomObject]@{
                trigger = -50
                qty_pct = 100
                type = 'price_pct'
            }
        )
        breakeven_after_tp = 1
        notes = "TORI: 3 TPs escalados, move SL para BE apos TP1, runner no TP3"
    }
}

# ────────────────────────────────────────────────────────────────────────────
# MELAO / SATURNO template
#
# Filosofia: Kelly fracionario com 4 TPs escalados
# - TP1: +33% / 25% size
# - TP2: +66% / 25% size
# - TP3: +100% / 25% size
# - TP4: +200% / 25% size
# - SL: ATR * 1.5 (adaptativo por volatilidade)
# ────────────────────────────────────────────────────────────────────────────

function Get-LadderTemplate-MelaoKelly {
    param([decimal] $Entry = 100, [decimal] $AtrValue = 0)

    $atrMult = if ($AtrValue -gt 0) { 1.5 } else { 1.5 }

    return [PSCustomObject]@{
        ladder_template_id = 'melao_kelly'
        tp_levels = @(
            [PSCustomObject]@{
                trigger = 33
                qty_pct = 25
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 66
                qty_pct = 25
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 100
                qty_pct = 25
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 200
                qty_pct = 25
                type = 'price_pct'
            }
        )
        sl_levels = @(
            [PSCustomObject]@{
                trigger = $atrMult
                qty_pct = 100
                type = 'atr_mult'
            }
        )
        breakeven_after_tp = 0
        notes = "MELAO: Kelly fracionario, 4 TPs 25% cada, SL por ATR * 1.5"
    }
}

# ────────────────────────────────────────────────────────────────────────────
# GEM RUNNER template
#
# Filosofia: Saida escalada em micro-cap com runner ate stop trail ou +1000%
# - TP1: +100% (recupera capital) / 30% size
# - TP2: +1000% (runner, deixa correr) / 30% size
# - SL inicial: -50%
# - Trailing stop ativado apos TP1
# ────────────────────────────────────────────────────────────────────────────

function Get-LadderTemplate-GemRunner {
    param([decimal] $Entry = 100)

    return [PSCustomObject]@{
        ladder_template_id = 'gem_runner'
        tp_levels = @(
            [PSCustomObject]@{
                trigger = 100
                qty_pct = 30
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 1000
                qty_pct = 30
                type = 'price_pct'
            },
            [PSCustomObject]@{
                trigger = 0
                qty_pct = 40
                type = 'price_pct'
            }
        )
        sl_levels = @(
            [PSCustomObject]@{
                trigger = -50
                qty_pct = 100
                type = 'price_pct'
            }
        )
        breakeven_after_tp = 1
        notes = "GEM: runner ate +1000% ou stop trail, recupera capital em TP1"
    }
}

# ────────────────────────────────────────────────────────────────────────────
# BULL_STRONG_CONSERVATIVE template
#
# Filosofia: Risk:Reward profissional 1:2 e 1:5, SL por ATR
# - TP1: 1:2 RR (entry + 2x risk) / 50% size
# - TP2: 1:5 RR (entry + 5x risk) / 50% size
# - SL: ATR * 1.5 (adaptativo)
# ────────────────────────────────────────────────────────────────────────────

function Get-LadderTemplate-BullStrongConservative {
    param([decimal] $Entry = 100, [decimal] $AtrValue = 0)

    $atrMult = if ($AtrValue -gt 0) { 1.5 } else { 1.5 }

    return [PSCustomObject]@{
        ladder_template_id = 'bull_strong_conservative'
        tp_levels = @(
            [PSCustomObject]@{
                trigger = 2
                qty_pct = 50
                type = 'rr_multiple'
            },
            [PSCustomObject]@{
                trigger = 5
                qty_pct = 50
                type = 'rr_multiple'
            }
        )
        sl_levels = @(
            [PSCustomObject]@{
                trigger = $atrMult
                qty_pct = 100
                type = 'atr_mult'
            }
        )
        breakeven_after_tp = 0
        notes = "BULL_STRONG: RR 1:2 e 1:5, SL por ATR * 1.5, entrada confluente obrigatoria"
    }
}

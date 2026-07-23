# lib_gates_drift_wire.ps1
# Wire gates_drift.json to gem_executor — dynamic gate application
# 2026-06-18: Solução rápida pra gates não estarem sendo lidas

function Get-GatesDriftConfig {
    <#
    .SYNOPSIS
        Lê config/gates_drift.json e retorna objeto com gates atuais
    .OUTPUTS
        PSCustomObject com todas as gates dinâmicas
    #>
    [CmdletBinding()]
    param()

    try {
        $gatesPath = Join-Path (Get-Location) "config/gates_drift.json"
        if (-not (Test-Path $gatesPath)) {
            # Fallback: usar padrões antigos
            Write-Verbose "[GATES] Arquivo gates_drift.json não encontrado, usando defaults"
            return @{
                conviction_threshold = 55
                conviction_floor = 40
                mesa_score_bypass = 75
                mesa_score_strong = 60
                conviction_threshold_standard = 50
                conviction_threshold_strong = 40
                tori_required = $true
                fqs_required = $true
            }
        }

        $config = Get-Content $gatesPath | ConvertFrom-Json
        return $config.gates
    }
    catch {
        Write-Warning "[GATES] Erro ao ler gates_drift.json: $_"
        return $null
    }
}

function Test-ConvictionGate {
    <#
    .SYNOPSIS
        Testa conviction contra gates dinâmicas (substitui hard-coded 55)
    .PARAMETER conviction
        Valor de conviction (0-100)
    .PARAMETER mesa_score
        Score de mesa (0-100) — se > 75, bypass conviction
    .OUTPUTS
        $true se passa, $false se rejeitado
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [int]$conviction,
        [Parameter(Mandatory=$false)] [int]$mesa_score = 0
    )

    $gates = Get-GatesDriftConfig
    if (-not $gates) { return $true }  # Fallback: deixa passar

    # Regra 1: Mesa score 75+ bypass conviction
    if ($mesa_score -gt $gates.mesa_score_bypass) {
        Write-Verbose "[GATES] Mesa score $mesa_score > 75 — BYPASS conviction"
        return $true
    }

    # Regra 2: Mesa score 60-75 usa conviction 40
    if ($mesa_score -gt $gates.mesa_score_strong) {
        $threshold = $gates.conviction_threshold_strong  # 40
        $passes = $conviction -gt $threshold
        Write-Verbose "[GATES] Mesa $mesa_score (strong), conviction $conviction vs threshold $threshold = $passes"
        return $passes
    }

    # Regra 3: floor (rede de seguranca final, nao filtro agressivo)
    # If both conviction AND mesa are low/zero, assume conviction not yet calculated — allow entry
    if ($conviction -le 0 -and $mesa_score -le 0) {
        Write-Verbose "[GATES] Both conviction and mesa unavailable (conviction=$conviction mesa=$mesa_score) — allow entry (conviction calc deferred)"
        return $true
    }

    # 2026-07-23 (auditoria "100% integro"): $Gem.conviction/mesa_score nunca
    # eram populados por nenhum gerador de candidato real -- esta regra 3
    # SEMPRE tomava o caminho acima (allow incondicional). gem_executor.ps1
    # agora calcula o ensemble real (Get-MarketConviction, 7 eixos) antes
    # deste gate, entao o threshold de fato entra em vigor pela 1a vez.
    # Medido com dados reais de mercado (2026-07-23): usar conviction_threshold
    # (50, calibrado 2026-06-18 sem nunca ter rodado) cortaria 69% dos
    # candidatos LONG que ja passaram Tori confluence>=80 -- agressivo demais
    # pra meta de volume alto (varios trades/dia, scalp). Decisao do usuario:
    # usar conviction_floor (40, ja existia no JSON desde 2026-06-18, nunca
    # usado) -- atua como rede de seguranca (so filtra os genuinamente fracos,
    # confirmado deixar passar 12/13 candidatos reais de hoje) em vez de
    # filtro agressivo. Reavaliar threshold conforme trade_outcomes reais
    # acumularem (Kelly graduation audit, ja corrigido hoje, vai ter dado
    # real pra calibrar isso soon).
    $threshold = $gates.conviction_floor  # 40
    $passes = $conviction -gt $threshold
    Write-Verbose "[GATES] Standard conviction $conviction vs floor $threshold = $passes"
    return $passes
}

function Get-ConvictionThreshold {
    <#
    .SYNOPSIS
        Retorna conviction threshold DINÂMICO (muda conforme aprende)
    .PARAMETER mesa_score
        Score de mesa (para determinar qual threshold usar)
    .OUTPUTS
        Inteiro (threshold)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [int]$mesa_score = 0
    )

    $gates = Get-GatesDriftConfig
    if (-not $gates) { return 55 }  # Fallback

    if ($mesa_score -gt $gates.mesa_score_bypass) { return 0 }     # Bypass
    if ($mesa_score -gt $gates.mesa_score_strong) { return $gates.conviction_threshold_strong }
    return $gates.conviction_threshold
}

# ═══════════════════════════════════════════════════════════════════════════════
# PATCH: Inject este arquivo em gem_executor.ps1 NO INÍCIO
# ═══════════════════════════════════════════════════════════════════════════════
#
# Adicionar após carregamento das libs:
#   . (Join-Path $PSScriptRoot "lib_gates_drift_wire.ps1")
#
# Depois, SUBSTITUA calls de conviction check:
#   OLD: if ($conviction -lt 55) { $decision = "skip_low_conviction" }
#   NEW: if (-not (Test-ConvictionGate -conviction $conviction -mesa_score $gem.mesa_score)) {
#            $decision = "skip_low_conviction"
#        }
#
# RESULT: Conviction threshold agora lido dynamicamente de gates_drift.json
# ═══════════════════════════════════════════════════════════════════════════════

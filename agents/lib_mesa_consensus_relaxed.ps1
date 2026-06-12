# agents/lib_mesa_consensus_relaxed.ps1
# TDD: Relaxar Mesa Consensus + Permitir Tier C com FORTE_3
# Data: 2026-06-01
# Objetivo: Aumentar trades de 5% para 15-20%

# ─────────────────────────────────────────────────────────────────────────────
# Test-MesaConsensusRelaxed -- Validar consensus com regra relaxada
# ─────────────────────────────────────────────────────────────────────────────
function Test-MesaConsensusRelaxed {
    <#
    .SYNOPSIS
    Valida Mesa Consensus com regra relaxada: 2/3 FORTE + 1 MEDIO (não todos FORTE)
    
    .PARAMETER TudorForce
    Força do Tudor (0-100)
    
    .PARAMETER RadarForce
    Força do Radar (0-100)
    
    .PARAMETER LidarForce
    Força do Lidar (0-100)
    
    .OUTPUTS
    [PSCustomObject]@{ passed, consensus, reason, forte_count, medio_count }
    
    .DESCRIPTION
    Regra ANTIGA (todos FORTE):
    - T >= 70 AND R >= 70 AND L >= 70 = FORTE_3
    - Resultado: ~50% bloqueado
    
    Regra NOVA (2/3 FORTE + 1 MEDIO):
    - 3/3 >= 70 = FORTE_3 (mantém)
    - 2/3 >= 70 AND 1/3 >= 50 = FORTE_3 (novo!)
    - 2/3 >= 70 AND 1/3 < 50 = MEDIO_2 (novo!)
    - 1/3 >= 70 = MEDIO_2 (novo!)
    - 0/3 >= 70 = CAOS (mantém)
    
    .EXAMPLE
    $result = Test-MesaConsensusRelaxed -TudorForce 75 -RadarForce 72 -LidarForce 45
    # Retorna: passed=$true, consensus=FORTE_3, reason="2/3 FORTE + 1 MEDIO"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][double]$TudorForce,
        [Parameter(Mandatory=$true)][double]$RadarForce,
        [Parameter(Mandatory=$true)][double]$LidarForce
    )

    # Contar quantos estão FORTE (>= 70)
    $forteCount = 0
    $medioCount = 0
    
    if ($TudorForce -ge 70) { $forteCount++ } elseif ($TudorForce -ge 50) { $medioCount++ }
    if ($RadarForce -ge 70) { $forteCount++ } elseif ($RadarForce -ge 50) { $medioCount++ }
    if ($LidarForce -ge 70) { $forteCount++ } elseif ($LidarForce -ge 50) { $medioCount++ }

    # Aplicar regra relaxada
    $consensus = "CAOS"
    $passed = $false
    $reason = ""

    if ($forteCount -eq 3) {
        # Todos FORTE
        $consensus = "FORTE_3"
        $passed = $true
        $reason = "3/3 FORTE (todos >= 70)"
    }
    elseif ($forteCount -eq 2) {
        # 2/3 FORTE - sempre FORTE_3 (relaxado)
        $consensus = "FORTE_3"
        $passed = $true
        if ($medioCount -ge 1) {
            $reason = "2/3 FORTE + 1 MEDIO (relaxado)"
        } else {
            $reason = "2/3 FORTE + 1 FRACO (relaxado)"
        }
    }
    elseif ($forteCount -eq 1 -and $medioCount -ge 2) {
        # 1/3 FORTE + 2 MEDIO
        $consensus = "MEDIO_2"
        $passed = $true
        $reason = "1/3 FORTE + 2 MEDIO"
    }
    elseif ($forteCount -eq 1 -and $medioCount -eq 1) {
        # 1/3 FORTE + 1 MEDIO + 1 FRACO
        $consensus = "MEDIO_2"
        $passed = $true
        $reason = "1/3 FORTE + 1 MEDIO + 1 FRACO"
    }
    else {
        # 0 FORTE ou muito fraco
        $consensus = "CAOS"
        $passed = $false
        $reason = "Sem consensus: $forteCount FORTE, $medioCount MEDIO"
    }

    return [PSCustomObject]@{
        passed = $passed
        consensus = $consensus
        reason = $reason
        forte_count = $forteCount
        medio_count = $medioCount
        tudor_force = $TudorForce
        radar_force = $RadarForce
        lidar_force = $LidarForce
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-TierCWithMesaForte -- Permitir Tier C se Mesa FORTE_3
# ─────────────────────────────────────────────────────────────────────────────
function Test-TierCWithMesaForte {
    <#
    .SYNOPSIS
    Permite Tier C se Mesa Consensus é FORTE_3 (novo!)
    
    .PARAMETER TriagemTier
    Tier da triagem (A/B/C/D)
    
    .PARAMETER MesaConsensus
    Consensus da mesa (FORTE_3/MEDIO_2/CAOS)
    
    .OUTPUTS
    [PSCustomObject]@{ approved, tier_final, reason }
    
    .DESCRIPTION
    Regra ANTIGA:
    - Tier C = ABORTAR (disqualificante direto)
    
    Regra NOVA:
    - Tier C + Mesa FORTE_3 = APROVADO (promove para Tier B)
    - Tier C + Mesa MEDIO_2 = ABORTAR (mantém)
    - Tier C + Mesa CAOS = ABORTAR (mantém)
    
    .EXAMPLE
    $result = Test-TierCWithMesaForte -TriagemTier "C" -MesaConsensus "FORTE_3"
    # Retorna: approved=$true, tier_final="B", reason="Tier C + Mesa FORTE_3 = promove"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$TriagemTier,
        [Parameter(Mandatory=$true)][string]$MesaConsensus
    )

    $approved = $false
    $tierFinal = $TriagemTier
    $reason = ""

    # Regra: Tier C + Mesa FORTE_3 = APROVADO
    if ($TriagemTier -eq "C" -and $MesaConsensus -eq "FORTE_3") {
        $approved = $true
        $tierFinal = "B"  # Promove para Tier B
        $reason = "Tier C + Mesa FORTE_3 = promove para Tier B (novo!)"
    }
    elseif ($TriagemTier -eq "C") {
        $approved = $false
        $tierFinal = "C"
        $reason = "Tier C sem Mesa FORTE_3 = ABORTAR (mantém regra)"
    }
    else {
        # Tier A/B/D - não afeta
        $approved = $true
        $tierFinal = $TriagemTier
        $reason = "Tier $TriagemTier (não afetado por regra Tier C)"
    }

    return [PSCustomObject]@{
        approved = $approved
        tier_final = $tierFinal
        reason = $reason
        triagem_tier = $TriagemTier
        mesa_consensus = $MesaConsensus
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TESTES TDD
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-MesaConsensusRelaxedTests {
    <#
    .SYNOPSIS
    Testes TDD para validar regras relaxadas
    #>
    [CmdletBinding()]
    param()

    Write-Host "🧪 TESTES TDD - MESA CONSENSUS RELAXADO" -ForegroundColor Cyan
    Write-Host ""

    $passed = 0
    $failed = 0

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 1: Todos FORTE (3/3)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 1: Todos FORTE (3/3)" -ForegroundColor Yellow
    $result = Test-MesaConsensusRelaxed -TudorForce 75 -RadarForce 72 -LidarForce 78
    if ($result.consensus -eq "FORTE_3" -and $result.passed -eq $true) {
        Write-Host "  ✅ PASSOU: consensus=FORTE_3, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado FORTE_3, obteve $($result.consensus)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 2: 2/3 FORTE + 1 MEDIO (novo!)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 2: 2/3 FORTE + 1 MEDIO (novo!)" -ForegroundColor Yellow
    $result = Test-MesaConsensusRelaxed -TudorForce 75 -RadarForce 72 -LidarForce 45
    if ($result.consensus -eq "FORTE_3" -and $result.passed -eq $true) {
        Write-Host "  ✅ PASSOU: consensus=FORTE_3, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado FORTE_3, obteve $($result.consensus)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 3: 2/3 FORTE + 1 FRACO (agora é FORTE_3 com regra relaxada)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 3: 2/3 FORTE + 1 FRACO (agora é FORTE_3)" -ForegroundColor Yellow
    $result = Test-MesaConsensusRelaxed -TudorForce 75 -RadarForce 72 -LidarForce 30
    if ($result.consensus -eq "FORTE_3" -and $result.passed -eq $true) {
        Write-Host "  ✅ PASSOU: consensus=FORTE_3, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado FORTE_3, obteve $($result.consensus)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 4: 1/3 FORTE + 2 MEDIO
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 4: 1/3 FORTE + 2 MEDIO" -ForegroundColor Yellow
    $result = Test-MesaConsensusRelaxed -TudorForce 75 -RadarForce 55 -LidarForce 52
    if ($result.consensus -eq "MEDIO_2" -and $result.passed -eq $true) {
        Write-Host "  ✅ PASSOU: consensus=MEDIO_2, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado MEDIO_2, obteve $($result.consensus)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 5: 0 FORTE (CAOS)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 5: 0 FORTE (CAOS)" -ForegroundColor Yellow
    $result = Test-MesaConsensusRelaxed -TudorForce 45 -RadarForce 40 -LidarForce 35
    if ($result.consensus -eq "CAOS" -and $result.passed -eq $false) {
        Write-Host "  ✅ PASSOU: consensus=CAOS, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado CAOS, obteve $($result.consensus)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 6: Tier C + Mesa FORTE_3 (novo!)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 6: Tier C + Mesa FORTE_3 (novo!)" -ForegroundColor Yellow
    $result = Test-TierCWithMesaForte -TriagemTier "C" -MesaConsensus "FORTE_3"
    if ($result.approved -eq $true -and $result.tier_final -eq "B") {
        Write-Host "  ✅ PASSOU: tier_final=B, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado tier=B, obteve $($result.tier_final)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 7: Tier C + Mesa MEDIO_2 (mantém ABORTAR)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 7: Tier C + Mesa MEDIO_2 (mantém ABORTAR)" -ForegroundColor Yellow
    $result = Test-TierCWithMesaForte -TriagemTier "C" -MesaConsensus "MEDIO_2"
    if ($result.approved -eq $false -and $result.tier_final -eq "C") {
        Write-Host "  ✅ PASSOU: tier_final=C (ABORTAR), reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado tier=C, obteve $($result.tier_final)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Teste 8: Tier B + Mesa MEDIO_2 (não afetado)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "Teste 8: Tier B + Mesa MEDIO_2 (não afetado)" -ForegroundColor Yellow
    $result = Test-TierCWithMesaForte -TriagemTier "B" -MesaConsensus "MEDIO_2"
    if ($result.approved -eq $true -and $result.tier_final -eq "B") {
        Write-Host "  ✅ PASSOU: tier_final=B, reason='$($result.reason)'" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ FALHOU: esperado tier=B, obteve $($result.tier_final)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""

    # ─────────────────────────────────────────────────────────────────────────
    # Resumo
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "RESUMO: $passed PASSOU, $failed FALHOU" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return @{ passed = $passed; failed = $failed }
}

# Exportadas: Test-MesaConsensusRelaxed, Test-TierCWithMesaForte, Invoke-MesaConsensusRelaxedTests

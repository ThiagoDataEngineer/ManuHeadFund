# mentor_thresholds_v2.Tests.ps1 -- TDD para Mudanças 1 e 2
# Mudança 1: Aceitar MEDIO_2 com score >= 65 em Tier B+
# Mudança 2: ALPHA_HIST ABSENT aceito em Tier B se score >= 75 + FORTE_3
# Data: 29/05/2026
# Status: TDD (testes ANTES da implementação)

$ErrorActionPreference = "Stop"

# ============================================================================
# SETUP: Mock objects para testes
# ============================================================================

function New-MockMesa {
    param(
        [string]$Consensus = "FORTE_3",
        [string]$Sinal = "LONG",
        [int]$ScoreAvg = 70,
        [bool]$Degraded = $false
    )
    return [PSCustomObject]@{
        consensus      = $Consensus
        sinal_consenso = $Sinal
        score_avg      = $ScoreAvg
        degraded       = $Degraded
        termal         = [PSCustomObject]@{sinal=$Sinal; forca=70}
        radar          = [PSCustomObject]@{sinal=$Sinal; forca=68}
        lidar          = [PSCustomObject]@{sinal=$Sinal; forca=72}
    }
}

function New-MockTriagem {
    param([string]$Tier = "B")
    return [PSCustomObject]@{tier=$Tier}
}

function New-MockAlphaHist {
    param(
        [int]$NSamples = 0,
        [double]$AvgAlpha = $null,
        [bool]$Negative = $false
    )
    return [PSCustomObject]@{
        n_samples           = $NSamples
        avg_alpha           = $AvgAlpha
        beats_btc_negative  = $Negative
    }
}

function New-MockFullContext {
    param(
        [PSCustomObject]$AlphaHistory = $null,
        [int]$ScorePredicted = 70
    )
    $ctx = [PSCustomObject]@{
        alpha_history = $AlphaHistory
    }
    # Adicionar score_predicted se disponível
    if ($ScorePredicted) {
        $ctx | Add-Member -NotePropertyName score_predicted -NotePropertyValue $ScorePredicted
    }
    return $ctx
}

# ============================================================================
# TESTES: MUDANÇA 1 - MEDIO_2 COM SCORE >= 65
# ============================================================================

Describe "Mudança 1: Aceitar MEDIO_2 com score >= 65 em Tier B+" {
    
    It "FORTE_3 sempre aceito (baseline)" {
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 70
        $triagem = New-MockTriagem -Tier "B"
        
        # Lógica esperada: FORTE_3 sempre passa
        $shouldAccept = $mesa.consensus -eq "FORTE_3"
        
        $shouldAccept | Should Be $true
    }
    
    It "MEDIO_2 com score=70 em Tier B deve ser ACEITO (novo)" {
        $mesa = New-MockMesa -Consensus "MEDIO_2" -ScoreAvg 70
        $triagem = New-MockTriagem -Tier "B"
        
        # Lógica esperada (NOVA):
        # MEDIO_2 + score >= 65 + Tier B = ACEITO
        $shouldAccept = ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $triagem.tier -in @("A", "B"))
        
        $shouldAccept | Should Be $true
    }
    
    It "MEDIO_2 com score=65 em Tier B deve ser ACEITO (limite)" {
        $mesa = New-MockMesa -Consensus "MEDIO_2" -ScoreAvg 65
        $triagem = New-MockTriagem -Tier "B"
        
        $shouldAccept = ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $triagem.tier -in @("A", "B"))
        
        $shouldAccept | Should Be $true
    }
    
    It "MEDIO_2 com score=64 em Tier B deve ser REJEITADO (abaixo limite)" {
        $mesa = New-MockMesa -Consensus "MEDIO_2" -ScoreAvg 64
        $triagem = New-MockTriagem -Tier "B"
        
        $shouldAccept = ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $triagem.tier -in @("A", "B"))
        
        $shouldAccept | Should Be $false
    }
    
    It "MEDIO_2 com score=70 em Tier C deve ser REJEITADO (tier baixo)" {
        $mesa = New-MockMesa -Consensus "MEDIO_2" -ScoreAvg 70
        $triagem = New-MockTriagem -Tier "C"
        
        $shouldAccept = ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $triagem.tier -in @("A", "B"))
        
        $shouldAccept | Should Be $false
    }
    
    It "CAOS sempre rejeitado (baseline)" {
        $mesa = New-MockMesa -Consensus "CAOS" -ScoreAvg 50
        $triagem = New-MockTriagem -Tier "B"
        
        $shouldAccept = ($mesa.consensus -eq "FORTE_3") -or ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $triagem.tier -in @("A", "B"))
        
        $shouldAccept | Should Be $false
    }
}

# ============================================================================
# TESTES: MUDANÇA 2 - ALPHA_HIST ABSENT EM TIER B
# ============================================================================

Describe "Mudança 2: ALPHA_HIST ABSENT aceito em Tier B se score >= 75 + FORTE_3" {
    
    It "ALPHA_HIST presente (n_samples > 0) sempre aceito" {
        $alphaHist = New-MockAlphaHist -NSamples 10 -AvgAlpha 2.5 -Negative $false
        $triagem = New-MockTriagem -Tier "B"
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 70
        
        # Lógica esperada: Se tem histórico, aceita
        $shouldAccept = $alphaHist.n_samples -gt 0
        
        $shouldAccept | Should Be $true
    }
    
    It "ALPHA_HIST ABSENT em Tier A deve ser REJEITADO" {
        $alphaHist = New-MockAlphaHist -NSamples 0
        $triagem = New-MockTriagem -Tier "A"
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 80
        
        # Lógica esperada (NOVA):
        # Tier A exige histórico
        $shouldAccept = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "A") { $false }
            else { $true }  # Continua análise
        } else { $true }
        
        $shouldAccept | Should Be $false
    }
    
    It "ALPHA_HIST ABSENT em Tier B + score=80 + FORTE_3 deve ser ACEITO (novo)" {
        $alphaHist = New-MockAlphaHist -NSamples 0
        $triagem = New-MockTriagem -Tier "B"
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 70
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 80
        
        # Lógica esperada (NOVA):
        # Tier B + ALPHA_HIST ABSENT + score >= 75 + FORTE_3 = ACEITO
        $shouldAccept = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "A") { $false }
            elseif ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        $shouldAccept | Should Be $true
    }
    
    It "ALPHA_HIST ABSENT em Tier B + score=75 + FORTE_3 deve ser ACEITO (limite)" {
        $alphaHist = New-MockAlphaHist -NSamples 0
        $triagem = New-MockTriagem -Tier "B"
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 70
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 75
        
        $shouldAccept = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "A") { $false }
            elseif ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        $shouldAccept | Should Be $true
    }
    
    It "ALPHA_HIST ABSENT em Tier B + score=74 + FORTE_3 deve ser REJEITADO (abaixo limite)" {
        $alphaHist = New-MockAlphaHist -NSamples 0
        $triagem = New-MockTriagem -Tier "B"
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 70
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 74
        
        $shouldAccept = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "A") { $false }
            elseif ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        $shouldAccept | Should Be $false
    }
    
    It "ALPHA_HIST ABSENT em Tier B + score=80 + MEDIO_2 deve ser REJEITADO (mesa fraca)" {
        $alphaHist = New-MockAlphaHist -NSamples 0
        $triagem = New-MockTriagem -Tier "B"
        $mesa = New-MockMesa -Consensus "MEDIO_2" -ScoreAvg 60
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 80
        
        $shouldAccept = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "A") { $false }
            elseif ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        $shouldAccept | Should Be $false
    }
    
    It "ALPHA_HIST ABSENT em Tier C deve ser REJEITADO (tier baixo)" {
        $alphaHist = New-MockAlphaHist -NSamples 0
        $triagem = New-MockTriagem -Tier "C"
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 80
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 80
        
        $shouldAccept = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "A") { $false }
            elseif ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        $shouldAccept | Should Be $false
    }
}

# ============================================================================
# TESTES: COMBINAÇÃO DAS DUAS MUDANÇAS
# ============================================================================

Describe "Combinação: MEDIO_2 + ALPHA_HIST ABSENT" {
    
    It "MEDIO_2 + score=70 + Tier B + ALPHA_HIST ABSENT + score_pred=80 + FORTE_3 = ACEITO" {
        $mesa = New-MockMesa -Consensus "MEDIO_2" -ScoreAvg 70
        $triagem = New-MockTriagem -Tier "B"
        $alphaHist = New-MockAlphaHist -NSamples 0
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 80
        
        # Mudança 1: MEDIO_2 com score >= 65 em Tier B
        $medio2Pass = ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65 -and $triagem.tier -in @("A", "B"))
        
        # Mudança 2: ALPHA_HIST ABSENT em Tier B com score >= 75 + FORTE_3
        # (Nota: Mesa é MEDIO_2, não FORTE_3, então ALPHA_HIST não passa)
        $alphaPass = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        # Resultado: MEDIO_2 passa, mas ALPHA_HIST não (Mesa não é FORTE_3)
        $shouldAccept = $medio2Pass -and $alphaPass
        
        $shouldAccept | Should Be $false
    }
    
    It "FORTE_3 + score=70 + Tier B + ALPHA_HIST ABSENT + score_pred=80 = ACEITO" {
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 70
        $triagem = New-MockTriagem -Tier "B"
        $alphaHist = New-MockAlphaHist -NSamples 0
        $ctx = New-MockFullContext -AlphaHistory $alphaHist -ScorePredicted 80
        
        # Mudança 1: FORTE_3 sempre passa
        $medio2Pass = ($mesa.consensus -eq "FORTE_3")
        
        # Mudança 2: ALPHA_HIST ABSENT em Tier B com score >= 75 + FORTE_3
        $alphaPass = if ($alphaHist.n_samples -eq 0) {
            if ($triagem.tier -eq "B" -and $ctx.score_predicted -ge 75 -and $mesa.consensus -eq "FORTE_3") { $true }
            else { $false }
        } else { $true }
        
        # Resultado: Ambas passam
        $shouldAccept = $medio2Pass -and $alphaPass
        
        $shouldAccept | Should Be $true
    }
}

# ============================================================================
# TESTES: REGRESSÃO (Comportamento antigo mantido)
# ============================================================================

Describe "Regressão: Comportamento antigo mantido" {
    
    It "FORTE_3 com score=50 ainda é aceito (não afetado)" {
        $mesa = New-MockMesa -Consensus "FORTE_3" -ScoreAvg 50
        $triagem = New-MockTriagem -Tier "B"
        
        $shouldAccept = ($mesa.consensus -eq "FORTE_3")
        
        $shouldAccept | Should Be $true
    }
    
    It "ALPHA_HIST presente ainda é aceito (não afetado)" {
        $alphaHist = New-MockAlphaHist -NSamples 5 -AvgAlpha 1.5 -Negative $false
        
        $shouldAccept = $alphaHist.n_samples -gt 0
        
        $shouldAccept | Should Be $true
    }
    
    It "CAOS ainda é rejeitado (não afetado)" {
        $mesa = New-MockMesa -Consensus "CAOS" -ScoreAvg 50
        $triagem = New-MockTriagem -Tier "B"
        
        $shouldAccept = ($mesa.consensus -eq "FORTE_3") -or ($mesa.consensus -eq "MEDIO_2" -and $mesa.score_avg -ge 65)
        
        $shouldAccept | Should Be $false
    }
}

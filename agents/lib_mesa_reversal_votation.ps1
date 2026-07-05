# lib_mesa_reversal_votation.ps1 — Fase 4: Mesa votação em REVERSAL_WATCH
# Tori (estrutura), Ricardo (reversão), López (funding/flow) votam em SHORT reversal setup

. (Join-Path $PSScriptRoot "lib_journal.ps1")

# ─────────────────────────────────────────────────────────────────────────────
# Tori-StructureVote: Valida estrutura do pico (confirmação de topo)
# Critérios: wick >2%, fechou below peak, volume decline
# ─────────────────────────────────────────────────────────────────────────────
function Tori-StructureVote {
    param(
        [double] $PeakPrice = 0,
        [double] $ClosePrice = 0,
        [double] $LowPrice = 0,
        [double] $WickPct = 0,
        [double] $PeakVolume = 0,
        [double] $CurrentVolume = 0
    )

    $vote = "NO_CONFIDENCE"
    $score = 0
    $reasons = @()

    # Critério 1: Wick (shadow superior) >2% = rejeitou pico
    if ($WickPct -ge 0.02) {
        $score += 25
        $reasons += "WICK_REJECTION_$($WickPct.ToString('P1'))"
    }

    # Critério 2: Fechou below peak = confirmação de reversão
    if ($ClosePrice -lt $PeakPrice) {
        $score += 25
        $reasons += "CLOSE_BELOW_PEAK"
    }

    # Critério 3: Volume no pico > volume agora (volume drying = perda de interesse)
    if ($PeakVolume -gt $CurrentVolume) {
        $score += 25
        $reasons += "VOLUME_DECLINE"
    }

    # Critério 4: Pico realmente foi o high (não é micro-wick)
    if ($PeakPrice -gt $ClosePrice * 1.01) {
        $score += 25
        $reasons += "PEAK_CONFIRMED_NOT_WICK"
    }

    if ($score -ge 75) {
        $vote = "STRONG_YES"
    } elseif ($score -ge 50) {
        $vote = "YES"
    } elseif ($score -ge 25) {
        $vote = "MAYBE"
    }

    return [PSCustomObject]@{
        voter = "TORI_STRUCTURE"
        vote = $vote
        score = $score
        reasons = $reasons
        confidence = [math]::Round(($score / 100), 2)
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Ricardo-ReversalVote: Valida padrão de reversão (ADX rise, RSI >70 then fall)
# Critérios: ADX >20, RSI decline from peak, MACD negative
# ─────────────────────────────────────────────────────────────────────────────
function Ricardo-ReversalVote {
    param(
        [double] $ADX = 0,
        [double] $RSI = 0,
        [double] $RSIPeakValue = 85,
        [double] $MACD = 0,
        [double] $RetractionPct = 0
    )

    $vote = "NO_CONFIDENCE"
    $score = 0
    $reasons = @()

    # Critério 1: ADX >20 = trend força rising (confirmação de reversão é forte)
    if ($ADX -ge 20) {
        $score += 25
        $reasons += "ADX_CONFIRMED_$($ADX.ToString('F1'))"
    }

    # Critério 2: RSI declined from overbought (85+)
    if ($RSI -lt $RSIPeakValue -and $RSI -lt 70) {
        $score += 25
        $reasons += "RSI_DECLINE_FROM_OVERBOUGHT"
    }

    # Critério 3: MACD negative (momentum turn)
    if ($MACD -lt 0) {
        $score += 25
        $reasons += "MACD_NEGATIVE"
    }

    # Critério 4: Retração visible (>5% = não micro movimento)
    if ($RetractionPct -gt 5) {
        $score += 25
        $reasons += "RETRACTION_VISIBLE_$($RetractionPct.ToString('F1'))%"
    }

    if ($score -ge 75) {
        $vote = "STRONG_YES"
    } elseif ($score -ge 50) {
        $vote = "YES"
    } elseif ($score -ge 25) {
        $vote = "MAYBE"
    }

    return [PSCustomObject]@{
        voter = "RICARDO_REVERSAL"
        vote = $vote
        score = $score
        reasons = $reasons
        confidence = [math]::Round(($score / 100), 2)
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Lopez-FundingVote: Valida exit de longs (funding rate, open interest decline)
# Critérios: funding <-0.001, OI decline, CVD negative
# ─────────────────────────────────────────────────────────────────────────────
function Lopez-FundingVote {
    param(
        [double] $FundingRate = 0,
        [double] $OpenInterestPeakValue = 0,
        [double] $OpenInterestCurrent = 0,
        [double] $CVD = 0,  # Cumulative Volume Delta
        [int] $OIDeclinePct = 0
    )

    $vote = "NO_CONFIDENCE"
    $score = 0
    $reasons = @()

    # Critério 1: Funding negativo (longs pagando = saindo)
    if ($FundingRate -lt -0.001) {
        $score += 25
        $reasons += "FUNDING_NEGATIVE_$($FundingRate.ToString('F6'))"
    }

    # Critério 2: OI em declínio (posições sendo fechadas)
    if ($OIDeclinePct -gt 5) {
        $score += 25
        $reasons += "OI_DECLINE_$($OIDeclinePct)%"
    }

    # Critério 3: CVD negativo (acúmulo de sales)
    if ($CVD -lt 0) {
        $score += 25
        $reasons += "CVD_NEGATIVE"
    }

    # Critério 4: Strong flow reversal
    if ($FundingRate -lt -0.003 -and $CVD -lt -1000000) {
        $score += 25
        $reasons += "STRONG_FLOW_REVERSAL"
    }

    if ($score -ge 75) {
        $vote = "STRONG_YES"
    } elseif ($score -ge 50) {
        $vote = "YES"
    } elseif ($score -ge 25) {
        $vote = "MAYBE"
    }

    return [PSCustomObject]@{
        voter = "LOPEZ_FUNDING"
        vote = $vote
        score = $score
        reasons = $reasons
        confidence = [math]::Round(($score / 100), 2)
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-MesaVotation: Executa votação 3-axis dos mentores
# Retorna: entry_approved (2+ YES), consensus_level
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-MesaVotation {
    param(
        [string] $Market = "BTCUSDT",
        [PSCustomObject] $StructureData = $null,
        [PSCustomObject] $ReversalData = $null,
        [PSCustomObject] $FundingData = $null
    )

    # Recolhe votos
    $tori_vote = Tori-StructureVote @StructureData
    $ricardo_vote = Ricardo-ReversalVote @ReversalData
    $lopez_vote = Lopez-FundingVote @FundingData

    # Contabiliza YES votes
    $yes_votes = @($tori_vote, $ricardo_vote, $lopez_vote) | Where-Object { $_.vote -in @("YES", "STRONG_YES") } | Measure-Object | Select-Object -ExpandProperty Count
    $strong_yes_votes = @($tori_vote, $ricardo_vote, $lopez_vote) | Where-Object { $_.vote -eq "STRONG_YES" } | Measure-Object | Select-Object -ExpandProperty Count

    # Consenso: 2+ YES ou 1+ STRONG_YES
    $entry_approved = ($yes_votes -ge 2) -or ($strong_yes_votes -ge 1)
    $consensus_level = "WEAK"
    if ($strong_yes_votes -ge 2) { $consensus_level = "STRONG" }
    elseif ($yes_votes -ge 3) { $consensus_level = "UNANIMOUS" }
    elseif ($yes_votes -ge 2) { $consensus_level = "MAJORITY" }

    $avg_confidence = [math]::Round((($tori_vote.confidence + $ricardo_vote.confidence + $lopez_vote.confidence) / 3), 2)

    return [PSCustomObject]@{
        market = $Market
        entry_approved = $entry_approved
        yes_votes = $yes_votes
        strong_yes_votes = $strong_yes_votes
        consensus_level = $consensus_level
        avg_confidence = $avg_confidence
        votes = @{
            tori = $tori_vote
            ricardo = $ricardo_vote
            lopez = $lopez_vote
        }
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Log-MesaVotation: Persiste resultados de votação
# ─────────────────────────────────────────────────────────────────────────────
function Log-MesaVotation {
    param(
        [PSCustomObject] $VotationResult
    )

    $log_file = "$(Get-JournalDir)\mesa_votations.jsonl"
    $json = $VotationResult | ConvertTo-Json -Compress
    Add-Content -Path $log_file -Value $json -ErrorAction SilentlyContinue
}

# PS 5.1: Export-ModuleMember only works inside modules; these functions are available via dot-source

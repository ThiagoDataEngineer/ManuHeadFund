# lib_mentor_hallucination_detector.ps1 -- Mentor hallucination detector v2

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-MentorHallucinationAudit {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $MentorOutput,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $hallucinPath = Join-Path $JournalDir "mentor_hallucinations.jsonl"

    $isHallucination = $false
    $reasons = @()

    # Check 1: conviction sem data sources
    if ($MentorOutput.conviction -gt 0 -and ($null -eq $MentorOutput.data_sources -or $MentorOutput.data_sources.Count -eq 0)) {
        $isHallucination = $true
        $reasons += "Conviction $($MentorOutput.conviction) sem fontes de dados"
    }

    # Check 2: reasoning menciona metricas não calculadas
    if ($null -ne $MentorOutput.reasoning -and $null -ne $MentorOutput.calculated_metrics) {
        $reasoning = $MentorOutput.reasoning
        if ($reasoning -match "RSI" -and $MentorOutput.calculated_metrics -notcontains "RSI") {
            $isHallucination = $true
            $reasons += "Reasoning cita RSI mas não foi calculado"
        }
    }

    # Registra audit entry
    $auditEntry = [ordered]@{
        timestamp = $timestamp
        market = $MentorOutput.market
        conviction = $MentorOutput.conviction
        is_hallucination = $isHallucination
        reason = ($reasons -join " | ")
    } | ConvertTo-Json -Compress

    Add-Content -Path $hallucinPath -Value $auditEntry -Encoding UTF8

    return [PSCustomObject]@{
        is_hallucination = $isHallucination
        reason = ($reasons -join " | ")
        market = $MentorOutput.market
        conviction = $MentorOutput.conviction
    }
}

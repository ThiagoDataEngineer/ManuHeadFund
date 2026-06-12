# lib_mentor_audit_simple.ps1 — Mentor decision audit (SIMPLIFICADO)

function Get-MentorDecisionsRecent {
    param([int]$Limit = 100, [string]$JournalDir = $global:JOURNAL_DIR)

    $file = Join-Path $JournalDir "decisions_text.jsonl"
    if (-not (Test-Path $file)) { return @() }

    # Read JSONL line by line
    $all = @()
    Get-Content $file | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try {
            $all += (ConvertFrom-Json $_)
        } catch { }
    }

    if ($all.Count -le $Limit) { return $all }
    return $all[-$Limit..-1]  # últimas N
}

function Sample-MentorDecisions {
    param([object[]]$Decisions, [int]$SampleSize = 20)

    if ($Decisions.Count -le $SampleSize) { return $Decisions }

    $indices = @(0..($Decisions.Count-1)) | Get-Random -Count $SampleSize
    return $Decisions[$indices]
}

function Export-MentorAuditSample {
    param(
        [object[]]$Decisions,
        [string]$OutputFile
    )

    $audit = @()
    foreach ($d in $Decisions) {
        $audit += [PSCustomObject]@{
            timestamp = $d.timestamp
            market = $d.market
            mentor_decision = $d.decision  # APROVAR/VETAR/SKIP
            direction = $d.direction
            score = $d.score
            gates_passed = ($d.gates_passed -join "|")
            notes = $d.notes
            # Human auditor fills:
            # was_correct_yn = "Y/N"
            # reason = "..."
        }
    }

    $audit | Export-Csv -Path $OutputFile -Encoding UTF8 -NoTypeInformation
    return @{ count=$audit.Count; file=$OutputFile }
}

function Get-MentorAccuracy {
    param([string]$AuditFile)

    if (-not (Test-Path $AuditFile)) { return @{ accuracy=0; total=0 } }

    $audit = Import-Csv $AuditFile -Encoding UTF8
    $correct = @($audit | Where-Object { $_.was_correct_yn -eq "Y" }).Count
    $total = $audit.Count

    return @{
        accuracy = if ($total -gt 0) { [math]::Round($correct/$total*100, 1) } else { 0 }
        correct = $correct
        total = $total
    }
}

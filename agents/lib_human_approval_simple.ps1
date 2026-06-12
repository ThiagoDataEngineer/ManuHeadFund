# lib_human_approval_simple.ps1 — Human approval >$100 (SIMPLIFICADO)

function Request-HumanApproval {
    param(
        [string]$Market,
        [double]$SizeUsd,
        [int]$TimeoutSeconds = 300
    )

    # Se <$100, sem aprovação
    if ($SizeUsd -lt 100) {
        return @{ approved=$true; method="auto_under_100" }
    }

    # Envia TG pedindo aprovação
    $msg = "🔔 **APROVAÇÃO NECESSÁRIA**`n$Market | Size: `$$([math]::Round($SizeUsd,2))`nResponda: /approve ou /reject (${TimeoutSeconds}s timeout)"
    try {
        Send-TelegramAlert -Message $msg | Out-Null
    } catch { }

    # Aguarda resposta (simples: sem timeout real por enquanto)
    # Em produção: query database de approvals
    $approvalFile = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
    $pending = @{ market=$Market; size_usd=$SizeUsd; requested_at=(Get-Date).ToString("o"); status="PENDING" }
    Add-Content -Path $approvalFile -Value ($pending | ConvertTo-Json -Compress) -Encoding UTF8

    # Retorna PENDING (sistema aguarda ou timeout)
    return @{ approved=$null; method="human_pending"; request_id="$Market-$(Get-Date -Format HHmmss)" }
}

function Get-PendingApprovals {
    param([string]$JournalDir = $global:JOURNAL_DIR)
    $file = Join-Path $JournalDir "human_approvals_pending.jsonl"
    if (-not (Test-Path $file)) { return @() }

    # Read JSONL line by line
    $result = @()
    Get-Content $file | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try {
            $obj = ConvertFrom-Json $_
            if ($obj.status -eq "PENDING") { $result += $obj }
        } catch { }
    }
    return $result
}

function Mark-ApprovalDone {
    param([string]$MarketId, [bool]$Approved)
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $file = Join-Path $journalDir "human_approvals_pending.jsonl"
    if (-not (Test-Path $file)) { return }

    $updated = @()
    Get-Content $file | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try {
            $obj = ConvertFrom-Json $_
            if ($obj.market -eq $MarketId) {
                $obj | Add-Member -Name "status" -Value (if ($Approved) { "APPROVED" } else { "REJECTED" }) -Force
                $obj | Add-Member -Name "decided_at" -Value ((Get-Date).ToString("o")) -Force
            }
            $updated += $obj
        } catch { }
    }

    if ($updated.Count -gt 0) {
        $updated | ConvertTo-Json -AsArray | Set-Content $file -Encoding UTF8
    }
}

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
    return ,$result
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
                # 2026-07-23 FIX: 2 bugs empilhados aqui, ambos engolidos
                # pelo catch abaixo (Mark-ApprovalDone NUNCA marcava status
                # em producao): (1) Add-Member exige -MemberType, nao existe
                # overload sem ele; (2) "if(){}else{}" usado como expressao
                # inline dentro de "-Value (...)" nao e valido como argumento
                # de parametro ("'if' is not recognized as a cmdlet") --
                # precisa ser calculado numa variavel antes.
                $newStatus = if ($Approved) { "APPROVED" } else { "REJECTED" }
                $obj | Add-Member -MemberType NoteProperty -Name "status" -Value $newStatus -Force
                $obj | Add-Member -MemberType NoteProperty -Name "decided_at" -Value ((Get-Date).ToString("o")) -Force
            }
            $updated += $obj
        } catch { }
    }

    if ($updated.Count -gt 0) {
        # 2026-07-23 FIX: -AsArray e PS7+ only, nao existe no PowerShell 5.1
        # (motor real de producao/CI) -- quebraria com "parametro nao
        # encontrado" em runtime real. Reescreve JSONL manualmente (1 linha
        # -Compress por registro), preservando o formato real do arquivo.
        $lines = @($updated | ForEach-Object { $_ | ConvertTo-Json -Compress })
        Set-Content -Path $file -Value $lines -Encoding UTF8
    }
}

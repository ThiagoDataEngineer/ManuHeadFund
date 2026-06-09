# lib_tg_approval_handler.ps1 — Handle /approve /reject /resume from Telegram

function Process-ApprovalCommand {
    param(
        [string]$Command,      # /approve, /reject, /resume
        [string]$Market = "",  # BTCUSDT (optional)
        [string]$JournalDir = $global:JOURNAL_DIR
    )

    $journalDir = if ($JournalDir) { $JournalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }

    switch -Regex ($Command.ToLower()) {
        '/approve' {
            if (-not $Market) { return @{ status="error"; message="Uso: /approve BTCUSDT" } }

            # Mark pending approval como APPROVED
            $file = Join-Path $journalDir "human_approvals_pending.jsonl"
            if (Test-Path $file) {
                $updated = @()
                Get-Content $file | Where-Object { $_ -match '^\{' } | ForEach-Object {
                    try {
                        $obj = ConvertFrom-Json $_
                        if ($obj.market -eq $Market) {
                            $obj | Add-Member -Name "status" -Value "APPROVED" -Force
                            $obj | Add-Member -Name "decided_at" -Value ((Get-Date).ToString("o")) -Force
                        }
                        $updated += $obj
                    } catch { }
                }
                if ($updated.Count -gt 0) {
                    $updated | ConvertTo-Json -AsArray | Set-Content $file -Encoding UTF8
                }
            }

            return @{ status="ok"; message="✅ $Market aprovado. Executando trade..." }
        }

        '/reject' {
            if (-not $Market) { return @{ status="error"; message="Uso: /reject BTCUSDT" } }

            # Mark pending approval como REJECTED
            $file = Join-Path $journalDir "human_approvals_pending.jsonl"
            if (Test-Path $file) {
                $updated = @()
                Get-Content $file | Where-Object { $_ -match '^\{' } | ForEach-Object {
                    try {
                        $obj = ConvertFrom-Json $_
                        if ($obj.market -eq $Market) {
                            $obj | Add-Member -Name "status" -Value "REJECTED" -Force
                            $obj | Add-Member -Name "decided_at" -Value ((Get-Date).ToString("o")) -Force
                        }
                        $updated += $obj
                    } catch { }
                }
                if ($updated.Count -gt 0) {
                    $updated | ConvertTo-Json -AsArray | Set-Content $file -Encoding UTF8
                }
            }

            return @{ status="ok"; message="❌ $Market rejeitado." }
        }

        '/resume' {
            # Remove circuit breaker flag (religar após -2% loss)
            $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"
            if (Test-Path $flagPath) {
                Remove-Item $flagPath
                return @{ status="ok"; message="🟢 Circuit breaker removido. Sistema LIVE novamente." }
            } else {
                return @{ status="ok"; message="⚪ Circuit breaker não está ativo." }
            }
        }

        '/pause' {
            # Manual pause (user quer pausar sem esperar -2% loss)
            $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"
            Add-Content -Path $flagPath -Value "manual_pause $(Get-Date)" -Encoding UTF8 -ErrorAction SilentlyContinue
            return @{ status="ok"; message="⏸️ Sistema pausado manualmente. Use /resume pra voltar." }
        }

        default {
            return @{ status="error"; message="Comando desconhecido. Use: /approve TICKER | /reject TICKER | /resume | /pause" }
        }
    }
}

function Get-PendingApprovalStatus {
    param([string]$JournalDir = $global:JOURNAL_DIR)

    $journalDir = if ($JournalDir) { $JournalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $file = Join-Path $journalDir "human_approvals_pending.jsonl"

    if (-not (Test-Path $file)) { return "✅ Nenhuma aprovação pendente" }

    $pending = @()
    Get-Content $file | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try {
            $obj = ConvertFrom-Json $_
            if ($obj.status -eq "PENDING") {
                $pending += "$($obj.market) \$$($obj.size_usd)"
            }
        } catch { }
    }

    if ($pending.Count -eq 0) {
        return "✅ Nenhuma aprovação pendente"
    } else {
        return "🔔 Pendentes (use /approve ou /reject):`n" + ($pending -join "`n")
    }
}

function Test-CircuitBreakerActive {
    param([string]$JournalDir = $global:JOURNAL_DIR)

    $journalDir = if ($JournalDir) { $journalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"

    return (Test-Path $flagPath)
}

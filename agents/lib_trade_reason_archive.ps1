# lib_trade_reason_archive.ps1 — Arquivo de razoes completas de trades
# 2026-05-29: Armazenar razoes completas em JSONL para auditoria
# Razoes sao truncadas no log master para evitar inflacao de contexto

function Add-TradeReasonArchive {
    param(
        [Parameter(Mandatory=$true)] [string] $Market,
        [Parameter(Mandatory=$true)] [string] $Decision,
        [Parameter(Mandatory=$true)] [string] $FullReason,
        [string] $ArchivePath = ""
    )

    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        $ArchivePath = Join-Path $global:JOURNAL_DIR "trade_reasons.jsonl"
    }

    # Criar diretorio se nao existir
    $dir = Split-Path $ArchivePath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $entry = [PSCustomObject]@{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        market    = $Market
        decision  = $Decision
        reason    = $FullReason
    }

    try {
        $entry | ConvertTo-Json -Compress | Add-Content -Path $ArchivePath -Encoding utf8 -ErrorAction Stop
    } catch {
        Write-Warning "Falha ao arquivar razao de trade: $_"
    }
}

function Get-TradeReasonArchive {
    param(
        [string] $Market = "",
        [string] $ArchivePath = "",
        [int] $LastN = 0
    )

    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        $ArchivePath = Join-Path $global:JOURNAL_DIR "trade_reasons.jsonl"
    }

    if (-not (Test-Path $ArchivePath)) {
        return @()
    }

    try {
        $lines = @(Get-Content -Path $ArchivePath -Encoding utf8 -ErrorAction Stop)
        $results = @()

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace($Market) -or $obj.market -eq $Market) {
                    $results += $obj
                }
            } catch {}
        }

        if ($LastN -gt 0 -and $results.Count -gt $LastN) {
            return $results[-$LastN..-1]
        }
        return $results
    } catch {
        Write-Warning "Falha ao ler arquivo de razoes: $_"
        return @()
    }
}

function Get-TradeReasonStats {
    param(
        [string] $ArchivePath = ""
    )

    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        $ArchivePath = Join-Path $global:JOURNAL_DIR "trade_reasons.jsonl"
    }

    if (-not (Test-Path $ArchivePath)) {
        return $null
    }

    try {
        $lines = @(Get-Content -Path $ArchivePath -Encoding utf8 -ErrorAction Stop)
        $stats = @{
            total_entries = 0
            by_market = @{}
            by_decision = @{}
            avg_reason_length = 0
        }

        $totalLength = 0
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json
                $stats.total_entries++
                $totalLength += $obj.reason.Length

                # Por mercado
                if (-not $stats.by_market.ContainsKey($obj.market)) {
                    $stats.by_market[$obj.market] = 0
                }
                $stats.by_market[$obj.market]++

                # Por decisao
                if (-not $stats.by_decision.ContainsKey($obj.decision)) {
                    $stats.by_decision[$obj.decision] = 0
                }
                $stats.by_decision[$obj.decision]++
            } catch {}
        }

        if ($stats.total_entries -gt 0) {
            $stats.avg_reason_length = [math]::Round($totalLength / $stats.total_entries, 1)
        }

        return $stats
    } catch {
        Write-Warning "Falha ao calcular stats: $_"
        return $null
    }
}
)

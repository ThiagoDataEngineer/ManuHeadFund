# lib_journal_sync_supabase.ps1 — Bridge local→cloud (2026-07-09)
#
# Gap: decision_grades (2806 linhas), evolution_history, trailing_effectiveness,
# counterfactual, boot_integrity_failures vivem LOCAL. Nuvem não consegue ler.
# Resultado: grading não alimenta rebalanceamento na nuvem.
#
# Solução: Sync one-way local→Supabase best-effort (não-crítico, dedup por ts).
# Consumo: evolution_engine + grade_llm_decisions na nuvem leem a tabela.
#
# PS 5.1. UTF-8 BOM.

function Sync-JournalToSupabase {
    [CmdletBinding()]
    param(
        [string] $JournalDir = "",
        [string[]] $FilesToSync = @("decision_grades.jsonl", "evolution_history.jsonl", "trailing_effectiveness.jsonl", "counterfactual_analysis.jsonl", "boot_integrity_failures.jsonl")
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    }

    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
        Write-Host "[journal-sync] Supabase not available, skipping" -ForegroundColor DarkGray
        return $true
    }

    $synced = 0
    foreach ($file in $FilesToSync) {
        $path = Join-Path $JournalDir $file
        if (-not (Test-Path $path)) { continue }

        try {
            $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue)
            if ($lines.Count -eq 0) { continue }

            # Batche 100 linhas por vez (rate limit Supabase)
            for ($i = 0; $i -lt $lines.Count; $i += 100) {
                $batch = $lines[$i..([math]::Min($i+99, $lines.Count-1))]
                $records = @()
                foreach ($line in $batch) {
                    if (-not $line) { continue }
                    try {
                        $obj = $line | ConvertFrom-Json
                        $records += [PSCustomObject]@{
                            id       = $file.Replace(".jsonl", "") + "_" + ($i + @($batch).IndexOf($line))
                            ts       = $obj.ts
                            source   = $file
                            payload  = $line
                        }
                    } catch {}
                }
                if ($records.Count -gt 0) {
                    Save-StateRecords -Table "journal_sync_log" -Records $records -PrimaryKey "id" | Out-Null
                    $synced += $records.Count
                }
            }
            Write-Host "[journal-sync] ${file}: $($lines.Count) lines synced" -ForegroundColor DarkCyan
        } catch {
            Write-Host "[journal-sync] $file failed: $_" -ForegroundColor DarkYellow
        }
    }
    Write-Host "[journal-sync] Total records synced: $synced" -ForegroundColor Green
    return $true
}


function Get-GradingFromSupabase {
    # Read-back para nuvem: evolution_engine + grading agents buscam aqui
    # NUNCA na nuvem — grading sempre local. Mas esta função pronta pra futuro.
    [CmdletBinding()]
    param(
        [string] $FileName = "decision_grades.jsonl",
        [int] $LimitRecords = 500
    )

    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        $rows = @(Get-StateRecords -Table "journal_sync_log" -Filter @{ source = $FileName } | Select-Object -Last $LimitRecords)
        return $rows | ForEach-Object { $_.payload | ConvertFrom-Json }
    } catch {
        return @()
    }
}

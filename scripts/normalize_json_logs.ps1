# normalize_json_logs.ps1 — Normaliza trade_outcomes.jsonl e decisions_text.jsonl
# Problema: campos inconsistentes, missing fields, múltiplas fontes com schemas diferentes
# Solução: lê cada linha, valida, normaliza schema, reescreve
#
# Uso:
#   pwsh -File scripts\normalize_json_logs.ps1              # teste (DryRun)
#   pwsh -File scripts\normalize_json_logs.ps1 -Apply       # executa normalização
#
# PS 5.1, UTF-8 BOM.

param(
    [switch]$Apply,     # Se true, sobrescreve os JSONs. Se false, testa só.
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

$projectRoot = Split-Path -Parent $PSScriptRoot
$journalDir = Join-Path $projectRoot "journal"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
}

# ═══════════════════════════════════════════════════════════════════════════
# 1. NORMALIZE TRADE_OUTCOMES.JSONL
# ═══════════════════════════════════════════════════════════════════════════

Log "[START] Normalizando trade_outcomes.jsonl..."

$tradesFile = Join-Path $journalDir "trade_outcomes.jsonl"
$trades = @()
$invalidTrades = 0

if (Test-Path $tradesFile) {
    Get-Content $tradesFile -Encoding UTF8 | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json

            # Normalizar schema
            $normalized = @{
                trade_id         = $obj.trade_id ?? "UNKNOWN"
                market           = $obj.market ?? ""
                direction        = $obj.direction ?? "UNKNOWN"
                entry_price      = $obj.entry_price ?? 0
                exit_price       = $obj.exit_price ?? $null
                entry_date       = $obj.entry_date ?? ""
                exit_date        = $obj.exit_date ?? $null
                entry_time       = $obj.entry_time ?? $obj.entry_date  # Fallback a entry_date
                exit_time        = $obj.exit_time ?? $obj.exit_date
                size_usd         = $obj.size_usd ?? 0
                pnl_usd          = $obj.pnl_usd ?? $null
                pnl_pct          = $obj.pnl_pct ?? $null
                win              = $obj.win ?? $null
                close_reason     = $obj.close_reason ?? "unknown"
                status           = if ($obj.status) { $obj.status } elseif ($obj.exit_price) { "closed" } else { "open" }
                notes            = $obj.notes ?? ""
                source           = $obj.source ?? "unknown"
                alpha_vs_btc     = $obj.alpha_vs_btc ?? "N/A"
                registered_at    = $obj.registered_at ?? (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
            }

            $trades += $normalized
        } catch {
            $invalidTrades++
            if ($Verbose) {
                Log "  [WARN] Invalid line (skipped): $($_.Exception.Message.Substring(0,50))"
            }
        }
    }

    Log "  Lidas: $($trades.Count) trades válidos, $invalidTrades inválidos"
} else {
    Log "  [ERROR] trade_outcomes.jsonl not found"
}

# ═══════════════════════════════════════════════════════════════════════════
# 2. NORMALIZE DECISIONS_TEXT.JSONL
# ═══════════════════════════════════════════════════════════════════════════

Log "[START] Normalizando decisions_text.jsonl..."

$decisionsFile = Join-Path $journalDir "decisions_text.jsonl"
$decisions = @()
$invalidDecisions = 0

if (Test-Path $decisionsFile) {
    Get-Content $decisionsFile -Encoding UTF8 | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json

            # Extrair action do mentor_decision se action for vazio ou array
            $action = $obj.action

            # Check PRIMEIRO se action é vazia (antes de processar)
            if ([string]::IsNullOrWhiteSpace($action)) {
                # Inferir do mentor_decision
                $action = switch ($obj.mentor_decision) {
                    "VETAR_MCE" { "ABORTAR" }
                    "VETAR" { "ABORTAR" }
                    "EXECUTAR" { "EXECUTAR" }
                    default { "ABORTAR" }
                }
            }

            # Converter array para string (join) se necessário
            if ($action -is [array]) {
                $action = $action[0]  # Pega primeiro valor se array
            }

            # Limpar espaços extras
            $action = [string]::Concat($action)  # Garantir string
            $action = ($action -split '\s+' | Where-Object {$_}) -join ' '

            # Normalizar schema
            $normalized = @{
                ts               = $obj.ts ?? (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                market           = $obj.market ?? ""
                action           = $action
                result           = $obj.result ?? $obj.reason ?? ""
                reason           = $obj.reason ?? ""
                mentor_decision  = $obj.mentor_decision ?? "UNKNOWN"
                mesa_consensus   = $obj.mesa_consensus ?? $null
                conviction_score = $obj.conviction_score ?? $null
                direction        = $obj.direction ?? $null
                status           = $obj.status ?? "pending"
            }

            $decisions += $normalized
        } catch {
            $invalidDecisions++
            if ($Verbose) {
                Log "  [WARN] Invalid decision (skipped): $($_.Exception.Message.Substring(0,50))"
            }
        }
    }

    Log "  Lidas: $($decisions.Count) decisions válidas, $invalidDecisions inválidas"
} else {
    Log "  [ERROR] decisions_text.jsonl not found"
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. VALIDAÇÃO E BACKUP
# ═══════════════════════════════════════════════════════════════════════════

Log "[VALIDATION] Checando schema..."

$tradesMissing = 0
$trades | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.market) -or [string]::IsNullOrWhiteSpace($_.trade_id)) {
        $tradesMissing++
    }
}

$decisionsMissing = 0
$decisions | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.market) -or [string]::IsNullOrWhiteSpace($_.action)) {
        $decisionsMissing++
    }
}

Log "  Trades com campos críticos missing: $tradesMissing / $($trades.Count)"
Log "  Decisions com campos críticos missing: $decisionsMissing / $($decisions.Count)"

if (-not $Apply) {
    Log "[DRY-RUN] Use -Apply para escrever as mudanças"
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. BACKUP DOS ORIGINALS
# ═══════════════════════════════════════════════════════════════════════════

Log "[BACKUP] Criando backups..."

$backupDir = Join-Path $journalDir "backups_before_normalize"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -ErrorAction SilentlyContinue | Out-Null
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

try {
    Copy-Item $tradesFile -Destination (Join-Path $backupDir "trade_outcomes_$ts.jsonl.bak")
    Log "  Backup: trade_outcomes_$ts.jsonl.bak"
} catch {
    Log "  [ERROR] Backup trade_outcomes falhou: $_"
}

try {
    Copy-Item $decisionsFile -Destination (Join-Path $backupDir "decisions_text_$ts.jsonl.bak")
    Log "  Backup: decisions_text_$ts.jsonl.bak"
} catch {
    Log "  [ERROR] Backup decisions_text falhou: $_"
}

# ═══════════════════════════════════════════════════════════════════════════
# 5. ESCREVER NORMALIZADOS
# ═══════════════════════════════════════════════════════════════════════════

Log "[WRITE] Normalizando trades..."

$tradeOutput = @()
$trades | ForEach-Object {
    $json = $_ | ConvertTo-Json -Compress
    $tradeOutput += $json
}

try {
    $tradeOutput | Out-File -FilePath $tradesFile -Encoding UTF8 -Force
    Log "  ✓ trade_outcomes.jsonl normalizado ($($trades.Count) linhas)"
} catch {
    Log "  [ERROR] Falha ao escrever trade_outcomes: $_"
}

Log "[WRITE] Normalizando decisions..."

$decisionOutput = @()
$decisions | ForEach-Object {
    $json = $_ | ConvertTo-Json -Compress
    $decisionOutput += $json
}

try {
    $decisionOutput | Out-File -FilePath $decisionsFile -Encoding UTF8 -Force
    Log "  ✓ decisions_text.jsonl normalizado ($($decisions.Count) linhas)"
} catch {
    Log "  [ERROR] Falha ao escrever decisions_text: $_"
}

# ═══════════════════════════════════════════════════════════════════════════
# 6. VALIDAÇÃO PÓS-NORMALIZAÇÃO
# ═══════════════════════════════════════════════════════════════════════════

Log "[VERIFY] Validando resultado..."

$tradesVerify = @()
Get-Content $tradesFile -Encoding UTF8 | ForEach-Object {
    try { $tradesVerify += $_ | ConvertFrom-Json } catch {}
}

$decisionsVerify = @()
Get-Content $decisionsFile -Encoding UTF8 | ForEach-Object {
    try { $decisionsVerify += $_ | ConvertFrom-Json } catch {}
}

Log "  trade_outcomes.jsonl: $($tradesVerify.Count) linhas válidas"
Log "  decisions_text.jsonl: $($decisionsVerify.Count) linhas válidas"

if ($tradesVerify.Count -eq $trades.Count -and $decisionsVerify.Count -eq $decisions.Count) {
    Log "✅ NORMALIZAÇÃO COMPLETA E VALIDADA"
} else {
    Log "⚠️  FALHA NA VALIDAÇÃO — verificar backups"
}

Log "[DONE]"

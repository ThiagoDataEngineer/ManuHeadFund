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
                trade_id         = if ($null -ne $obj.trade_id) { $obj.trade_id } else { "UNKNOWN" }
                market           = if ($null -ne $obj.market) { $obj.market } else { "" }
                direction        = if ($null -ne $obj.direction) { $obj.direction } else { "UNKNOWN" }
                entry_price      = if ($null -ne $obj.entry_price) { $obj.entry_price } else { 0 }
                exit_price       = if ($null -ne $obj.exit_price) { $obj.exit_price } else { $null }
                entry_date       = if ($null -ne $obj.entry_date) { $obj.entry_date } else { "" }
                exit_date        = if ($null -ne $obj.exit_date) { $obj.exit_date } else { $null }
                entry_time       = if ($null -ne $obj.entry_time) { $obj.entry_time } else { $obj.entry_date }  # Fallback a entry_date
                exit_time        = if ($null -ne $obj.exit_time) { $obj.exit_time } else { $obj.exit_date }
                size_usd         = if ($null -ne $obj.size_usd) { $obj.size_usd } else { 0 }
                pnl_usd          = if ($null -ne $obj.pnl_usd) { $obj.pnl_usd } else { $null }
                pnl_pct          = if ($null -ne $obj.pnl_pct) { $obj.pnl_pct } else { $null }
                win              = if ($null -ne $obj.win) { $obj.win } else { $null }
                close_reason     = if ($null -ne $obj.close_reason) { $obj.close_reason } else { "unknown" }
                status           = if ($obj.status) { $obj.status } elseif ($obj.exit_price) { "closed" } else { "open" }
                notes            = if ($null -ne $obj.notes) { $obj.notes } else { "" }
                source           = if ($null -ne $obj.source) { $obj.source } else { "unknown" }
                alpha_vs_btc     = if ($null -ne $obj.alpha_vs_btc) { $obj.alpha_vs_btc } else { "N/A" }
                registered_at    = if ($null -ne $obj.registered_at) { $obj.registered_at } else { (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ') }
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
            $result = if ($null -ne $obj.result) { $obj.result } elseif ($null -ne $obj.reason) { $obj.reason } else { "" }
            $normalized = @{
                ts               = if ($null -ne $obj.ts) { $obj.ts } else { (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') }
                market           = if ($null -ne $obj.market) { $obj.market } else { "" }
                action           = $action
                result           = $result
                reason           = if ($null -ne $obj.reason) { $obj.reason } else { "" }
                mentor_decision  = if ($null -ne $obj.mentor_decision) { $obj.mentor_decision } else { "UNKNOWN" }
                mesa_consensus   = if ($null -ne $obj.mesa_consensus) { $obj.mesa_consensus } else { $null }
                conviction_score = if ($null -ne $obj.conviction_score) { $obj.conviction_score } else { $null }
                direction        = if ($null -ne $obj.direction) { $obj.direction } else { $null }
                status           = if ($null -ne $obj.status) { $obj.status } else { "pending" }
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

# agents/lib_trade_journal_supabase.ps1
# Trade journal persistence layer (Supabase + local fallback)
#
# Persists trade outcomes (entry/exit/PnL) in Supabase table trade_outcomes
# with local JSON mirror (journal/trade_outcomes.jsonl) for quick reads.
#
# PS 5.1 compatible. UTF-8 BOM tolerated.

$_tradeJournalDir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "journal"

function _Get-TradeJournalDir {
    # Honors STATE_STORE_LOCAL_DIR override (used by tests for isolation);
    # falls back to the real production journal dir otherwise.
    if ($global:STATE_STORE_LOCAL_DIR) { return $global:STATE_STORE_LOCAL_DIR }
    return $_tradeJournalDir
}

function Save-TradeOutcome {
    <#
    .SYNOPSIS
    Persist trade outcome to Supabase trade_outcomes table (+ local mirror).

    .PARAMETER TradeRecord
    PSCustomObject with fields:
      - entry_ts (datetime)
      - symbol (string)
      - direction (LONG|SHORT)
      - source (gem_executor|mock_trade_test|app_import)
      - entry_price (double)
      - exit_price (double, optional)
      - quantity (double)
      - pnl_realized (double, optional)
      - pnl_percent (double, optional)
      - status (pending|closed|orphan, optional)
      - regime (string, optional)
      - has_confluence (bool, optional)
      - conviction_score (double, optional)

    .OUTPUTS
    $true if saved successfully
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [PSCustomObject]$TradeRecord
    )

    try {
        # Normalize record
        $ts = if ($TradeRecord.entry_ts -is [datetime]) {
            $TradeRecord.entry_ts
        } else {
            [datetime]::Parse([string]$TradeRecord.entry_ts)
        }

        # 2026-07-27 FIX: quando o CALLER ja monta um id ESTAVEL (ex:
        # _Convert-ClosedTradeToOutcome usa position_id da CoinEx, unico por
        # posicao fechada -- ver lib_position_sync_live.ps1), preservar esse
        # id em vez de sempre gerar um GUID novo aqui. O GUID aleatorio
        # quebrava a idempotencia do upsert (PrimaryKey "id"): toda vez que
        # Reconcile-AppToJournal reprocessava as MESMAS ultimas 10 posicoes
        # fechadas (CoinEx-GetClosedPositions nao filtra so as novas), cada
        # chamada gerava um id diferente e regravava o mesmo fechamento de
        # novo -- achado real: 8 valores de PnL duplicados 3-5x cada em
        # trade_outcomes, inflando qualquer soma de PnL diario (inclusive o
        # circuit breaker -2%, que disparou hoje com -$7.75 de PnL nao-real).
        # Sem id estavel no caller, mantem o comportamento antigo (GUID) --
        # nao quebra os outros 2 callers que nunca passavam id (fallback
        # seguro, mesmo risco de duplicata que ja existia antes do fix).
        $stableId = if ($TradeRecord.id) { [string]$TradeRecord.id } else { $null }
        $record = @{
            id = if ($stableId) { $stableId } else { "{0}|{1}|{2}|{3}" -f $ts.Ticks, $TradeRecord.symbol, $TradeRecord.direction, ([guid]::NewGuid()).ToString().Substring(0, 8) }
            entry_ts = $ts.ToUniversalTime()
            symbol = [string]$TradeRecord.symbol
            direction = [string]$TradeRecord.direction  # LONG|SHORT
            # 2026-07-09 FIX PS5.1: ?? e PS7-only -- quebrava parse (28 erros, journal Supabase morto local)
            source = [string]$(if ($TradeRecord.source) { $TradeRecord.source } else { "gem_executor" })
            entry_price = [double]$TradeRecord.entry_price
            exit_price = [double]$(if ($TradeRecord.exit_price) { $TradeRecord.exit_price } else { 0 })
            quantity = [double]$TradeRecord.quantity
            pnl_realized = [double]$(if ($TradeRecord.pnl_realized) { $TradeRecord.pnl_realized } else { 0 })
            pnl_percent = [double]$(if ($TradeRecord.pnl_percent) { $TradeRecord.pnl_percent } else { 0 })
            status = [string]$(if ($TradeRecord.status) { $TradeRecord.status } else { "pending" })
            regime = if ($TradeRecord.regime) { [string]$TradeRecord.regime } else { $null }
            has_confluence = [bool]$(if ($null -ne $TradeRecord.has_confluence) { $TradeRecord.has_confluence } else { $false })
            conviction_score = [double]$(if ($TradeRecord.conviction_score) { $TradeRecord.conviction_score } else { 0 })
            created_at = (Get-Date).ToUniversalTime()
        }

        # Save to Supabase (best-effort)
        if (Test-Command -Name "Save-StateRecords") {
            try {
                Save-StateRecords -Table "trade_outcomes" -Records @($record) -PrimaryKey "id" -ErrorAction SilentlyContinue | Out-Null
            } catch {
                Write-Warning "[trade_journal] Supabase save failed: $_"
            }
        }

        # Save to local mirror (always succeeds)
        _Mirror-TradeOutcomeLocal -Record $record | Out-Null

        return $true
    } catch {
        Write-Error "[trade_journal] Save-TradeOutcome failed: $_"
        return $false
    }
}

function Get-RecentTrades {
    <#
    .SYNOPSIS
    Fetch recent closed trades (defaults to last 7 days).
    Reads from Supabase; falls back to local JSON.

    .PARAMETER DaysBack
    Number of days to look back (default 7)

    .PARAMETER Status
    Filter by status: closed|pending|all (default "closed")

    .PARAMETER Limit
    Max records to return (default 100)

    .OUTPUTS
    @(trade_records...)
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [int]$DaysBack = 7,
        [ValidateSet("closed", "pending", "all")]
        [string]$Status = "closed",
        [int]$Limit = 100
    )

    try {
        $trades = @()

        # Try Supabase first
        if (Test-Command -Name "Get-StateRecords") {
            try {
                $filter = if ($Status -ne "all") { @{ status = $Status } } else { @{} }
                $trades = @(Get-StateRecords -Table "trade_outcomes" -Filter $filter -ErrorAction SilentlyContinue)
            } catch {
                Write-Verbose "[trade_journal] Supabase read failed, falling back to local"
            }
        }

        # Fallback to local mirror
        if ($trades.Count -eq 0) {
            $trades = @(_Read-TradeOutcomesLocal)
            if ($Status -ne "all") {
                $trades = @($trades | Where-Object { $_.status -eq $Status })
            }
        }

        # Filter by date
        $cutoff = (Get-Date).AddDays(-$DaysBack)
        $trades = @($trades | Where-Object {
            $ts = if ($_.entry_ts -is [datetime]) { $_.entry_ts } else { [datetime]::Parse([string]$_.entry_ts) }
            $ts -ge $cutoff
        })

        # Sort + limit
        $trades = @($trades | Sort-Object entry_ts -Descending | Select-Object -First $Limit)
        return $trades
    } catch {
        Write-Error "[trade_journal] Get-RecentTrades failed: $_"
        return @()
    }
}

function Get-TradeStats {
    <#
    .SYNOPSIS
    Calculate trade statistics (win rate, PnL, etc).

    .PARAMETER Regime
    Optional: filter by regime (e.g., "BEAR_WEAK")

    .PARAMETER DaysBack
    Lookback window (default 30)

    .OUTPUTS
    @{
        total = int
        win_count = int
        loss_count = int
        win_rate = double (0-1)
        pnl_total = double
        pnl_avg = double
        pnl_median = double
        pnl_min = double
        pnl_max = double
    }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Regime = $null,
        [int]$DaysBack = 30
    )

    try {
        $trades = @(Get-RecentTrades -DaysBack $DaysBack -Status "closed" -Limit 10000)

        if ($Regime) {
            $trades = @($trades | Where-Object { $_.regime -eq $Regime })
        }

        if ($trades.Count -eq 0) {
            return @{
                total = 0
                win_count = 0
                loss_count = 0
                win_rate = 0
                pnl_total = 0
                pnl_avg = 0
                pnl_median = 0
                pnl_min = 0
                pnl_max = 0
            }
        }

        # Coerce PnL to double
        $pnls = @($trades | ForEach-Object { [double]$_.pnl_realized })
        $sorted = @($pnls | Sort-Object)
        $wins = @($pnls | Where-Object { $_ -gt 0 })
        $losses = @($pnls | Where-Object { $_ -le 0 })

        $median = if ($sorted.Count % 2 -eq 0) {
            ($sorted[($sorted.Count / 2 - 1)] + $sorted[$sorted.Count / 2]) / 2
        } else {
            $sorted[($sorted.Count - 1) / 2]
        }

        return @{
            total = $trades.Count
            win_count = $wins.Count
            loss_count = $losses.Count
            win_rate = if ($trades.Count -gt 0) { $wins.Count / $trades.Count } else { 0 }
            pnl_total = ($pnls | Measure-Object -Sum).Sum
            pnl_avg = ($pnls | Measure-Object -Average).Average
            pnl_median = $median
            pnl_min = ($pnls | Measure-Object -Minimum).Minimum
            pnl_max = ($pnls | Measure-Object -Maximum).Maximum
        }
    } catch {
        Write-Error "[trade_journal] Get-TradeStats failed: $_"
        return $null
    }
}

function Test-Command {
    param([string]$Name)
    try {
        Get-Command $Name -ErrorAction SilentlyContinue | Out-Null
        return $?
    } catch {
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────
# Private helpers (local JSON mirror)
# ─────────────────────────────────────────────────────────────────────

function _Mirror-TradeOutcomeLocal {
    param([hashtable]$Record)

    try {
        $journalDir = _Get-TradeJournalDir
        $path = Join-Path $journalDir "trade_outcomes.jsonl"
        if (-not (Test-Path $journalDir)) {
            New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        }

        $line = $Record | ConvertTo-Json -Compress -Depth 4
        Add-Content -Path $path -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue | Out-Null

        return $true
    } catch {
        Write-Verbose "[trade_journal] Local mirror failed: $_"
        return $false
    }
}

function _Read-TradeOutcomesLocal {
    try {
        $path = Join-Path (_Get-TradeJournalDir) "trade_outcomes.jsonl"
        if (-not (Test-Path $path)) { return @() }

        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue)
        $records = @()

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json
                $records += $record
            } catch {
                Write-Verbose "[trade_journal] JSON parse error on line: $line"
            }
        }

        return @($records)
    } catch {
        Write-Verbose "[trade_journal] Read local failed: $_"
        return @()
    }
}

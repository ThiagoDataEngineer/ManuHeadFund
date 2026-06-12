# lib_journal.ps1 — Journal de sinais do GemAgent
# Registra cada sinal gerado (passou ou não os gates) para backtesting e calibração.
# Arquivo: journal/gem_signals.csv

$global:JOURNAL_DIR  = if ($JOURNAL_DIR)  { $JOURNAL_DIR  } else { Join-Path $PSScriptRoot "..\journal" }
$global:JOURNAL_FILE = Join-Path $global:JOURNAL_DIR "gem_signals.csv"

# B11 fix 2026-05-20 PM6+: ConvertTo-CsvField helper unico em lib_csv_utils.ps1
if (-not (Get-Command ConvertTo-CsvField -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_csv_utils.ps1")
}

$JOURNAL_HEADERS = @(
    "timestamp","market","score","mode","gates_passed","gate_failed",
    "spike_ratio","spike_type","pct_change_today","mcap_usd",
    "price_at_scan","vol_today","sizing_usd","stop_pct","target_pct",
    "alerta","scan_id"
)

# _Format-CsvField: stringify locale-safe + RFC 4180 quoting
# - $null/empty -> string vazia
# - decimais usam InvariantCulture (ponto, nunca virgula)
# - quoting se contem virgula, aspas dupla, CR ou LF; aspas internas dobradas
function _Format-CsvField {
    param($Value)
    if ($null -eq $Value) { return "" }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $s = $null
    if ($Value -is [string]) {
        $s = $Value
    } elseif ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        # "R" preserva round-trip; usa ponto via InvariantCulture
        $s = ([System.Convert]::ToDouble($Value, $inv)).ToString("R", $inv)
    } elseif ($Value -is [System.IFormattable]) {
        $s = $Value.ToString($null, $inv)
    } else {
        $s = [string]$Value
    }
    if ($null -eq $s) { return "" }
    if ($s.IndexOfAny([char[]]@(',','"',"`r","`n")) -ge 0) {
        $s = '"' + ($s -replace '"','""') + '"'
    }
    return $s
}

function _Format-CsvRow {
    param([System.Collections.IEnumerable]$Values)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Values) { $parts.Add((_Format-CsvField $v)) | Out-Null }
    return ($parts -join ",")
}

function Initialize-GemJournal {
    if (-not (Test-Path $global:JOURNAL_DIR)) {
        New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null
    }
    if (-not (Test-Path $global:JOURNAL_FILE)) {
        $JOURNAL_HEADERS -join "," | Out-File -FilePath $global:JOURNAL_FILE -Encoding utf8 -Force
    }
}

# Escreve uma entrada no journal para cada par analisado (passou ou não)
function Write-GemJournalEntry {
    param(
        [Parameter(Mandatory)] [object] $GemResult,   # saída de Invoke-GemScore
        [string] $ScanId = ""
    )

    Initialize-GemJournal

    $vd = $GemResult.vol_data
    $sz = $GemResult.sizing

    $row = [ordered]@{
        timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        market           = $GemResult.market
        score            = $GemResult.score
        mode             = $GemResult.mode
        gates_passed     = ($GemResult.gates_passed -join "|")
        gate_failed      = $GemResult.gate_failed
        spike_ratio      = if ($vd) { $vd.spike_ratio } else { "" }
        spike_type       = if ($vd) { $vd.spike_type  } else { "" }
        pct_change_today = if ($vd) { $vd.pct_change_today } else { "" }
        mcap_usd         = $GemResult.mcap_usd
        price_at_scan    = if ($vd) { "" } else { "" }   # preenchido abaixo
        vol_today        = if ($vd) { $vd.vol_today } else { "" }
        sizing_usd       = if ($sz) { $sz.sizing_usd } else { 0 }
        stop_pct         = if ($sz) { $sz.stop_pct   } else { "" }
        target_pct       = if ($sz) { $sz.target_pct } else { "" }
        alerta           = $GemResult.alerta   # raw — _Format-CsvRow (linha 100) ja faz RFC4180 uniforme; pre-escapar aqui causava double-escape
        scan_id          = $ScanId
    }

    # Preço atual via ticker (best-effort)
    try {
        $ticker = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/spot/ticker?market=$($GemResult.market)" -Method GET
        if ($ticker.code -eq 0) { $row.price_at_scan = [double]$ticker.data[0].last }
    } catch {}

    $line = _Format-CsvRow $row.Values
    Add-Content -Path $global:JOURNAL_FILE -Value $line -Encoding utf8
}

# Escreve todos os resultados de um scan (incluindo bloqueados)
function Write-GemScanJournal {
    param(
        [Parameter(Mandatory)] [object[]] $AllResults,
        [string] $ScanId = ""
    )
    if (-not $ScanId) { $ScanId = (Get-Date -Format "yyyyMMdd_HHmm") }
    Initialize-GemJournal
    foreach ($r in $AllResults) {
        Write-GemJournalEntry -GemResult $r -ScanId $ScanId
    }
    Write-Host "  Journal: $($AllResults.Count) entradas salvas em gem_signals.csv  [scan $ScanId]" -ForegroundColor DarkGray
}

# Lê o journal e retorna os últimos N dias
function Read-GemJournal {
    param([int]$Days = 30)
    if (-not (Test-Path $global:JOURNAL_FILE)) { return @() }
    $cutoff = (Get-Date).AddDays(-$Days)
    Import-Csv -Path $global:JOURNAL_FILE -Encoding utf8 |
        Where-Object { [datetime]$_.timestamp -ge $cutoff }
}

# Estatísticas simples: taxa de acerto por gate_failed
function Get-GemJournalStats {
    param([int]$Days = 30)
    $entries = Read-GemJournal -Days $Days
    if (-not $entries) { Write-Host "Journal vazio."; return }

    $total    = $entries.Count
    $approved = @($entries | Where-Object { [int]$_.score -ge 70 }).Count
    $byGate   = $entries | Group-Object gate_failed | Sort-Object Count -Descending

    Write-Host "=== JOURNAL STATS (últimos $Days dias) ===" -ForegroundColor Cyan
    Write-Host "Total sinais  : $total"
    Write-Host "Aprovados (≥70): $approved ($([math]::Round($approved/$total*100,1))%)"
    Write-Host ""
    Write-Host "Bloqueios por gate:" -ForegroundColor Yellow
    foreach ($g in $byGate) {
        $pct = [math]::Round($g.Count / $total * 100, 1)
        Write-Host "  $($g.Name.PadRight(10)) $($g.Count.ToString().PadLeft(4))  ($pct%)"
    }
}

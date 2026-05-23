# lib_observation_logger.ps1 — Persist whitelist 'observe' cycles para audit pos-14d.
# Schema definido em journal/short_promotion_criteria_2026_05_15.md (17 campos).
# Driver: orchestrator_v6.ps1 chama Add-Observation quando whitelist retorna tier='observe'.
# UTF-8 BOM, PS 5.1, pure functions (zero dependencia externa alem do disco).

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
}

$OBSERVATIONS_FILE = Join-Path $global:JOURNAL_DIR "observations.csv"
$DECISIONS_FILE    = Join-Path $global:JOURNAL_DIR "decisions.csv"

$OBSERVATIONS_HEADER = "timestamp,market,regime,direction,dow_brt,whitelist_tier,whitelist_reason,scanner_score,mesa_consensus,mesa_sinal,mentor_decision,mentor_confidence,entry_price,stop_price,target_price,atr_proxy_pct,mode"
$DECISIONS_HEADER    = "timestamp,market,decision,reason,abort_stage,regime,direction,scanner_score,whitelist_tier,mesa_consensus,mentor_decision,paper_only,provider_used"

$script:VALID_DECISIONS = @("EXECUTAR","ABORTAR","SKIP","PAPER")

function Add-DecisionText {
    # D3 fix 2026-05-20 PM6+: JSONL sidecar pra texto livre.
    # CSV continua SSoT pra tabular; JSONL guarda reason/alerta/notes/mesa/mentor sem
    # risco de corruption (sem ,->; hack, sem RFC4180 quote-escape visualmente ilegivel).
    # Schema: {ts, market, reason, alerta?, notes?, mesa_consensus?, mentor_decision?}
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $Reason = "",
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $Alerta = $null,
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $Notes = $null,
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $MesaConsensus = $null,
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $MentorDecision = $null
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $obj = [ordered]@{
        ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        market = $Market
        reason = $Reason
    }
    if (-not [string]::IsNullOrEmpty($Alerta))         { $obj.alerta = $Alerta }
    if (-not [string]::IsNullOrEmpty($Notes))          { $obj.notes  = $Notes  }
    if (-not [string]::IsNullOrEmpty($MesaConsensus))  { $obj.mesa_consensus  = $MesaConsensus  }
    if (-not [string]::IsNullOrEmpty($MentorDecision)) { $obj.mentor_decision = $MentorDecision }

    # Compress=$true mantem JSONL valido (1 linha = 1 objeto)
    $line = ($obj | ConvertTo-Json -Compress -Depth 4)
    Add-Content -Path $Path -Value $line -Encoding utf8
}

# B11 fix 2026-05-20 PM6+: ConvertTo-CsvField moveu pra lib_csv_utils.ps1 (DRY).
# Dot-source aqui pra back-compat dos callers existentes.
if (-not (Get-Command ConvertTo-CsvField -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_csv_utils.ps1")
}

function Add-Observation {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $ObsFile = $OBSERVATIONS_FILE,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [int] $DowBrt,
        [Parameter(Mandatory)] [string] $WhitelistTier,
        [Parameter()] [string] $WhitelistReason = "",
        [Parameter()] [double] $ScannerScore = 0,
        [Parameter()] [AllowNull()] [string] $MesaConsensus = $null,
        [Parameter()] [AllowNull()] [string] $MesaSinal = $null,
        [Parameter()] [AllowNull()] [string] $MentorDecision = $null,
        [Parameter()] [double] $MentorConfidence = 0,
        [Parameter()] [double] $EntryPrice = 0,
        [Parameter()] [double] $StopPrice = 0,
        [Parameter()] [double] $TargetPrice = 0,
        [Parameter()] [double] $AtrProxyPct = 0,
        [Parameter()] [string] $Mode = "paper"
    )

    # Garante diretorio
    $dir = Split-Path $ObsFile
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Header se arquivo novo
    if (-not (Test-Path $ObsFile)) {
        $OBSERVATIONS_HEADER | Out-File -FilePath $ObsFile -Encoding utf8 -Force
    }

    # Invariant culture para floats (decimal ponto)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    # B1 refino 2026-05-20 PM6+: veto-early (todos 4 numerics zerados) -> escreve "".
    # Distingue "nao computado" (orchestrator abortou ANTES do setup) de "trade real zerado"
    # (matematicamente impossivel ter entry+stop+target+atr todos 0 num trade legitimo).
    $vetoEarly = ($EntryPrice -eq 0 -and $StopPrice -eq 0 -and $TargetPrice -eq 0 -and $AtrProxyPct -eq 0)
    $entryStr  = if ($vetoEarly) { "" } else { $EntryPrice.ToString("F8", $inv) }
    $stopStr   = if ($vetoEarly) { "" } else { $StopPrice.ToString("F8", $inv) }
    $targetStr = if ($vetoEarly) { "" } else { $TargetPrice.ToString("F8", $inv) }
    $atrStr    = if ($vetoEarly) { "" } else { $AtrProxyPct.ToString("F4", $inv) }

    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $row = @(
        $ts,
        $Market,
        $Regime,
        $Direction,
        $DowBrt,
        $WhitelistTier,
        (ConvertTo-CsvField $WhitelistReason),  # RFC4180 quoting
        $ScannerScore.ToString("F4", $inv),
        ($MesaConsensus -as [string]),
        ($MesaSinal -as [string]),
        ($MentorDecision -as [string]),
        $MentorConfidence.ToString("F2", $inv),
        $entryStr,
        $stopStr,
        $targetStr,
        $atrStr,
        $Mode
    ) -join ","

    Add-Content -Path $ObsFile -Value $row -Encoding utf8
}


function Add-Decision {
    # Loga TODA decisao do orchestrator_v6 (independente de paperOnly).
    # Resolve bug observations.csv vazia. Append-only em journal/decisions.csv.
    [CmdletBinding()]
    param(
        [Parameter()] [string] $DecFile = $DECISIONS_FILE,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Decision,
        [Parameter()] [string] $Reason = "",
        [Parameter()] [string] $AbortStage = "",
        [Parameter()] [string] $Regime = "",
        [Parameter()] [string] $Direction = "",
        [Parameter()] [double] $ScannerScore = 0,
        [Parameter()] [string] $WhitelistTier = "",
        [Parameter()] [AllowNull()] [string] $MesaConsensus = $null,
        [Parameter()] [AllowNull()] [string] $MentorDecision = $null,
        [Parameter()] [bool] $PaperOnly = $false,
        [Parameter()] [AllowNull()] [string] $ProviderUsed = $null,  # 2026-05-20 PM: which LLM responded
        # D3 fix 2026-05-20 PM6+: JSONL sidecar pra texto livre sem corruption.
        # Default = journal/decisions_text.jsonl. Caller pode override pra testes.
        [Parameter()] [string] $TextSidecarFile = ""
    )

    if ($script:VALID_DECISIONS -notcontains $Decision) {
        throw "Add-Decision: Decision invalida '$Decision' (esperado EXECUTAR|ABORTAR|SKIP|PAPER)"
    }

    $dir = Split-Path $DecFile
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path $DecFile)) {
        $DECISIONS_HEADER | Out-File -FilePath $DecFile -Encoding utf8 -Force
    }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $row = @(
        $ts,
        $Market,
        $Decision,
        (ConvertTo-CsvField $Reason),
        $AbortStage,
        $Regime,
        $Direction,
        $ScannerScore.ToString("F2", $inv),
        $WhitelistTier,
        ($MesaConsensus -as [string]),
        ($MentorDecision -as [string]),
        $PaperOnly.ToString().ToLower(),
        ($ProviderUsed -as [string])
    ) -join ","
    Add-Content -Path $DecFile -Value $row -Encoding utf8

    # D3 fix: JSONL sidecar pra texto livre. Default na mesma pasta do DecFile.
    $sidecar = if ($TextSidecarFile) { $TextSidecarFile } else { Join-Path (Split-Path $DecFile -Parent) "decisions_text.jsonl" }
    try {
        Add-DecisionText -Path $sidecar -Market $Market -Reason $Reason `
                         -MesaConsensus $MesaConsensus -MentorDecision $MentorDecision
    } catch { Write-Warning "Add-DecisionText sidecar falhou: $_" }
}


function Get-DecisionStats {
    [CmdletBinding()]
    param([Parameter()] [string] $DecFile = $DECISIONS_FILE)
    $result = @{ total = 0; executar = 0; abortar = 0; skip = 0; paper = 0 }
    if (-not (Test-Path $DecFile)) { return $result }
    try {
        $rows = Import-Csv $DecFile -ErrorAction Stop
        if ($null -eq $rows) { return $result }
        if ($rows -isnot [array]) { $rows = @($rows) }
        $result.total = $rows.Count
        foreach ($r in $rows) {
            switch ($r.decision) {
                "EXECUTAR" { $result.executar++ }
                "ABORTAR"  { $result.abortar++ }
                "SKIP"     { $result.skip++ }
                "PAPER"    { $result.paper++ }
            }
        }
    } catch {}
    return $result
}


function Get-ObservationsByCell {
    # Retorna array de cells unicas (regime+direction+dow) com Count.
    # Cada cell: @{Regime, Direction, DowBrt, Count, Markets[]}
    [CmdletBinding()]
    param(
        [Parameter()] [string] $ObsFile = $OBSERVATIONS_FILE,
        [Parameter()] [string] $Direction = $null
    )
    if (-not (Test-Path $ObsFile)) { return ,@() }
    try {
        $rows = Import-Csv $ObsFile -ErrorAction Stop
        if ($null -eq $rows) { return ,@() }
        if ($rows -isnot [array]) { $rows = @($rows) }
        if ($Direction) {
            $rows = @($rows | Where-Object { $_.direction -eq $Direction })
        }
        if ($rows.Count -eq 0) { return ,@() }

        # Agrupa por chave composta
        $cells = @{}
        foreach ($r in $rows) {
            $key = "$($r.regime)|$($r.direction)|$($r.dow_brt)"
            if (-not $cells.ContainsKey($key)) {
                $cells[$key] = [PSCustomObject]@{
                    Regime    = $r.regime
                    Direction = $r.direction
                    DowBrt    = [int]$r.dow_brt
                    N         = 0
                    Markets   = @()
                    Rows      = @()
                }
            }
            $cells[$key].N++
            $cells[$key].Markets += $r.market
            $cells[$key].Rows += $r
        }
        # Forca array de PSCustomObject (.NET List evita unrolling weirdness)
        $out = [System.Collections.Generic.List[object]]::new()
        foreach ($v in $cells.Values) { [void]$out.Add($v) }
        return $out.ToArray()
    } catch {
        return @()
    }
}

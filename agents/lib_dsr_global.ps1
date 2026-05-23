# lib_dsr_global.ps1 -- DSR global cumulative trials registry
#
# Bailey-LdP multi-testing penalty: cada gate eval = +1 trial.
# Conforme N cresce, gate threshold sobe (mais rigor para passar).
#
# Sem isso, ladder vira overfit factory ao longo de meses.
#
# === B15 fix 2026-05-20 PM6+380min ===
# Antes: $Path apontava pra journal/dsr_global.json (JSON unico) e Out-File overwrite.
#   Problema: 9 gates concurrentes em Invoke-AllGates -> race condition -> trial perdido.
# Agora: append-only JSONL em journal/dsr_trials.jsonl (Add-Content atomic at OS level
#   pra small writes em Windows NTFS). Agregacao computada on-read.
# Back-compat: $Path antigo (dsr_global.json) ainda aceito; auto-detecta extensao.
#   .jsonl path = new format; .json path = legacy format (read-only).
#
# Schema JSONL (B15):
#   {"ts":"...","gate":"obs_to_c","market":"BTCUSDT"}
#   {"ts":"...","gate":"funding","market":"BTCUSDT"}
#   ...
#
# Schema legacy JSON (kept for read):
#   {as_of, total_trials, by_gate:{...}, history:[]}
#
# PS 5.1. UTF-8 BOM.

function _Dsr-IsJsonl {
    param([string] $Path)
    return ($Path -like "*.jsonl")
}

function _Dsr-LoadJsonl {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $lines = Get-Content $Path -Encoding UTF8 -ErrorAction Stop
        if (-not $lines) { return @() }
        $out = @()
        foreach ($l in @($lines)) {
            $trim = $l.Trim()
            if (-not $trim) { continue }
            try {
                $obj = $trim | ConvertFrom-Json -ErrorAction Stop
                $out += $obj
            } catch {
                # linha corrompida — skip silencioso, continua
            }
        }
        return $out
    } catch {
        return @()
    }
}

function Get-DsrTrials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $GateName = $null      # se null, retorna total
    )
    if (-not (Test-Path $Path)) { return 0 }

    # B15: novo path JSONL
    if (_Dsr-IsJsonl $Path) {
        $entries = @(_Dsr-LoadJsonl -Path $Path)
        if ($GateName) {
            return @($entries | Where-Object { $_.gate -eq $GateName }).Count
        }
        return $entries.Count
    }

    # Legacy JSON path
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        if ($GateName) {
            if ($data.by_gate -and $data.by_gate.PSObject.Properties.Name -contains $GateName) {
                return [int]$data.by_gate.$GateName
            }
            return 0
        }
        return [int]$data.total_trials
    } catch {
        return 0
    }
}


function Add-DsrTrial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $GateName,
        [Parameter(Mandatory)] [string] $Market,
        # Tier 2 Block 2 E.1 (2026-05-23): direction tracking pra DSR per-direction.
        # Backward compat: default LONG (existing behavior). SHORT permite analise separada.
        [ValidateSet("LONG","SHORT")] [string] $Direction = "LONG"
    )
    # Cria diretorio se necessario
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # B15: novo path JSONL (atomic append, race-safe)
    if (_Dsr-IsJsonl $Path) {
        $entry = [ordered]@{
            ts        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            gate      = $GateName
            market    = $Market
            direction = $Direction
        }
        $line = ($entry | ConvertTo-Json -Compress -Depth 3)
        # Add-Content em PS 5.1 NTFS = atomic pra writes <512 bytes
        Add-Content -Path $Path -Value $line -Encoding UTF8
        # Stats apenas pra back-compat de retorno
        $total = @(Get-Content $Path -Encoding UTF8).Count
        $gateCount = @(_Dsr-LoadJsonl -Path $Path | Where-Object { $_.gate -eq $GateName }).Count
        return [PSCustomObject]@{
            success      = $true
            total_trials = $total
            gate_trials  = $gateCount
        }
    }

    # Legacy JSON path — preservado pra back-compat de testes existentes,
    # mas NAO race-safe. Callers de prod DEVEM usar .jsonl path.
    if (Test-Path $Path) {
        try {
            $raw = Get-Content $Path -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json
        } catch {
            $data = $null
        }
    }
    if (-not $data) {
        $data = [PSCustomObject]@{
            as_of = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            total_trials = 0
            by_gate = [PSCustomObject]@{}
            history = @()
        }
    }
    $data.total_trials = [int]$data.total_trials + 1
    if (-not ($data.by_gate.PSObject.Properties.Name -contains $GateName)) {
        $data.by_gate | Add-Member -NotePropertyName $GateName -NotePropertyValue 0
    }
    $data.by_gate.$GateName = [int]$data.by_gate.$GateName + 1
    $entry = [PSCustomObject]@{
        ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        gate = $GateName
        market = $Market
        direction = $Direction  # E.1 backward compat: default LONG
    }
    $hist = @($data.history) + $entry
    if ($hist.Count -gt 1000) { $hist = $hist[-1000..-1] }
    $data.history = $hist
    $data.as_of = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $json = $data | ConvertTo-Json -Depth 6
    $json | Out-File -FilePath $Path -Encoding UTF8
    return [PSCustomObject]@{
        success = $true
        total_trials = $data.total_trials
        gate_trials = $data.by_gate.$GateName
    }
}


function Get-DsrTrialsByDirection {
    <#
    .SYNOPSIS
    E.1 (2026-05-23): retorna trials filtrados por direction (LONG/SHORT/ALL).

    .DESCRIPTION
    Reads JSONL OR legacy JSON. Filters by direction field (default LONG pra back-compat).

    .OUTPUTS
    Array PSCustomObject {ts, gate, market, direction}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [ValidateSet("LONG","SHORT","ALL")] [string] $Direction = "ALL"
    )
    if (-not (Test-Path $Path)) { return @() }

    $trials = @()
    if (_Dsr-IsJsonl $Path) {
        $trials = @(_Dsr-LoadJsonl -Path $Path)
    } else {
        try {
            $data = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.history) { $trials = @($data.history) }
        } catch { return @() }
    }

    if ($Direction -eq "ALL") { return ,@($trials) }

    # Filter — entries sem direction default LONG (backward compat)
    $filtered = @($trials | Where-Object {
        $dir = if ($_.PSObject.Properties['direction']) { $_.direction } else { "LONG" }
        $dir -eq $Direction
    })
    return ,$filtered
}


function Get-DsrAdjustedThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $BaseThreshold,
        [Parameter(Mandatory)] [int] $NTrials
    )
    if ($NTrials -lt 1) { $NTrials = 1 }
    $logN = [Math]::Log10([double]$NTrials)
    $factor = 0.95 + ($logN * 0.15)
    $adjusted = $BaseThreshold * $factor
    $floor = $BaseThreshold * 0.95
    if ($adjusted -lt $floor) { $adjusted = $floor }
    if ($adjusted -gt 0.999)  { $adjusted = 0.999 }
    return [Math]::Round($adjusted, 4)
}

# lib_trailing_auto_activate.ps1 -- Ativa trailing automático em posições abertas

function Update-TrailingIfNeeded {
    [CmdletBinding()]
    param(
        [PSObject]$Position,        # posição do trailing_positions.json
        [double]$CurrentPrice,
        [string]$TrailFile          # caminho trailing_positions.json
    )

    # Se já tem trailing ativo, skip
    if ($Position.trailingEnabled -eq $true) { return $Position }

    $entry = [double]$Position.entry
    $peak = [double]$Position.peak
    if ($entry -le 0) { return $Position }

    $pnlPct = (($CurrentPrice - $entry) / $entry) * 100

    # Ativa trailing se:
    # 1) +5% a +10% com vol baixa = 3% trailing
    # 2) +2% a +5% = 2% trailing
    # 3) Já passou +10% = lock profit 2%

    $trailing_pct = 0
    if ($pnlPct -ge 10) {
        $trailing_pct = 0.02  # lock profit
    } elseif ($pnlPct -ge 5) {
        $trailing_pct = 0.03  # trailing 3%
    } elseif ($pnlPct -ge 2) {
        $trailing_pct = 0.02  # trailing 2%
    }

    if ($trailing_pct -gt 0) {
        $Position.trailingEnabled = $true
        $Position.trailingPct = $trailing_pct
        $Position.trailingActivatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Position.phase = 0  # start phase
    }

    $Position
}

function Activate-AllOpenTrailing {
    [CmdletBinding()]
    param(
        [string]$TrailFile
    )

    if (-not (Test-Path $TrailFile)) { return @() }

    try {
        $positions = Get-Content $TrailFile -Raw | ConvertFrom-Json
        if (-not $positions) { return @() }

        $activated = @()
        $positions | ForEach-Object {
            if ($_.active -ne $true) { return }  # skip closed
            if ($_.trailingEnabled -eq $true) { return }  # skip already enabled

            # Mark for activation
            $_.trailingEnabled = $true
            $_.trailingPct = 0.03  # default 3%
            $_.trailingActivatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $_.phase = 0

            $activated += @{
                market    = $_.market
                entry     = $_.entry
                status    = "trailing_activated"
            }
        }

        # Save back
        $positions | ConvertTo-Json -Depth 10 | Set-Content $TrailFile -Encoding UTF8 -Force

        $activated
    } catch {
        Write-Warning "[trailing-auto] falha: $_"
        @()
    }
}

function Get-TrailingStatus {
    [CmdletBinding()]
    param([string]$TrailFile)

    if (-not (Test-Path $TrailFile)) { return @() }

    try {
        $positions = Get-Content $TrailFile -Raw | ConvertFrom-Json
        $positions | ForEach-Object {
            if ($_.active -eq $true) {
                @{
                    market          = $_.market
                    trailing        = $_.trailingEnabled -eq $true
                    trailing_pct    = $_.trailingPct
                    phase           = $_.phase
                    peak            = $_.peak
                    stop_current    = $_.stopCurrent
                }
            }
        }
    } catch { @() }
}

# Export-ModuleMember nao necessario em dot-source; comentado para compatibilidade Pester

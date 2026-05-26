# agents/lib_moon_bag.ps1
# Layer 5: Moon Bag (50/50 Harvest + Upside)
#
# Filosofia: ao entrar numa posição, divide em duas pernas:
#   - Harvest (50% size): target +5%, stop -2% — captura ganho de certeza rápido
#   - Moon Bag (50% size): target +30%, stop -10%, time-limit 20d — busca o moonshot
#
# Defesa contra "BNB scenario": peak passou +3.75% mas saímos com +1.7% (stop tightened).
# Com Moon Bag, harvest leg teria fechado +5% em metade da posição enquanto
# moon leg continuava buscando o upside.
#
# Dot-source: . (Join-Path $PSScriptRoot "lib_moon_bag.ps1")

# Resolve caminhos com fallback (testes podem dot-source isolado)
$_moonBagAgentsDir = $PSScriptRoot
$_moonBagJournalDir = Join-Path (Split-Path $_moonBagAgentsDir -Parent) "journal"
$MOON_BAG_DEFAULT_FILE = Join-Path $_moonBagJournalDir "trailing_positions.json"

# ─────────────────────────────────────────────────────────────────────
# Split-MoonBagPosition — Divide entrada em 2 pernas (harvest + moon)
# ─────────────────────────────────────────────────────────────────────
function Split-MoonBagPosition {
    <#
    .SYNOPSIS
    Calcula configuração de duas pernas (harvest + moon) para Moon Bag strategy.

    .PARAMETER Entry
    Preço de entrada da posição.

    .PARAMETER Size
    Tamanho total da posição (em USD ou unidade base).

    .PARAMETER Side
    "LONG" (default) ou "SHORT".

    .PARAMETER HarvestRatio
    Fração da size para harvest leg (default 0.5 = 50/50).

    .PARAMETER HarvestTargetPct
    Target do harvest em % (default 5.0 = +5%).

    .PARAMETER HarvestStopPct
    Stop do harvest em % (default 2.0 = -2%).

    .PARAMETER MoonTargetPct
    Target do moon bag em % (default 30.0 = +30%).

    .PARAMETER MoonStopPct
    Stop do moon bag em % (default 10.0 = -10%).

    .PARAMETER MoonMaxDays
    Dias máximos pra moon leg antes de timeout (default 20).

    .OUTPUTS
    PSCustomObject com .harvest e .moon (ambos com size/target/stop/maxDays).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][double]$Entry,
        [Parameter(Mandatory=$true)][double]$Size,
        [ValidateSet("LONG","SHORT")][string]$Side = "LONG",
        [ValidateRange(0.1, 0.9)][double]$HarvestRatio = 0.5,
        [double]$HarvestTargetPct = 5.0,
        [double]$HarvestStopPct = 2.0,
        [double]$MoonTargetPct = 30.0,
        [double]$MoonStopPct = 10.0,
        [int]$MoonMaxDays = 20
    )

    $harvestSize = $Size * $HarvestRatio
    $moonSize    = $Size * (1.0 - $HarvestRatio)

    if ($Side -eq "LONG") {
        $harvestTarget = $Entry * (1.0 + $HarvestTargetPct / 100.0)
        $harvestStop   = $Entry * (1.0 - $HarvestStopPct / 100.0)
        $moonTarget    = $Entry * (1.0 + $MoonTargetPct / 100.0)
        $moonStop      = $Entry * (1.0 - $MoonStopPct / 100.0)
    }
    else {
        # SHORT: target abaixo (lucro quando preço cai), stop acima
        $harvestTarget = $Entry * (1.0 - $HarvestTargetPct / 100.0)
        $harvestStop   = $Entry * (1.0 + $HarvestStopPct / 100.0)
        $moonTarget    = $Entry * (1.0 - $MoonTargetPct / 100.0)
        $moonStop      = $Entry * (1.0 + $MoonStopPct / 100.0)
    }

    return [PSCustomObject]@{
        side    = $Side
        entry   = $Entry
        harvest = [PSCustomObject]@{
            kind    = "harvest"
            size    = [math]::Round($harvestSize, 8)
            entry   = $Entry
            target  = [math]::Round($harvestTarget, 8)
            stop    = [math]::Round($harvestStop, 8)
            maxDays = 0
        }
        moon = [PSCustomObject]@{
            kind    = "moon"
            size    = [math]::Round($moonSize, 8)
            entry   = $Entry
            target  = [math]::Round($moonTarget, 8)
            stop    = [math]::Round($moonStop, 8)
            maxDays = $MoonMaxDays
        }
    }
}

# ─────────────────────────────────────────────────────────────────────
# Get-MoonBagLegDecision — Decide ação para uma perna individual
# ─────────────────────────────────────────────────────────────────────
function Get-MoonBagLegDecision {
    <#
    .SYNOPSIS
    Avalia uma perna (harvest ou moon) e retorna ação: CLOSE_TARGET, CLOSE_STOP,
    CLOSE_TIMEOUT ou HOLD.

    .PARAMETER Leg
    PSCustomObject com kind, side, entry, target, stop, openedAt, maxDays.

    .PARAMETER CurrentPrice
    Preço atual da posição.

    .OUTPUTS
    PSCustomObject com .action e .reason.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Leg,
        [Parameter(Mandatory=$true)][double]$CurrentPrice
    )

    $side    = if ($Leg.side) { [string]$Leg.side } else { "LONG" }
    $target  = [double]$Leg.target
    $stop    = [double]$Leg.stop
    $maxDays = if ($Leg.maxDays) { [int]$Leg.maxDays } else { 0 }

    # Priority: target > stop > timeout > hold
    if ($side -eq "LONG") {
        if ($CurrentPrice -ge $target) {
            return [PSCustomObject]@{
                action = "CLOSE_TARGET"
                reason = "target_hit_long"
                kind   = $Leg.kind
            }
        }
        if ($CurrentPrice -le $stop) {
            return [PSCustomObject]@{
                action = "CLOSE_STOP"
                reason = "stop_hit_long"
                kind   = $Leg.kind
            }
        }
    }
    else {
        # SHORT: lucra quando preço cai (target abaixo), perde quando sobe (stop acima)
        if ($CurrentPrice -le $target) {
            return [PSCustomObject]@{
                action = "CLOSE_TARGET"
                reason = "target_hit_short"
                kind   = $Leg.kind
            }
        }
        if ($CurrentPrice -ge $stop) {
            return [PSCustomObject]@{
                action = "CLOSE_STOP"
                reason = "stop_hit_short"
                kind   = $Leg.kind
            }
        }
    }

    # Verificar timeout (apenas se maxDays > 0)
    if ($maxDays -gt 0 -and $Leg.openedAt) {
        try {
            $entryTime = [DateTime]::Parse([string]$Leg.openedAt)
            $daysElapsed = ((Get-Date) - $entryTime).TotalDays
            if ($daysElapsed -gt $maxDays) {
                return [PSCustomObject]@{
                    action = "CLOSE_TIMEOUT"
                    reason = "max_days_exceeded"
                    kind   = $Leg.kind
                    daysElapsed = [math]::Round($daysElapsed, 2)
                }
            }
        } catch {
            # openedAt inválido — ignora timeout, segue HOLD
        }
    }

    return [PSCustomObject]@{
        action = "HOLD"
        reason = "in_range"
        kind   = $Leg.kind
    }
}

# ─────────────────────────────────────────────────────────────────────
# Add-MoonBagPair — Persiste duas pernas (harvest + moon) no journal
# ─────────────────────────────────────────────────────────────────────
function Add-MoonBagPair {
    <#
    .SYNOPSIS
    Adiciona duas entradas (harvest + moon) ao journal de posições com pairId
    compartilhado.

    .PARAMETER Market
    Símbolo do mercado (ex: BNBUSDT).

    .PARAMETER Side
    LONG ou SHORT.

    .PARAMETER Entry
    Preço de entrada.

    .PARAMETER Size
    Tamanho total (será dividido pela strategy).

    .PARAMETER JournalPath
    Caminho do arquivo journal (default: journal/trailing_positions.json).

    .PARAMETER OrderId
    ID da ordem original (opcional, replicado em ambas pernas).

    .PARAMETER HarvestRatio
    Fração harvest (default 0.5).

    .PARAMETER HarvestTargetPct, HarvestStopPct, MoonTargetPct, MoonStopPct, MoonMaxDays
    Parâmetros de configuração (vide Split-MoonBagPosition).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [ValidateSet("LONG","SHORT")][string]$Side = "LONG",
        [Parameter(Mandatory=$true)][double]$Entry,
        [Parameter(Mandatory=$true)][double]$Size,
        [string]$JournalPath = $MOON_BAG_DEFAULT_FILE,
        [string]$OrderId = "",
        [double]$HarvestRatio = 0.5,
        [double]$HarvestTargetPct = 5.0,
        [double]$HarvestStopPct = 2.0,
        [double]$MoonTargetPct = 30.0,
        [double]$MoonStopPct = 10.0,
        [int]$MoonMaxDays = 20
    )

    $cfg = Split-MoonBagPosition -Entry $Entry -Size $Size -Side $Side `
        -HarvestRatio $HarvestRatio `
        -HarvestTargetPct $HarvestTargetPct -HarvestStopPct $HarvestStopPct `
        -MoonTargetPct $MoonTargetPct -MoonStopPct $MoonStopPct `
        -MoonMaxDays $MoonMaxDays

    $pairId = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $now    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Constrói as duas pernas como objetos compatíveis com lib_trailing schema
    $harvestLeg = [PSCustomObject]@{
        market         = $Market
        side           = $Side
        entry          = $Entry
        stop           = $cfg.harvest.stop
        target         = $cfg.harvest.target
        size           = $cfg.harvest.size
        orderId        = $OrderId
        source         = "moon_bag"
        mode           = "MOON_BAG_HARVEST"
        max_days       = 0
        dd_threshold_pct = 30.0
        phase          = 0
        peak           = $Entry
        stopCurrent    = $cfg.harvest.stop
        active         = $true
        openedAt       = $now
        updatedAt      = $now
        moonBagPairId  = $pairId
        moonBagKind    = "harvest"
    }

    $moonLeg = [PSCustomObject]@{
        market         = $Market
        side           = $Side
        entry          = $Entry
        stop           = $cfg.moon.stop
        target         = $cfg.moon.target
        size           = $cfg.moon.size
        orderId        = $OrderId
        source         = "moon_bag"
        mode           = "MOON_BAG_MOON"
        max_days       = $MoonMaxDays
        dd_threshold_pct = 50.0
        phase          = 0
        peak           = $Entry
        stopCurrent    = $cfg.moon.stop
        active         = $true
        openedAt       = $now
        updatedAt      = $now
        moonBagPairId  = $pairId
        moonBagKind    = "moon"
    }

    # Branch path: state_store (preferido quando flag ativa + JournalPath default)
    # vs legacy file path (sempre que JournalPath foi explicitamente passado).
    $isDefaultPath = ($JournalPath -eq $MOON_BAG_DEFAULT_FILE)
    $hasStateStore = (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue) -ne $null

    if ($isDefaultPath -and $hasStateStore) {
        # Usa Save-TrailingPositions que respeita TRAILING_USE_STATE_STORE flag.
        # Se flag OFF: escreve em journal/trailing_positions.json (legacy).
        # Se flag ON: escreve em state_store backend (local OR supabase).
        # Importante: precisamos preservar legs existentes (lib_trailing faz upsert
        # por pk_id, e harvest/moon tem pk_ids diferentes mesmo no mesmo market).

        # Garantir que outras posicoes nao-Moon-Bag (e outros pairs) sao preservadas
        $existing = @()
        if (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue) {
            try { $existing = @(Get-TrailingPositions) } catch { $existing = @() }
        }
        $combined = @($existing) + @($harvestLeg) + @($moonLeg)
        Save-TrailingPositions -Positions $combined

    } else {
        # Legacy file path (back-compat tests + custom JournalPath callers)
        $existing = @()
        if (Test-Path $JournalPath) {
            try {
                $raw = Get-Content $JournalPath -Raw
                if ($raw -and $raw.Trim().Length -gt 0) {
                    $parsed = $raw | ConvertFrom-Json
                    if ($parsed) { $existing = @($parsed) }
                }
            } catch {
                $existing = @()
            }
        } else {
            $dir = Split-Path $JournalPath
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        $combined = @($existing) + @($harvestLeg) + @($moonLeg)
        $combined | ConvertTo-Json -Depth 5 | Set-Content $JournalPath -Encoding utf8
    }

    return [PSCustomObject]@{
        pairId  = $pairId
        harvest = $harvestLeg
        moon    = $moonLeg
    }
}

# ─────────────────────────────────────────────────────────────────────
# Get-MoonBagPositions — Filtra apenas pernas Moon Bag do journal
# ─────────────────────────────────────────────────────────────────────
function Get-MoonBagPositions {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string]$JournalPath = $MOON_BAG_DEFAULT_FILE,
        [switch]$ActiveOnly
    )

    # Branch path: state_store (preferido) vs legacy file
    $isDefaultPath = ($JournalPath -eq $MOON_BAG_DEFAULT_FILE)
    $hasStateStore = (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue) -ne $null

    $all = @()
    if ($isDefaultPath -and $hasStateStore) {
        try {
            $all = @(Get-TrailingPositions)
        } catch {
            $all = @()
        }
    }

    # Fallback / legacy path: ler direto do arquivo
    if (@($all).Count -eq 0 -and (Test-Path $JournalPath)) {
        try {
            $raw = Get-Content $JournalPath -Raw
            if ($raw -and $raw.Trim().Length -gt 0) {
                $all = @($raw | ConvertFrom-Json)
            }
        } catch {
            $all = @()
        }
    }

    # Flatten qualquer wrapper aninhado: PS 5.1 ConvertFrom-Json pode devolver
    # arrays aninhados ou wrappers {value=[...], Count=N}.
    $flat = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    foreach ($x in $all) { $stack.Push($x) }

    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        if ($null -eq $item) { continue }

        if ($item -is [array]) {
            foreach ($inner in $item) { $stack.Push($inner) }
            continue
        }
        if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
            foreach ($inner in $item) { $stack.Push($inner) }
            continue
        }
        if ($item.PSObject.Properties['value'] -and $item.PSObject.Properties['Count'] -and ($item.value -is [array])) {
            foreach ($inner in $item.value) { $stack.Push($inner) }
            continue
        }
        [void]$flat.Add($item)
    }

    $moonBag = @($flat | Where-Object {
        $null -ne $_ -and $null -ne $_.moonBagKind -and ([string]$_.moonBagKind).Length -gt 0
    })

    if ($ActiveOnly) {
        $moonBag = @($moonBag | Where-Object { $_.active })
    }

    return @($moonBag)
}

# ─────────────────────────────────────────────────────────────────────
# Update-MoonBagReview — Loop integrator (chamado a cada scan cycle)
# ─────────────────────────────────────────────────────────────────────
# MODO PADRÃO: ADVISORY (somente alerta, NÃO executa close)
# Para opt-in de execução automática: $global:MOON_BAG_AUTO_EXECUTE = $true
# ─────────────────────────────────────────────────────────────────────
function Update-MoonBagReview {
    [CmdletBinding()]
    param(
        [string]$JournalPath = $MOON_BAG_DEFAULT_FILE,
        [switch]$AutoExecute
    )

    $autoExec = $AutoExecute.IsPresent -or ($global:MOON_BAG_AUTO_EXECUTE -eq $true)
    $modeLabel = if ($autoExec) { "AUTO_EXECUTE" } else { "ADVISORY" }

    $legs = @(Get-MoonBagPositions -JournalPath $JournalPath -ActiveOnly)
    if ($legs.Count -eq 0) { return }

    Write-Host "  [Layer5/MoonBag] Reviewing $($legs.Count) leg(s) in $modeLabel mode..." -ForegroundColor DarkCyan

    $changed = $false
    $allPositions = @()
    if (Test-Path $JournalPath) {
        try {
            $allPositions = @(Get-Content $JournalPath -Raw | ConvertFrom-Json)
        } catch {
            $allPositions = @()
        }
    }

    foreach ($pos in $allPositions) {
        if (-not $pos.active) { continue }
        if (-not $pos.PSObject.Properties['moonBagKind']) { continue }

        # Atualiza preço atual via CoinEx-GetTicker se disponível
        $current = if ($pos.currentPrice) { [double]$pos.currentPrice } else { [double]$pos.entry }
        if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
            try {
                $tk = CoinEx-GetTicker $pos.market
                if ($tk -and $tk.last) {
                    $current = [double]$tk.last
                    $pos | Add-Member -NotePropertyName "currentPrice" -NotePropertyValue $current -Force
                }
            } catch { }
        }

        $decision = Get-MoonBagLegDecision -Leg $pos -CurrentPrice $current

        $color = switch ($decision.action) {
            "CLOSE_TARGET"  { "Green" }
            "CLOSE_STOP"    { "Red" }
            "CLOSE_TIMEOUT" { "Yellow" }
            default         { "DarkCyan" }
        }
        Write-Host "    [Layer5] $($pos.market) $($pos.moonBagKind) $($pos.side): $($decision.action)" -ForegroundColor $color

        if ($decision.action -eq "HOLD") { continue }

        if (-not $autoExec) {
            # ADVISORY: alerta + tag, sem fechar
            $pos | Add-Member -NotePropertyName "moonBagAdvisory" -NotePropertyValue $decision.action -Force
            $pos | Add-Member -NotePropertyName "moonBagAdvisoryReason" -NotePropertyValue $decision.reason -Force
            $pos | Add-Member -NotePropertyName "lastMoonBagReview" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
            $changed = $true

            if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                try {
                    $msg = "[Layer5 ADVISORY] $($pos.market) $($pos.moonBagKind) $($pos.side) suggests $($decision.action) at $current. Manual action required."
                    Send-TelegramAlert -Message $msg | Out-Null
                } catch { }
            }
            continue
        }

        # AUTO_EXECUTE: fecha na exchange
        $exchangeClosed = $false
        if (Get-Command CoinEx-ClosePosition -ErrorAction SilentlyContinue) {
            try {
                $r = CoinEx-ClosePosition $pos.market
                if ($r -and $r.code -eq 0) { $exchangeClosed = $true }
            } catch { }
        }

        if ($exchangeClosed) {
            $pos.active = $false
            $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue $decision.reason -Force
            $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
            $changed = $true

            if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                try {
                    Send-TelegramAlert -Message "[Layer5 EXECUTED] $($pos.market) $($pos.moonBagKind) CLOSED: $($decision.reason)" | Out-Null
                } catch { }
            }
        }
    }

    if ($changed) {
        $allPositions | ConvertTo-Json -Depth 5 | Set-Content $JournalPath -Encoding utf8
    }
}

# Functions exported (PS dot-source pattern):
# - Split-MoonBagPosition
# - Get-MoonBagLegDecision
# - Add-MoonBagPair
# - Get-MoonBagPositions
# - Update-MoonBagReview

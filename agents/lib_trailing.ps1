# lib_trailing.ps1 — Trailing stop em 3 fases para posicoes abertas
# Dot-source: . (Join-Path $PSScriptRoot "lib_trailing.ps1")
#
# Fases (LONG):
#   Fase 1 — preco atinge 33% do alvo → move stop para breakeven (+buffer)
#   Fase 2 — preco atinge 66% do alvo → move stop para +33% do ganho
#   Fase 3 — preco ultrapassa alvo    → trailing 15% abaixo do pico
#
# Para SHORT: logica espelhada (stop desce conforme preco cai)

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_telegram.ps1")

$TRAILING_FILE = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "trailing_positions.json"

# ── Persistencia ──────────────────────────────────────────────────────────────

function Get-TrailingPositions {
    if (-not (Test-Path $TRAILING_FILE)) { return @() }
    try {
        $json = Get-Content $TRAILING_FILE -Raw | ConvertFrom-Json
        # Force flat array - fix corruption issues
        $result = @()
        foreach ($item in $json) {
            # Skip corrupted nested objects
            if ($item.PSObject.Properties['market']) {
                $result += $item
            }
        }
        return $result
    } catch {
        return @()
    }
}

function Save-TrailingPositions {
    param([object[]]$Positions)
    $dir = Split-Path $TRAILING_FILE
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Positions | ConvertTo-Json -Depth 5 | Set-Content $TRAILING_FILE -Encoding utf8
}

# ── Registrar posicao nova ─────────────────────────────────────────────────────

function Add-TrailingPosition {
    # 2026-05-19 PM: extended com Mode + MaxDays + DdThresholdPct pra
    # source-aware downstream behavior (GEM != STANDARD != TIER_A_LIVE).
    # Mode "GEM"     -> wide stop 20% + moon bag + max_days enforced
    # Mode "TIER_A"  -> ATR stop progressivo, DD threshold conservador
    # Mode "STANDARD"-> orchestrator legacy
    param(
        [string]$Market,
        [string]$Side,          # "LONG" | "SHORT"
        [double]$Entry,
        [double]$Stop,
        [double]$Target,
        [string]$OrderId  = "",
        [string]$Source   = "orchestrator",   # "orchestrator" | "gem" | "tier_a"
        [string]$Mode     = "",               # "STANDARD" | "GEM" | "TIER_A" (auto-deriv se vazio)
        [int]   $MaxDays  = 0,                # 0 = sem limite. GEM costuma ter 5-30 dias.
        [double]$DdThresholdPct = 0           # 0 = global default. GEM=40%, TIER_A=25%.
    )

    $positions = @(Get-TrailingPositions)
    $existing  = $positions | Where-Object { $_.market -eq $Market -and $_.active }
    if ($existing) {
        Write-Host "  [Trailing] Posicao ja existe para $Market - ignorando duplicata." -ForegroundColor DarkYellow
        return
    }

    # Auto-derive Mode a partir de Source se nao explicito
    if (-not $Mode) {
        $Mode = switch ($Source) {
            "gem"        { "GEM" }
            "tier_a"     { "TIER_A" }
            default      { "STANDARD" }
        }
    }
    # Defaults inteligentes por mode quando user nao especifica
    if ($MaxDays -eq 0 -and $Mode -eq "GEM") { $MaxDays = 14 }   # GEM default 14d budget
    if ($DdThresholdPct -eq 0) {
        $DdThresholdPct = switch ($Mode) {
            "GEM"     { 40.0 }   # GEM tolera mais DD (vol alto natural)
            "TIER_A"  { 25.0 }   # Tier A LIVE conservador
            default   { 30.0 }
        }
    }

    $pos = [PSCustomObject]@{
        market         = $Market
        side           = $Side
        entry          = $Entry
        stop           = $Stop
        target         = $Target
        orderId        = $OrderId
        source         = $Source
        mode           = $Mode
        max_days       = $MaxDays
        dd_threshold_pct = $DdThresholdPct
        phase          = 0          # 0=inicial 1=BE 2=lock1 3=trailing
        peak           = $Entry     # maior preco visto (LONG) ou menor (SHORT)
        stopCurrent    = $Stop
        active         = $true
        openedAt       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        updatedAt      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    $positions += $pos
    Save-TrailingPositions $positions
    Write-Host "  [Trailing] Registrado: $Market $Side mode=$Mode entry=$Entry stop=$Stop target=$Target max_days=$MaxDays dd_cap=${DdThresholdPct}%" -ForegroundColor Green
}

# ── Fechar posicao ────────────────────────────────────────────────────────────

function Close-TrailingPosition {
    # 2026-05-19 PM: emite outcome pra feedback loop (Add-TradeOutcome) ao fechar.
    # Computa R-multiple: gain / risk (entry - stop). LONG positivo se exit > entry;
    # SHORT positivo se exit < entry.
    param(
        [string]$Market,
        [string]$Reason = "",
        [double]$ExitPrice = 0,
        [string]$OutcomePath = ""
    )
    $positions = @(Get-TrailingPositions)
    $script:closedPos = $null
    $updated   = $positions | ForEach-Object {
        if ($_.market -eq $Market -and $_.active) {
            $_.active = $false
            $_ | Add-Member -MemberType NoteProperty -Name closedAt   -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
            $_ | Add-Member -MemberType NoteProperty -Name closeReason -Value $Reason -Force
            if ($ExitPrice -gt 0) { $_ | Add-Member -MemberType NoteProperty -Name exitPrice -Value $ExitPrice -Force }
            $script:closedPos = $_
        }
        $_
    }
    Save-TrailingPositions $updated
    Write-Host "  [Trailing] Fechado: $Market ($Reason)" -ForegroundColor Yellow

    # Feedback emit (best-effort; tolerante a falha)
    if ($script:closedPos -and $ExitPrice -gt 0 -and (Get-Command Add-TradeOutcome -ErrorAction SilentlyContinue)) {
        try {
            $entry = [double]$script:closedPos.entry
            $stop  = [double]$script:closedPos.stop
            $target = [double]$script:closedPos.target
            $side = [string]$script:closedPos.side
            $mode = if ($script:closedPos.PSObject.Properties['mode']) { [string]$script:closedPos.mode } else { "STANDARD" }
            $risk = [Math]::Abs($entry - $stop)
            $gain = if ($side -eq "LONG") { $ExitPrice - $entry } else { $entry - $ExitPrice }
            $r = if ($risk -gt 0) { [Math]::Round($gain / $risk, 3) } else { 0 }
            $pnl = $gain   # rough USD proxy (precisa size pra real; usa diff de preco)
            # Duration aproximada
            $duration = 0
            if ($script:closedPos.openedAt) {
                try {
                    $opened = [DateTime]::Parse([string]$script:closedPos.openedAt)
                    $duration = [Math]::Round(((Get-Date) - $opened).TotalDays, 2)
                } catch {}
            }
            $kwargs = @{
                Market = $Market; Side = $side; Mode = $mode
                EntryPrice = $entry; ExitPrice = $ExitPrice
                StopPrice = $stop; TargetPrice = $target
                R = $r; Pnl = $pnl; DurationDays = $duration
                ExitReason = $Reason
            }
            if ($OutcomePath) { $kwargs.OutcomePath = $OutcomePath }
            Add-TradeOutcome @kwargs
        } catch {
            Write-Host "  [Trailing] Add-TradeOutcome falhou (nao bloqueia): $_" -ForegroundColor DarkYellow
        }
    }
}

# ── Calcular novo stop por fase ───────────────────────────────────────────────

function Get-TrailingNewStop {
    param([object]$Pos, [double]$CurrentPrice)

    $entry  = [double]$Pos.entry
    $target = [double]$Pos.target
    $stop   = [double]$Pos.stopCurrent
    $peak   = [double]$Pos.peak
    $phase  = [int]$Pos.phase
    $side   = $Pos.side

    $range  = [math]::Abs($target - $entry)   # distancia entry→target
    $buffer = $range * 0.02                    # 2% de buffer acima do entry no BE

    if ($side -eq "LONG") {
        $gain1  = $entry + $range * 0.33
        $gain2  = $entry + $range * 0.66
        $newPeak = [math]::Max($peak, $CurrentPrice)

        $newStop  = $stop
        $newPhase = $phase

        if ($phase -lt 3 -and $CurrentPrice -ge $target) {
            # Fase 3: trailing 15% abaixo do pico — nunca recua do stop atual
            $newPhase = 3
            $newStop  = [math]::Max($stop, [math]::Round($newPeak * 0.85, 4))
        } elseif ($phase -lt 2 -and $CurrentPrice -ge $gain2) {
            # Fase 2: stop em +33% do ganho
            $newPhase = 2
            $newStop  = [math]::Round($entry + $range * 0.33, 4)
        } elseif ($phase -lt 1 -and $CurrentPrice -ge $gain1) {
            # Fase 1: breakeven + buffer
            $newPhase = 1
            $newStop  = [math]::Round($entry + $buffer, 4)
        } elseif ($phase -eq 3) {
            # Trailing ativo: atualiza se pico subiu
            $newStop = [math]::Max($stop, [math]::Round($newPeak * 0.85, 4))
        }

        return [PSCustomObject]@{
            newStop  = $newStop
            newPhase = $newPhase
            newPeak  = $newPeak
            changed  = ($newStop -gt $stop -or $newPhase -gt $phase)
        }

    } else {
        # SHORT: logica espelhada
        $gain1  = $entry - $range * 0.33
        $gain2  = $entry - $range * 0.66
        $newPeak = [math]::Min($peak, $CurrentPrice)

        $newStop  = $stop
        $newPhase = $phase

        if ($phase -lt 3 -and $CurrentPrice -le $target) {
            # Fase 3 SHORT: trailing 15% acima do pico (preco minimo) — nunca recua
            $newPhase = 3
            $newStop  = [math]::Min($stop, [math]::Round($newPeak * 1.15, 4))
        } elseif ($phase -lt 2 -and $CurrentPrice -le $gain2) {
            $newPhase = 2
            $newStop  = [math]::Round($entry - $range * 0.33, 4)
        } elseif ($phase -lt 1 -and $CurrentPrice -le $gain1) {
            $newPhase = 1
            $newStop  = [math]::Round($entry - $buffer, 4)
        } elseif ($phase -eq 3) {
            $newStop = [math]::Min($stop, [math]::Round($newPeak * 1.15, 4))
        }

        return [PSCustomObject]@{
            newStop  = $newStop
            newPhase = $newPhase
            newPeak  = $newPeak
            changed  = ($newStop -lt $stop -or $newPhase -gt $phase)
        }
    }
}

# ── Ciclo de atualizacao (chamado pelo master loop) ───────────────────────────

function Test-MaxDaysExceeded {
    # Pure function: testa se posicao excedeu max_days budget. Retorna $true se sim.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Pos,
        [datetime] $Now = (Get-Date)
    )
    $maxDays = if ($Pos.PSObject.Properties['max_days']) { [int]$Pos.max_days } else { 0 }
    if ($maxDays -le 0) { return $false }
    $openedStr = if ($Pos.openedAt) { [string]$Pos.openedAt } else { return $false }
    try {
        $opened = [DateTime]::Parse($openedStr)
    } catch { return $false }
    $daysOpen = ($Now - $opened).TotalDays
    return ($daysOpen -ge $maxDays)
}


function Update-TrailingStops {
    $positions = @(Get-TrailingPositions)
    $active    = $positions | Where-Object { $_.active }

    if (-not $active -or @($active).Count -eq 0) { return }

    Write-Host "  [Trailing] Verificando $(@($active).Count) posicao(oes) ativa(s)..." -ForegroundColor DarkGreen

    $updated = $false
    $positions = $positions | ForEach-Object {
        $pos = $_
        if (-not $pos.active) { return $pos }

        try {
            $ticker = CoinEx-GetTicker $pos.market
            if (-not $ticker) { return $pos }
            $price = [double]$ticker.last

            $phaseLabel = @("inicial","breakeven","lock+33%","trailing")

            # 2026-05-19 PM: max_days enforcement (GEM positions tem budget de tempo).
            # Se max_days excedido, FORCE close com reason "max_days_exceeded".
            # Aplica ANTES do stop check (priority sobre stop natural).
            if (Test-MaxDaysExceeded -Pos $pos) {
                $msg = "<b>MAX_DAYS EXCEDIDO</b>`n$($pos.market) $($pos.side) mode=$($pos.mode) max_days=$($pos.max_days)`nForce close em \$$price"
                Write-Host "  [Trailing] MAX_DAYS $($pos.market) mode=$($pos.mode) - force close" -ForegroundColor DarkYellow
                try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
                $pos.active     = $false
                $pos.closedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $pos.closeReason = "max_days_exceeded"
                $updated = $true
                return $pos
            }

            # Verifica se stop foi atingido
            $stopped = if ($pos.side -eq "LONG") { $price -le [double]$pos.stopCurrent } `
                       else                       { $price -ge [double]$pos.stopCurrent }

            if ($stopped) {
                $msg = Format-TgTrailStopHit -Pos $pos -CurrentPrice $price
                Write-Host "  [Trailing] STOP $($pos.market) fase=$($pos.phase) preco=$price" -ForegroundColor Red
                Send-TelegramAlert -Message $msg | Out-Null
                $pos.active     = $false
                $pos.closedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $pos.closeReason = "stop_atingido"
                $updated = $true
                return $pos
            }

            $calc = Get-TrailingNewStop -Pos $pos -CurrentPrice $price
            
            # 2026-05-25 BUG FIX: peak deve persistir mesmo sem mudanca de fase.
            # Antes: peak so era salvo se $calc.changed -> em mercado lateral o peak
            # nunca subia, e quando trigger acontecia entre runs, o peak antigo
            # bloqueava avanco de fase. Caso BNB: peak subiu para 672.89 mas peak
            # registrado ainda 662.24, perdendo Phase 2.
            $peakChanged = ($calc.newPeak -ne [double]$pos.peak)
            $pos.peak = $calc.newPeak
            if ($peakChanged) { $updated = $true }

            if ($calc.changed) {
                $oldStop  = $pos.stopCurrent
                $oldPhase = $pos.phase
                $pos.stopCurrent = $calc.newStop
                $pos.phase       = $calc.newPhase
                $pos.updatedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $updated = $true

                $msg = Format-TgTrailPhase -Pos $pos -OldStop $oldStop -OldPhase $oldPhase -CurrentPrice $price
                Write-Host "  [Trailing] $($pos.market) stop $oldStop -> $($calc.newStop) fase=$($pos.phase) preco=$price" -ForegroundColor Green
                Send-TelegramAlert -Message $msg | Out-Null

                # Tenta mover stop na exchange (best-effort)
                try {
                    CoinEx-SetStopLoss -Market $pos.market -OrderId $pos.orderId -StopPrice $calc.newStop | Out-Null
                } catch {
                    Write-Host "  [Trailing] Aviso: nao foi possivel mover stop na exchange: $_" -ForegroundColor DarkYellow
                }
            }

        } catch {
            Write-Host "  [Trailing] Erro ao atualizar $($pos.market): $_" -ForegroundColor DarkRed
        }
        return $pos
    }

    if ($updated) { Save-TrailingPositions @($positions) }
}

# ── Status resumido ───────────────────────────────────────────────────────────

function Show-TrailingStatus {
    $positions = @(Get-TrailingPositions) | Where-Object { $_.active }
    if (-not $positions -or @($positions).Count -eq 0) {
        Write-Host "  [Trailing] Nenhuma posicao ativa." -ForegroundColor DarkGray
        return
    }
    $phaseLabel = @("inicial","breakeven","lock+33%","trailing")
    foreach ($p in $positions) {
        Write-Host ("  [Trailing] {0} {1} | fase={2} ({3}) | stop={4} | peak={5} | desde={6}" -f `
            $p.market, $p.side, $p.phase, $phaseLabel[$p.phase], $p.stopCurrent, $p.peak, $p.openedAt) -ForegroundColor Cyan
    }
}

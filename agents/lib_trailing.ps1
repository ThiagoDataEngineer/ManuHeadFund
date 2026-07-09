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
# 2026-05-26 A.1 wire: reflection ledger E3 (graceful se lib ausente)
if (Test-Path (Join-Path $PSScriptRoot "lib_decision_reflection.ps1")) {
    . (Join-Path $PSScriptRoot "lib_decision_reflection.ps1")
}

$TRAILING_FILE = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "trailing_positions.json"

# Helper: resolve TRAILING_FILE com override de $global:TRAILING_FILE (para tests)
function _Get-TrailingFile {
    if ($global:TRAILING_FILE) { return [string]$global:TRAILING_FILE }
    return $TRAILING_FILE
}

# Lazy load state_store (sibling lib). Skip se nao disponivel.
$_trailingStateStorePath = Join-Path $PSScriptRoot "lib_state_store.ps1"
if (Test-Path $_trailingStateStorePath) {
    . $_trailingStateStorePath
}

# Helper: decide if trailing should use state_store (opt-in)
function _Test-TrailingUsesStateStore {
    if ($null -ne $global:TRAILING_USE_STATE_STORE) {
        return [bool]$global:TRAILING_USE_STATE_STORE
    }
    # Filesystem flag fallback
    $flagPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "USE_SUPABASE_STATE.flag"
    return (Test-Path $flagPath)
}

# Helper: compute pk_id for a position (Moon Bag has 2 legs per market)
function _Get-TrailingPkId {
    param([PSCustomObject]$Position)
    $market = [string]$Position.market
    if ($Position.PSObject.Properties['moonBagKind'] -and $Position.moonBagKind) {
        return "$market`:$($Position.moonBagKind)"
    }
    return $market
}

# ── Persistencia ──────────────────────────────────────────────────────────────

function Get-TrailingPositions {
    # state_store path (opt-in)
    if ((_Test-TrailingUsesStateStore) -and (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) {
        try {
            # 2026-07-09 FIX: tabela renomeada trailing_positions -> trailing_state.
            # A 'trailing_positions' do Supabase pertence ao position_sync (shape
            # id/symbol/...); este estado usa pk_id/market/... — dois shapes na mesma
            # tabela = upsert 400 silencioso = estado NUNCA persistia na nuvem
            # (peaks/fases resetavam a cada run stateless). DDL: docs/SETUP v2.
            $rows = @(Get-StateRecords -Table "trailing_state")
            $result = @()
            foreach ($item in $rows) {
                if ($null -ne $item -and $item.PSObject.Properties['market']) {
                    $result += $item
                }
            }
            # 2026-06-11 fix: _Supabase-Get engole erros e retorna @() sem throw
            # (ex.: tabela ausente PGRST205). Resultado vazio NAO pode mascarar o
            # arquivo local — posicoes ativas ficavam invisiveis pro trailing
            # updater (scan_master mostrava "Nenhuma posicao ativa" com posicoes
            # reais no arquivo). Vazio => fall through pro arquivo.
            if (@($result).Count -gt 0) { return $result }
        } catch {
            Write-Warning "[trailing] state_store read failed, falling back to file: $_"
            # fall through to legacy
        }
    }

    # Legacy file path (default)
    $tf = _Get-TrailingFile
    if (-not (Test-Path $tf)) { return @() }
    try {
        $json = Get-Content $tf -Raw | ConvertFrom-Json
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

    # state_store path (opt-in)
    if ((_Test-TrailingUsesStateStore) -and (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
        try {
            # Anota pk_id em cada posicao para upsert correto
            $augmented = @()
            foreach ($p in $Positions) {
                if ($null -eq $p) { continue }
                if (-not $p.PSObject.Properties['market']) { continue }
                $pkId = _Get-TrailingPkId -Position $p
                # Force pk_id property (override se ja existir)
                $copy = [PSCustomObject]@{}
                foreach ($prop in $p.PSObject.Properties) {
                    $copy | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
                $copy | Add-Member -NotePropertyName "pk_id" -NotePropertyValue $pkId -Force
                $augmented += $copy
            }
            if (@($augmented).Count -gt 0) {
                # 2026-07-09: trailing_state (nao trailing_positions — ver Get acima)
                Save-StateRecords -Table "trailing_state" -Records $augmented -PrimaryKey "pk_id"
            }
            return
        } catch {
            Write-Warning "[trailing] state_store write failed, falling back to file: $_"
            # fall through to legacy
        }
    }

    # Legacy file path (default)
    $tf = _Get-TrailingFile
    $dir = Split-Path $tf
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Positions | ConvertTo-Json -Depth 5 | Set-Content $tf -Encoding utf8
}

# ── Registrar posicao nova ─────────────────────────────────────────────────────

function Add-TrailingPosition {
    # 2026-05-19 PM: extended com Mode + MaxDays + DdThresholdPct pra
    # source-aware downstream behavior (GEM != STANDARD != TIER_A_LIVE).
    # Mode "GEM"     -> wide stop 20% + moon bag + max_days enforced
    # Mode "TIER_A"  -> ATR stop progressivo, DD threshold conservador
    # Mode "STANDARD"-> orchestrator legacy
    # 2026-05-26 A.1: Mentor* params opt-in -- se presentes, escreve pending
    # reflection (E3 ledger). Se ausentes, comportamento legacy preservado.
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
        [double]$DdThresholdPct = 0,          # 0 = global default. GEM=40%, TIER_A=25%.
        # A.1 wire (opt-in)
        [string]$MentorVeredicto = "",
        [int]   $MentorConfidence = 0,
        [string]$MentorMensagem = "",
        [string]$MesaSinal = "",
        [string]$Tier = ""
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

    # A.1 wire: pending reflection (E3 ledger). Opt-in via MentorVeredicto.
    # trade_id = market + openedAt ts (sufice como unique pair pra Close lookup)
    if ($MentorVeredicto -and (Get-Command Add-PendingReflection -ErrorAction SilentlyContinue)) {
        try {
            $tradeId = "$Market@$($pos.openedAt -replace ' |:','')"
            $entryDateUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
            $reflPath = if ($global:REFLECTIONS_PATH_OVERRIDE) { $global:REFLECTIONS_PATH_OVERRIDE } else { "" }
            Add-PendingReflection -TradeId $tradeId -Market $Market -EntryDateUtc $entryDateUtc `
                -MentorVeredicto $MentorVeredicto -MentorConfidence $MentorConfidence `
                -MentorMensagem $MentorMensagem -MesaSinal $MesaSinal -Tier $Tier `
                -ReflectionsPath $reflPath
        } catch {
            Write-Host "  [Trailing] Add-PendingReflection falhou (nao bloqueia): $_" -ForegroundColor DarkYellow
        }
    }
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

    # A.1 wire: resolved reflection (E3). Procura pending pra mesmo market,
    # computa pnl_pct (ExitPrice vs entry), escreve resolved entry.
    if ($script:closedPos -and $ExitPrice -gt 0 -and (Get-Command Get-PendingReflections -ErrorAction SilentlyContinue)) {
        try {
            $entry = [double]$script:closedPos.entry
            $side = [string]$script:closedPos.side
            $pnlPct = if ($side -eq "LONG") {
                (($ExitPrice - $entry) / $entry) * 100
            } else {
                (($entry - $ExitPrice) / $entry) * 100
            }
            $reflPath = if ($global:REFLECTIONS_PATH_OVERRIDE) { $global:REFLECTIONS_PATH_OVERRIDE } else { "" }
            $pendingAll = @(Get-PendingReflections -ReflectionsPath $reflPath)
            $pendingMatch = @($pendingAll | Where-Object { $_.market -eq $Market }) | Select-Object -First 1
            if ($pendingMatch) {
                $exitDateUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
                $holdingDays = 0
                try {
                    $entryDt = [DateTime]::Parse($pendingMatch.entry_date_utc)
                    $holdingDays = [Math]::Max(0, [int]((Get-Date).ToUniversalTime() - $entryDt).TotalDays)
                } catch {}
                $reflText = "[$Reason] pnl=$([Math]::Round($pnlPct,2))% in ${holdingDays}d (entry=$entry exit=$ExitPrice)"
                Add-ResolvedReflection -TradeId $pendingMatch.trade_id -ExitDateUtc $exitDateUtc `
                    -PnlPct $pnlPct -HoldingDays $holdingDays -Reflection $reflText `
                    -ReflectionsPath $reflPath
            }
        } catch {
            Write-Host "  [Trailing] Add-ResolvedReflection falhou (nao bloqueia): $_" -ForegroundColor DarkYellow
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
                $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue "max_days_exceeded" -Force
                # 2026-06-17 #2: auto-registra outcome p/ o motor de aprendizado (fail-safe)
                if (Get-Command Add-LearningOutcome -ErrorAction SilentlyContinue) {
                    try {
                        $reg = if ($pos.PSObject.Properties['regime'] -and $pos.regime) { "$($pos.regime)" }
                               elseif ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
                        Add-LearningOutcome -Market $pos.market -Side $pos.side -EntryPrice ([double]$pos.entry) `
                            -ExitPrice $price -OpenedAt "$($pos.openedAt)" -CloseReason "max_days_exceeded" `
                            -OrderId "$($pos.orderId)" -Regime $reg | Out-Null
                    } catch {}
                }
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
                $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue "stop_atingido" -Force

                # 2026-07-08: Log efetividade do stop pra aprendizado
                if (Get-Command Write-TrailingEffectiveness -ErrorAction SilentlyContinue) {
                    try {
                        $regime = if ($pos.PSObject.Properties['regime'] -and $pos.regime) { "$($pos.regime)" } else { "UNKNOWN" }
                        $maxGain = if ($pos.side -eq "LONG") { ([double]$pos.peak - [double]$pos.entry) } `
                                   else { ([double]$pos.entry - ([double]$pos.peak)) }
                        $openedAt = if ($pos.PSObject.Properties['openedAt']) { [datetime]$pos.openedAt } else { [datetime]::UtcNow }
                        $duration = ([datetime]::UtcNow - $openedAt).TotalMinutes

                        [void](Write-TrailingEffectiveness -Market $pos.market `
                            -Side $pos.side `
                            -Entry ([double]$pos.entry) `
                            -Exit ([double]$pos.stopCurrent) `
                            -ExitPrice $price `
                            -StopLossAtExit ([double]$pos.stopCurrent) `
                            -ExitReason "SL_HIT" `
                            -MaxGain $maxGain `
                            -DurationMinutes $duration `
                            -Regime $regime)
                    } catch { }
                }

                # 2026-06-17 #2: auto-registra outcome p/ o motor de aprendizado (fail-safe)
                if (Get-Command Add-LearningOutcome -ErrorAction SilentlyContinue) {
                    try {
                        $reg = if ($pos.PSObject.Properties['regime'] -and $pos.regime) { "$($pos.regime)" }
                               elseif ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
                        Add-LearningOutcome -Market $pos.market -Side $pos.side -EntryPrice ([double]$pos.entry) `
                            -ExitPrice $price -OpenedAt "$($pos.openedAt)" -CloseReason "stop_atingido" `
                            -OrderId "$($pos.orderId)" -Regime $reg | Out-Null
                    } catch {}
                }
                $updated = $true
                return $pos
            }

            $calc = Get-TrailingNewStop -Pos $pos -CurrentPrice $price

            # 2026-07-08: Enrich trailing logs pra auto-aprendizado do sistema
            if (Get-Command Write-TrailingDecision -ErrorAction SilentlyContinue) {
                try {
                    $regime = if ($pos.PSObject.Properties['regime'] -and $pos.regime) { "$($pos.regime)" } `
                              elseif ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
                    $atr = if ($pos.PSObject.Properties['atr'] -and $pos.atr) { [double]$pos.atr } else { 0 }

                    [void](Write-TrailingDecision -Market $pos.market `
                        -Side $pos.side `
                        -Phase $calc.newPhase `
                        -Entry ([double]$pos.entry) `
                        -CurrentPrice $price `
                        -StopOld ([double]$pos.stopCurrent) `
                        -StopNew ([double]$calc.newStop) `
                        -TakeProfit ([double]$pos.target) `
                        -Peak ([double]$calc.newPeak) `
                        -Regime $regime `
                        -ATR $atr `
                        -Changed $calc.changed `
                        -Reason $(if ($calc.changed) { "phase_$($calc.newPhase)" } else { "routine_update" }) )
                } catch {
                    # Silent fail - não interrompe trailing
                }
            }

            # Se fase mudou, log de transição
            if ($calc.newPhase -ne [int]$pos.phase) {
                if (Get-Command Write-TrailingPhaseTransition -ErrorAction SilentlyContinue) {
                    try {
                        $regime = if ($pos.PSObject.Properties['regime'] -and $pos.regime) { "$($pos.regime)" } else { "UNKNOWN" }
                        $buffer = [math]::Abs([double]$calc.newStop - [double]$pos.entry)

                        Write-TrailingPhaseTransition -Market $pos.market `
                            -Side $pos.side `
                            -PhaseFrom ([int]$pos.phase) `
                            -PhaseTo ([int]$calc.newPhase) `
                            -Entry ([double]$pos.entry) `
                            -CurrentPrice $price `
                            -StopNew ([double]$calc.newStop) `
                            -TakeProfit ([double]$pos.target) `
                            -Regime $regime `
                            -BufferApplied $buffer `
                            -TriggerCondition "Price reached $(if($calc.newPhase -eq 1) { '33%' } elseif($calc.newPhase -eq 2) { '66%' } elseif($calc.newPhase -eq 3) { 'target' })" | Out-Null
                    } catch { }
                }
            }

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

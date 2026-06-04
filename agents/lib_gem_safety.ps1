# lib_gem_safety.ps1 -- GEM Safety Guards (learning phase, defaults loose)
#
# Contrato:
#   Test-GemSafetyGuards -TradeSizeUsdt N -TotalCapitalUsdt M [-StateFilePath p] [-Config h]
#       -> PSCustomObject @{
#            allowed                bool
#            requires_confirmation  bool
#            reason                 string   # ok|cap_exposure|daily_limit|weekly_limit|circuit_breaker|state_corrupted
#            current_exposure_pct   double
#            projected_exposure_pct double
#            daily_count            int
#            weekly_count           int
#            consecutive_stops      int
#            telegram_message       string
#          }
#
#   Add-GemTradeResult  -Market m -Result WIN|LOSS|STOP|EXPIRED -PnlUsdt p
#   Get-GemSafetyState  [-StateFilePath p]
#   Update-GemSafetyState -State s [-StateFilePath p]
#   Get-OpenGemExposurePct -StateFilePath p -TotalCapitalUsdt c
#
# Ordem dos guards (primeiro falhar bloqueia):
#   1) circuit_breaker (consec stops >= CircuitBreakerStops)
#   2) daily_limit     (daily_count    >= MaxGemsPerDay)
#   3) weekly_limit    (weekly_count   >= MaxGemsPerWeek)
#   4) cap_exposure    (projected_pct  >= MaxExposurePct)
#   5) double-confirm  (projected_pct  > DoubleConfirmThreshold) -> allowed=true, requires_confirmation=true
#
# Estado em journal/gem_safety_state.json. Reset automatico: daily por dia BRT,
# weekly comparando segunda-feira da semana corrente.

function Get-GemSafetyDefaults {
    if ($global:GEM_SAFETY) { return $global:GEM_SAFETY }
    return @{
        MaxExposurePct          = 15.0
        MaxGemsPerDay           = 10
        MaxGemsPerWeek          = 40
        CircuitBreakerStops     = 5
        DoubleConfirmThreshold  = 10.0
    }
}

function Get-MondayOfWeek {
    param([datetime] $RefDate = (Get-Date))
    $d   = $RefDate.Date
    $dow = [int]$d.DayOfWeek           # Sunday=0, Monday=1 ... Saturday=6
    $diff = if ($dow -eq 0) { -6 } else { 1 - $dow }
    return $d.AddDays($diff)
}

function Get-GemSafetyState {
    param([string] $StateFilePath = "journal/gem_safety_state.json")

    if (-not (Test-Path $StateFilePath)) {
        return [PSCustomObject]@{
            open_positions     = @()
            daily_count        = 0
            daily_reset_date   = (Get-Date).ToString("yyyy-MM-dd")
            weekly_count       = 0
            weekly_reset_date  = (Get-MondayOfWeek).ToString("yyyy-MM-dd")
            consecutive_stops  = 0
            last_trade_result  = $null
            last_updated       = (Get-Date).ToString("o")
        }
    }

    $raw = Get-Content -Path $StateFilePath -Raw -ErrorAction Stop
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Update-GemSafetyState {
    param(
        [Parameter(Mandatory)] $State,
        [string] $StateFilePath = "journal/gem_safety_state.json"
    )

    $dir = Split-Path -Parent $StateFilePath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $State.last_updated = (Get-Date).ToString("o")
    ($State | ConvertTo-Json -Depth 6) | Out-File -FilePath $StateFilePath -Encoding utf8 -Force
}

function Get-OpenGemExposurePct {
    param(
        [string] $StateFilePath    = "journal/gem_safety_state.json",
        [Parameter(Mandatory)] [double] $TotalCapitalUsdt
    )

    if ($TotalCapitalUsdt -le 0) { return 0.0 }

    try {
        $s = Get-GemSafetyState -StateFilePath $StateFilePath
    } catch {
        return 0.0
    }

    $sum = 0.0
    if ($s.open_positions) {
        foreach ($p in $s.open_positions) {
            $sum += [double]$p.size_usdt
        }
    }
    return [math]::Round(($sum / $TotalCapitalUsdt) * 100.0, 4)
}

function Reset-ThrottleCounters {
    # Aplica reset diario/semanal se necessario. Retorna o estado (possivelmente modificado)
    # e flag se houve mudanca.
    param($State)

    $today    = (Get-Date).Date
    $todayStr = $today.ToString("yyyy-MM-dd")
    $changed  = $false

    if ($State.daily_reset_date -ne $todayStr) {
        $State.daily_count      = 0
        $State.daily_reset_date = $todayStr
        $changed = $true
    }

    $thisMonday = Get-MondayOfWeek -RefDate $today
    $stateMonday = [datetime]::MinValue
    [void][datetime]::TryParse($State.weekly_reset_date, [ref]$stateMonday)
    if ($stateMonday -lt $thisMonday) {
        $State.weekly_count      = 0
        $State.weekly_reset_date = $thisMonday.ToString("yyyy-MM-dd")
        $changed = $true
    }

    return @{ state = $State; changed = $changed }
}

function Test-GemSafetyGuards {
    param(
        [Parameter(Mandatory)] [double]    $TradeSizeUsdt,
        [Parameter(Mandatory)] [double]    $TotalCapitalUsdt,
        [string]                           $StateFilePath = "journal/gem_safety_state.json",
        [hashtable]                        $Config        = $null
    )

    $cfg = if ($Config) { $Config } else { Get-GemSafetyDefaults }

    # Defensive read — corrupted JSON should not crash live trading
    try {
        $state = Get-GemSafetyState -StateFilePath $StateFilePath
    } catch {
        return [PSCustomObject]@{
            allowed                 = $false
            requires_confirmation   = $false
            reason                  = "state_corrupted"
            current_exposure_pct    = 0.0
            projected_exposure_pct  = 0.0
            daily_count             = 0
            weekly_count            = 0
            consecutive_stops       = 0
            telegram_message        = "Estado de seguranca corrompido em $StateFilePath -- intervencao manual necessaria."
        }
    }

    # Auto reset diario/semanal
    $r = Reset-ThrottleCounters -State $state
    $state = $r.state
    if ($r.changed) { Update-GemSafetyState -State $state -StateFilePath $StateFilePath }

    # Calculos de exposure
    $currentExposureUsdt = 0.0
    if ($state.open_positions) {
        foreach ($p in $state.open_positions) { $currentExposureUsdt += [double]$p.size_usdt }
    }
    $currentPct   = if ($TotalCapitalUsdt -gt 0) { [math]::Round(($currentExposureUsdt / $TotalCapitalUsdt) * 100.0, 4) } else { 0.0 }
    $projectedPct = if ($TotalCapitalUsdt -gt 0) { [math]::Round((($currentExposureUsdt + $TradeSizeUsdt) / $TotalCapitalUsdt) * 100.0, 4) } else { 0.0 }

    $base = [PSCustomObject]@{
        allowed                 = $true
        requires_confirmation   = $false
        reason                  = "ok"
        current_exposure_pct    = $currentPct
        projected_exposure_pct  = $projectedPct
        daily_count             = [int]$state.daily_count
        weekly_count            = [int]$state.weekly_count
        consecutive_stops       = [int]$state.consecutive_stops
        telegram_message        = ""
    }

    # 1) Circuit breaker
    if ([int]$state.consecutive_stops -ge [int]$cfg.CircuitBreakerStops) {
        $base.allowed          = $false
        $base.reason           = "circuit_breaker"
        $base.telegram_message = "Circuit breaker ativo: $([int]$state.consecutive_stops) stops consecutivos (max $($cfg.CircuitBreakerStops)). Pausa 24h."
        return $base
    }

    # 2) Daily limit
    if ([int]$state.daily_count -ge [int]$cfg.MaxGemsPerDay) {
        $base.allowed          = $false
        $base.reason           = "daily_limit"
        $base.telegram_message = "Daily limit atingido: $([int]$state.daily_count)/$($cfg.MaxGemsPerDay) gems hoje."
        return $base
    }

    # 3) Weekly limit
    if ([int]$state.weekly_count -ge [int]$cfg.MaxGemsPerWeek) {
        $base.allowed          = $false
        $base.reason           = "weekly_limit"
        $base.telegram_message = "Weekly limit atingido: $([int]$state.weekly_count)/$($cfg.MaxGemsPerWeek) gems esta semana."
        return $base
    }

    # 4) Cap exposure
    if ($projectedPct -ge [double]$cfg.MaxExposurePct) {
        $base.allowed          = $false
        $base.reason           = "cap_exposure"
        $base.telegram_message = "Cap exposure: atual ${currentPct}%, projetado ${projectedPct}% (max $($cfg.MaxExposurePct)%)."
        return $base
    }

    # 5) Double confirmation
    if ($projectedPct -gt [double]$cfg.DoubleConfirmThreshold) {
        $base.requires_confirmation = $true
        $base.telegram_message      = "Confirmacao dupla: exposure atual ${currentPct}%, projetado ${projectedPct}% (threshold $($cfg.DoubleConfirmThreshold)%). Confirme manualmente."
    }

    return $base
}

function Add-GemTradeResult {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [ValidateSet("WIN","LOSS","STOP","EXPIRED")] [string] $Result,
        [Parameter(Mandatory)] [double] $PnlUsdt,
        [string] $StateFilePath = "journal/gem_safety_state.json"
    )

    try {
        $state = Get-GemSafetyState -StateFilePath $StateFilePath
    } catch {
        # State corrompido: nao avancar contadores; reinicializar arquivo nao eh seguro aqui
        return
    }

    # Reset automatico antes de aplicar resultado
    $r = Reset-ThrottleCounters -State $state
    $state = $r.state

    # Remover posicao aberta (match por market)
    if ($state.open_positions) {
        $state.open_positions = @($state.open_positions | Where-Object { $_.market -ne $Market })
    }

    # Atualizar contadores de stops consecutivos
    if ($Result -eq "STOP") {
        $state.consecutive_stops = [int]$state.consecutive_stops + 1
    } elseif ($Result -eq "WIN") {
        $state.consecutive_stops = 0
    }
    # LOSS / EXPIRED: nao reseta nem incrementa (politica conservadora — so STOP conta)

    $state.last_trade_result = @{
        market    = $Market
        result    = $Result
        pnl_usdt  = $PnlUsdt
        timestamp = (Get-Date).ToString("o")
    }

    Update-GemSafetyState -State $state -StateFilePath $StateFilePath
}

function Add-OpenGemPosition {
    # Helper: usado pelo gem_executor apos ordem aceita para registrar exposure.
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $SizeUsdt,
        [string] $StateFilePath = "journal/gem_safety_state.json"
    )

    try { $state = Get-GemSafetyState -StateFilePath $StateFilePath } catch { return }

    $r = Reset-ThrottleCounters -State $state
    $state = $r.state

    # Append
    $list = @()
    if ($state.open_positions) { $list = @($state.open_positions) }
    $list += @{ market=$Market; size_usdt=$SizeUsdt; entry_ts=(Get-Date).ToString("o") }
    $state.open_positions = $list
    $state.daily_count    = [int]$state.daily_count  + 1
    $state.weekly_count   = [int]$state.weekly_count + 1

    Update-GemSafetyState -State $state -StateFilePath $StateFilePath
}

function Remove-OpenGemPosition {
    # Remove posicao do safety state sem alterar contadores de throttle.
    # Chamado por phantom_reconciliation para liberar exposure quando posicao
    # foi fechada externamente (SL/TP/manual) sem passar pelo gem_executor.
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $StateFilePath = "journal/gem_safety_state.json"
    )
    try { $state = Get-GemSafetyState -StateFilePath $StateFilePath } catch { return }
    if ($state.open_positions) {
        $state.open_positions = @($state.open_positions | Where-Object { $_.market -ne $Market })
    }
    Update-GemSafetyState -State $state -StateFilePath $StateFilePath
}

function Initialize-GemSafetyStateFile {
    param([string] $StateFilePath = "journal/gem_safety_state.json")

    if (Test-Path $StateFilePath) { return }
    $dir = Split-Path -Parent $StateFilePath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $state = [PSCustomObject]@{
        open_positions     = @()
        daily_count        = 0
        daily_reset_date   = (Get-Date).ToString("yyyy-MM-dd")
        weekly_count       = 0
        weekly_reset_date  = (Get-MondayOfWeek).ToString("yyyy-MM-dd")
        consecutive_stops  = 0
        last_trade_result  = $null
        last_updated       = (Get-Date).ToString("o")
    }
    ($state | ConvertTo-Json -Depth 6) | Out-File -FilePath $StateFilePath -Encoding utf8 -Force
}

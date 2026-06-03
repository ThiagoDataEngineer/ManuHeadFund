# lib_signal_trigger_bus.ps1 -- Trigger-bus event-driven para sinais-lider.
#
# Sinais-lider (whale, cold_wallet, faro, funding, vol_climax, news, gem_spike,
# tori_ripe) enfileiram um trigger quando cruzam o limiar de conviccao. O
# scan_master consome a fila no loop de espera (Wait-WithCommands) e dispara
# analise imediata e direcionada (full Mesa+Mentor) no mercado especifico --
# fast path, latencia ~segundos, em vez de esperar o ciclo de polling de 30min.
#
# Guarda-custo (sistema e custo-consciente):
#   1. Gate de conviccao por sinal (so dispara acima do limiar)
#   2. Dedupe/cooldown por market+signal+cluster (nao re-dispara no mesmo evento)
#   3. Expiry: trigger velho (evento ja passou) nao e mais consumido
#
# Storage: journal/signal_triggers.jsonl (append-only, lifecycle por id:
#   created -> processed). State = ultimo evento por id.
#
# PS 5.1. UTF-8 BOM.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

$script:TRIGGER_BUS_PATH    = Join-Path $global:JOURNAL_DIR "signal_triggers.jsonl"
$script:TRIGGER_COOLDOWN_MIN = 20    # dedupe: nao re-dispara mesmo market+signal+cluster
$script:TRIGGER_EXPIRE_MIN   = 60    # trigger pendente vira stale (evento passou)

# Limiar de conviccao por sinal (taxonomia 2026-06-03). Sinais-lider exigem
# mais conviccao porque disparam fluxo caro (Mesa+Mentor) imediatamente.
$script:SIGNAL_CONVICTION_THRESHOLD = @{
    whale       = 70
    cold_wallet = 70
    faro        = 65
    funding     = 60
    vol_climax  = 60
    news        = 60
    gem_spike   = 55
    tori_ripe   = 50
}
$script:SIGNAL_CONVICTION_DEFAULT = 60


function Set-TriggerBusConfig {
    [CmdletBinding()]
    param(
        [string] $Path,
        [int]    $CooldownMin = -1,
        [int]    $ExpireMin   = -1
    )
    if ($Path)            { $script:TRIGGER_BUS_PATH    = $Path }
    if ($CooldownMin -ge 0) { $script:TRIGGER_COOLDOWN_MIN = $CooldownMin }
    if ($ExpireMin   -ge 0) { $script:TRIGGER_EXPIRE_MIN   = $ExpireMin }
}


function Get-SignalConvictionThreshold {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Signal)
    $key = $Signal.ToLower()
    if ($script:SIGNAL_CONVICTION_THRESHOLD.ContainsKey($key)) {
        return [int]$script:SIGNAL_CONVICTION_THRESHOLD[$key]
    }
    return [int]$script:SIGNAL_CONVICTION_DEFAULT
}


function _NewTriggerId {
    return [Guid]::NewGuid().ToString().Substring(0, 8)
}

function _ParseTriggerTs {
    param([string] $Ts)
    # Forca UTC: sem AdjustToUniversal o 'Z' converte p/ local (UTC-3) e
    # desalinha as comparacoes (tudo vira "expirado", cooldown calcula errado).
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    try { return [datetime]::ParseExact($Ts, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, $styles) } catch { return $null }
}

# Le todos os eventos brutos (uma linha por evento). Fail-safe a linha corrompida.
function _ReadTriggerEventsRaw {
    if (-not (Test-Path $script:TRIGGER_BUS_PATH)) { return @() }
    $lines = Get-Content $script:TRIGGER_BUS_PATH -Encoding UTF8 -ErrorAction SilentlyContinue
    $out = @()
    foreach ($line in $lines) {
        if (-not $line) { continue }
        # Add-Content -Encoding UTF8 (PS 5.1) escreve BOM na 1a linha; Get-Content
        # nao o remove -> quebra ConvertFrom-Json. Strip defensivo do BOM/ZWNBSP.
        $clean = $line.TrimStart([char]0xFEFF)
        if (-not $clean) { continue }
        try { $out += ($clean | ConvertFrom-Json) } catch {}
    }
    return @($out)
}


function Add-SignalTrigger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Signal,
        [Parameter(Mandatory)] [double] $Conviction,
        [ValidateSet("long","short","auto")] [string] $Direction = "auto",
        [ValidateSet("scan","observe")] [string] $Mode = "scan",
        [string] $ClusterKey = "",
        [hashtable] $Meta = $null,
        [string] $Notes = ""
    )
    $market = $Market.ToUpper()
    $signal = $Signal.ToLower()

    # 1. Gate de conviccao
    $threshold = Get-SignalConvictionThreshold -Signal $signal
    if ($Conviction -lt $threshold) {
        return [PSCustomObject]@{ enqueued = $false; reason = "below_conviction"; threshold = $threshold; conviction = $Conviction }
    }

    # 2. Dedupe/cooldown por market+signal+cluster
    $now = Get-Date
    $key = "$market|$signal|$ClusterKey"
    foreach ($e in (_ReadTriggerEventsRaw)) {
        $eKey = "$($e.market)|$($e.signal)|$($e.cluster)"
        if ($eKey -ne $key) { continue }
        $ets = _ParseTriggerTs $e.ts
        if ($null -eq $ets) { continue }
        if (($now.ToUniversalTime() - $ets).TotalMinutes -lt $script:TRIGGER_COOLDOWN_MIN) {
            return [PSCustomObject]@{ enqueued = $false; reason = "cooldown"; threshold = $threshold; conviction = $Conviction }
        }
    }

    # 3. Enfileira
    $id = _NewTriggerId
    $obj = [ordered]@{
        id         = $id
        event      = "created"
        ts         = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        market     = $market
        signal     = $signal
        conviction = [int]$Conviction
        direction  = $Direction
        mode       = $Mode
        cluster    = $ClusterKey
        status     = "pending"
        notes      = $Notes
        meta       = if ($Meta) { $Meta } else { @{} }
        expires_at = $now.AddMinutes($script:TRIGGER_EXPIRE_MIN).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $dir = Split-Path $script:TRIGGER_BUS_PATH -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($obj | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $script:TRIGGER_BUS_PATH -Encoding UTF8
    return [PSCustomObject]@{ enqueued = $true; reason = "enqueued"; id = $id; threshold = $threshold; conviction = [int]$Conviction }
}


function Get-PendingSignalTriggers {
    [CmdletBinding()]
    param()
    $events = _ReadTriggerEventsRaw
    if ($events.Count -eq 0) { return @() }

    # Collapse por id -> ultimo evento ganha (status atual)
    $byId = @{}
    foreach ($e in $events) { if ($e.id) { $byId[$e.id] = $e } }

    $now = (Get-Date).ToUniversalTime()
    $pending = @()
    foreach ($k in $byId.Keys) {
        $o = $byId[$k]
        if ($o.status -ne "pending") { continue }
        $exp = _ParseTriggerTs $o.expires_at
        if ($null -ne $exp -and $now -gt $exp) { continue }   # expirado
        $pending += $o
    }
    return @($pending | Sort-Object @{ Expression = { [int]$_.conviction }; Descending = $true }, @{ Expression = { $_.ts }; Descending = $false })
}


function Get-NextTriggerScan {
    # Consumer (scan_master): pega o trigger pendente de maior conviccao, marca
    # como processado e retorna {market, direction, signal, conviction, id} para
    # disparar Invoke-MasterCycle -ForcePair. Retorna $null se nao ha pendentes.
    [CmdletBinding()]
    param()
    $pending = @(Get-PendingSignalTriggers)
    if ($pending.Count -eq 0) { return $null }
    $top = $pending[0]
    Set-SignalTriggerProcessed -Id $top.id -Result "scan_dispatched" | Out-Null
    $mode = if ($top.PSObject.Properties['mode'] -and $top.mode) { [string]$top.mode } else { "scan" }
    return [PSCustomObject]@{
        market     = [string]$top.market
        direction  = [string]$top.direction
        signal     = [string]$top.signal
        conviction = [int]$top.conviction
        mode       = $mode
        id         = [string]$top.id
    }
}


function Set-SignalTriggerProcessed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [string] $Result = "processed"
    )
    $current = (_ReadTriggerEventsRaw) | Where-Object { $_.id -eq $Id } | Select-Object -Last 1
    if (-not $current) { return $null }
    $obj = [ordered]@{
        id         = $current.id
        event      = "status_change"
        ts         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        market     = $current.market
        signal     = $current.signal
        conviction = [int]$current.conviction
        direction  = $current.direction
        cluster    = $current.cluster
        status     = "processed"
        notes      = $Result
        expires_at = $current.expires_at
    }
    ($obj | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $script:TRIGGER_BUS_PATH -Encoding UTF8
    return $obj
}

# tori_proximity_scanner.ps1 -- Scanner anticipatorio Tori (cron 15min default).
#
# Filosofia: GEM/V6 atuais acordam por vol_spike (lagging, +14% ja foi). Este
# scanner roda em paralelo sobre o whitelist PAPER, computa proximidade
# deterministica da action_line e alerta no TG ANTES do bounce maturar.
# Zero LLM, ~13 fetches CoinEx por ciclo, dedup TTL 4h por market.
#
# Uso:
#   pwsh -File scripts\tori_proximity_scanner.ps1                 # cycle unico
#   pwsh -File scripts\tori_proximity_scanner.ps1 -Markets BTCUSDT,ETHUSDT  # custom
#   pwsh -File scripts\tori_proximity_scanner.ps1 -DryRun         # nao envia TG
#
# Saida:
#   journal\tori_proximity_scanner.log         (heartbeat + decisions)
#   journal\tori_proximity_alerts.jsonl        (dedup store, rolling)
#
# PS 5.1. UTF-8 BOM.

param(
    [string[]] $Markets   = @(),     # vazio = usa Get-QuantWhitelistMarkets -Mode PAPER
    [int]      $TtlMinutes = 240,    # dedup window (4h)
    [switch]   $DryRun               # nao envia TG, so loga
)

$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir   = Join-Path $projectRoot "agents"
$journalDir  = Join-Path $projectRoot "journal"
$logPath     = Join-Path $journalDir "tori_proximity_scanner.log"
$alertsPath  = Join-Path $journalDir "tori_proximity_alerts.jsonl"
$statePath   = Join-Path $journalDir "tori_proximity_state.json"

function Write-ProxLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    if (-not (Test-Path $journalDir)) { New-Item -ItemType Directory -Path $journalDir -Force | Out-Null }
    Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

Set-Location $projectRoot

# Config (silencioso se nao existir local)
try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
} catch {
    Write-ProxLog "ERROR" "Falha config: $($_.Exception.Message)"
    exit 1
}

# Libs
try {
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_quant_whitelist.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_tori_proximity.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_signal_trigger_bus.ps1") -ErrorAction SilentlyContinue  # fast-path: enfileira trigger tori_ripe
    . (Join-Path $agentsDir "lib_state_store.ps1") -ErrorAction SilentlyContinue  # 2026-07-23: snapshot cross-job via Supabase
} catch {
    Write-ProxLog "ERROR" "Falha libs: $($_.Exception.Message)"
    exit 1
}

# Resolve markets alvo
if (-not $Markets -or @($Markets).Count -eq 0) {
    try {
        $Markets = @(Get-QuantWhitelistMarkets -Mode PAPER)
    } catch {
        Write-ProxLog "ERROR" "Falha ao ler whitelist: $($_.Exception.Message)"
        exit 1
    }
}
$Markets = @($Markets | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)

if (@($Markets).Count -eq 0) {
    Write-ProxLog "WARN" "Nenhum market resolvido. Saindo."
    exit 0
}

Write-ProxLog "CYCLE" "Iniciando proximity scan -- $(@($Markets).Count) markets | dedup=${TtlMinutes}min | dry=$DryRun"

$alertsSent = 0
$ripening   = 0
$invalid    = 0
$snapshot   = @{}   # market -> proximity record (pra discovery consumers lerem)

foreach ($mkt in $Markets) {
    try {
        $p = Get-ToriProximity -Market $mkt
    } catch {
        Write-ProxLog "ERROR" "$mkt -- exception: $($_.Exception.Message)"
        $invalid++
        continue
    }

    # Snapshot enriquecido pra discovery consumers (active side + ambos lados)
    $snapshot[$mkt] = [ordered]@{
        valid          = [bool]$p.valid
        reason         = "$($p.reason)"
        side           = "$($p.side)"          # LONG | SHORT | NONE
        price          = $p.price
        action_line    = $p.action_line
        proximity_pct  = $p.proximity_pct
        touches        = $p.touches
        slope_deg      = $p.slope_deg
        rsi            = $p.rsi
        vol_drying     = $p.vol_drying
        setup_ripening = [bool]$p.setup_ripening
        setup_staging  = [bool]$p.setup_staging
        conviction     = if ($p.PSObject.Properties['conviction']) { [int]$p.conviction } else { 0 }
        long_side      = $p.long_side          # sub-objeto completo (Mentor consulta)
        short_side     = $p.short_side
    }

    if (-not $p.valid) {
        Write-ProxLog "SKIP" "$mkt -- both_sides_invalid: long=$($p.long_side.reason) short=$($p.short_side.reason)"
        $invalid++
        continue
    }

    $detail = ("side={0} prox={1}% line={2} px={3} touches={4} slope={5}deg rsi={6} vol_dry={7}" -f `
        $p.side, $p.proximity_pct, $p.action_line, $p.price, $p.touches, $p.slope_deg, $p.rsi, $p.vol_drying)

    if (-not $p.setup_ripening) {
        Write-ProxLog "WATCH" "$mkt -- $detail"
        continue
    }

    $ripening++

    if (Test-ProximityAlertRecent -Market $mkt -JsonlPath $alertsPath -TtlMinutes $TtlMinutes) {
        Write-ProxLog "DEDUP" "$mkt -- ripening mas alerta dentro de ${TtlMinutes}min ja enviado"
        continue
    }

    $sideLabel = if ($p.side -eq "SHORT") { "RESISTENCIA DESCENDENTE (rally rejection)" } else { "SUPORTE ASCENDENTE (bounce)" }
    $actionHint = if ($p.side -eq "SHORT") {
        "observar candles 4H -- se rejeitar a linha, oportunidade SHORT manual via CoinEx (executor LONG-only ainda)"
    } else {
        "observar candles 4H -- se bounce confirmar, pipeline normal (GemScan / scan_master) executa"
    }

    $msg = @"
TORI PROXIMITY $($p.side) -- $mkt
$sideLabel
Preco $($p.price) a $($p.proximity_pct)% da action_line $($p.action_line)
Toques: $($p.touches) | Slope: $($p.slope_deg) deg
RSI 14: $($p.rsi) | Volume secando: $($p.vol_drying)

Setup amadurecendo -- $actionHint
"@

    if ($DryRun) {
        Write-ProxLog "ALERT-DRY" "$mkt -- $detail"
    } else {
        try {
            Send-TelegramAlert -Message $msg | Out-Null
            Write-ProxLog "ALERT" "$mkt -- $detail"
            $alertsSent++
        } catch {
            Write-ProxLog "ERROR" "$mkt -- TG send fail: $($_.Exception.Message)"
            continue
        }
    }

    try {
        Add-ProximityAlert -Market $mkt -JsonlPath $alertsPath -Proximity $p
    } catch {
        Write-ProxLog "WARN" "$mkt -- falha persist dedup: $($_.Exception.Message)"
    }

    # Fast-path: enfileira trigger tori_ripe (setup amadurecendo) -> scan_master
    # roda analise full direcionada. Conviccao por proximidade + toques.
    if ((-not $DryRun) -and (Get-Command Add-SignalTrigger -ErrorAction SilentlyContinue)) {
        $toriConv = Get-ToriConviction -Ripening $true -ProximityPct ([double]$p.proximity_pct) -Touches ([int]$p.touches)
        if ($toriConv -gt 0) {
            $dir = if ($p.side -eq "SHORT") { "short" } else { "long" }
            try { Add-SignalTrigger -Market $mkt -Signal "tori_ripe" -Conviction $toriConv -Direction $dir -Notes "prox=$($p.proximity_pct)% touches=$($p.touches) side=$($p.side)" | Out-Null } catch {}
        }
    }
}

# Persiste snapshot pra discovery (scan_master, gem_loop, Mentor consultam)
try {
    $payload = [ordered]@{
        ts_utc      = (Get-Date).ToUniversalTime().ToString("o")
        ts_brt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
        ttl_minutes = 30     # snapshot considerado fresco por 30min (2x o ciclo cron)
        markets     = $snapshot
    }
    $json = $payload | ConvertTo-Json -Depth 6
    Set-Content -Path $statePath -Value $json -Encoding UTF8
    Write-ProxLog "SNAPSHOT" "Persistido state ($($snapshot.Keys.Count) markets) -> $statePath"
} catch {
    Write-ProxLog "ERROR" "Falha ao persistir snapshot: $($_.Exception.Message)"
}

# 2026-07-23: cada job GitHub Actions e um runner isolado -- o arquivo local acima
# nunca chega no job Gem Scanner+Executor (checkout proprio, sem filesystem
# compartilhado). Grava tambem no Supabase (mesmo padrao de capital_context/
# trade_outcomes) pra o executor conseguir ler conviction real cross-job.
if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
    try {
        Save-StateRecords -Table "tori_proximity_state" -PrimaryKey "id" -Records @([ordered]@{
            id      = 1
            ts_utc  = $payload.ts_utc
            markets = ($snapshot | ConvertTo-Json -Depth 6 -Compress)
        })
        Write-ProxLog "SNAPSHOT" "Persistido state tambem no Supabase (tori_proximity_state)"
    } catch {
        Write-ProxLog "WARN" "Falha ao persistir snapshot no Supabase: $($_.Exception.Message)"
    }
}

Write-ProxLog "DONE" "Cycle completo -- markets=$(@($Markets).Count) ripening=$ripening alerts_sent=$alertsSent invalid=$invalid"

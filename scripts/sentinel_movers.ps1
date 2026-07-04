# sentinel_movers.ps1 — Sentinela de mercado (produtor do trigger-bus, fase 2)
# 2026-07-03: fecha o gap polling vs event-driven. Alfa tem meia-vida curta
# (aviso pre-pump 1-2h); ciclo de 30-60min chega atrasado. O sentinela olha o
# universo INTEIRO a cada 3min (1 chamada de ticker, ZERO LLM) e, quando algo
# mexe de verdade, publica no trigger-bus -> scan_master dispara ciclo
# direcionado NA HORA (Invoke-MasterCycle -ForcePair via Get-NextTriggerScan).
#
# Deteccao (barata, por snapshot delta):
#   A) MOVE 3min: |delta preco| >= 2.5% com vol 24h >= $30k  -> conviction 70-95
#   B) IGNICAO 24h: |change 24h| cruzou 12% desde o ultimo poll -> conviction 72
# Dedupe/cooldown (20min) e expiry (60min) ja sao do bus — sem duplicar logica.
#
# Licoes 2026-07-03: BOM UTF-8, PS 5.1, singleton via lock file, log proprio.

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $root "journal"
$logFile = Join-Path $journalDir "sentinel.log"
$lockFile = Join-Path $journalDir "sentinel.pid"

function Write-SentLog {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Add-Content -Path $logFile -Value $line -Encoding utf8
    Write-Host $line
}

# Singleton
if (Test-Path $lockFile) {
    $oldPid = 0
    try { $oldPid = [int](Get-Content $lockFile -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { }
    if ($oldPid -and $oldPid -ne $PID -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Host "Sentinela ja rodando (PID=$oldPid). Saindo."; exit 0
    }
}
Set-Content -Path $lockFile -Value $PID -Encoding ascii

# Bus (producer) + Evolution Engine (thresholds auto-tunados)
$global:JOURNAL_DIR = $journalDir
. (Join-Path $root "agents\lib_signal_trigger_bus.ps1")
. (Join-Path $root "agents\lib_evolution_engine.ps1")

Write-SentLog "Sentinela iniciado (PID=$PID). Poll 3min | thresholds via evolution engine (defaults 2.5%/12%)."

$prev = @{}   # market -> @{ last; chg24 }
$pollSec = 180

while ($true) {
    try {
        # Thresholds do evolution engine (overlay; CLAMP no consumidor = bound 2 de 2)
        $movePct = 2.5; $ignPct = 12.0
        try {
            $ep = Get-EvolutionParams -JournalDir $journalDir
            $movePct = [math]::Max(1.5, [math]::Min(5.0, [double]$ep.sentinel_move_pct))
            $ignPct  = [math]::Max(8.0, [math]::Min(20.0, [double]$ep.sentinel_ignition_pct))
        } catch { }

        $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/spot/ticker" -Method GET -TimeoutSec 30
        if ($r.code -eq 0 -and $r.data) {
            $fired = 0; $seen = 0
            foreach ($t in $r.data) {
                if ($t.market -notmatch 'USDT$') { continue }
                $seen++
                $last = 0.0; $open = 0.0; $vol = 0.0
                try { $last = [double]$t.last; $open = [double]$t.open; $vol = [double]$t.value } catch { continue }
                if ($last -le 0 -or $open -le 0) { continue }
                $chg24 = ($last - $open) / $open * 100

                $p = $prev[$t.market]
                if ($p) {
                    # A) MOVE 3min (threshold auto-tunado pelo evolution engine)
                    $d3m = ($last - $p.last) / $p.last * 100
                    if ([math]::Abs($d3m) -ge $movePct -and $vol -ge 30000) {
                        $conv = [math]::Min(95, [int](70 + [math]::Abs($d3m) * 3))
                        $res = Add-SignalTrigger -Market $t.market -Signal "sentinel_move" -Conviction $conv -Direction "auto" -Mode "scan" -Notes ("d3m={0:+0.0}% vol24h={1:0}k thr={2}" -f $d3m, ($vol/1000), $movePct)
                        if ($res.enqueued) {
                            $fired++
                            Write-SentLog ("TRIGGER move: {0} d3m={1:+0.0}% conv={2} (thr={3})" -f $t.market, $d3m, $conv, $movePct)
                        }
                    }
                    # B) IGNICAO 24h (cruzou o threshold auto-tunado desde o poll anterior)
                    if ([math]::Abs($chg24) -ge $ignPct -and [math]::Abs($p.chg24) -lt $ignPct -and $vol -ge 30000) {
                        $res = Add-SignalTrigger -Market $t.market -Signal "sentinel_ignition" -Conviction 72 -Direction "auto" -Mode "scan" -Notes ("chg24 cruzou: {0:+0.0}%" -f $chg24)
                        if ($res.enqueued) {
                            $fired++
                            Write-SentLog ("TRIGGER ignicao: {0} chg24={1:+0.0}%" -f $t.market, $chg24)
                        }
                    }
                }
                $prev[$t.market] = @{ last = $last; chg24 = $chg24 }
            }
            if ($fired -gt 0) {
                Write-SentLog "poll: $seen pares | $fired trigger(s) publicados"
            }
        } else {
            Write-SentLog "ticker vazio/erro (code=$($r.code))"
        }
    } catch {
        Write-SentLog "erro no poll: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $pollSec
}

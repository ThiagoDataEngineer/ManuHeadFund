# collect_1h_klines.ps1 — Coleta continua de klines 1h (fundacao do intraday)
# 2026-07-03: destrava Frente 1 (short intraday pump-fade) e Frente 2 (fingerprint
# pre-pump LONG). Estudo mostrou: aviso pre-pump = 1-2h (vol 1.26x em H-1); entrada
# intraday exige historico 1h continuo em TODOS os regimes.
#
# Escopo por hora (2 grupos, dedupe):
#   A) pares com vol 24h >= $50k        (liquidez minima operavel)
#   B) pares com |change 24h| >= 5%     (movers — incl. microcaps, alvo do estudo)
# Cap: 600 pares/hora. Append em journal/klines_1h_YYYYMM.jsonl (rotacao mensal).
# Dedupe na LEITURA por (market, ts) — o coletor pode repetir candles sem problema.
#
# Licoes 2026-07-03 aplicadas: BOM UTF-8, PS 5.1 puro, singleton via lock file
# (nao CommandLine regex), log proprio (nunca tail -f neste arquivo com writer ativo).

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $root "journal"
$logFile = Join-Path $journalDir "collect_1h.log"
$lockFile = Join-Path $journalDir "collect_1h.pid"
$baseUrl = "https://api.coinex.com"

function Write-ColLog {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Add-Content -Path $logFile -Value $line -Encoding utf8
    Write-Host $line
}

# Singleton via lock file
if (Test-Path $lockFile) {
    $oldPid = 0
    try { $oldPid = [int](Get-Content $lockFile -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { }
    if ($oldPid -and $oldPid -ne $PID -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Host "Coletor ja rodando (PID=$oldPid). Saindo."; exit 0
    }
}
Set-Content -Path $lockFile -Value $PID -Encoding ascii

Write-ColLog "Coletor 1h iniciado (PID=$PID). Escopo: vol>=50k OU |change|>=5%, cap 600/h."

while ($true) {
    $cycleStart = Get-Date
    try {
        # 1 chamada: todos os tickers spot
        $tickers = $null
        try {
            $r = Invoke-RestMethod -Uri "$baseUrl/v2/spot/ticker" -Method GET -TimeoutSec 30
            if ($r.code -eq 0) { $tickers = $r.data }
        } catch { Write-ColLog "ticker fetch falhou: $($_.Exception.Message)" }

        if ($tickers) {
            $selected = @{}
            foreach ($t in $tickers) {
                if ($t.market -notmatch 'USDT$') { continue }
                $vol = 0.0; $chg = 0.0
                try { $vol = [double]$t.value } catch { }   # value = volume em quote (USDT)
                try {
                    $last = [double]$t.last; $open = [double]$t.open
                    if ($open -gt 0) { $chg = ($last - $open) / $open * 100 }
                } catch { }
                if ($vol -ge 50000 -or [math]::Abs($chg) -ge 5) {
                    $selected[$t.market] = [math]::Abs($chg)
                }
            }
            # Cap 600: prioriza maiores movers
            $markets = @($selected.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 600 | ForEach-Object { $_.Key })

            $outFile = Join-Path $journalDir "klines_1h_$(Get-Date -Format 'yyyyMM').jsonl"
            $written = 0; $failed = 0
            $sb = New-Object System.Text.StringBuilder

            foreach ($m in $markets) {
                try {
                    $kr = Invoke-RestMethod -Uri "$baseUrl/v2/spot/kline?market=$m&period=1hour&limit=2" -Method GET -TimeoutSec 10
                    if ($kr.code -eq 0 -and $kr.data) {
                        foreach ($c in $kr.data) {
                            $row = @{ market = $m; ts = [long]$c.created_at; o = [double]$c.open; h = [double]$c.high; l = [double]$c.low; c = [double]$c.close; v = [double]$c.volume } | ConvertTo-Json -Compress
                            [void]$sb.AppendLine($row)
                            $written++
                        }
                    } else { $failed++ }
                } catch { $failed++ }
                Start-Sleep -Milliseconds 80
            }

            if ($sb.Length -gt 0) {
                Add-Content -Path $outFile -Value $sb.ToString().TrimEnd() -Encoding utf8
            }
            Write-ColLog "coleta: $($markets.Count) pares | $written candles gravados | $failed falhas | $([math]::Round(((Get-Date) - $cycleStart).TotalSeconds))s"
        } else {
            Write-ColLog "sem tickers nesta rodada (API indisponivel?)"
        }
    } catch {
        Write-ColLog "erro no ciclo: $_"
    }

    # Dorme ate o proximo fechamento de hora + 2min (candle 1h completo garantido)
    $now = Get-Date
    $nextHour = $now.Date.AddHours($now.Hour + 1).AddMinutes(2)
    $sleepSec = [math]::Max(60, ($nextHour - $now).TotalSeconds)
    Write-ColLog "dormindo $([math]::Round($sleepSec/60,1))min (proxima coleta $($nextHour.ToString('HH:mm')))"
    Start-Sleep -Seconds $sleepSec
}

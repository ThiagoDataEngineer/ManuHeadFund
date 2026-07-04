# self_heal_guardian.ps1 — Guardiao de auto-cura + auto-aprendizado da APLICACAO
# 2026-07-04: pedido do dono ("nao deveriam existir erros assim; auto aprender,
# auto solucionar"). Fecha o loop: DETECTA -> CURA -> REGISTRA -> APRENDE -> ESCALA.
#
# A cada 10 min:
#   1. FROTA: scan_master / sentinela / coletor 1h — processo vivo E log andando
#      (zumbi = processo vivo com log parado; licao 2026-07-03). Morto/zumbi ->
#      mata + reinicia + registra incidente + Telegram.
#   2. INFRA: balance_snapshot fresco; Supabase alcancavel; densidade de ERROR
#      no master log; nuvem (ultimo Trading Pipeline) quando gh disponivel.
#   3. APRENDIZADO: todo incidente vira linha em journal/self_heal_incidents.jsonl
#      {ts, signature, action, outcome}. Mesma assinatura 3+ vezes em 24h ->
#      ESCALA no Telegram ("recorrente — exige fix estrutural, nao restart").
#      Esse jsonl e o dataset pro proximo fix de causa raiz (como o counterfactual
#      dos gates foi pro beta/FQS).
#   4. AUDITORIA DIARIA (1x/dia ~06:00): roda a suite E2E completa + contrato de
#      dependencias; FAIL -> Telegram com detalhe.
#
# Substitui watchdog_scan_master (escopo era so 1 daemon). Licoes aplicadas:
# BOM UTF-8, PS 5.1, lock file, deteccao por '-File' via CIM, sem tail -f em log ativo.

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $root "journal"
$logFile = Join-Path $journalDir "self_heal_guardian.log"
$lockFile = Join-Path $journalDir "self_heal_guardian.pid"
$incidentsFile = Join-Path $journalDir "self_heal_incidents.jsonl"

function Write-GLog { param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Add-Content -Path $logFile -Value $line -Encoding utf8
    Write-Host $line
}

# Singleton via lock file
if (Test-Path $lockFile) {
    $oldPid = 0
    try { $oldPid = [int](Get-Content $lockFile -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { }
    if ($oldPid -and $oldPid -ne $PID -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Host "Guardian ja rodando (PID=$oldPid)."; exit 0
    }
}
Set-Content -Path $lockFile -Value $PID -Encoding ascii

try { . (Join-Path $root "agents\lib_telegram.ps1") } catch { }

function Send-GAlert { param([string]$Msg)
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        try { Send-TelegramAlert -Message $Msg | Out-Null } catch { }
    }
}

function Add-Incident {
    param([string]$Signature, [string]$Action, [string]$Outcome)
    $obj = @{ ts = (Get-Date).ToUniversalTime().ToString("o"); signature = $Signature; action = $Action; outcome = $Outcome } | ConvertTo-Json -Compress
    Add-Content -Path $incidentsFile -Value $obj -Encoding utf8
    # APRENDIZADO: recorrencia 24h da mesma assinatura
    $count = 0
    try {
        $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
        foreach ($line in (Get-Content $incidentsFile -ErrorAction SilentlyContinue)) {
            try {
                $i = $line | ConvertFrom-Json
                if ($i.signature -eq $Signature -and ([datetime]::Parse($i.ts).ToUniversalTime() -gt $cutoff)) { $count++ }
            } catch { }
        }
    } catch { }
    if ($count -ge 3) {
        Write-GLog "ESCALADO: '$Signature' recorrente (${count}x/24h) — restart nao resolve, exige fix estrutural"
        Send-GAlert "🔁 <b>GUARDIAN ESCALA</b>`nIncidente recorrente: <code>$Signature</code> (${count}x em 24h)`nRestart NAO esta resolvendo — precisa de fix de causa raiz.`nDataset: journal/self_heal_incidents.jsonl"
    }
    return $count
}

function Get-DaemonProc { param([string]$Pattern)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-File\s+.*$Pattern" -and $_.CommandLine -notmatch 'guardian|watchdog' -and $_.ProcessId -ne $PID } |
        Select-Object -First 1
}

function Restart-Daemon {
    param([string]$Name, [string]$ScriptRel, [object]$Proc, [string]$Reason, [string[]]$ExtraArgs = @())
    if ($Proc) { Stop-Process -Id $Proc.ProcessId -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
    $procArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File", (Join-Path $root $ScriptRel)) + $ExtraArgs
    Start-Process powershell -ArgumentList $procArgs -WindowStyle Hidden
    Start-Sleep -Seconds 5
    $new = Get-DaemonProc -Pattern ([System.IO.Path]::GetFileName($ScriptRel))
    $outcome = if ($new) { "restarted_pid_$($new.ProcessId)" } else { "restart_FAILED" }
    Write-GLog "HEAL $Name : $Reason -> $outcome"
    $n = Add-Incident -Signature "daemon:${Name}:${Reason}" -Action "restart" -Outcome $outcome
    Send-GAlert "🩹 <b>GUARDIAN</b> $Name $outcome`n<i>motivo: $Reason (ocorrencia $n/24h)</i>"
}

function Test-LogFresh { param([string]$Path, [int]$MaxAgeMin)
    if (-not (Test-Path $Path)) { return $false }
    return (((Get-Date) - (Get-Item $Path).LastWriteTime).TotalMinutes -lt $MaxAgeMin)
}

Write-GLog "Guardian iniciado (PID=$PID). Check 10min; auditoria E2E diaria ~06h."
Send-GAlert "🛡️ <b>GUARDIAN LIVE</b> — auto-cura + auto-aprendizado ativos (frota + infra + escalacao de recorrentes)"

$lastDailyAudit = [datetime]::MinValue

while ($true) {
    try {
        # ── 1. FROTA ──
        # scan_master: processo + log do dia andando (zumbi <45min... ciclos podem dormir 60min -> 90min)
        $sm = Get-DaemonProc -Pattern 'scan_master\.ps1'
        $smLog = Join-Path $root "logs\master_$(Get-Date -Format 'yyyyMMdd').log"
        if (-not $sm) {
            Restart-Daemon -Name "scan_master" -ScriptRel "scripts\scan_master.ps1" -Proc $null -Reason "processo_morto"
        } elseif (-not (Test-LogFresh -Path $smLog -MaxAgeMin 90)) {
            $ageMin = ((Get-Date) - $sm.CreationDate).TotalMinutes
            if ($ageMin -gt 20) {
                Restart-Daemon -Name "scan_master" -ScriptRel "scripts\scan_master.ps1" -Proc $sm -Reason "zumbi_log_parado"
            }
        }

        # sentinela: processo + log <10min (poll 3min)
        $sent = Get-DaemonProc -Pattern 'sentinel_movers\.ps1'
        $sentLog = Join-Path $journalDir "sentinel.log"
        if (-not $sent) {
            Restart-Daemon -Name "sentinela" -ScriptRel "scripts\sentinel_movers.ps1" -Proc $null -Reason "processo_morto"
        } elseif (-not (Test-LogFresh -Path $sentLog -MaxAgeMin 15)) {
            Restart-Daemon -Name "sentinela" -ScriptRel "scripts\sentinel_movers.ps1" -Proc $sent -Reason "zumbi_log_parado"
        }

        # coletor 1h: processo + log <75min (coleta por hora)
        $col = Get-DaemonProc -Pattern 'collect_1h_klines\.ps1'
        $colLog = Join-Path $journalDir "collect_1h.log"
        if (-not $col) {
            Restart-Daemon -Name "coletor_1h" -ScriptRel "scripts\collect_1h_klines.ps1" -Proc $null -Reason "processo_morto"
        } elseif (-not (Test-LogFresh -Path $colLog -MaxAgeMin 75)) {
            Restart-Daemon -Name "coletor_1h" -ScriptRel "scripts\collect_1h_klines.ps1" -Proc $col -Reason "zumbi_log_parado"
        }

        # ── 2. INFRA ──
        # balance snapshot fresco (<90min = ciclos rodando o fetcher)
        $balFile = Join-Path $journalDir "balance_snapshot.json"
        if ((Test-Path $balFile) -and -not (Test-LogFresh -Path $balFile -MaxAgeMin 120)) {
            Write-GLog "WARN infra: balance_snapshot parado ha 2h+ (fetcher nao roda?)"
            Add-Incident -Signature "infra:balance_snapshot_stale" -Action "log_only" -Outcome "observed" | Out-Null
        }
        # Supabase alcancavel (1 probe barato)
        try {
            if (-not $env:SUPABASE_URL) { . (Join-Path $root "agents\config.local.ps1") 2>$null }
            if ($env:SUPABASE_URL -and $env:SUPABASE_SERVICE_KEY) {
                $h = @{ apikey = $env:SUPABASE_SERVICE_KEY; Authorization = "Bearer $($env:SUPABASE_SERVICE_KEY)" }
                $null = Invoke-RestMethod -Uri "$($env:SUPABASE_URL)/rest/v1/regime_state?limit=1" -Headers $h -TimeoutSec 15
            }
        } catch {
            Write-GLog "WARN infra: Supabase inacessivel ($($_.Exception.Message))"
            Add-Incident -Signature "infra:supabase_unreachable" -Action "log_only" -Outcome "observed" | Out-Null
        }
        # Densidade de ERROR no master log (ultimos 100 = >10 ERROR -> alerta)
        if (Test-Path $smLog) {
            $recent = Get-Content $smLog -Tail 100 -ErrorAction SilentlyContinue
            $errCount = @($recent | Where-Object { $_ -match '\[ERROR\]' }).Count
            if ($errCount -gt 10) {
                Write-GLog "WARN infra: densidade de ERROR alta ($errCount/100 linhas)"
                $n = Add-Incident -Signature "infra:error_storm_master" -Action "alert" -Outcome "observed"
                Send-GAlert "⚠️ <b>GUARDIAN</b> tempestade de ERRORs no scan_master ($errCount/100 linhas) — verificar log"
            }
        }

        # ── 3. AUDITORIA DIARIA (E2E + contrato) ~06:00 ──
        $now = Get-Date
        if ($now.Hour -eq 6 -and ($now - $lastDailyAudit).TotalHours -gt 20) {
            $lastDailyAudit = $now
            # AUTO-APRENDIZADO LLM: grada as decisoes de 48h+ contra o mercado
            # e atualiza o placar que o mentor le no prompt ([CALIBRACAO]).
            Write-GLog "GRADING DIARIO: gradeando decisoes LLM vs mercado..."
            try {
                $gr = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts\grade_llm_decisions.ps1") 2>&1
                $grLine = ($gr | Select-String "gradeadas agora|placar" | ForEach-Object { $_.ToString() }) -join " | "
                Write-GLog "GRADING: $grLine"
            } catch { Write-GLog "GRADING falhou: $_" }
            # EVOLUTION ENGINE: auto-tuning de parametros de deteccao por evidencia
            # (bounds duros, anti-oscilacao, risk nunca-auto). L2 do auto-aprendizado.
            try {
                . (Join-Path $root "agents\lib_evolution_engine.ps1")
                $evo = Invoke-EvolutionCycle -JournalDir $journalDir -LogsDir (Join-Path $root "logs")
                $evoMsg = "applied=$(@($evo.applied).Count) frozen=$(@($evo.frozen).Count) owner_pending=$(@($evo.owner_pending).Count)"
                Write-GLog "EVOLUTION: $evoMsg"
                foreach ($a in @($evo.applied)) {
                    Write-GLog "EVOLUTION aplicou: $($a.param) $($a.before)->$($a.after) ($($a.reason))"
                    Send-GAlert "🧬 <b>EVOLUTION</b> $($a.param): $($a.before) → $($a.after)`n<i>$($a.reason)</i>"
                }
                foreach ($o in @($evo.owner_pending)) {
                    Send-GAlert "🔐 <b>EVOLUTION (aguarda dono)</b> $($o.param): $($o.before) → $($o.after)`n<i>$($o.reason)</i>`nParametro de RISCO nunca muda sozinho."
                }
            } catch { Write-GLog "EVOLUTION falhou: $_" }
            Write-GLog "AUDITORIA DIARIA: rodando suite E2E + contrato..."
            $e2e = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts\verify_system_e2e.ps1") 2>&1
            $resLine = ($e2e | Select-String "RESULTADO" | Select-Object -Last 1).ToString()
            Write-GLog "AUDITORIA: $resLine"
            if ($resLine -match "0 FAIL") {
                Send-GAlert "🌅 <b>AUDITORIA DIARIA</b> $resLine — sistema integro"
            } else {
                $fails = ($e2e | Select-String "FAIL:" | ForEach-Object { $_.ToString() }) -join "`n"
                Add-Incident -Signature "audit:e2e_fail" -Action "alert" -Outcome $resLine | Out-Null
                Send-GAlert "🚨 <b>AUDITORIA DIARIA FALHOU</b>`n$resLine`n$fails"
            }
        }
    } catch {
        Write-GLog "erro no check do guardian: $_"
    }

    Start-Sleep -Seconds 600
}

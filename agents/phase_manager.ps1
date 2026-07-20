# phase_manager.ps1 — Fase 3: Daemon orquestrador de transição pump
# Loop 15min: monitora active_discoveries, classifica pump phase, dispara reversals

param(
    [int] $IntervalSeconds = 900  # 15 min
)

$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "lib_journal.ps1")
. (Join-Path $PSScriptRoot "lib_pump_reversal_monitor.ps1")
. (Join-Path $PSScriptRoot "lib_telegram.ps1")

$daemon_name = "phase_manager"
$journal_dir = if (Get-Command Get-JournalDir -ErrorAction SilentlyContinue) { Get-JournalDir } else { "journal" }
$log_file = "$journal_dir\phase_manager.log"
$active_discoveries_file = "$journal_dir\active_discoveries.jsonl"
$phase_transitions_file = "$journal_dir\phase_transitions.jsonl"

Write-Host "[phase_manager] Iniciado" -ForegroundColor Green
$start_time = Get-Date

# ─────────────────────────────────────────────────────────────────────────────
# Loop principal
# ─────────────────────────────────────────────────────────────────────────────
$loop_count = 0
while ($true) {
    try {
        $loop_count++
        $loop_start = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Fase 1: Lê active discoveries
        $discoveries = @()
        if (Test-Path $active_discoveries_file) {
            $discoveries = @(Get-Content $active_discoveries_file | ConvertFrom-Json -ErrorAction SilentlyContinue)
        }

        if ($discoveries.Count -eq 0) {
            Write-Host "[$loop_start] Nenhuma discovery ativa" -ForegroundColor Gray
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        # Fase 2: Classifica pump phase de cada discovery
        $reversals = @()
        foreach ($disc in $discoveries) {
            $market = $disc.market
            $pump_pct = $disc.pct_today
            $pump_hours = $disc.hours_since_pump_start
            $current_price = $disc.current_price
            $peak_price = $disc.pump_peak_price

            # Calcula retração
            $retraction = Get-ReversalRetraction -PeakPrice $peak_price -CurrentPrice $current_price
            $retraction_pct = [math]::Abs($retraction * 100)

            # Fase 3: Monitora candidatos à reversão
            if ($pump_pct -ge 40 -and $pump_pct -le 60) {
                # REVERSAL_WATCH range
                $monitor_result = Monitor-PumpReversalEntry `
                    -Market $market `
                    -PumpPeakPct $pump_pct `
                    -PumpPeakPrice $peak_price `
                    -CurrentPrice $current_price `
                    -CurrentVolume $disc.current_volume `
                    -AvgVolume $disc.avg_volume_24h `
                    -ADX $disc.adx `
                    -FundingRate $disc.funding_rate

                # Log transição de fase
                $phase_transition = [PSCustomObject]@{
                    market = $market
                    from_phase = "MOMENTUM"
                    to_phase = if ($retraction_pct -gt 15) { "REVERSAL_ACTIVE" } else { "TOPO_ABSOLUTO" }
                    pump_pct = $pump_pct
                    retraction_pct = $retraction_pct
                    confluence_score = $monitor_result.score
                    entry_signal = $monitor_result.entry_signal
                    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }

                $json = $phase_transition | ConvertTo-Json -Compress
                Add-Content -Path $phase_transitions_file -Value $json -ErrorAction SilentlyContinue

                # Se entry_trigger, adiciona à reversal watchlist
                if ($monitor_result.entry_trigger) {
                    $reversals += $monitor_result
                    Write-Host "[$loop_start] ✓ SHORT_REVERSAL $market (pump:$($pump_pct)%, retr:$($retraction_pct)%)" -ForegroundColor Yellow
                }
            }
        }

        # Fase 4: Notify Telegram (resumo)
        if ($reversals.Count -gt 0) {
            $msg = "🔄 PHASE MANAGER — $($reversals.Count) reversal(s) pronto(s):`n"
            foreach ($rev in $reversals) {
                $msg += "• $($rev.market): pump $($rev.pump_peak_pct)%, retr $($rev.retraction_pct)%`n"
            }
            Send-TelegramAlert -Message $msg -AlertLevel "INFO"
        }

        # Log ciclo
        $log_entry = @{
            loop = $loop_count
            timestamp = $loop_start
            discoveries_monitored = $discoveries.Count
            reversals_found = $reversals.Count
            status = "OK"
        } | ConvertTo-Json -Compress

        Add-Content -Path $log_file -Value $log_entry -ErrorAction SilentlyContinue

        Start-Sleep -Seconds $IntervalSeconds

    } catch {
        $error_msg = "[phase_manager] Erro: $_"
        Write-Host $error_msg -ForegroundColor Red
        Add-Content -Path $log_file -Value $error_msg -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 60
    }
}

# diag_trailing_activity_assessment_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu avaliacao critica: o sistema esta REALMENTE atuando nas 5
# posicoes abertas (trailing avancando fase, SL sendo puxado conforme o
# preco anda a favor) ou esta so parado com o TP/SL inicial da abertura,
# sem nenhum ajuste desde entao? Puxa historico real: phase atual, peak
# registrado, ultima atualizacao (updatedAt) vs abertura (openedAt), e
# calcula se o SL real na CoinEx ja capturou parte do lucro ou ainda esta
# no nivel de risco original.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: o sistema esta atuando de verdade nas posicoes abertas? ===" -ForegroundColor Cyan

try {
    $positions = @(CoinEx-GetPendingPositions)
    $trailingRows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })

    foreach ($p in $positions) {
        $mkt = [string]$p.market
        $side = ([string]$p.side).ToLower()
        $entry = [double]$p.avg_entry_price
        $curPrice = 0.0
        try { $curPrice = [double](CoinEx-GetTicker $mkt).last } catch {}

        $tRow = $trailingRows | Where-Object { $_.market -eq $mkt } | Select-Object -First 1

        Write-Host "--- $mkt ($side) ---" -ForegroundColor Cyan
        if (-not $tRow) {
            Write-Host "  SEM REGISTRO no trailing_state (orfa ou nao rastreada)" -ForegroundColor Red
            continue
        }

        $phase = [int]$tRow.phase
        $peak = [double]$tRow.peak
        $stopCurrent = [double]$tRow.stopCurrent
        $stopOriginal = [double]$tRow.stop
        $openedAt = try { [datetime]::Parse([string]$tRow.openedAt) } catch { $null }
        $updatedAt = try { [datetime]::Parse([string]$tRow.updatedAt) } catch { $null }

        $ageHours = if ($openedAt) { [math]::Round(((Get-Date) - $openedAt).TotalHours, 1) } else { -1 }
        $sinceUpdateHours = if ($updatedAt) { [math]::Round(((Get-Date) - $updatedAt).TotalHours, 1) } else { -1 }

        # SL real na CoinEx (fonte de verdade) vs o que o journal acha
        $realSL = [double]$p.stop_loss_price
        $realTP = [double]$p.take_profit_price

        # SL moveu a favor desde a abertura? (LONG: SL subiu; SHORT: SL desceu)
        $slMovedInFavor = if ($side -eq "long") { $stopCurrent -gt $stopOriginal } else { $stopCurrent -lt $stopOriginal }
        $slDelta = if ($stopOriginal -gt 0) { [math]::Round((($stopCurrent - $stopOriginal) / $stopOriginal) * 100, 2) } else { 0 }

        # Ja protegeu lucro (SL do lado ganhador do entry)?
        $slLocksProfit = if ($side -eq "long") { $stopCurrent -gt $entry } else { $stopCurrent -lt $entry }

        Write-Host ("  phase={0} openedAt={1} ({2}h atras) updatedAt={3} ({4}h atras)" -f $phase, $openedAt, $ageHours, $updatedAt, $sinceUpdateHours)
        Write-Host ("  stop original={0} stop atual (journal)={1} (moveu a favor: {2}, delta={3}%)" -f $stopOriginal, $stopCurrent, $slMovedInFavor, $slDelta)
        Write-Host ("  SL real na corretora={0} TP real na corretora={1}" -f $realSL, $realTP)
        Write-Host ("  journal.stopCurrent == corretora real? {0}" -f ([math]::Abs($stopCurrent - $realSL) -lt 0.0001))
        $lockColor = if ($slLocksProfit) { "Green" } else { "Yellow" }
        Write-Host ("  SL ja protege LUCRO (nao so limita perda)? {0}" -f $slLocksProfit) -ForegroundColor $lockColor
        Write-Host ""
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan

# diag_tp_sl_source_frequency_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner quer refinar a proposta de auto-calibragem de TP%/SL% (fallback fixo
# do Get-StructuralStopTarget) com visao de QUANTO ganho isso traria -- nao
# so o mecanismo de seguranca. Passo 1: medir com que frequencia o fallback
# fixed_pct dispara de verdade nas posicoes reais abertas hoje (ja vimos
# 3/10 no diag qualitativo anterior: SOONUSDT, OPUSDT, ARBUSDT no SL) e
# tentar cruzar com trade_outcomes fechados recentes pra ver se ha sinal de
# PnL diferente entre trades que usaram estrutural vs fixo -- mesmo sem
# sl_source/tp_source persistido historicamente (gap real, confirmado),
# reconstroi uma aproximacao rodando Get-StructuralStopTarget hoje com o
# ENTRY REAL de cada trade fechado (o range de candle pode ter mudado desde
# entao, mas ainda indica se o fallback teria disparado).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: frequencia real fixed_pct vs structural (posicoes ABERTAS agora) ===" -ForegroundColor Cyan

try {
    $positions = @(CoinEx-GetPendingPositions)
    Write-Host "Total posicoes FUTURES: $($positions.Count)`n"

    $slFixed = 0; $slStruct = 0; $tpFixed = 0; $tpStruct = 0
    foreach ($p in $positions) {
        $mkt = [string]$p.market
        $side = ([string]$p.side).ToLower()
        $entry = [double]$p.avg_entry_price

        $candles = $null
        try { $candles = @(CoinEx-GetFuturesCandles $mkt "4hour" 180) } catch {}
        if (-not $candles) { continue }

        $struct = Get-StructuralStopTarget -Side $side -Entry $entry -Candles $candles -StopPct 0.08 -TargetPct 0.32
        if ($struct.sl_source -eq "fixed_pct") { $slFixed++ } else { $slStruct++ }
        if ($struct.tp_source -eq "fixed_pct") { $tpFixed++ } else { $tpStruct++ }
        Write-Host ("  {0,-14} SL={1,-10} TP={2}" -f $mkt, $struct.sl_source, $struct.tp_source)
    }

    Write-Host "`n--- Resumo (posicoes abertas agora) ---" -ForegroundColor Yellow
    Write-Host "SL: structural=$slStruct fixed_pct=$slFixed"
    Write-Host "TP: structural=$tpStruct fixed_pct=$tpFixed"

    Write-Host "`n--- trade_outcomes fechados: reconstrucao aproximada (candles ATUAIS, nao os da epoca) ---" -ForegroundColor Yellow
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ status = "closed" } -ErrorAction Stop)
    Write-Host "Total trade_outcomes closed: $($outcomes.Count)"

    $sample = @($outcomes | Where-Object { $_.entry_price -and [double]$_.entry_price -gt 0 } | Select-Object -Last 40)
    Write-Host "Amostra avaliada (ultimos 40 com entry_price valido): $($sample.Count)"

    $pnlByFixedSl = @(); $pnlByStructSl = @()
    foreach ($o in $sample) {
        $mkt = [string]$o.symbol
        $side = ([string]$o.direction).ToLower()
        $entry = [double]$o.entry_price
        $pnlPct = if ($null -ne $o.pnl_percent) { [double]$o.pnl_percent } else { $null }
        if ($null -eq $pnlPct) { continue }

        $candles = $null
        try { $candles = @(CoinEx-GetFuturesCandles $mkt "4hour" 180) } catch {}
        if (-not $candles) { continue }

        try {
            $struct = Get-StructuralStopTarget -Side $side -Entry $entry -Candles $candles -StopPct 0.08 -TargetPct 0.32
            if ($struct.sl_source -eq "fixed_pct") { $pnlByFixedSl += $pnlPct } else { $pnlByStructSl += $pnlPct }
        } catch {}
    }

    Write-Host "`nPnL% medio (trades cujo SL SERIA fixed_pct hoje, aproximado): $(if ($pnlByFixedSl.Count -gt 0) { [math]::Round(($pnlByFixedSl | Measure-Object -Average).Average,2) } else { 'sem amostra' }) (n=$($pnlByFixedSl.Count))"
    Write-Host "PnL% medio (trades cujo SL SERIA structural hoje, aproximado): $(if ($pnlByStructSl.Count -gt 0) { [math]::Round(($pnlByStructSl | Measure-Object -Average).Average,2) } else { 'sem amostra' }) (n=$($pnlByStructSl.Count))"
    Write-Host "`nAVISO: esta e uma RECONSTRUCAO aproximada (candles de HOJE, nao da epoca da entrada) -- nao e prova estatistica, so um indicador de direcao pra decidir se vale instrumentar sl_source/tp_source de verdade daqui pra frente." -ForegroundColor DarkYellow

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan

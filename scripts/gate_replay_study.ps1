# gate_replay_study.ps1 -- 2026-07-16
# Estudo ativo (nao passivo): pega top movers reais da CoinEx agora,
# simula os thresholds/gates ATUAIS via Invoke-GemExecute -DryRun (fiel,
# roda breadth/pump/tori/quality de verdade, incluindo LLM), grava
# snapshot, e revisita snapshots antigos em horizontes curtos
# (10min/30min/1h/4h) pra medir o que realmente aconteceu -- avaliando os
# DOIS sentidos: threshold bloqueou e teria dado certo (falso negativo) vs
# threshold bloqueou e teria dado errado (acerto correto).
#
# Roda a cada ciclo do cron (nao ha agendamento exato de "daqui 10min" --
# throttle de plataforma faz o cron rodar a cada ~5-35min, entao a
# revisita so preenche o horizonte quando ele JA passou, olhando pro
# candle mais proximo do alvo).
#
# Pre-requisito: manuheadfund.gate_replay_study precisa existir
# (docs/SETUP_SUPABASE_GATE_REPLAY_STUDY_2026_07_16.sql).

param(
    [int] $NewCandidatesPerRun = 2,
    [double] $MinAbsChangePct = 5.0   # so considera "top mover" se |change24h| >= 5%
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\config.ps1")
. (Join-Path $root "agents\gem_executor.ps1")
. (Join-Path $root "agents\lib_state_store.ps1")

Write-Host "=== GATE REPLAY STUDY ===" -ForegroundColor Cyan

# Horizontes em minutos e o rotulo usado na coluna JSONB "returns"
$horizons = @(
    @{ label = "10m"; minutes = 10 },
    @{ label = "30m"; minutes = 30 },
    @{ label = "1h";  minutes = 60 },
    @{ label = "4h";  minutes = 240 }
)

# =========================================================================
# [1] REVISITA snapshots antigos -- preenche horizontes ja maturados
# =========================================================================
Write-Host ""
Write-Host "[1] Revisitando snapshots existentes..." -ForegroundColor Yellow

$nowUtc = (Get-Date).ToUniversalTime()
$candleCache = @{}

function Get-CandleReturn {
    param([string]$Market, [datetime]$BaseTs, [double]$BasePrice, [int]$Minutes)
    if (-not $candleCache.ContainsKey($Market)) {
        # 2026-07-16 FIX (achado real, nao teorico): CoinEx-GetCandles
        # (lib_coinex.ps1:120) roteia "futures" pra qualquer market que
        # termine em USDT e nao contenha literalmente "SPOT" no nome --
        # ou seja, quase TODO par vira futures por default. Gemas pequenas
        # (AKEUSDT, ARGUSDT) frequentemente so existem em SPOT -- chamada
        # ia pro endpoint futures errado, API retornava code=4004 "invalid
        # argument" (confirmado via curl direto), try/catch engolia
        # silenciosamente, candleCache ficava vazio, Revisitados sempre
        # 0/N mesmo com horizonte ja maturado. Fix: candidatos deste
        # estudo vem de /v2/spot/ticker (sempre spot) -- busca direto no
        # endpoint spot, sem depender da heuristica ambigua da lib
        # compartilhada.
        try {
            $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/kline?market=$Market&period=1min&limit=250" -Method GET -TimeoutSec 15 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data) {
                $candleCache[$Market] = @($r.data | ForEach-Object {
                    [PSCustomObject]@{ ts = [long]$_.created_at; close = [double]$_.close }
                })
            } else {
                $candleCache[$Market] = @()
            }
        } catch { $candleCache[$Market] = @() }
    }
    $candles = $candleCache[$Market]
    if ($candles.Count -eq 0) { return $null }
    $targetTs = [long](([datetimeoffset]$BaseTs.AddMinutes($Minutes)).ToUnixTimeMilliseconds())
    $best = $null; $bestDelta = [long]::MaxValue
    foreach ($c in $candles) {
        $d = [Math]::Abs($c.ts - $targetTs)
        if ($d -lt $bestDelta) { $bestDelta = $d; $best = $c }
    }
    # Candle 1min: aceita ate 5min de folga do alvo (senao dado ainda nao existe/velho demais)
    if ($null -eq $best -or $bestDelta -gt 300000) { return $null }
    return [Math]::Round((($best.close - $BasePrice) / $BasePrice) * 100, 3)
}

$existing = @()
try {
    $existing = @(Get-StateRecords -Table "gate_replay_study" -ErrorAction Stop)
} catch {
    Write-Host "  AVISO: nao consegui ler gate_replay_study ($($_.Exception.Message)) -- pulando revisita." -ForegroundColor Yellow
}

$revisited = 0
foreach ($row in $existing) {
    $ts = [datetime]::Parse($row.ts).ToUniversalTime()
    $ageMinutes = ($nowUtc - $ts).TotalMinutes
    $returns = if ($row.returns) { $row.returns | ConvertTo-Json | ConvertFrom-Json } else { [PSCustomObject]@{} }
    $changed = $false

    foreach ($h in $horizons) {
        $already = $returns.PSObject.Properties[$h.label]
        if ($already -and $null -ne $already.Value) { continue }   # ja medido
        if ($ageMinutes -lt $h.minutes) { continue }                # ainda nao maturou

        $ret = Get-CandleReturn -Market $row.market -BaseTs $ts -BasePrice ([double]$row.entry_price) -Minutes $h.minutes
        if ($null -ne $ret) {
            $signed = if ($row.direction -eq "SHORT") { -$ret } else { $ret }
            Add-Member -InputObject $returns -MemberType NoteProperty -Name $h.label -Value $signed -Force
            $changed = $true
            $passLabel = if ($row.would_pass) { "PASSARIA" } else { "bloqueado:$($row.blocked_by)" }
            Write-Host "    [$($h.label)] $($row.market) $($row.direction) ($passLabel): $signed%" -ForegroundColor $(if ($signed -gt 0) { "Green" } else { "Red" })
        }
    }

    if ($changed) {
        try {
            # 2026-07-16 FIX: _Supabase-Save sempre faz upsert (POST +
            # on_conflict), nao UPDATE parcial de verdade -- enviar so
            # {id, returns, updated_at} fazia o PostgREST tentar validar a
            # linha INTEIRA contra os campos NOT NULL (market, direction,
            # ts, entry_price, would_pass), todos vindo como null no
            # payload parcial -> 23502 "null value in column market
            # violates not-null constraint". Confirmado no erro real: o
            # calculo do retorno funcionava (-0.916% em 10m pra AKEUSDT),
            # so a gravacao falhava. Fix: reenvia a linha completa
            # (todos os campos originais de $row + returns atualizado).
            Save-StateRecords -Table "gate_replay_study" -Records @([PSCustomObject]@{
                id             = $row.id
                market         = $row.market
                direction      = $row.direction
                ts             = $row.ts
                entry_price    = $row.entry_price
                change_24h_pct = $row.change_24h_pct
                regime         = $row.regime
                would_pass     = $row.would_pass
                blocked_by     = $row.blocked_by
                gates_snapshot = $row.gates_snapshot
                returns        = $returns
                updated_at     = $nowUtc.ToString("o")
            }) -PrimaryKey "id"
            $revisited++
        } catch {
            Write-Host "  AVISO: falha ao atualizar returns de $($row.market) (id=$($row.id)): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
Write-Host "  Revisitados: $revisited / $($existing.Count) snapshots (novos horizontes preenchidos)" -ForegroundColor White

# =========================================================================
# [2] NOVOS candidatos -- top movers reais, simula gates, grava snapshot
# =========================================================================
Write-Host ""
Write-Host "[2] Buscando top movers reais na CoinEx..." -ForegroundColor Yellow

$tickers = @()
try {
    $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/ticker" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ($r.code -eq 0 -and $r.data) {
        $tickers = @($r.data | Where-Object { $_.market -match "USDT$" } | ForEach-Object {
            $openPx = [double]$_.open
            $closePx = [double]$_.close
            $chg = if ($openPx -gt 0) { (($closePx - $openPx) / $openPx) * 100 } else { 0 }
            [PSCustomObject]@{ market = $_.market; price = $closePx; change24h = $chg }
        })
    }
} catch {
    Write-Host "  ERRO ao buscar tickers: $($_.Exception.Message)" -ForegroundColor Red
}

$topMovers = @($tickers | Where-Object { [Math]::Abs($_.change24h) -ge $MinAbsChangePct } |
    Sort-Object { [Math]::Abs($_.change24h) } -Descending | Select-Object -First $NewCandidatesPerRun)

Write-Host "  Top movers (|change24h| >= $MinAbsChangePct%): $($topMovers.Count) encontrados" -ForegroundColor White

# 2026-07-16: BTC sempre entra no estudo, independente de bater o filtro de
# top mover -- BTC raramente move >=5%/24h (baixa vol relativa a altcoin),
# entao o filtro acima o exclui quase sempre e ele nunca seria estudado.
# Motivo de incluir: BTC e o proprio "pai" do regime (Get-MarketScenario) e
# raramente entra em trade real (confluence Tori 1h quase nunca bate 80 --
# ver commit 9e30422); precisamos medir se scalps de 15m que o sweep live
# passou a testar realmente teriam dado lucro, com dado real, nao so
# opiniao. Nao usa MinAbsChangePct: BTC entra sempre que ainda nao foi
# medido nesta janela (dedup abaixo evita spam a cada ciclo de 5min).
$btcTicker = $tickers | Where-Object { $_.market -eq "BTCUSDT" } | Select-Object -First 1
if ($btcTicker -and -not ($topMovers | Where-Object { $_.market -eq "BTCUSDT" })) {
    $btcAlreadyRecent = $false
    try {
        $recentBtc = @(Get-StateRecords -Table "gate_replay_study" -ErrorAction Stop |
            Where-Object { $_.market -eq "BTCUSDT" })
        foreach ($rb in $recentBtc) {
            $rbTs = [datetime]::Parse($rb.ts).ToUniversalTime()
            if (($nowUtc - $rbTs).TotalMinutes -lt 15) { $btcAlreadyRecent = $true; break }
        }
    } catch {}
    if (-not $btcAlreadyRecent) {
        $topMovers += $btcTicker
        Write-Host "  + BTCUSDT incluido manualmente (fixo no estudo, fora do filtro de top mover)" -ForegroundColor Cyan
    }
}

if ($topMovers.Count -eq 0) {
    Write-Host "  Nenhum candidato novo neste ciclo." -ForegroundColor Yellow
} else {
    $btcScenario = Get-MarketScenario
    $newRows = @()

    foreach ($t in $topMovers) {
        # 2026-07-16: simula AMBAS direcoes por candidato -- "seguir o
        # movimento" (LONG em alta, SHORT em queda) E "contrarian/reversao"
        # (SHORT em alta forte, LONG em queda forte). Pump grande as vezes
        # e setup de exaustao/reversao, nao so continuacao -- captura os
        # dois lados pro auto-aprendizado, nao so o obvio.
        foreach ($direction in @("LONG", "SHORT")) {
            $gem = [PSCustomObject]@{
                market = $t.market; direction = $direction
                score = 65; mode = "DISCOVERY"; sizing_pct = 0.03
                change_24h = $t.change24h
            }

            Write-Host "  Simulando $($t.market) $direction (change24h=$([Math]::Round($t.change24h,2))%)..." -ForegroundColor Gray
            $result = $null
            try {
                $result = Invoke-GemExecute -Gem $gem -DryRun
            } catch {
                Write-Host "    ERRO na simulacao: $($_.Exception.Message)" -ForegroundColor Yellow
                continue
            }

            $wouldPass = -not [bool]$result.blocked
            $blockedBy = if ($result.blocked_by) { ($result.blocked_by -join ", ") } else { $null }

            $newRows += [PSCustomObject]@{
                market         = $t.market
                direction      = $direction
                ts             = $nowUtc.ToString("o")
                entry_price    = $t.price
                change_24h_pct = [Math]::Round($t.change24h, 3)
                regime         = "$($btcScenario.scenario)"
                would_pass     = $wouldPass
                blocked_by     = $blockedBy
                gates_snapshot = ($result | Select-Object -ExcludeProperty market)
                returns        = [PSCustomObject]@{}
            }

            $verdict = if ($wouldPass) { "PASSARIA" } else { "BLOQUEADO: $blockedBy" }
            Write-Host "    -> $verdict" -ForegroundColor $(if ($wouldPass) { "Green" } else { "DarkYellow" })
        }
    }

    if ($newRows.Count -gt 0) {
        try {
            # Sem -PrimaryKey: cada top-mover vira uma linha NOVA (id auto-gerado).
            # Nao usar "market" como conflict-key -- faria upsert sobrescrever o
            # snapshot anterior da mesma moeda em vez de registrar um novo evento
            # "virou top mover agora", que e o que queremos capturar ao longo do tempo.
            Save-StateRecords -Table "gate_replay_study" -Records $newRows
            Write-Host "  Gravados $($newRows.Count) snapshots novos." -ForegroundColor Green
        } catch {
            Write-Host "  ERRO ao gravar snapshots: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "=== FIM ===" -ForegroundColor Cyan

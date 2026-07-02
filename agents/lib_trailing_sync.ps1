# lib_trailing_sync.ps1 -- Empurra a SL do journal pra corretora (elo que faltava)
# O trailing REGISTRAVA (journal) mas nao EXECUTAVA. Aqui sincroniza journal->exchange.
# SEGURANCA CRITICA: nunca empurra uma SL que ja dispararia (fecharia a mercado).
#   LONG : so empurra se journalStop < precoAtual (nao dispara) E melhora (> exchangeStop)
#   SHORT: so empurra se journalStop > precoAtual (nao dispara) E melhora (< exchangeStop)
# 2026-06-17. ASCII-only (PS 5.1 safe). Sem Export-ModuleMember (dot-source).

function Resolve-TrailingSync {
    [CmdletBinding()]
    param(
        [string] $Side = "LONG",
        [double] $CurrentPrice,
        [double] $JournalStop,
        [double] $ExchangeStop
    )

    if ($JournalStop -le 0) {
        return @{ should_push = $false; new_sl = $JournalStop; reason = "journal_stop_invalido" }
    }

    $isShort = ("$Side".ToUpper() -eq "SHORT")

    if ($isShort) {
        $improves = $JournalStop -lt $ExchangeStop
        $safe     = $JournalStop -gt $CurrentPrice   # SL acima do preco no SHORT = nao dispara
        $triggerReason = "SL $JournalStop <= preco $CurrentPrice (dispararia)"
    } else {
        $improves = $JournalStop -gt $ExchangeStop
        $safe     = $JournalStop -lt $CurrentPrice   # SL abaixo do preco no LONG = nao dispara
        $triggerReason = "SL $JournalStop acima do preco $CurrentPrice (dispararia)"
    }

    if (-not $improves) {
        return @{ should_push = $false; new_sl = $JournalStop; reason = "sem melhora (journal=$JournalStop exch=$ExchangeStop)" }
    }
    if (-not $safe) {
        return @{ should_push = $false; new_sl = $JournalStop; reason = $triggerReason }
    }

    @{ should_push = $true; new_sl = $JournalStop; reason = "empurra SL $ExchangeStop -> $JournalStop (seguro)" }
}

function Sync-TrailingToExchange {
    # Le journal trailing, e p/ cada posicao ativa decide+empurra a SL na corretora.
    # FUTURES: CoinEx-ModifyPositionStopLoss. Fail-soft por posicao.
    [CmdletBinding()]
    param(
        [string] $TrailingFile = "",
        [switch] $DryRun
    )

    # 2026-06-25 fix: ler o arquivo local direto sempre achava vazio desde a
    # migracao p/ Supabase (USE_SUPABASE_STATE.flag) -- trailing_positions.json
    # nao existe mais no disco, entao esta funcao nunca via posicao alguma e o
    # SL adaptativo nunca chegava na corretora (mesma causa raiz do lado SPOT,
    # ver lib_spot_stop_guard.ps1 Get-SpotHoldingsForStop). Usa Get-TrailingPositions
    # (resolve Supabase-vs-arquivo) quando disponivel e nenhum -TrailingFile
    # explicito foi passado (preserva comportamento de teste com path custom).
    $explicitTrailingFile = [bool]$TrailingFile
    $positions = @()
    if (-not $explicitTrailingFile -and (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        try { $positions = @(Get-TrailingPositions) } catch { $positions = @() }
    } else {
        if (-not $TrailingFile) {
            $jdir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
            $TrailingFile = Join-Path $jdir "trailing_positions.json"
        }
        if (-not (Test-Path $TrailingFile)) { return @() }
        try { $positions = @(Get-Content $TrailingFile -Raw | ConvertFrom-Json) } catch { return @() }
    }

    # Snapshot das posicoes da corretora (preco atual + SL atual)
    $live = @{}
    if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
        try {
            foreach ($p in @(CoinEx-GetPendingPositions)) {
                $mark = [double]$p.mark_price
                # mark=0 e bug comum em micro-caps -> fallback ticker last (senao trava cega)
                if ($mark -le 0) {
                    try {
                        $ft = Invoke-RestMethod "https://api.coinex.com/v2/futures/ticker?market=$($p.market)" -TimeoutSec 8 -EA Stop
                        if ($ft.data) { $mark = [double]$ft.data[0].last }
                    } catch {}
                }
                $live["$($p.market)"] = @{
                    mark = $mark
                    sl   = [double]$p.stop_loss_price
                    side = "$($p.side)".ToUpper()
                }
            }
        } catch {}
    }

    $results = @()
    foreach ($pos in $positions) {
        if ($pos.active -ne $true) { continue }
        $mkt = "$($pos.market)"
        $journalStop = [double]$pos.stopCurrent
        $side = if ($pos.PSObject.Properties['side'] -and "$($pos.side)") { "$($pos.side)".ToUpper() } else { "LONG" }

        $lp = $live[$mkt]
        if (-not $lp) { continue }   # so futures abertas na corretora

        $decision = Resolve-TrailingSync -Side $side -CurrentPrice $lp.mark -JournalStop $journalStop -ExchangeStop $lp.sl

        $pushed = $false
        $err = $null
        if ($decision.should_push -and -not $DryRun) {
            if (Get-Command CoinEx-ModifyPositionStopLoss -ErrorAction SilentlyContinue) {
                try {
                    $resp = CoinEx-ModifyPositionStopLoss -Market $mkt -Price ([decimal]$decision.new_sl)
                    $pushed = ($resp.success -eq $true)
                    if (-not $pushed) { $err = "api_falhou" }
                } catch { $err = $_.Exception.Message }
            } else { $err = "ModifyPositionStopLoss_indisponivel" }
        }

        $results += [PSCustomObject]@{
            market      = $mkt
            side        = $side
            current     = $lp.mark
            exch_sl     = $lp.sl
            journal_sl  = $journalStop
            should_push = $decision.should_push
            pushed      = $pushed
            reason      = $decision.reason
            error       = $err
        }
    }

    return $results
}

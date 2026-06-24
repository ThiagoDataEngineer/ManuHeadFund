# lib_state_reconcile.ps1 -- Fix #2 (2026-06-23): UMA fonte de verdade.
#
# PROBLEMA: 3 fontes se contradizem ->
#   - gem_trades.csv: 6 futures OPEN (MON/XMR/TRUMP/...) que JA FECHARAM (status nunca atualizado)
#   - trailing_positions.json: 4 recovery (UB/PAXG/TNSR/XRP) gravadas 2x (risco vender em dobro)
#   - exchange: a verdade real
# Auditoria automatica lia lixo. Estas funcoes PURAS reconciliam.

function Remove-DuplicatePositions {
    <#
      Dedup por market. Mantem 1 por market:
        - prefere a ATIVA (active=true) se houver
        - desempate: created_at mais recente
      PURO. Retorna lista deduplicada.
    #>
    param([array]$Positions)
    $out = @()
    $groups = @($Positions) | Group-Object market
    foreach ($g in $groups) {
        $items = @($g.Group)
        if ($items.Count -eq 1) { $out += $items[0]; continue }
        # prefere ativa(s); se nenhuma ativa, considera todas
        $actives = @($items | Where-Object { $_.active -eq $true })
        $pool = if ($actives.Count -gt 0) { $actives } else { $items }
        # mais recente por created_at (string ISO ordena lexicograficamente)
        $keep = $pool | Sort-Object { "$($_.created_at)" } -Descending | Select-Object -First 1
        $out += $keep
    }
    return $out
}

function Resolve-StaleCsvStatus {
    <#
      Acha linhas do CSV marcadas OPEN que NAO existem mais na exchange (fantasmas).
      CsvRows:     objetos { market, status, ... }
      LiveMarkets: markets realmente abertos na corretora (verdade)
      Retorna as linhas que devem virar CLOSED. PURO.
    #>
    param(
        [array]$CsvRows,
        [array]$LiveMarkets = @()
    )
    $liveSet = @{}
    foreach ($m in @($LiveMarkets)) { $liveSet["$m"] = $true }
    $stale = @()
    foreach ($row in @($CsvRows)) {
        if ("$($row.status)" -ne "OPEN") { continue }
        if (-not $liveSet.ContainsKey("$($row.market)")) {
            $stale += $row
        }
    }
    return $stale
}

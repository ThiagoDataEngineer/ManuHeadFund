# lib_entry_direction.ps1 -- Cerebro bidirecional (2026-06-24)
#
# "Se aparecer LONG bom atua, se SHORT bom atua, e sempre tem." Decide o LADO com EDGE:
# combina o cenario (allow_long/allow_short do lib_market_scenario) com a conviccao de
# cada lado. NUNCA opera contra o cenario. SKIP quando nenhum lado tem edge suficiente
# (ficar em caixa tambem e decisao). PURO, zero LLM. Alimenta o auto-aprendizado
# (lib_direction_learning ja agrega stats por direcao).

function Resolve-EntryDirection {
    param(
        [bool]$AllowLong,
        [bool]$AllowShort,
        [double]$LongConviction = 0,
        [double]$ShortConviction = 0,
        [double]$MinConviction = 60
    )
    # candidatos viaveis = lado permitido pelo cenario E conviccao >= minimo
    $longOk  = $AllowLong  -and ($LongConviction  -ge $MinConviction)
    $shortOk = $AllowShort -and ($ShortConviction -ge $MinConviction)

    if (-not $longOk -and -not $shortOk) {
        return [pscustomobject]@{ act=$false; direction="SKIP"; conviction=0; reason="nenhum lado com edge (caixa)" }
    }
    if ($longOk -and -not $shortOk) {
        return [pscustomobject]@{ act=$true; direction="LONG"; conviction=$LongConviction; reason="long com edge ($LongConviction)" }
    }
    if ($shortOk -and -not $longOk) {
        return [pscustomobject]@{ act=$true; direction="SHORT"; conviction=$ShortConviction; reason="short com edge ($ShortConviction)" }
    }
    # ambos viaveis -> pega o de MAIOR conviccao
    if ($ShortConviction -gt $LongConviction) {
        return [pscustomobject]@{ act=$true; direction="SHORT"; conviction=$ShortConviction; reason="ambos ok, short maior" }
    }
    return [pscustomobject]@{ act=$true; direction="LONG"; conviction=$LongConviction; reason="ambos ok, long maior" }
}

# Shadow logger: registra o que o cerebro DECIDIRIA (forward-test sem risco), p/ validar
# o SHORT antes de ligar execucao real. JSONL append. Alimenta auditoria + aprendizado.
function Write-DirectionShadow {
    param(
        [string]$Market,
        [pscustomobject]$Decision,
        [string]$Scenario,
        [string]$JournalDir = ""
    )
    try {
        $jdir = if ($JournalDir) { $JournalDir } elseif ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot) "journal" }
        $rec = @{
            ts         = (Get-Date).ToUniversalTime().ToString("o")
            market     = $Market
            scenario   = $Scenario
            direction  = $Decision.direction
            act        = $Decision.act
            conviction = $Decision.conviction
            reason     = $Decision.reason
        } | ConvertTo-Json -Compress
        Add-Content -Path (Join-Path $jdir "direction_shadow.jsonl") -Value $rec -Encoding UTF8
    } catch {}
}

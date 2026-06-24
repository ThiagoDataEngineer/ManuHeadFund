# lib_asymmetric_trail.ps1 -- Fix #3 / Evolucao B (2026-06-23): deixar o GANHADOR correr.
#
# PROBLEMA: R:R invertido. Ganho medio $1.15 vs perda media $4.45 (ratio 0.26, meta 1:5).
# O sistema estrangula o vencedor (AIN cortado a +19% por $1.77; breakeven a +2.5% choca o
# moonshot) e segura o perdedor. Precisa do OPOSTO: perdedor sai no SL planejado (ja controlado),
# vencedor ganha ESPACO (trail largo) pra capturar a perna grande.
#
# Resolve-AsymmetricStop e PURO. Regras (LONG; SHORT espelhado):
#   - lucro < BreakevenTriggerPct  -> mantem BaseStop (deixa respirar ate o SL planejado)
#   - lucro >= BreakevenTriggerPct -> stop = max(BaseStop, breakeven, peak*(1-TrailWidthPct))
#     (ratchet: so sobe; trail LARGO 12% da espaco pro winner correr; nunca acima do peak)

function Resolve-AsymmetricStop {
    param(
        [Parameter(Mandatory)] [double]$Entry,
        [Parameter(Mandatory)] [double]$Peak,        # melhor preco atingido (high p/ LONG, low p/ SHORT)
        [Parameter(Mandatory)] [double]$BaseStop,    # SL planejado original
        [string]$Side = "LONG",
        [double]$BreakevenTriggerPct = 0.05,         # lucro a partir do qual trava breakeven
        [double]$TrailWidthPct = 0.12                # largura do trail do winner (espaco p/ correr)
    )

    if ($Side -eq "SHORT") {
        # ganho do SHORT = quanto o peak (low) caiu abaixo do entry
        $gain = ($Entry - $Peak) / $Entry
        if ($gain -lt $BreakevenTriggerPct) { return $BaseStop }
        $trail = $Peak * (1 + $TrailWidthPct)   # stop acima do peak (low)
        $be    = $Entry
        # SHORT: stop desce conforme protege -> queremos o MENOR entre candidatos validos,
        # mas nunca acima do BaseStop (ratchet pra baixo).
        $cand = @($BaseStop, $be, $trail) | Where-Object { $_ -gt $Peak }  # tem que ficar acima do low
        $newStop = ($cand | Measure-Object -Minimum).Minimum
        if ($newStop -gt $BaseStop) { $newStop = $BaseStop }
        return [math]::Round($newStop, 8)
    }

    # LONG
    $gain = ($Peak - $Entry) / $Entry
    if ($gain -lt $BreakevenTriggerPct) { return $BaseStop }
    $trail = $Peak * (1 - $TrailWidthPct)
    $be    = $Entry
    $newStop = ($BaseStop, $be, $trail | Measure-Object -Maximum).Maximum  # ratchet up
    if ($newStop -ge $Peak) { $newStop = $Peak * (1 - $TrailWidthPct) }    # nunca no/acima do peak
    return [math]::Round($newStop, 8)
}

# lib_btc_relative_strength.ps1 -- Eixo 2 do ensemble de conviccao
# Mede se a altcoin sobe no PROPRIO combustivel (decoupling do BTC) = assinatura pre-pump.
# Puro (sem API/LLM): caller passa as series de close. Rapido e barato.
#
# Conceito: RS = retorno_alt - beta * retorno_btc
#   RS forte positivo + BTC parado/caindo = demanda idiossincratica (pre-pump LONG)
#   RS forte negativo + BTC parado/subindo = fraqueza idiossincratica (pre-dump SHORT)
#
# 2026-06-17. ASCII-only (PS 5.1 safe). Sem Export-ModuleMember (dot-source).

function Get-BtcRelativeStrength {
    [CmdletBinding()]
    param(
        [double[]] $AltCloses,
        [double[]] $BtcCloses,
        [double]   $Beta = 1.0
    )

    if ($null -eq $AltCloses -or $null -eq $BtcCloses) { return $null }
    if ($AltCloses.Count -lt 2 -or $BtcCloses.Count -lt 2) { return $null }
    if ($AltCloses[0] -le 0 -or $BtcCloses[0] -le 0) { return $null }

    $altReturn = ($AltCloses[-1] - $AltCloses[0]) / $AltCloses[0] * 100
    $btcReturn = ($BtcCloses[-1] - $BtcCloses[0]) / $BtcCloses[0] * 100
    $rs = $altReturn - ($Beta * $btcReturn)

    # Decoupling: alt sobe no proprio combustivel (rs forte, btc quase parado, alt positiva)
    $decoupled = ($rs -ge 5 -and $btcReturn -le 2 -and $altReturn -gt 0)

    @{
        alt_return = [math]::Round($altReturn, 2)
        btc_return = [math]::Round($btcReturn, 2)
        rs         = [math]::Round($rs, 2)
        beta       = $Beta
        decoupled  = $decoupled
    }
}

function Get-RsConvictionScore {
    [CmdletBinding()]
    param(
        [double] $Rs,
        [double] $BtcReturn,
        [string] $Direction = "LONG"
    )

    # Direcao-aware: para SHORT, rs negativo eh bom (espelha sinais)
    if ($Direction -eq "SHORT") {
        $effRs  = -$Rs
        $effBtc = -$BtcReturn
    } else {
        $effRs  = $Rs
        $effBtc = $BtcReturn
    }

    # 50 = neutro. Cada 1pct de RS efetivo move 3 pontos.
    $score = 50 + ($effRs * 3)

    # Bonus decoupling: RS forte com BTC parado/contra = sinal idiossincratico puro
    if ($effRs -ge 5 -and $effBtc -le 2) { $score += 10 }

    # Clamp 0..100
    if ($score -gt 100) { $score = 100 }
    if ($score -lt 0)   { $score = 0 }

    [int][math]::Round($score, 0)
}

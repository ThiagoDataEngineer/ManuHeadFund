# lib_trailing_walkforward.ps1 -- Camada de VALIDACAO das politicas de saida.
#
# Walk-forward multi-ativo + teste PAREADO: a MESMA entrada roda em todas as
# politicas, entao o delta (candidate - baseline) isola o efeito da SAIDA,
# controlando a qualidade da entrada (que e ruido comum). Bootstrap CI da o
# veredicto: so e ROBUST se o intervalo de confianca do delta nao cruza zero.
#
# Disciplina (memoria realidade_dura/pericia): nenhuma politica vai live sem
# delta robusto vs ATUAL em amostra grande e nao-sobreposta. PURO. PS 5.1 safe.
# Requer lib_exit_backtest + lib_trailing_policy + lib_trailing_baseline.

function Invoke-WalkForwardExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $CandlesMap,   # ticker -> array de candles
        [string[]] $PolicyNames = @("atual","scalp","swing_long","runner"),
        [string]   $Direction = "LONG",
        [int]      $EntryFrequency = 40,   # >= HoldBars => janelas nao-sobrepostas
        [int]      $HoldBars = 30,
        [double]   $AtrStopMult = 2.0,
        [int]      $AtrPeriod = 14
    )

    $isShort = ($Direction -eq "SHORT")

    # resolve as politicas uma vez
    $pols = @{}
    foreach ($name in $PolicyNames) {
        switch ($name) {
            "atual"       { $pols[$name] = Get-CurrentTrailingPolicy }
            "scalp"       { $pols[$name] = Resolve-ExitPolicy -TradeType "scalp"  -Direction $Direction }
            "swing_long"  { $pols[$name] = Resolve-ExitPolicy -TradeType "swing"  -Direction "LONG" }
            "swing_short" { $pols[$name] = Resolve-ExitPolicy -TradeType "swing"  -Direction "SHORT" }
            "swing"       { $pols[$name] = Resolve-ExitPolicy -TradeType "swing"  -Direction $Direction }
            "runner"      { $pols[$name] = Resolve-ExitPolicy -TradeType "runner" -Direction $Direction }
            default       { $pols[$name] = Resolve-ExitPolicy -TradeType $name    -Direction $Direction }
        }
    }

    $result = @{}
    foreach ($name in $PolicyNames) { $result[$name] = New-Object System.Collections.ArrayList }

    foreach ($ticker in $CandlesMap.Keys) {
        $bars = @($CandlesMap[$ticker])
        if ($bars.Count -lt ($EntryFrequency + $HoldBars + $AtrPeriod)) { continue }

        # ATR
        $atrVals = Get-ATRValues -Candles $bars -Period $AtrPeriod
        for ($i = 0; $i -lt $bars.Count; $i++) { $bars[$i].atr = $atrVals[$i] }

        # entradas nao-sobrepostas
        $idx = [math]::Max($AtrPeriod, $EntryFrequency)
        while ($idx -lt ($bars.Count - $HoldBars - 1)) {
            $e = $bars[$idx]
            if ($e.atr -le 0) { $idx += $EntryFrequency; continue }

            $risk = $e.atr * $AtrStopMult
            $stop = if ($isShort) { $e.close + $risk } else { $e.close - $risk }
            $entrySpec = @{ side = $Direction; entry_price = $e.close; initial_stop = $stop; market = $ticker }

            $endIdx = $idx + $HoldBars
            $post = $bars[($idx + 1)..$endIdx]

            foreach ($name in $PolicyNames) {
                $script:_wf_pol = $pols[$name]
                $fn = { param($ctx) Get-ExitDecision -Policy $script:_wf_pol -Context $ctx }
                $o = Invoke-ExitReplay -Entry $entrySpec -Candles $post -PolicyFn $fn -MaxBars $HoldBars
                [void]$result[$name].Add($o)
            }
            $idx += $EntryFrequency
        }
    }

    # converte ArrayList -> array
    $out = @{}
    foreach ($name in $PolicyNames) { $out[$name] = @($result[$name]) }
    return $out
}


function Get-PairedDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $BaselineOutcomes,
        [Parameter(Mandatory)] [object[]] $CandidateOutcomes,
        [int] $BootstrapIters = 1000,
        [double] $CiAlpha = 0.05,
        [int] $Seed = 42
    )

    $n = [math]::Min($BaselineOutcomes.Count, $CandidateOutcomes.Count)
    if ($n -eq 0) {
        return [PSCustomObject]@{ n=0; mean_delta=0; win_rate=0; ci_low=0; ci_high=0; verdict="NO_DATA" }
    }

    # deltas pareados (candidate - baseline) por indice
    $deltas = New-Object double[] $n
    $wins = 0
    for ($i = 0; $i -lt $n; $i++) {
        $d = [double]$CandidateOutcomes[$i].r - [double]$BaselineOutcomes[$i].r
        $deltas[$i] = $d
        if ($d -gt 0) { $wins++ }
    }
    $meanDelta = ($deltas | Measure-Object -Average).Average

    # bootstrap da media do delta (reamostragem com reposicao)
    $rng = New-Object System.Random($Seed)
    $boots = New-Object double[] $BootstrapIters
    for ($b = 0; $b -lt $BootstrapIters; $b++) {
        $sum = 0.0
        for ($k = 0; $k -lt $n; $k++) {
            $sum += $deltas[$rng.Next($n)]
        }
        $boots[$b] = $sum / $n
    }
    $sortedBoots = @($boots | Sort-Object)
    $loIdx = [int][math]::Floor(($CiAlpha / 2) * $BootstrapIters)
    $hiIdx = [int][math]::Ceiling((1 - $CiAlpha / 2) * $BootstrapIters) - 1
    if ($loIdx -lt 0) { $loIdx = 0 }
    if ($hiIdx -ge $BootstrapIters) { $hiIdx = $BootstrapIters - 1 }
    $ciLow  = $sortedBoots[$loIdx]
    $ciHigh = $sortedBoots[$hiIdx]

    # veredicto: ROBUST so se o CI inteiro esta acima de zero (melhora confiavel)
    $verdict = if ($ciLow -gt 0) { "ROBUST" }
               elseif ($ciHigh -lt 0) { "PIOR" }
               else { "FRAGIL" }

    return [PSCustomObject]@{
        n          = $n
        mean_delta = [math]::Round($meanDelta, 4)
        win_rate   = [math]::Round($wins / $n, 4)
        ci_low     = [math]::Round($ciLow, 4)
        ci_high    = [math]::Round($ciHigh, 4)
        verdict    = $verdict
    }
}


function Get-PairedDeltaBlocked {
    # Block bootstrap: reamostra BLOCOS (ex: por ativo) com reposicao em vez de
    # entradas individuais. Respeita a correlacao intra-bloco (entradas do mesmo
    # ativo nao sao independentes) -> CI mais honesto que o bootstrap ingenuo.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $BaselineOutcomes,
        [Parameter(Mandatory)] [object[]] $CandidateOutcomes,
        [Parameter(Mandatory)] [string[]] $BlockKeys,    # bloco de cada entrada (mesmo len)
        [int] $BootstrapIters = 1000,
        [double] $CiAlpha = 0.05,
        [int] $Seed = 42
    )

    $n = [math]::Min($BaselineOutcomes.Count, $CandidateOutcomes.Count)
    if ($n -eq 0) { return [PSCustomObject]@{ n=0; n_blocks=0; mean_delta=0; ci_low=0; ci_high=0; verdict="NO_DATA" } }

    # agrupa deltas por bloco
    $byBlock = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $d = [double]$CandidateOutcomes[$i].r - [double]$BaselineOutcomes[$i].r
        $k = [string]$BlockKeys[$i]
        if (-not $byBlock.ContainsKey($k)) { $byBlock[$k] = New-Object System.Collections.ArrayList }
        [void]$byBlock[$k].Add($d)
    }
    $blocks = @($byBlock.Keys)
    $nb = $blocks.Count
    $allDeltas = @($byBlock.Values | ForEach-Object { $_ })
    $meanDelta = ($allDeltas | Measure-Object -Average).Average

    $rng = New-Object System.Random($Seed)
    $boots = New-Object double[] $BootstrapIters
    for ($b = 0; $b -lt $BootstrapIters; $b++) {
        $sum = 0.0; $cnt = 0
        for ($k = 0; $k -lt $nb; $k++) {
            $blk = $byBlock[$blocks[$rng.Next($nb)]]
            foreach ($v in $blk) { $sum += $v; $cnt++ }
        }
        $boots[$b] = if ($cnt -gt 0) { $sum / $cnt } else { 0 }
    }
    $sorted = @($boots | Sort-Object)
    $loIdx = [int][math]::Floor(($CiAlpha/2)*$BootstrapIters)
    $hiIdx = [int][math]::Ceiling((1-$CiAlpha/2)*$BootstrapIters) - 1
    if ($loIdx -lt 0) { $loIdx = 0 }
    if ($hiIdx -ge $BootstrapIters) { $hiIdx = $BootstrapIters - 1 }
    $ciLow = $sorted[$loIdx]; $ciHigh = $sorted[$hiIdx]
    $verdict = if ($ciLow -gt 0) { "ROBUST" } elseif ($ciHigh -lt 0) { "PIOR" } else { "FRAGIL" }

    return [PSCustomObject]@{
        n = $n; n_blocks = $nb
        mean_delta = [math]::Round($meanDelta,4)
        ci_low = [math]::Round($ciLow,4); ci_high = [math]::Round($ciHigh,4)
        verdict = $verdict
    }
}

function Get-CandlesMapFromFiles {
    [CmdletBinding()]
    param(
        [string[]] $Tickers,
        [string]   $Dir = "journal/candles_coinex"
    )
    $map = @{}
    foreach ($t in $Tickers) {
        try {
            $map[$t] = Get-CandlesFromFile -Ticker $t -Dir $Dir
        } catch {
            Write-Warning "Skip $t : $($_.Exception.Message)"
        }
    }
    return $map
}

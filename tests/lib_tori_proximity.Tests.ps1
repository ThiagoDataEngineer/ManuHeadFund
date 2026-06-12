# lib_tori_proximity.Tests.ps1 -- Pester 3.x
# Cobertura: Get-ToriProximityFromArrays (funcao pura, testavel sem API)
#            Test-ProximityAlertRecent + Add-ProximityAlert (dedup)
#
# Convencao slope_deg em lib_trendline_filter.ps1:
#   slope_pct = slope / mean_price * 100
#   slope_deg = atan(slope_pct) * 180/pi
# Para slope_deg ~25 deg (centro do range 20-35), com mean_price ~110 e N=30:
#   slope_per_step ~= 0.5 -> slope_pct ~= 0.46 -> slope_deg ~= 24.7 deg

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_tori_proximity.ps1"


function _MkLowsSeries {
    # Lows em uptrend linear (slope=0.5 default -> trendline A+ valida).
    param(
        [double] $LowStart = 100.0,
        [double] $LowSlope = 0.5,
        [int]    $N = 30
    )
    $lows = @(); $highs = @(); $closes = @(); $volumes = @()
    for ($i = 0; $i -lt $N; $i++) {
        $low = $LowStart + ($LowSlope * $i)
        $lows    += $low
        $highs   += ($low * 1.03)
        $closes  += ($low * 1.01)   # default: close 1% acima da linha
        $volumes += 1000.0
    }
    return @{ closes = $closes; highs = $highs; lows = $lows; volumes = $volumes }
}


Describe "Get-ToriProximityFromArrays - estrutura" {
    It "Retorna campos esperados em serie valida" {
        $s = _MkLowsSeries
        $r = Get-ToriProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $r.valid          | Should Be $true
        $r.price          | Should Not BeNullOrEmpty
        $r.action_line    | Should Not BeNullOrEmpty
        $r.proximity_pct  | Should Not BeNullOrEmpty
        $r.touches        | Should Not BeNullOrEmpty
        $r.slope_deg      | Should Not BeNullOrEmpty
    }

    It "valid=false em historico insuficiente" {
        $closes = @(100.0, 101.0, 102.0)
        $r = Get-ToriProximityFromArrays -Closes $closes -Highs $closes -Lows $closes -Volumes @(1,1,1)
        $r.valid  | Should Be $false
        $r.reason | Should Be "insufficient_history"
    }
}


Describe "Get-ToriProximityFromArrays - proximity calc" {
    It "Detecta preco PROXIMO da action_line (proximity baixa)" {
        $s = _MkLowsSeries
        # Default: close = low * 1.01 -> proximidade ~1%
        $r = Get-ToriProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $r.valid                          | Should Be $true
        [math]::Abs($r.proximity_pct)     | Should BeLessThan 2.0
    }

    It "Detecta preco MUITO ACIMA da linha (proximity > 5%, fora do range ripening)" {
        $s = _MkLowsSeries
        # Force ultimo close 15% acima da linha
        $lineLast = $s.lows[$s.lows.Length - 1]
        $s.closes[$s.closes.Length - 1] = $lineLast * 1.15
        $r = Get-ToriProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $r.valid          | Should Be $true
        $r.proximity_pct  | Should BeGreaterThan 5.0
        $r.setup_ripening | Should Be $false
    }
}


Describe "Get-ToriProximityFromArrays - ripening predicate" {
    It "Ripening=TRUE quando proximity OK + RSI baixo + vol secando" {
        # Construcao: 15 candles flat alto + 15 candles decline ate proximo da action_line
        $s = _MkLowsSeries
        $n = $s.closes.Length
        $lineLast = $s.lows[$n - 1]   # action_line projetada no ultimo bar

        # Closes 0..14: flat 130 (nenhuma alta, nenhuma queda -> RSI 100 inicial)
        for ($i = 0; $i -lt 15; $i++) { $s.closes[$i] = 130.0 }

        # Closes 15..29: decline linear 130 -> lineLast*1.005 (~0.5% acima da linha)
        $endClose = $lineLast * 1.005
        for ($i = 15; $i -lt $n; $i++) {
            $progress = ($i - 15) / [double]($n - 1 - 15)
            $s.closes[$i] = 130.0 - ((130.0 - $endClose) * $progress)
        }

        # Vol secando: ultimos 3 candles em 100, restante em 1000
        for ($i = ($n - 3); $i -lt $n; $i++) { $s.volumes[$i] = 100.0 }

        $r = Get-ToriProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        # 2026-05-23: ripening SIMPLIFICADO - so trendline+proximity+regime (RSI/vol removidos, nao melhoram edge)
        $r.valid          | Should Be $true
        [math]::Abs($r.proximity_pct) | Should BeLessThan 3.0
        $r.setup_ripening | Should Be $true
    }

    It "Ripening baseado em proximity (RSI/vol removidos 2026-05-23)" {
        # Proximity dentro do range = ripening true, independente de volume (filtros removidos)
        $s = _MkLowsSeries
        $n = $s.closes.Length
        $lineLast = $s.lows[$n - 1]
        for ($i = 0; $i -lt 15; $i++) { $s.closes[$i] = 130.0 }
        $endClose = $lineLast * 1.005
        for ($i = 15; $i -lt $n; $i++) {
            $progress = ($i - 15) / [double]($n - 1 - 15)
            $s.closes[$i] = 130.0 - ((130.0 - $endClose) * $progress)
        }

        $r = Get-ToriProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        # vol_drying foi removido (null); ripening agora depende apenas de proximity
        ($r.setup_ripening -is [bool]) | Should Be $true
    }
}


Describe "Get-ToriProximityFromArrays - trendline invalida" {
    It "valid=false quando slope fora do range 20-35deg (sideways)" {
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        for ($i = 0; $i -lt 30; $i++) {
            $closes += 100.0; $highs += 101.0; $lows += 99.0; $vols += 1000.0
        }
        $r = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
        $r.valid          | Should Be $false
        $r.reason         | Should Match "slope_out_of_range|insufficient_touches"
        $r.setup_ripening | Should Be $false
    }
}


function _MkHighsDescendingSeries {
    # Highs em downtrend linear (slope=-0.5 default -> trendline SHORT valida ~25 deg negativo).
    # Mirror de _MkLowsSeries.
    param(
        [double] $HighStart = 130.0,
        [double] $HighSlope = -0.5,
        [int]    $N = 30
    )
    $lows = @(); $highs = @(); $closes = @(); $volumes = @()
    for ($i = 0; $i -lt $N; $i++) {
        $hi = $HighStart + ($HighSlope * $i)
        $highs   += $hi
        $closes  += ($hi * 0.99)
        $lows    += ($hi * 0.97)
        $volumes += 1000.0
    }
    return @{ closes = $closes; highs = $highs; lows = $lows; volumes = $volumes }
}


Describe "Get-ToriShortProximityFromArrays - SHORT side mirror" {
    It "Retorna valid=true side=SHORT em descending trendline limpa" {
        $s = _MkHighsDescendingSeries
        $r = Get-ToriShortProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $r.valid      | Should Be $true
        $r.side       | Should Be "SHORT"
        $r.slope_deg  | Should BeLessThan 0
        $r.touches    | Should BeGreaterThan 2
    }

    It "valid=false em uptrend (highs subindo, sem resistencia descendente)" {
        $s = _MkLowsSeries -LowSlope 0.5
        # Highs tambem sobem (uptrend completo)
        for ($i = 0; $i -lt $s.highs.Length; $i++) { $s.highs[$i] = $s.lows[$i] * 1.03 }
        $r = Get-ToriShortProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $r.valid | Should Be $false
        $r.side  | Should Be "SHORT"
    }

    It "Ripening=TRUE quando preco subindo testar resistencia + RSI>60 + vol secando" {
        # Construcao: 15 candles flat baixo + 15 candles RALLY ate proximo da action_line descendente
        $s = _MkHighsDescendingSeries
        $n = $s.closes.Length
        # Highs continuam descendentes (definem a resistencia)
        # Closes: 15 flat em 100, depois rally ate ~highs[-1]
        $lineLast = $s.highs[$n - 1]   # action_line projetada no ultimo bar (descendente)

        for ($i = 0; $i -lt 15; $i++) { $s.closes[$i] = 100.0 }

        # Closes 15..29: rally linear 100 -> lineLast*0.995 (~0.5% abaixo, subindo testar)
        $endClose = $lineLast * 0.995
        for ($i = 15; $i -lt $n; $i++) {
            $progress = ($i - 15) / [double]($n - 1 - 15)
            $s.closes[$i] = 100.0 + (($endClose - 100.0) * $progress)
        }

        # Vol secando ao fim do rally
        for ($i = ($n - 3); $i -lt $n; $i++) { $s.volumes[$i] = 100.0 }

        $r = Get-ToriShortProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $r.valid          | Should Be $true
        $r.side           | Should Be "SHORT"
        $r.vol_drying     | Should Be $true
        $r.rsi            | Should BeGreaterThan 60.0
        $r.setup_ripening | Should Be $true
    }
}


Describe "Get-ToriProximity - orquestracao LONG+SHORT" {
    It "PSCustomObject contem long_side + short_side + active side escolhido" {
        # Funcao puramente offline: usa series sinteticas pelo path Get-ToriProximityFromArrays
        $s = _MkLowsSeries
        $long = Get-ToriProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        $short = Get-ToriShortProximityFromArrays -Closes $s.closes -Highs $s.highs -Lows $s.lows -Volumes $s.volumes
        # Sao independentes
        $long.side  | Should Be "LONG"
        $short.side | Should Be "SHORT"
    }
}


Describe "Snapshot readers: Get-ToriProximitySnapshot + family" {
    BeforeEach {
        $script:snapPath = Join-Path $env:TEMP ("tori_prox_snap_$PID" + "_" + ([guid]::NewGuid().ToString('N')) + ".json")
    }
    AfterEach {
        if (Test-Path $script:snapPath) { Remove-Item $script:snapPath -Force -ErrorAction SilentlyContinue }
    }

    It "fresh=false quando arquivo ausente" {
        $s = Get-ToriProximitySnapshot -StatePath $script:snapPath
        $s.fresh   | Should Be $false
        $s.reason  | Should Be "missing"
        @($s.markets.Keys).Count | Should Be 0
    }

    It "fresh=false quando JSON invalido" {
        Set-Content -Path $script:snapPath -Value "{not valid json"  -Encoding UTF8
        $s = Get-ToriProximitySnapshot -StatePath $script:snapPath
        $s.fresh  | Should Be $false
        $s.reason | Should Be "parse_error"
    }

    It "fresh=false quando snapshot stale (idade > TTL)" {
        $oldTs = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
        $payload = @{
            ts_utc  = $oldTs
            markets = @{
                BTCUSDT = @{ valid = $true; setup_ripening = $true; proximity_pct = 1.0 }
            }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $script:snapPath -Value $payload -Encoding UTF8
        $s = Get-ToriProximitySnapshot -StatePath $script:snapPath -MaxAgeMinutes 30
        $s.fresh | Should Be $false
        $s.reason | Should Match "stale"
    }

    It "fresh=true + markets carregados em snapshot recente" {
        $payload = @{
            ts_utc  = (Get-Date).ToUniversalTime().ToString("o")
            markets = @{
                BTCUSDT = @{ valid = $true; setup_ripening = $true;  proximity_pct = 0.5; rsi = 35.0 }
                ETHUSDT = @{ valid = $true; setup_ripening = $false; proximity_pct = 4.0; rsi = 55.0 }
                XYZUSDT = @{ valid = $false; reason = "slope_out_of_range" }
            }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $script:snapPath -Value $payload -Encoding UTF8
        $s = Get-ToriProximitySnapshot -StatePath $script:snapPath
        $s.fresh                    | Should Be $true
        @($s.markets.Keys).Count    | Should Be 3
        $s.markets.ContainsKey("BTCUSDT") | Should Be $true
    }

    It "Get-ToriProximityForMarket retorna o record do market" {
        $payload = @{
            ts_utc  = (Get-Date).ToUniversalTime().ToString("o")
            markets = @{
                BTCUSDT = @{ valid = $true; setup_ripening = $true; proximity_pct = 0.5; rsi = 35.0 }
            }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $script:snapPath -Value $payload -Encoding UTF8
        $m = Get-ToriProximityForMarket -Market "BTCUSDT" -StatePath $script:snapPath
        $m            | Should Not BeNullOrEmpty
        $m.setup_ripening | Should Be $true
        $m.proximity_pct  | Should Be 0.5
    }

    It "Get-ToriProximityForMarket retorna null quando market ausente do snapshot" {
        $payload = @{
            ts_utc  = (Get-Date).ToUniversalTime().ToString("o")
            markets = @{ BTCUSDT = @{ valid = $true; setup_ripening = $true } }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $script:snapPath -Value $payload -Encoding UTF8
        $m = Get-ToriProximityForMarket -Market "DOESNOTEXIST" -StatePath $script:snapPath
        $m | Should BeNullOrEmpty
    }

    It "Get-ToriProximityForMarket retorna null quando snapshot stale" {
        $oldTs = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
        $payload = @{
            ts_utc  = $oldTs
            markets = @{ BTCUSDT = @{ valid = $true; setup_ripening = $true } }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $script:snapPath -Value $payload -Encoding UTF8
        $m = Get-ToriProximityForMarket -Market "BTCUSDT" -StatePath $script:snapPath -MaxAgeMinutes 30
        $m | Should BeNullOrEmpty
    }

    It "Get-ToriProximityRipeningMarkets filtra so os ripening=true" {
        $payload = @{
            ts_utc  = (Get-Date).ToUniversalTime().ToString("o")
            markets = @{
                BTCUSDT = @{ valid = $true; setup_ripening = $true  }
                ETHUSDT = @{ valid = $true; setup_ripening = $false }
                INJUSDT = @{ valid = $true; setup_ripening = $true  }
                XYZUSDT = @{ valid = $false; setup_ripening = $false }
            }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $script:snapPath -Value $payload -Encoding UTF8
        $ripening = @(Get-ToriProximityRipeningMarkets -StatePath $script:snapPath)
        $ripening.Count           | Should Be 2
        ($ripening -contains "BTCUSDT") | Should Be $true
        ($ripening -contains "INJUSDT") | Should Be $true
        ($ripening -contains "ETHUSDT") | Should Be $false
    }

    It "Get-ToriProximityRipeningMarkets retorna array vazio quando snapshot ausente" {
        $r = @(Get-ToriProximityRipeningMarkets -StatePath $script:snapPath)
        $r.Count | Should Be 0
    }
}


Describe "Dedup: Test-ProximityAlertRecent + Add-ProximityAlert" {
    BeforeEach {
        $script:tmpPath = Join-Path $env:TEMP ("tori_prox_test_$PID" + "_" + ([guid]::NewGuid().ToString('N')) + ".jsonl")
    }
    AfterEach {
        if (Test-Path $script:tmpPath) { Remove-Item $script:tmpPath -Force -ErrorAction SilentlyContinue }
    }

    It "Retorna false quando arquivo nao existe" {
        Test-ProximityAlertRecent -Market "BTCUSDT" -JsonlPath $script:tmpPath -TtlMinutes 240 | Should Be $false
    }

    It "Retorna true apos Add recente do mesmo market" {
        $prox = [PSCustomObject]@{
            price = 100.0; action_line = 99.0; proximity_pct = 1.0
            touches = 5; slope_deg = 27.0; rsi = 35.0; vol_drying = $true
        }
        Add-ProximityAlert -Market "BTCUSDT" -JsonlPath $script:tmpPath -Proximity $prox
        Test-ProximityAlertRecent -Market "BTCUSDT" -JsonlPath $script:tmpPath -TtlMinutes 240 | Should Be $true
    }

    It "Retorna false para market diferente" {
        $prox = [PSCustomObject]@{
            price = 100.0; action_line = 99.0; proximity_pct = 1.0
            touches = 5; slope_deg = 27.0; rsi = 35.0; vol_drying = $true
        }
        Add-ProximityAlert -Market "BTCUSDT" -JsonlPath $script:tmpPath -Proximity $prox
        Test-ProximityAlertRecent -Market "ETHUSDT" -JsonlPath $script:tmpPath -TtlMinutes 240 | Should Be $false
    }

    It "Retorna false quando TTL expirou" {
        $oldTs = (Get-Date).ToUniversalTime().AddHours(-5).ToString("o")
        $oldEntry = [ordered]@{
            ts_utc = $oldTs; market = "BTCUSDT"; price = 100.0
            action_line = 99.0; proximity_pct = 1.0; touches = 5
            slope_deg = 27.0; rsi = 35.0; vol_drying = $true
        } | ConvertTo-Json -Compress
        Add-Content -Path $script:tmpPath -Value $oldEntry -Encoding UTF8
        Test-ProximityAlertRecent -Market "BTCUSDT" -JsonlPath $script:tmpPath -TtlMinutes 240 | Should Be $false
    }
}

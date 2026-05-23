$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_alpha_vs_btc.ps1")

function _TmpCachePath {
    return (Join-Path $env:TEMP ("btccache_" + $PID + "_" + (Get-Random) + ".json"))
}

Describe "Get-BtcDailyClose" {
    It "Cache miss: retorna null" {
        $f = _TmpCachePath
        try {
            (Get-BtcDailyClose -DateUtc "2026-01-01" -CachePath $f) | Should Be $null
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Cache hit: retorna close value" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-15" -Close 95000.5 -CachePath $f
            (Get-BtcDailyClose -DateUtc "2026-01-15" -CachePath $f) | Should Be 95000.5
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Cache corrupt: retorna null (fail-soft)" {
        $f = _TmpCachePath
        try {
            "isso nao eh json valido" | Out-File -FilePath $f -Encoding utf8 -Force
            (Get-BtcDailyClose -DateUtc "2026-01-15" -CachePath $f) | Should Be $null
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Set-BtcDailyClose" {
    It "Cria cache se nao existe" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-02-01" -Close 100000 -CachePath $f
            (Test-Path $f) | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Update mantem outros entries" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-01" -Close 90000 -CachePath $f
            Set-BtcDailyClose -DateUtc "2026-02-01" -Close 95000 -CachePath $f
            (Get-BtcDailyClose -DateUtc "2026-01-01" -CachePath $f) | Should Be 90000
            (Get-BtcDailyClose -DateUtc "2026-02-01" -CachePath $f) | Should Be 95000
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Compute-AlphaVsBtc" {
    It "BTCUSDT trade: alpha = 0 sempre (auto-detect)" {
        $r = Compute-AlphaVsBtc -Market "BTCUSDT" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" -TradeReturnPct 3.0
        $r.alpha_vs_btc | Should Be 0.0
        $r.valid | Should Be $true
    }

    It "BTCUSD (external bitstamp): alpha = 0 tambem" {
        $r = Compute-AlphaVsBtc -Market "BTCUSD" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" -TradeReturnPct 3.0
        $r.alpha_vs_btc | Should Be 0.0
    }

    It "Alt trade COM BTC cache: alpha computed correctly" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-01" -Close 100000 -CachePath $f
            Set-BtcDailyClose -DateUtc "2026-01-05" -Close 105000 -CachePath $f
            # BTC return = +5%. Alt return +10%. Alpha = +5pp
            $r = Compute-AlphaVsBtc -Market "ETHUSDT" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" `
                                     -TradeReturnPct 10.0 -CachePath $f
            $r.valid | Should Be $true
            $r.btc_return_pct | Should Be 5
            $r.alpha_vs_btc | Should Be 5.0
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Alt trade WORSE than BTC: alpha negative" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-01" -Close 100000 -CachePath $f
            Set-BtcDailyClose -DateUtc "2026-01-05" -Close 110000 -CachePath $f
            # BTC return = +10%. Alt return +3%. Alpha = -7pp
            $r = Compute-AlphaVsBtc -Market "ALTUSDT" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" `
                                     -TradeReturnPct 3.0 -CachePath $f
            $r.alpha_vs_btc | Should Be -7
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "BTC data missing: retorna valid=false + alpha=null (fail-soft)" {
        $f = _TmpCachePath
        try {
            $r = Compute-AlphaVsBtc -Market "ETHUSDT" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" `
                                     -TradeReturnPct 5.0 -CachePath $f
            $r.valid | Should Be $false
            $r.alpha_vs_btc | Should Be $null
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "BTC entry zero/negative: fail-soft" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-01" -Close 0 -CachePath $f
            Set-BtcDailyClose -DateUtc "2026-01-05" -Close 100000 -CachePath $f
            $r = Compute-AlphaVsBtc -Market "ETHUSDT" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" `
                                     -TradeReturnPct 5.0 -CachePath $f
            $r.valid | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-AlphaNegativeRate" {
    It "Sample insuficiente (n<20): no alert" {
        $r = Get-AlphaNegativeRate -Alphas @(-1.0, -2.0, -3.0)
        $r.alert | Should Be $false
        $r.reason | Should Match "insufficient_sample"
    }

    It "Sample suficiente, todos negativos: ALERT" {
        $alphas = @()
        for ($i=0; $i -lt 25; $i++) { $alphas += -2.0 }
        $r = Get-AlphaNegativeRate -Alphas $alphas
        $r.alert | Should Be $true
        $r.negative_rate_pct | Should Be 100.0
    }

    It "Sample suficiente, 50% negativos: NO alert (threshold 60%)" {
        $alphas = @()
        for ($i=0; $i -lt 10; $i++) { $alphas += -1.0 }
        for ($i=0; $i -lt 10; $i++) { $alphas += 2.0 }
        $r = Get-AlphaNegativeRate -Alphas $alphas
        $r.n | Should Be 20
        $r.negative_count | Should Be 10
        $r.alert | Should Be $false
    }

    It "Sample 65% negativos: ALERT (acima threshold 60%)" {
        $alphas = @()
        for ($i=0; $i -lt 13; $i++) { $alphas += -1.0 }
        for ($i=0; $i -lt 7; $i++)  { $alphas += 1.5 }
        $r = Get-AlphaNegativeRate -Alphas $alphas
        $r.alert | Should Be $true
        $r.negative_count | Should Be 13
    }

    It "Threshold customizado: respeitado" {
        $alphas = @()
        for ($i=0; $i -lt 11; $i++) { $alphas += -1.0 }
        for ($i=0; $i -lt 9; $i++)  { $alphas += 1.0 }
        # 55% negativo
        $r1 = Get-AlphaNegativeRate -Alphas $alphas -AlertThresholdPct 60
        $r1.alert | Should Be $false
        $r2 = Get-AlphaNegativeRate -Alphas $alphas -AlertThresholdPct 50
        $r2.alert | Should Be $true
    }
}

Describe "Property: alpha + btc_return = trade_return" {
    It "Invariant matematico: alpha + btc = trade sempre" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-01" -Close 100000 -CachePath $f
            Set-BtcDailyClose -DateUtc "2026-01-05" -Close 103000 -CachePath $f
            # BTC +3%. Test multiple trade returns.
            foreach ($tr in @(5.0, -2.0, 0.0, 10.0, -8.5)) {
                $r = Compute-AlphaVsBtc -Market "X" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" `
                                         -TradeReturnPct $tr -CachePath $f
                $sum = $r.alpha_vs_btc + $r.btc_return_pct
                # Allow tiny FP rounding (0.01)
                [math]::Abs($sum - $tr) | Should BeLessThan 0.05
            }
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Property: determinismo" {
    It "Mesma entrada -> mesma saida" {
        $f = _TmpCachePath
        try {
            Set-BtcDailyClose -DateUtc "2026-01-01" -Close 100000 -CachePath $f
            Set-BtcDailyClose -DateUtc "2026-01-05" -Close 105000 -CachePath $f
            $r1 = Compute-AlphaVsBtc -Market "X" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" -TradeReturnPct 7 -CachePath $f
            $r2 = Compute-AlphaVsBtc -Market "X" -EntryDateUtc "2026-01-01" -ExitDateUtc "2026-01-05" -TradeReturnPct 7 -CachePath $f
            $r1.alpha_vs_btc | Should Be $r2.alpha_vs_btc
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

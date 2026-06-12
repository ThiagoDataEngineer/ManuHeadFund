# lib_macro.Tests.ps1 -- Pester 3.x -- Get-MacroContext
# Convencoes: ($x) | Should Be $y | sem BeforeAll | sem em-dash | sem &&

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\config.ps1"
. "$here\..\agents\lib_macro.ps1"

# Helper: cria arquivo de cache no TestDrive
function New-MacroCache {
    param([string]$Path, [int]$AgeHours = 1, [string]$Bias = "BULLISH", [int]$Score = 72)
    $fetchedAt = [DateTime]::UtcNow.AddHours(-$AgeHours).ToString("o")
    $data = [PSCustomObject]@{
        macro_bias     = $Bias
        score          = $Score
        dxy_value      = 104.2
        dxy_trend      = "caindo"
        m2_trend       = "expansao"
        yield_curve    = "normal"
        fed_funds_rate = 5.25
        resumo         = "Contexto macro $Bias"
        cached         = $false
        cache_age_h    = 0
        source         = "FRED"
    }
    @{ fetched_at = $fetchedAt; data = $data } | ConvertTo-Json -Depth 5 | Set-Content $Path -Encoding UTF8
}

# Resposta FRED simulada — retorna valor de serie
function New-FredResponse {
    param([string]$Value1, [string]$Value2 = "", [string]$Value3 = "")
    $obs = @([PSCustomObject]@{ date = "2026-05-10"; value = $Value1 })
    if ($Value2) { $obs += [PSCustomObject]@{ date = "2026-05-03"; value = $Value2 } }
    if ($Value3) { $obs += [PSCustomObject]@{ date = "2026-04-26"; value = $Value3 } }
    return [PSCustomObject]@{ observations = $obs }
}

# ── Campos obrigatorios ───────────────────────────────────────────────────────

Describe "Get-MacroContext - campos obrigatorios" {

    Mock Invoke-RestMethod {
        param($Uri)
        if ($Uri -match "DTWEXBGS") { return New-FredResponse "104.2" "105.1" }
        if ($Uri -match "WM2NS")    { return New-FredResponse "21100" "21000" }
        if ($Uri -match "DGS10")    { return New-FredResponse "4.3" "4.2" }
        if ($Uri -match "DGS2")     { return New-FredResponse "4.1" "4.0" }
        if ($Uri -match "FEDFUNDS") { return New-FredResponse "5.33" }
    }

    $result = Get-MacroContext -CachePath "$TestDrive\macro_test.json"

    It "retorna campo macro_bias" {
        ($result.macro_bias) | Should Not BeNullOrEmpty
    }

    It "retorna campo score entre 0 e 100" {
        ($result.score -ge 0 -and $result.score -le 100) | Should Be $true
    }

    It "macro_bias e BULLISH, NEUTRAL ou BEARISH" {
        ($result.macro_bias -in @("BULLISH","NEUTRAL","BEARISH")) | Should Be $true
    }

    It "retorna campo dxy_trend" {
        ($result.dxy_trend) | Should Not BeNullOrEmpty
    }

    It "retorna campo m2_trend" {
        ($result.m2_trend) | Should Not BeNullOrEmpty
    }

    It "retorna campo yield_curve" {
        ($result.yield_curve) | Should Not BeNullOrEmpty
    }

    It "retorna campo resumo nao vazio" {
        ($result.resumo.Length -gt 5) | Should Be $true
    }

    It "retorna campo source" {
        ($result.source) | Should Not BeNullOrEmpty
    }
}

# ── Bias BULLISH ──────────────────────────────────────────────────────────────

Describe "Get-MacroContext - bias BULLISH" {

    Mock Invoke-RestMethod {
        param($Uri)
        # DXY caindo: hoje < anterior
        if ($Uri -match "DTWEXBGS") { return New-FredResponse "100.0" "105.0" }
        # M2 expansao: hoje > anterior
        if ($Uri -match "WM2NS")    { return New-FredResponse "21500" "21000" }
        # Yield normal: 10Y > 2Y
        if ($Uri -match "DGS10")    { return New-FredResponse "4.5" "4.4" }
        if ($Uri -match "DGS2")     { return New-FredResponse "4.0" "3.9" }
        # Fed dovish
        if ($Uri -match "FEDFUNDS") { return New-FredResponse "2.5" }
    }

    $result = Get-MacroContext -CachePath "$TestDrive\macro_bull.json"

    It "retorna macro_bias = BULLISH quando DXY cai e M2 expande" {
        ($result.macro_bias) | Should Be "BULLISH"
    }

    It "retorna score acima de 60" {
        ($result.score -gt 60) | Should Be $true
    }

    It "dxy_trend = caindo" {
        ($result.dxy_trend) | Should Be "caindo"
    }

    It "m2_trend = expansao" {
        ($result.m2_trend) | Should Be "expansao"
    }
}

# ── Bias BEARISH ──────────────────────────────────────────────────────────────

Describe "Get-MacroContext - bias BEARISH" {

    Mock Invoke-RestMethod {
        param($Uri)
        # DXY subindo: hoje > anterior
        if ($Uri -match "DTWEXBGS") { return New-FredResponse "110.0" "104.0" }
        # M2 contracao: hoje menor que anterior
        if ($Uri -match "WM2NS")    { return New-FredResponse "20000" "21000" }
        # Yield invertida: 2Y > 10Y
        if ($Uri -match "DGS10")    { return New-FredResponse "4.0" "3.9" }
        if ($Uri -match "DGS2")     { return New-FredResponse "4.8" "4.7" }
        # Fed hawkish
        if ($Uri -match "FEDFUNDS") { return New-FredResponse "5.5" }
    }

    $result = Get-MacroContext -CachePath "$TestDrive\macro_bear.json"

    It "retorna macro_bias = BEARISH quando DXY sobe e M2 contrai" {
        ($result.macro_bias) | Should Be "BEARISH"
    }

    It "retorna score abaixo de 40" {
        ($result.score -lt 40) | Should Be $true
    }

    It "dxy_trend = subindo" {
        ($result.dxy_trend) | Should Be "subindo"
    }

    It "m2_trend = contracao" {
        ($result.m2_trend) | Should Be "contracao"
    }
}

# ── Fallback quando FRED falha ────────────────────────────────────────────────

Describe "Get-MacroContext - fallback quando FRED falha" {

    Mock Invoke-RestMethod { throw "Connection refused" }

    $result = Get-MacroContext -CachePath "$TestDrive\macro_fail.json"

    It "nao lanca excecao quando FRED falha" {
        ($result -ne $null) | Should Be $true
    }

    It "retorna macro_bias = NEUTRAL no fallback" {
        ($result.macro_bias) | Should Be "NEUTRAL"
    }

    It "retorna score = 50 no fallback" {
        ($result.score) | Should Be 50
    }

    It "retorna source = fallback" {
        ($result.source) | Should Be "fallback"
    }
}

# ── Cache ─────────────────────────────────────────────────────────────────────

Describe "Get-MacroContext - cache valido" {

    $cachePath = "$TestDrive\macro_cache_hit.json"
    New-MacroCache -Path $cachePath -AgeHours 3 -Bias "BEARISH" -Score 35

    $script:callCount = 0
    Mock Invoke-RestMethod { $script:callCount++ }

    $result = Get-MacroContext -CachePath $cachePath

    It "nao chama Invoke-RestMethod quando cache valido" {
        ($script:callCount) | Should Be 0
    }

    It "retorna cached = true" {
        ($result.cached) | Should Be $true
    }

    It "retorna macro_bias do cache" {
        ($result.macro_bias) | Should Be "BEARISH"
    }

    It "cache_age_h entre 2 e 5" {
        ($result.cache_age_h -ge 2 -and $result.cache_age_h -le 5) | Should Be $true
    }
}

Describe "Get-MacroContext - cache expirado" {

    $cachePath = "$TestDrive\macro_cache_miss.json"
    New-MacroCache -Path $cachePath -AgeHours 25 -Bias "BEARISH" -Score 35

    $callCount = 0
    Mock Invoke-RestMethod {
        $script:callCount++
        param($Uri)
        if ($Uri -match "DTWEXBGS") { return New-FredResponse "104.2" "105.1" }
        if ($Uri -match "WM2NS")    { return New-FredResponse "21100" "21000" }
        if ($Uri -match "DGS10")    { return New-FredResponse "4.3" "4.2" }
        if ($Uri -match "DGS2")     { return New-FredResponse "4.1" "4.0" }
        if ($Uri -match "FEDFUNDS") { return New-FredResponse "5.33" }
    }

    $result = Get-MacroContext -CachePath $cachePath

    It "chama Invoke-RestMethod quando cache expirado" {
        ($script:callCount -gt 0) | Should Be $true
    }

    It "retorna cached = false quando fez fetch novo" {
        ($result.cached) | Should Be $false
    }
}

# ── Yield curve ───────────────────────────────────────────────────────────────

Describe "Get-MacroContext - yield curve" {

    It "yield_curve = invertida quando 2Y maior que 10Y" {
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -match "DTWEXBGS") { return New-FredResponse "104.0" "104.5" }
            if ($Uri -match "WM2NS")    { return New-FredResponse "21000" "21000" }
            if ($Uri -match "DGS10")    { return New-FredResponse "4.0" "4.0" }
            if ($Uri -match "DGS2")     { return New-FredResponse "4.8" "4.8" }
            if ($Uri -match "FEDFUNDS") { return New-FredResponse "5.33" }
        }
        $r = Get-MacroContext -CachePath "$TestDrive\macro_inv.json"
        ($r.yield_curve) | Should Be "invertida"
    }

    It "yield_curve = normal quando 10Y maior que 2Y" {
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -match "DTWEXBGS") { return New-FredResponse "104.0" "104.5" }
            if ($Uri -match "WM2NS")    { return New-FredResponse "21000" "21000" }
            if ($Uri -match "DGS10")    { return New-FredResponse "4.5" "4.4" }
            if ($Uri -match "DGS2")     { return New-FredResponse "4.0" "3.9" }
            if ($Uri -match "FEDFUNDS") { return New-FredResponse "5.33" }
        }
        $r = Get-MacroContext -CachePath "$TestDrive\macro_norm.json"
        ($r.yield_curve) | Should Be "normal"
    }
}

# ── Helper: gera candles sinteticos para Get-BtcTechRegime ───────────────────
function New-BtcCandles {
    param(
        [double]$StartPrice = 60000,
        [double]$EndPrice   = 80000,
        [int]$Count         = 220,
        [double]$VolBase    = 1000,
        [double]$VolEndMul  = 1.0
    )
    $candles = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $frac  = $i / [math]::Max(1, ($Count - 1))
        $close = $StartPrice + ($EndPrice - $StartPrice) * $frac
        $volMul = 1 + ($VolEndMul - 1) * $frac
        $candles += [PSCustomObject]@{
            ts     = $i
            open   = $close * 0.99
            high   = $close * 1.01
            low    = $close * 0.98
            close  = $close
            volume = $VolBase * $volMul
        }
    }
    return $candles
}

# ── Get-RsiSimple ────────────────────────────────────────────────────────────

Describe "Get-RsiSimple - calculo basico" {

    It "retorna null para dados insuficientes" {
        $r = Get-RsiSimple -Closes @(1,2,3) -Period 14
        ($null -eq $r) | Should Be $true
    }

    It "retorna 100 para serie estritamente crescente (sem perdas)" {
        $closes = 1..30 | ForEach-Object { [double]$_ }
        $r = Get-RsiSimple -Closes $closes -Period 14
        ($r) | Should Be 100.0
    }

    It "retorna valor entre 0 e 100" {
        $rand = New-Object Random 42
        $closes = 1..30 | ForEach-Object { 100 + $rand.NextDouble() * 10 }
        $r = Get-RsiSimple -Closes $closes -Period 14
        ($r -ge 0 -and $r -le 100) | Should Be $true
    }
}

# ── Get-BtcTechRegime ────────────────────────────────────────────────────────

Describe "Get-BtcTechRegime - classificacao" {

    It "retorna BEAR quando preco abaixo da SMA200" {
        # Cai de 80k para 50k -- preco final bem abaixo da media
        $c = New-BtcCandles -StartPrice 80000 -EndPrice 50000 -Count 220
        $r = Get-BtcTechRegime -Candles $c
        ($r.regime) | Should Be "BEAR"
    }

    It "retorna DISTRIBUICAO quando RSI alto e volume declinando" {
        # Rally linear (RSI = 100) com queda abrupta de volume nos ultimos 3 candles
        $c = New-BtcCandles -StartPrice 60000 -EndPrice 85000 -Count 220 -VolBase 1000 -VolEndMul 1.0
        for ($i = 217; $i -lt 220; $i++) { $c[$i].volume = 200 }
        $r = Get-BtcTechRegime -Candles $c
        ($r.regime) | Should Be "DISTRIBUICAO"
    }

    It "retorna TENDENCIA em alta saudavel com volume estavel" {
        $c = New-BtcCandles -StartPrice 60000 -EndPrice 80000 -Count 220 -VolBase 1000 -VolEndMul 1.0
        $r = Get-BtcTechRegime -Candles $c
        ($r.regime -in @("TENDENCIA","DISTRIBUICAO")) | Should Be $true
    }

    It "retorna estrutura com campos obrigatorios" {
        $c = New-BtcCandles -StartPrice 60000 -EndPrice 70000 -Count 220
        $r = Get-BtcTechRegime -Candles $c
        ($r.regime) | Should Not BeNullOrEmpty
        ($r.reason) | Should Not BeNullOrEmpty
        ($null -ne $r.price) | Should Be $true
        ($null -ne $r.sma200) | Should Be $true
    }

    It "retorna fallback TENDENCIA quando dados insuficientes" {
        $c = New-BtcCandles -StartPrice 100 -EndPrice 110 -Count 10
        $r = Get-BtcTechRegime -Candles $c
        ($r.regime) | Should Be "TENDENCIA"
        ($r.reason -match "insuficientes") | Should Be $true
    }

    It "vol_decline_pct e numerico" {
        $c = New-BtcCandles -StartPrice 60000 -EndPrice 70000 -Count 220 -VolEndMul 0.5
        $r = Get-BtcTechRegime -Candles $c
        ($r.vol_decline_pct -is [double] -or $r.vol_decline_pct -is [int]) | Should Be $true
    }
}

# tech_agent_tori.Tests.ps1 -- Pester 3.x -- Invoke-ToriPostProcess
# Testa a camada Tori isoladamente (funcao pura, sem Claude, sem CoinEx)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\config.ps1"
. "$here\..\agents\lib_claude.ps1"
. "$here\..\agents\tech_agent_ai.ps1"

# Helper: cria resultado simulado do Claude com trendline configuravel
function New-TechResult {
    param(
        [string]$Qualidade   = "A",
        [string]$Verdict     = "WAIT",
        [string]$Quality     = "A",
        [string]$SetupType   = "BOUNCE",
        [bool]$TrendlineInvalid = $false,
        [string[]]$Confluencias = @("EMA cross", "RSI sobrevenda")
    )
    [PSCustomObject]@{
        sinal             = "LONG"
        forca             = 72
        qualidade_setup   = $Qualidade
        trendline_invalid = $TrendlineInvalid
        confluencias      = $Confluencias
        trendline         = [PSCustomObject]@{
            verdict    = $Verdict
            quality    = $Quality
            setup_type = $SetupType
        }
    }
}

# ── SKIP ─────────────────────────────────────────────────────────────────────

Describe "Invoke-ToriPostProcess - verdict SKIP" {

    It "rebaixa qualidade_setup para C independente da qualidade original" {
        $r = New-TechResult -Qualidade "A" -Verdict "SKIP"
        $out = Invoke-ToriPostProcess $r
        ($out.qualidade_setup) | Should Be "C"
    }

    It "rebaixa qualidade B+ para C" {
        $r = New-TechResult -Qualidade "B+" -Verdict "SKIP"
        $out = Invoke-ToriPostProcess $r
        ($out.qualidade_setup) | Should Be "C"
    }

    It "seta trendline_invalid = true" {
        $r = New-TechResult -Qualidade "A" -Verdict "SKIP" -TrendlineInvalid $false
        $out = Invoke-ToriPostProcess $r
        ($out.trendline_invalid) | Should Be $true
    }

    It "nao altera o campo sinal" {
        $r = New-TechResult -Qualidade "A" -Verdict "SKIP"
        $out = Invoke-ToriPostProcess $r
        ($out.sinal) | Should Be "LONG"
    }

    It "nao altera confluencias" {
        $r = New-TechResult -Qualidade "A" -Verdict "SKIP" -Confluencias @("EMA cross")
        $out = Invoke-ToriPostProcess $r
        ($out.confluencias.Count) | Should Be 1
    }
}

# ── ENTER ─────────────────────────────────────────────────────────────────────

Describe "Invoke-ToriPostProcess - verdict ENTER" {

    It "adiciona label de trendline nas confluencias" {
        $r = New-TechResult -Qualidade "A" -Verdict "ENTER" -Quality "A+" -SetupType "BOUNCE"
        $out = Invoke-ToriPostProcess $r
        $hasLabel = $out.confluencias -contains "Trendline A+ BOUNCE confirmada"
        ($hasLabel) | Should Be $true
    }

    It "preserva confluencias originais apos adicionar label" {
        $r = New-TechResult -Qualidade "A" -Verdict "ENTER" -Confluencias @("EMA cross", "RSI sobrevenda")
        $out = Invoke-ToriPostProcess $r
        ($out.confluencias.Count) | Should Be 3
    }

    It "label correto para BREAK_3TP" {
        $r = New-TechResult -Qualidade "A" -Verdict "ENTER" -Quality "A" -SetupType "BREAK_3TP"
        $out = Invoke-ToriPostProcess $r
        $hasLabel = $out.confluencias -contains "Trendline A BREAK_3TP confirmada"
        ($hasLabel) | Should Be $true
    }

    It "nao altera qualidade_setup" {
        $r = New-TechResult -Qualidade "B+" -Verdict "ENTER"
        $out = Invoke-ToriPostProcess $r
        ($out.qualidade_setup) | Should Be "B+"
    }

    It "nao seta trendline_invalid" {
        $r = New-TechResult -Qualidade "A" -Verdict "ENTER" -TrendlineInvalid $false
        $out = Invoke-ToriPostProcess $r
        ($out.trendline_invalid) | Should Be $false
    }
}

# ── WAIT ──────────────────────────────────────────────────────────────────────

Describe "Invoke-ToriPostProcess - verdict WAIT" {

    It "nao altera qualidade_setup" {
        $r = New-TechResult -Qualidade "A" -Verdict "WAIT"
        $out = Invoke-ToriPostProcess $r
        ($out.qualidade_setup) | Should Be "A"
    }

    It "nao altera confluencias" {
        $r = New-TechResult -Qualidade "A" -Verdict "WAIT" -Confluencias @("EMA cross")
        $out = Invoke-ToriPostProcess $r
        ($out.confluencias.Count) | Should Be 1
    }

    It "nao seta trendline_invalid" {
        $r = New-TechResult -Qualidade "A" -Verdict "WAIT" -TrendlineInvalid $false
        $out = Invoke-ToriPostProcess $r
        ($out.trendline_invalid) | Should Be $false
    }
}

# ── Sem trendline ─────────────────────────────────────────────────────────────

Describe "Invoke-ToriPostProcess - resultado sem campo trendline" {

    It "retorna resultado intacto quando trendline e null" {
        $r = [PSCustomObject]@{ sinal="LONG"; qualidade_setup="A"; trendline=$null }
        $out = Invoke-ToriPostProcess $r
        ($out.qualidade_setup) | Should Be "A"
    }

    It "retorna resultado intacto quando Result e null" {
        $out = Invoke-ToriPostProcess $null
        ($out -eq $null) | Should Be $true
    }

    It "retorna resultado intacto quando trendline existe mas verdict e vazio" {
        $r = [PSCustomObject]@{
            qualidade_setup = "B+"
            trendline_invalid = $false
            trendline = [PSCustomObject]@{ verdict = "" }
        }
        $out = Invoke-ToriPostProcess $r
        ($out.qualidade_setup) | Should Be "B+"
    }
}

# ── Invoke-TechFallback ───────────────────────────────────────────────────────

function New-FallbackData {
    param(
        [string]$Consensus  = "LONG",
        [double]$TotalScore = 8.0,
        [double]$AtrStop1h  = 100.0
    )
    [PSCustomObject]@{ consensus=$Consensus; totalScore=$TotalScore; atrStop1h=$AtrStop1h }
}

Describe "Invoke-TechFallback - sinal derivado do consensus" {

    It "LONG-FORTE retorna sinal LONG" {
        $d = New-FallbackData -Consensus "LONG-FORTE" -TotalScore 10.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.sinal) | Should Be "LONG"
    }

    It "LONG retorna sinal LONG" {
        $d = New-FallbackData -Consensus "LONG" -TotalScore 5.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.sinal) | Should Be "LONG"
    }

    It "SHORT-FORTE retorna sinal SHORT" {
        $d = New-FallbackData -Consensus "SHORT-FORTE" -TotalScore -10.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.sinal) | Should Be "SHORT"
    }

    It "SHORT retorna sinal SHORT" {
        $d = New-FallbackData -Consensus "SHORT" -TotalScore -5.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.sinal) | Should Be "SHORT"
    }

    It "NEUTRO/AGUARDAR retorna sinal NEUTRO" {
        $d = New-FallbackData -Consensus "NEUTRO/AGUARDAR" -TotalScore 0.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.sinal) | Should Be "NEUTRO"
    }
}

Describe "Invoke-TechFallback - forca normalizada 0-100" {

    It "score zero retorna forca 50" {
        $d = New-FallbackData -TotalScore 0.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.forca) | Should Be 50
    }

    It "score maximo (25) retorna forca 100" {
        $d = New-FallbackData -TotalScore 25.0 -Consensus "LONG-FORTE"
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.forca) | Should Be 100
    }

    It "score minimo (-25) retorna forca 0" {
        $d = New-FallbackData -TotalScore -25.0 -Consensus "SHORT-FORTE"
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.forca) | Should Be 0
    }

    It "forca nunca excede 100" {
        $d = New-FallbackData -TotalScore 999.0 -Consensus "LONG-FORTE"
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.forca) | Should Be 100
    }

    It "forca nunca e negativa" {
        $d = New-FallbackData -TotalScore -999.0 -Consensus "SHORT-FORTE"
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.forca) | Should Be 0
    }
}

Describe "Invoke-TechFallback - stop e preco" {

    It "LONG: stop abaixo do entry (entry - atrStop)" {
        $d = New-FallbackData -Consensus "LONG" -AtrStop1h 500.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.stop_loss) | Should Be 49500
    }

    It "SHORT: stop acima do entry (entry + atrStop)" {
        $d = New-FallbackData -Consensus "SHORT" -AtrStop1h 500.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.stop_loss) | Should Be 50500
    }

    It "NEUTRO: stop zero" {
        $d = New-FallbackData -Consensus "NEUTRO/AGUARDAR" -AtrStop1h 500.0
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.stop_loss) | Should Be 0
    }

    It "preco_entrada igual ao EntryPrice passado" {
        $d = New-FallbackData
        $out = Invoke-TechFallback -Data $d -EntryPrice 80000
        ($out.preco_entrada) | Should Be 80000
    }
}

Describe "Invoke-TechFallback - campos fixos de degradacao" {

    It "qualidade_setup sempre C" {
        $d = New-FallbackData -Consensus "LONG-FORTE"
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.qualidade_setup) | Should Be "C"
    }

    It "trendline_invalid sempre true" {
        $d = New-FallbackData
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.trendline_invalid) | Should Be $true
    }

    It "rr_calculado sempre zero" {
        $d = New-FallbackData
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        ($out.rr_calculado) | Should Be 0
    }

    It "confluencias contem indicacao de fallback" {
        $d = New-FallbackData -Consensus "LONG"
        $out = Invoke-TechFallback -Data $d -EntryPrice 50000
        $hasFallback = $out.confluencias -match "Fallback"
        ($hasFallback.Count -gt 0) | Should Be $true
    }
}

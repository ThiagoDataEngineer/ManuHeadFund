# sub_dollar_precision.Tests.ps1 -- TDD para bug AIUSDT precision em pares sub-dollar
# Pester 3.x compatible -- sem acentos
#
# Bug observado 2026-05-14 (paper trade real):
#   AIUSDT SPOT entry=0.099895, stop_pct=-50%, target_pct=+200%
#     -> stop saiu 0.0149475 (-85% real, 3x mais largo)
#     -> target saiu 0.099685 (alvo INVERTIDO)
#
# Esta suite cobre:
#   1. Calculo correto em pares >= $1 (HYPE-like)
#   2. Calculo correto em pares sub-dollar (AIUSDT, sub-cent)
#   3. Consistencia SPOT vs FUTURES
#   4. Guardas defensivos (target invertido, stop invertido, desvio >5%)
#   5. Robustez a culture PT-BR (decimal vs comma)

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Globals minimos
$global:COINEX_BASE_URL        = "https://api.coinex.com"
$global:CAPITAL_FUTURES        = 1000.0
$global:CAPITAL_SPOT           = 300.0
$global:CAPITAL_TOTAL          = 1300.0
$global:GEM_SCORE_MIN_DISC     = 70
$global:GEM_SCORE_MIN_MOM      = 60
$global:GEM_CAPITAL_DISCOVERY  = 0.002
$global:GEM_CAPITAL_MOMENTUM   = 0.004
$global:GEM_STOP_DISCOVERY     = 0.50
$global:GEM_STOP_MOMENTUM      = 0.30
$global:GEM_TARGET_DISCOVERY   = 2.00
$global:GEM_TARGET_MOMENTUM    = 0.90
$global:GEM_MAX_DAYS_DISC      = 30
$global:GEM_MAX_DAYS_MOM       = 21
$global:GEM_TRAILING_PCT       = 0.30
$global:COINEX_FEE_ROUNDTRIP_FALLBACK = 0.0008

function CoinEx-Post { param($path, $body) }

. (Join-Path $agentsDir "gem_executor.ps1")

# Re-set journal dir
$global:JOURNAL_DIR  = Join-Path $env:TEMP "gem_sub_dollar_test_$((Get-Random).ToString())"
$global:JOURNAL_FILE = Join-Path $global:JOURNAL_DIR "gem_signals.csv"
New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null

Describe "Calculate-StopTarget -- formula nuclear" {

    Context "Par caro tipo HYPE (\$44) -- DEVE preservar comportamento atual" {
        It "Stop em par \$44 com stop_pct=0.50 LONG = 22.23" {
            $r = Calculate-StopTarget -Entry 44.46 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            [math]::Round($r.stop_price, 2) | Should Be 22.23
        }

        It "Target em par \$44 com target_pct=2.00 LONG = 133.38" {
            $r = Calculate-StopTarget -Entry 44.46 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            [math]::Round($r.target_price, 2) | Should Be 133.38
        }
    }

    Context "Par sub-dollar tipo AIUSDT (\$0.099895) -- REPRODUZ BUG" {
        It "Stop em par \$0.10 com stop_pct=0.50 LONG = 0.0499475 (NAO 0.0149475)" {
            $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.stop_price | Should Be 0.0499475
        }

        It "Target em par \$0.10 com target_pct=2.00 LONG = 0.299685 (NAO 0.099685)" {
            $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.target_price | Should Be 0.299685
        }

        It "Stop em par sub-cent \$0.001 com stop_pct=0.50 LONG = 0.0005" {
            $r = Calculate-StopTarget -Entry 0.001 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.stop_price | Should Be 0.0005
        }

        It "Target em par sub-cent \$0.001 com target_pct=2.00 LONG = 0.003" {
            $r = Calculate-StopTarget -Entry 0.001 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.target_price | Should Be 0.003
        }

        It "Stop em par micro \$0.00001234 com stop_pct=0.30 LONG calcula corretamente" {
            $r = Calculate-StopTarget -Entry 0.00001234 -StopPct 0.30 -TargetPct 0.90 -Direction "LONG"
            # entry * 0.7 = 0.000008638
            [math]::Abs($r.stop_price - 0.000008638) | Should BeLessThan 0.0000001
        }
    }

    Context "Consistencia SPOT vs FUTURES" {
        It "Calculo identico para mesmo entry/pct (formula nao depende de market type)" {
            $a = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $b = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $a.stop_price   | Should Be $b.stop_price
            $a.target_price | Should Be $b.target_price
        }
    }

    Context "Invariantes geometricos -- LONG" {
        It "Target sempre > Entry quando direction=LONG e target_pct>0" {
            $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.target_price | Should BeGreaterThan 0.099895
        }

        It "Stop sempre < Entry quando direction=LONG e stop_pct>0" {
            $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.stop_price | Should BeLessThan 0.099895
        }

        It "Target sempre > Stop em LONG (R:R bem formado)" {
            $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
            $r.target_price | Should BeGreaterThan $r.stop_price
        }
    }

    Context "Guardas defensivas -- robustez" {
        It "Entry <= 0 lanca excecao" {
            { Calculate-StopTarget -Entry 0 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG" } | Should Throw
        }

        It "StopPct fora de (0,1) lanca excecao" {
            { Calculate-StopTarget -Entry 0.10 -StopPct 1.50 -TargetPct 2.00 -Direction "LONG" } | Should Throw
        }

        It "TargetPct negativo em LONG lanca excecao" {
            { Calculate-StopTarget -Entry 0.10 -StopPct 0.50 -TargetPct -0.5 -Direction "LONG" } | Should Throw
        }

        It "Direction invalida lanca excecao" {
            { Calculate-StopTarget -Entry 0.10 -StopPct 0.50 -TargetPct 2.00 -Direction "SIDEWAYS" } | Should Throw
        }
    }

    Context "Culture-invariance -- robustez PT-BR" {
        It "Funciona corretamente sob CurrentCulture=pt-BR" {
            $prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
                $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
                $r.stop_price   | Should Be 0.0499475
                $r.target_price | Should Be 0.299685
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev
            }
        }

        It "Serializa stop_price com ponto decimal (InvariantCulture) mesmo em PT-BR" {
            $prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
                $r = Calculate-StopTarget -Entry 0.099895 -StopPct 0.50 -TargetPct 2.00 -Direction "LONG"
                $r.stop_price_str | Should Be "0.0499475"
                $r.target_price_str | Should Be "0.299685"
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev
            }
        }
    }
}

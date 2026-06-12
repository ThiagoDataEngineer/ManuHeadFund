# orchestrator_setup_calc.Tests.ps1
# TDD strict: Get-SetupForCascade calcula entry/stop/target ANTES da cascade.
# Bug residual (2026-05-16 02:40): Mentor vetava 100% porque recebia zeros.
# Fix: orchestrator preenche setup real via current price + ATR-proxy.
# UTF-8 BOM. Pester 3.x.

# Stub para nao chamar CoinEx real
function CoinEx-GetTicker { param([string]$Market) return @{ last = "100.00"; change_rate = "0.05" } }

# Extrai funcao do orchestrator_v6 sem dot-source completo
$orchPath = "$PSScriptRoot\..\agents\orchestrator_v6.ps1"
$content = Get-Content $orchPath -Raw
if ($content -match '(?ms)(^function Get-SetupForCascade\s*\{.*?^\})') {
    Invoke-Expression $matches[1]
}

Describe "Get-SetupForCascade - calcula entry/stop/target via price + change" {

    Context "LONG direction" {
        It "entry = current price" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 100.0 -Change24h 5.0
            $s.entry | Should Be 100.0
        }

        It "stop abaixo do entry para LONG (stop_pct min 2%)" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 100.0 -Change24h 5.0
            ($s.stop -lt $s.entry) | Should Be $true
            # stop_pct = max(2%, |change|*0.5) = max(2, 2.5) = 2.5% -> stop=97.5
            $s.stop | Should Be 97.5
        }

        It "target acima do entry, R:R = 5" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 100.0 -Change24h 5.0
            ($s.target -gt $s.entry) | Should Be $true
            # stop_dist = 2.5; target_dist = 2.5 * 5 = 12.5; target = 112.5
            $s.target | Should Be 112.5
            $s.rr | Should Be 5.0
        }

        It "respeita stop minimo 2% mesmo com change pequeno" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 100.0 -Change24h 0.5
            # |0.5|*0.5 = 0.25 < 2.0 floor -> usa 2%
            $s.stop | Should Be 98.0
            $s.target | Should Be 110.0
        }
    }

    Context "SHORT direction" {
        It "entry = current price" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "SHORT" -Price 100.0 -Change24h 5.0
            $s.entry | Should Be 100.0
        }

        It "stop ACIMA do entry para SHORT" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "SHORT" -Price 100.0 -Change24h 5.0
            ($s.stop -gt $s.entry) | Should Be $true
            $s.stop | Should Be 102.5
        }

        It "target ABAIXO do entry, RR 5" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "SHORT" -Price 100.0 -Change24h 5.0
            ($s.target -lt $s.entry) | Should Be $true
            $s.target | Should Be 87.5
        }
    }

    Context "Edge cases" {
        It "Direction NEUTRO/desconhecido retorna placeholder zerado" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "NEUTRO" -Price 100.0 -Change24h 5.0
            $s.entry | Should Be 0
            $s.stop | Should Be 0
            $s.target | Should Be 0
        }

        It "Price <= 0 retorna placeholder zerado" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 0 -Change24h 5.0
            $s.entry | Should Be 0
        }

        It "Change extremo: stop_pct cap em 8%" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 100.0 -Change24h 50.0
            # |50|*0.5 = 25, cap em 8% -> stop=92
            $s.stop | Should Be 92.0
        }

        It "retorna PSCustomObject com 4 campos" {
            $s = Get-SetupForCascade -Market "BTC" -Direction "LONG" -Price 100.0 -Change24h 5.0
            $names = $s.PSObject.Properties.Name
            ($names -contains "entry") | Should Be $true
            ($names -contains "stop") | Should Be $true
            ($names -contains "target") | Should Be $true
            ($names -contains "rr") | Should Be $true
        }
    }
}

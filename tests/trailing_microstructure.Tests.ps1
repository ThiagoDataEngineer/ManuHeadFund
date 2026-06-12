# trailing_microstructure.Tests.ps1
# TDD para Camada 4: Microstructure (OI, funding, whales)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$libPath = Join-Path (Join-Path $projectRoot "agents") "lib_trailing_microstructure.ps1"
if (Test-Path $libPath) { . $libPath }

Describe "Trailing Microstructure - Camada 4" {

    Context "Test-OiDivergence - OI cai enquanto preco sobe (LONG warning)" {
        It "Preco em HH com OI caindo = divergencia bearish" {
            $priceHistory = @(100, 102, 105)  # subindo
            $oiHistory = @(1000, 950, 900)    # caindo
            Test-OiDivergence -PriceHistory $priceHistory -OiHistory $oiHistory -Side "LONG" | Should Be $true
        }
        It "Preco e OI subindo = sem divergencia" {
            $priceHistory = @(100, 102, 105)
            $oiHistory = @(1000, 1050, 1100)
            Test-OiDivergence -PriceHistory $priceHistory -OiHistory $oiHistory -Side "LONG" | Should Be $false
        }
        It "Preco caindo e OI subindo em SHORT = divergencia (vendedores fortes)" {
            $priceHistory = @(105, 102, 100)
            $oiHistory = @(1000, 1050, 1100)
            Test-OiDivergence -PriceHistory $priceHistory -OiHistory $oiHistory -Side "SHORT" | Should Be $false
        }
        It "Dados insuficientes (< 3 pontos) retorna false" {
            Test-OiDivergence -PriceHistory @(100,101) -OiHistory @(1000,990) -Side "LONG" | Should Be $false
        }
    }

    Context "Test-FundingFlip - funding rate mudando de direcao" {
        It "LONG com funding flip positivo->negativo = vendedores agressivos" {
            $fundingHistory = @(0.01, 0.005, -0.002, -0.01)  # positivo -> negativo
            Test-FundingFlip -FundingHistory $fundingHistory -Side "LONG" | Should Be $true
        }
        It "LONG com funding consistentemente positivo = saudavel" {
            $fundingHistory = @(0.01, 0.012, 0.015, 0.013)
            Test-FundingFlip -FundingHistory $fundingHistory -Side "LONG" | Should Be $false
        }
        It "SHORT com funding negativo->positivo = compradores agressivos (warning)" {
            $fundingHistory = @(-0.01, -0.005, 0.002, 0.01)
            Test-FundingFlip -FundingHistory $fundingHistory -Side "SHORT" | Should Be $true
        }
        It "Dados insuficientes (<4 pontos) retorna false" {
            Test-FundingFlip -FundingHistory @(0.01,-0.01) -Side "LONG" | Should Be $false
        }
    }

    Context "Get-MicrostructureScore - score combinado" {
        It "Sem sinais retorna 0" {
            $r = Get-MicrostructureScore `
                -PriceHistory @(100,100,100) `
                -OiHistory @(1000,1000,1000) `
                -FundingHistory @(0.01,0.01,0.01,0.01) `
                -Side "LONG"
            $r | Should Be 0
        }
        It "OI divergence + funding flip = score alto (>50)" {
            $r = Get-MicrostructureScore `
                -PriceHistory @(100,102,105) `
                -OiHistory @(1000,950,900) `
                -FundingHistory @(0.01,0.005,-0.002,-0.01) `
                -Side "LONG"
            $r | Should BeGreaterThan 50
        }
    }
}

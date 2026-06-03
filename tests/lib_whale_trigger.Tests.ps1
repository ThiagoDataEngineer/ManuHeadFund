# lib_whale_trigger.Tests.ps1 -- TDD da conviccao do whale producer.
#
# Get-WhaleConviction mapeia tamanho da whale TX (BTC) -> 0-100 (log-scaled).
# Whales pequenas caem abaixo do limiar (70) e nao disparam trigger (gate custo).
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_whale_watcher.ps1")


Describe "Get-WhaleConviction" {
    It "100 BTC -> 70 (baseline whale)" {
        Get-WhaleConviction -ValueBtc 100 | Should Be 70
    }
    It "~1000 BTC -> 100 (cap superior)" {
        Get-WhaleConviction -ValueBtc 1000 | Should Be 100
    }
    It "~316 BTC -> ~85 (meio da escala log)" {
        Get-WhaleConviction -ValueBtc 316.23 | Should Be 85
    }
    It "valor enorme satura em 100" {
        Get-WhaleConviction -ValueBtc 50000 | Should Be 100
    }
    It "whale pequena (50 BTC) cai abaixo do limiar 70" {
        (Get-WhaleConviction -ValueBtc 50) -lt 70 | Should Be $true
    }
    It "monotonico: maior valor >= menor" {
        (Get-WhaleConviction -ValueBtc 500) -ge (Get-WhaleConviction -ValueBtc 200) | Should Be $true
    }
    It "valor invalido (<=0) retorna 0" {
        Get-WhaleConviction -ValueBtc 0 | Should Be 0
    }
}

# trailing_sync_exchange.Tests.ps1 -- TDD do sync journal->corretora (empurra SL real)
# Elo que faltava: trailing REGISTRAVA mas nao EXECUTAVA. Agora empurra a SL.
# SEGURANCA: nunca empurra SL que ja dispararia (fecharia a mercado).
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_trailing_sync.ps1"

Describe "Resolve-TrailingSync (decisao pura)" {

    Context "LONG" {

        It "empurra quando melhora E e seguro (nao dispara)" {
            $r = Resolve-TrailingSync -Side "LONG" -CurrentPrice 80 -JournalStop 76 -ExchangeStop 70
            $r.should_push | Should Be $true
            $r.new_sl | Should Be 76
        }

        It "HYPE: NAO empurra breakeven que ja dispararia (mantem posicao)" {
            # SL journal 74.65 (breakeven) > preco atual 72.49 -> fecharia a mercado
            $r = Resolve-TrailingSync -Side "LONG" -CurrentPrice 72.49 -JournalStop 74.65 -ExchangeStop 68.67
            $r.should_push | Should Be $false
            $r.reason | Should Match "dispararia|trigger|acima"
        }

        It "NAO empurra se nao melhora (journal <= corretora)" {
            $r = Resolve-TrailingSync -Side "LONG" -CurrentPrice 80 -JournalStop 67 -ExchangeStop 68.67
            $r.should_push | Should Be $false
        }

        It "NAO empurra se igual" {
            $r = Resolve-TrailingSync -Side "LONG" -CurrentPrice 80 -JournalStop 70 -ExchangeStop 70
            $r.should_push | Should Be $false
        }
    }

    Context "SHORT (espelhado)" {

        It "empurra quando melhora (SL desce) E e seguro" {
            $r = Resolve-TrailingSync -Side "SHORT" -CurrentPrice 90 -JournalStop 95 -ExchangeStop 108
            $r.should_push | Should Be $true
            $r.new_sl | Should Be 95
        }

        It "NAO empurra SL que ja dispararia (abaixo do preco)" {
            # SHORT: SL 95 < preco 96 -> dispararia
            $r = Resolve-TrailingSync -Side "SHORT" -CurrentPrice 96 -JournalStop 95 -ExchangeStop 108
            $r.should_push | Should Be $false
        }

        It "NAO empurra se nao melhora (journal >= corretora)" {
            $r = Resolve-TrailingSync -Side "SHORT" -CurrentPrice 90 -JournalStop 110 -ExchangeStop 108
            $r.should_push | Should Be $false
        }
    }

    Context "Robustez" {

        It "stop journal <= 0 = nao empurra" {
            $r = Resolve-TrailingSync -Side "LONG" -CurrentPrice 80 -JournalStop 0 -ExchangeStop 70
            $r.should_push | Should Be $false
        }
    }
}

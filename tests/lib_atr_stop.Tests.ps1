# lib_atr_stop.Tests.ps1 -- Pester 3.x
# ATR stop obrigatorio (Soros guardrail).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_atr_stop.ps1"


Describe "Get-AtrStop - LONG direction" {
    It "Entry 100 ATR 2 mult 2 LONG retorna 96" {
        $s = Get-AtrStop -Entry 100 -Atr 2 -Direction "long" -Multiplier 2.0
        $s | Should Be 96
    }

    It "Entry 100 ATR 5 mult 1.5 LONG retorna 92.5" {
        $s = Get-AtrStop -Entry 100 -Atr 5 -Direction "long" -Multiplier 1.5
        $s | Should Be 92.5
    }
}


Describe "Get-AtrStop - SHORT direction" {
    It "Entry 100 ATR 2 mult 2 SHORT retorna 104" {
        $s = Get-AtrStop -Entry 100 -Atr 2 -Direction "short" -Multiplier 2.0
        $s | Should Be 104
    }
}


Describe "Get-AtrStop - validacoes" {
    It "ATR zero retorna entry (proteje contra div zero)" {
        $s = Get-AtrStop -Entry 100 -Atr 0 -Direction "long" -Multiplier 2.0
        $s | Should Be 100
    }

    It "Direction invalido tira excecao" {
        { Get-AtrStop -Entry 100 -Atr 2 -Direction "sideways" -Multiplier 2.0 } | Should Throw
    }
}


Describe "Get-AtrFromHighLow - calculo simplificado" {
    It "Highs/Lows constantes retorna diferenca media" {
        $highs = @(102, 102, 102, 102, 102, 102, 102, 102, 102, 102, 102, 102, 102, 102)
        $lows  = @(98, 98, 98, 98, 98, 98, 98, 98, 98, 98, 98, 98, 98, 98)
        $atr = Get-AtrFromHighLow -Highs $highs -Lows $lows -Period 14
        $atr | Should Be 4
    }

    It "Dados insuficientes retorna 0" {
        $highs = @(102, 102)
        $lows  = @(98, 98)
        $atr = Get-AtrFromHighLow -Highs $highs -Lows $lows -Period 14
        $atr | Should Be 0
    }
}

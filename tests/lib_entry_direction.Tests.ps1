# lib_entry_direction.Tests.ps1 -- Pester 3.x
# TDD 2026-06-24: cerebro bidirecional. "Se aparecer LONG bom atua, se SHORT bom atua."
# Decide o LADO com edge = scenario (allow_long/short) X conviccao de cada lado.
# Nunca opera contra o cenario. SKIP quando nenhum lado tem edge suficiente.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_entry_direction.ps1")

Describe "Resolve-EntryDirection - escolhe o lado com edge" {
    It "Bull + LONG forte -> LONG" {
        $r = Resolve-EntryDirection -AllowLong $true -AllowShort $false -LongConviction 80 -ShortConviction 20 -MinConviction 60
        $r.direction | Should Be "LONG"; $r.act | Should Be $true
    }
    It "Bear + SHORT forte -> SHORT (lucra na queda)" {
        $r = Resolve-EntryDirection -AllowLong $false -AllowShort $true -LongConviction 15 -ShortConviction 78 -MinConviction 60
        $r.direction | Should Be "SHORT"; $r.act | Should Be $true
    }
    It "Bear mas SHORT fraco (<min) -> SKIP (sem edge, fica em caixa)" {
        $r = Resolve-EntryDirection -AllowLong $false -AllowShort $true -LongConviction 10 -ShortConviction 45 -MinConviction 60
        $r.act | Should Be $false; $r.direction | Should Be "SKIP"
    }
    It "Bull mas SHORT seria maior -> NAO shorta contra o cenario (LONG fraco -> SKIP)" {
        $r = Resolve-EntryDirection -AllowLong $true -AllowShort $false -LongConviction 40 -ShortConviction 90 -MinConviction 60
        $r.act | Should Be $false   # short nao permitido pelo cenario, long fraco
    }
    It "Capitulacao (allow_long) + LONG forte -> LONG (compra o fundo)" {
        $r = Resolve-EntryDirection -AllowLong $true -AllowShort $false -LongConviction 72 -ShortConviction 30 -MinConviction 60
        $r.direction | Should Be "LONG"; $r.act | Should Be $true
    }
    It "Neutro (nenhum lado permitido) -> SKIP" {
        $r = Resolve-EntryDirection -AllowLong $false -AllowShort $false -LongConviction 90 -ShortConviction 90 -MinConviction 60
        $r.act | Should Be $false
    }
    It "Ambos permitidos -> pega o lado de MAIOR conviccao" {
        (Resolve-EntryDirection -AllowLong $true -AllowShort $true -LongConviction 65 -ShortConviction 80 -MinConviction 60).direction | Should Be "SHORT"
        (Resolve-EntryDirection -AllowLong $true -AllowShort $true -LongConviction 85 -ShortConviction 70 -MinConviction 60).direction | Should Be "LONG"
    }
}

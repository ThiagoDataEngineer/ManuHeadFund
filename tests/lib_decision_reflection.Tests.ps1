$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_decision_reflection.ps1")

function _TmpPath {
    return (Join-Path $env:TEMP ("refl_" + $PID + "_" + (Get-Random) + ".jsonl"))
}

Describe "Add-PendingReflection" {
    It "Cria entry pending pra trade novo" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "T1" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" `
                -MentorVeredicto "EXECUTAR" -MentorConfidence 75 `
                -MentorMensagem "Setup decent" -MesaSinal "LONG" -Tier "A_LIVE" `
                -ReflectionsPath $f
            (Test-Path $f) | Should Be $true
            $content = @(Get-Content $f -Encoding UTF8)
            $content.Count | Should Be 1
            $obj = $content[0] | ConvertFrom-Json
            $obj.trade_id | Should Be "T1"
            $obj.status | Should Be "pending"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Idempotente: nao duplica mesmo trade_id" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "T2" -Market "ETHUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
            Add-PendingReflection -TradeId "T2" -Market "ETHUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
            $content = @(Get-Content $f -Encoding UTF8)
            $content.Count | Should Be 1
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-PendingReflections" {
    It "Cache vazio: retorna lista vazia" {
        $f = _TmpPath
        try {
            $r = Get-PendingReflections -ReflectionsPath $f
            $r.Count | Should Be 0
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Trade so com pending: aparece em pending list" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "T3" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
            $r = Get-PendingReflections -ReflectionsPath $f
            $r.Count | Should Be 1
            $r[0].trade_id | Should Be "T3"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Trade com resolved: NAO aparece em pending" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "T4" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "T4" -ExitDateUtc "2026-05-25" -PnlPct 3.2 -AlphaVsBtc 1.1 `
                -HoldingDays 3 -Reflection "Bull thesis held" -ReflectionsPath $f
            $r = Get-PendingReflections -ReflectionsPath $f
            $r.Count | Should Be 0
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Multiplos trades: separa pending vs resolved corretamente" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "P1" -Market "BTCUSDT" -EntryDateUtc "2026-05-20" -ReflectionsPath $f
            Add-PendingReflection -TradeId "P2" -Market "ETHUSDT" -EntryDateUtc "2026-05-21" -ReflectionsPath $f
            Add-PendingReflection -TradeId "R1" -Market "RENDERUSDT" -EntryDateUtc "2026-05-19" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "R1" -ExitDateUtc "2026-05-22" -PnlPct 5 -ReflectionsPath $f
            $pending = Get-PendingReflections -ReflectionsPath $f
            $pending.Count | Should Be 2
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Add-ResolvedReflection" {
    It "Append resolved entry preservando alpha_vs_btc null" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "T5" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "T5" -ExitDateUtc "2026-05-25" -PnlPct 2.0 -AlphaVsBtc $null `
                -HoldingDays 3 -Reflection "alpha n/a" -ReflectionsPath $f
            $content = Get-Content $f -Encoding UTF8
            $content.Count | Should Be 2  # pending + resolved
            $resolved = $content[1] | ConvertFrom-Json
            $resolved.status | Should Be "resolved"
            $resolved.alpha_vs_btc | Should Be $null
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-PriorReflectionsForMarket" {
    It "Sem reflections market match: retorna vazio" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "X1" -Market "BTCUSDT" -EntryDateUtc "2026-05-20" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "X1" -ExitDateUtc "2026-05-22" -PnlPct 2 -Reflection "x" -ReflectionsPath $f
            $r = Get-PriorReflectionsForMarket -Market "ETHUSDT" -ReflectionsPath $f
            $r.Count | Should Be 0
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Retorna apenas resolved do market alvo" {
        $f = _TmpPath
        try {
            Add-PendingReflection -TradeId "B1" -Market "BTCUSDT" -EntryDateUtc "2026-05-20" -MentorVeredicto "EXECUTAR" -MentorConfidence 70 -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "B1" -ExitDateUtc "2026-05-22" -PnlPct 3.2 -AlphaVsBtc 1.1 -HoldingDays 2 -Reflection "Bull held" -ReflectionsPath $f
            Add-PendingReflection -TradeId "B2" -Market "BTCUSDT" -EntryDateUtc "2026-05-23" -MentorVeredicto "EXECUTAR" -MentorConfidence 80 -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "B2" -ExitDateUtc "2026-05-24" -PnlPct -1 -AlphaVsBtc -2 -HoldingDays 1 -Reflection "Loss thesis broken" -ReflectionsPath $f
            Add-PendingReflection -TradeId "E1" -Market "ETHUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "E1" -ExitDateUtc "2026-05-23" -PnlPct 5 -Reflection "ETH" -ReflectionsPath $f

            $r = Get-PriorReflectionsForMarket -Market "BTCUSDT" -ReflectionsPath $f
            $r.Count | Should Be 2
            ($r | ForEach-Object { $_.market } | Sort-Object -Unique) | Should Be "BTCUSDT"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Limita ao MaxN" {
        $f = _TmpPath
        try {
            for ($i = 1; $i -le 10; $i++) {
                Add-PendingReflection -TradeId "T$i" -Market "BTCUSDT" -EntryDateUtc "2026-05-$($i+9)" -ReflectionsPath $f
                Add-ResolvedReflection -TradeId "T$i" -ExitDateUtc "2026-05-$($i+10)" -PnlPct ($i/2) -Reflection "lesson $i" -ReflectionsPath $f
                Start-Sleep -Milliseconds 5  # garante ordering distinct
            }
            $r = Get-PriorReflectionsForMarket -Market "BTCUSDT" -MaxN 3 -ReflectionsPath $f
            $r.Count | Should Be 3
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Format-PriorReflectionsBlock" {
    It "Vazio: retorna string vazia" {
        Format-PriorReflectionsBlock -Reflections @() | Should Be ""
    }

    It "Format bem-formado com PRIOR/END markers" {
        $r = @(
            [PSCustomObject]@{
                entry_date_utc="2026-05-20"; mentor_veredicto="EXECUTAR"; mentor_confidence=70
                pnl_pct=3.2; alpha_vs_btc=1.1; holding_days=2; reflection="Bull held"
            }
        )
        $block = Format-PriorReflectionsBlock -Reflections $r
        $block | Should Match "PRIOR RESOLVED"
        $block | Should Match "END PRIOR"
        $block | Should Match "Bull held"
        $block | Should Match "3.2%"
        $block | Should Match "alpha 1.1pp"
    }

    It "Alpha null: shows 'alpha n/a'" {
        $r = @(
            [PSCustomObject]@{
                entry_date_utc="2026-05-20"; mentor_veredicto="EXECUTAR"; mentor_confidence=70
                pnl_pct=3.2; alpha_vs_btc=$null; holding_days=2; reflection="Lesson"
            }
        )
        $block = Format-PriorReflectionsBlock -Reflections $r
        $block | Should Match "alpha n/a"
    }
}

Describe "Property: Add/Get cycle determinism" {
    It "Mesma sequencia de Add resulta em mesmo Get" {
        $f1 = _TmpPath; $f2 = _TmpPath
        try {
            foreach ($f in @($f1, $f2)) {
                Add-PendingReflection -TradeId "D1" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" -ReflectionsPath $f
                Add-ResolvedReflection -TradeId "D1" -ExitDateUtc "2026-05-25" -PnlPct 3 -Reflection "test" -ReflectionsPath $f
            }
            $r1 = Get-PriorReflectionsForMarket -Market "BTCUSDT" -ReflectionsPath $f1
            $r2 = Get-PriorReflectionsForMarket -Market "BTCUSDT" -ReflectionsPath $f2
            $r1.Count | Should Be $r2.Count
            $r1[0].pnl_pct | Should Be $r2[0].pnl_pct
        } finally {
            if (Test-Path $f1) { Remove-Item $f1 -Force }
            if (Test-Path $f2) { Remove-Item $f2 -Force }
        }
    }
}

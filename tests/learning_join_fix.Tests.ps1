# learning_join_fix.Tests.ps1 (Pester 3.x)
# TDD #1: conserta o join snapshot<->outcome do motor de aprendizado.
#
# Bug original: snapshots tem `ts` (ISO) mas NAO `entry_date` nem `trade_id`,
# entao Join-SignalOutcomes casava 0 de 1186 -> learned_multipliers.json = lixo.
#
# Fix: (a) Get-SnapshotDate deriva data de entry_date OU ts;
#      (b) New-SignalSnapshot grava entry_date;
#      (c) Join-SignalOutcomes casa por market+data (tolerancia +-1 dia),
#          so para snapshots APROVAR, carregando win/pnl do outcome.

$here = Split-Path $MyInvocation.MyCommand.Path
$root = Split-Path $here -Parent
. (Join-Path $root "agents\lib_direction_learning.ps1")

Describe "Get-SnapshotDate (PURA)" {
    It "retorna entry_date quando presente" {
        $snap = [PSCustomObject]@{ entry_date="2026-05-24"; ts="2026-06-09T01:25:35Z" }
        Get-SnapshotDate -Snapshot $snap | Should Be "2026-05-24"
    }
    It "deriva data do ts quando entry_date ausente" {
        $snap = [PSCustomObject]@{ ts="2026-06-09T01:25:35.7380740Z" }
        Get-SnapshotDate -Snapshot $snap | Should Be "2026-06-09"
    }
    It "retorna vazio quando nem ts nem entry_date" {
        $snap = [PSCustomObject]@{ market="BTCUSDT" }
        Get-SnapshotDate -Snapshot $snap | Should Be ""
    }
}

Describe "New-SignalSnapshot grava entry_date" {
    It "inclui entry_date derivado do ts" {
        $s = New-SignalSnapshot -Market "BTCUSDT" -Direction "LONG" -Source "regime" `
            -Regime "BULL_WEAK" -Decision "APROVAR" -EntryPrice 65000
        $s.Contains("entry_date") | Should Be $true
        # entry_date deve bater com a porcao de data do ts
        # 2026-07-25 FIX: [datetime]::Parse sem AdjustToUniversal converte
        # o "Z" (UTC) pro horario LOCAL da maquina -- diverge do entry_date
        # (sempre UTC) numa janela de ~3h/dia (21h-00h local = 00h-03h UTC
        # do dia seguinte). Fix: parse preservando UTC explicitamente.
        $tsDate = ([datetime]::Parse($s.ts, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)).ToString("yyyy-MM-dd")
        $s.entry_date | Should Be $tsDate
    }
}

Describe "Join-SignalOutcomes (fix do join)" {

    It "casa por market + data derivada do ts (cenario do bug real)" {
        # snapshot sem trade_id e sem entry_date, so ts — como os 1186 reais
        $snaps = @(
            [PSCustomObject]@{ ts="2026-05-24T14:00:00Z"; trade_id=""; market="SOLUSDT"
                direction="LONG"; source="regime"; regime="BULL_WEAK"; decision="APROVAR"; entry_price=150 }
        )
        $outs = @(
            [PSCustomObject]@{ trade_id="SOLUSDT-20260524-close"; market="SOLUSDT"
                entry_date="2026-05-24"; direction="LONG"; win=$false; pnl_pct=-0.6 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 1
        $joined[0].market  | Should Be "SOLUSDT"
        $joined[0].win     | Should Be $false
        $joined[0].pnl_pct | Should Be -0.6
    }

    It "casa dentro da tolerancia de +-1 dia (fronteira UTC)" {
        $snaps = @(
            [PSCustomObject]@{ ts="2026-05-25T02:00:00Z"; trade_id=""; market="LINKUSDT"
                direction="LONG"; source="regime"; regime="BULL_WEAK"; decision="APROVAR"; entry_price=20 }
        )
        $outs = @(
            [PSCustomObject]@{ trade_id=""; market="LINKUSDT"; entry_date="2026-05-24"
                direction="LONG"; win=$true; pnl_pct=5.0 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 1
        $joined[0].win | Should Be $true
    }

    It "NAO casa mercados diferentes" {
        $snaps = @(
            [PSCustomObject]@{ ts="2026-05-24T14:00:00Z"; trade_id=""; market="SOLUSDT"
                direction="LONG"; source="regime"; regime="BULL_WEAK"; decision="APROVAR"; entry_price=150 }
        )
        $outs = @(
            [PSCustomObject]@{ trade_id=""; market="BTCUSDT"; entry_date="2026-05-24"
                direction="LONG"; win=$true; pnl_pct=5.0 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 0
    }

    It "exclui snapshots VETAR/SKIP (so ENTRADAS reais geram stats)" {
        $snaps = @(
            [PSCustomObject]@{ ts="2026-05-24T14:00:00Z"; trade_id=""; market="SOLUSDT"
                direction="SHORT"; source="regime"; regime="BEAR_STRONG"; decision="VETAR"; entry_price=150 }
        )
        $outs = @(
            [PSCustomObject]@{ trade_id=""; market="SOLUSDT"; entry_date="2026-05-24"
                direction="LONG"; win=$true; pnl_pct=5.0 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 0
    }

    It "ainda casa por trade_id exato (regressao)" {
        $snaps = @(
            [PSCustomObject]@{ ts="2026-05-24T14:00:00Z"; trade_id="SOLUSDT-20260524-close"
                market="SOLUSDT"; direction="LONG"; source="regime"; regime="BULL_WEAK"
                decision="APROVAR"; entry_price=150 }
        )
        $outs = @(
            [PSCustomObject]@{ trade_id="SOLUSDT-20260524-close"; market="SOLUSDT"
                entry_date="2026-05-24"; direction="LONG"; win=$true; pnl_pct=3.2 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 1
        $joined[0].pnl_pct | Should Be 3.2
    }

    It "DEDUP: N snapshots do mesmo trade contam como 1 (effective_n honesto)" {
        # 4 snapshots APROVAR do mesmo XMR em dias adjacentes (4 ciclos de scan),
        # mas e UM unico trade. Deve casar 1 vez, nao 4 (anti-inflacao de n).
        $snaps = @(
            [PSCustomObject]@{ ts="2026-06-11T10:00:00Z"; trade_id=""; market="XMRUSDT"
                direction="LONG"; source="regime"; regime="BULL_STRONG"; decision="APROVAR"; entry_price=376 }
            [PSCustomObject]@{ ts="2026-06-11T11:00:00Z"; trade_id=""; market="XMRUSDT"
                direction="LONG"; source="regime"; regime="BULL_STRONG"; decision="APROVAR"; entry_price=376 }
            [PSCustomObject]@{ ts="2026-06-12T10:00:00Z"; trade_id=""; market="XMRUSDT"
                direction="LONG"; source="regime"; regime="BULL_STRONG"; decision="APROVAR"; entry_price=376 }
            [PSCustomObject]@{ ts="2026-06-12T11:00:00Z"; trade_id=""; market="XMRUSDT"
                direction="LONG"; source="regime"; regime="BULL_STRONG"; decision="APROVAR"; entry_price=376 }
        )
        $outs = @(
            [PSCustomObject]@{ trade_id="XMRUSDT-20260611"; market="XMRUSDT"; entry_date="2026-06-11"
                direction="LONG"; win=$true; pnl_pct=12.08 }
        )
        $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
        $joined.Count | Should Be 1
    }

    It "pipeline real: snapshots+outcomes do journal produzem >0 matches (quando ha overlap temporal)" {
        # 2026-07-23 FIX REAL: Join-SignalOutcomes usava $o.market (outcomes
        # reais tem "symbol", nao "market" -- ver ConvertTo-SupabaseOutcome)
        # e Get-SnapshotDate nao reconhecia entry_ts (so ts/entry_date) --
        # motor de aprendizado direcional NUNCA casava outcomes reais em
        # producao, 0 matches sempre. Corrigido na lib (fallback symbol +
        # entry_ts). Mas os dados REAIS desta maquina agora (snapshots
        # APROVAR de 2026-06-09/11, outcomes de 2026-07-07/19) nao se
        # sobrepoem temporalmente -- sem trades reais fechados no MESMO
        # periodo dos snapshots aprovados, 0 matches e o resultado correto,
        # nao um bug. Teste so valida quando ha overlap real de mercado+data.
        $snaps = @(Read-JsonLines -Path (Join-Path $root "journal\signal_snapshots.jsonl"))
        $outs  = @(Read-JsonLines -Path (Join-Path $root "journal\trade_outcomes.jsonl"))
        if ($snaps.Count -gt 0 -and $outs.Count -gt 0) {
            $approveSnapKeys = @($snaps | Where-Object { "$($_.decision)".ToUpper() -eq "APROVAR" } |
                ForEach-Object { "$($_.market)|$(Get-SnapshotDate -Snapshot $_)" } | Select-Object -Unique)
            $outKeys = @($outs | ForEach-Object {
                $m = if ($_.PSObject.Properties['market'] -and $_.market) { $_.market } else { $_.symbol }
                "$m|$(Get-SnapshotDate -Snapshot $_)"
            } | Select-Object -Unique)
            $hasOverlap = @($approveSnapKeys | Where-Object { $outKeys -contains $_ }).Count -gt 0

            $joined = @(Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs)
            if ($hasOverlap) {
                ($joined.Count -gt 0) | Should Be $true
            } else {
                Write-Host "  [SKIP] sem overlap temporal real entre snapshots APROVAR e outcomes nesta maquina agora" -ForegroundColor Yellow
            }
        }
    }
}

# trade_logger.Tests.ps1 -- Pester 3.x -- Format-TradeLogEntry / Parse-TradeLogEntry
# TDD strict: RED -> GREEN -> REFACTOR
#
# Contrato (lib_trade_logger.ps1):
#   Format-TradeLogEntry -Timestamp -Market -Decision -Regime -Direction -Score -Razao -Tier -ConsensusMesa
#     => string formato:
#        [HH:mm:ss] [TRADE] {Market}: {Decision} regime={X} direction={Y} score={Z} tier={T} consensus={C} razao={R}
#     - Nulls/empty viram "-"
#     - Escape de aspas duplas em razao com \"
#     - Pipes/newlines em razao sao removidos (ou substituidos por espaco)
#
#   Parse-TradeLogEntry -Line  => PSCustomObject (round-trip)
#
# Notas: Pester 3.x usa "Should Be", "Should Match", "Should BeNullOrEmpty".

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_trade_logger.ps1"


Describe "Format-TradeLogEntry - formato basico (todos campos presentes)" {
    It "Produz linha com todos campos quando tudo preenchido (v1.5)" {
        # Legacy -Score 82 vira score_predicted=82 (backward-compat 2026-05-15)
        $line = Format-TradeLogEntry `
            -Timestamp "03:31:05" -Market "BTCUSDT" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 82 `
            -Razao "score_alto" -Tier "A" -ConsensusMesa "FORTE_3"
        $line | Should Match "^\[03:31:05\] \[TRADE\] BTCUSDT: EXECUTAR "
        $line | Should Match "regime=UP_MON"
        $line | Should Match "direction=LONG"
        $line | Should Match "score_predicted=82"
        $line | Should Match "tier=A"
        $line | Should Match "consensus=FORTE_3"
        $line | Should Match "razao=score_alto"
    }

    It "Inclui prefixo [TRADE] entre timestamp e market" {
        $line = Format-TradeLogEntry -Timestamp "12:00:00" -Market "ETHUSDT" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" -Score 50 `
            -Razao "ok" -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Match "\[TRADE\] ETHUSDT:"
    }
}


Describe "Format-TradeLogEntry - nulls e empty viram '-'" {
    It "Score null vira '-'" {
        $line = Format-TradeLogEntry -Timestamp "03:30:20" -Market "KITEUSDT" -Decision "ABORTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score $null `
            -Razao "x" -Tier "C" -ConsensusMesa "MEDIO_1"
        $line | Should Match "score=-"
    }

    It "Regime/Direction null viram '-'" {
        $line = Format-TradeLogEntry -Timestamp "03:30:20" -Market "FFUSDT" -Decision "ABORTAR" `
            -Regime $null -Direction $null -Score 0 `
            -Razao "x" -Tier "D" -ConsensusMesa "CAOS"
        $line | Should Match "regime=-"
        $line | Should Match "direction=-"
    }

    It "Razao empty vira '-'" {
        $line = Format-TradeLogEntry -Timestamp "03:30:20" -Market "X" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" -Score 30 `
            -Razao "" -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Match "razao=-"
    }

    It "Tier e Consensus null viram '-'" {
        $line = Format-TradeLogEntry -Timestamp "00:00:00" -Market "X" -Decision "ABORTAR" `
            -Regime "X" -Direction "LONG" -Score 0 `
            -Razao "x" -Tier $null -ConsensusMesa $null
        $line | Should Match "tier=-"
        $line | Should Match "consensus=-"
    }
}


Describe "Format-TradeLogEntry - Decision em varios valores" {
    It "Aceita EXECUTAR" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 80 -Razao "ok" -Tier "A" -ConsensusMesa "FORTE_3"
        $line | Should Match ": EXECUTAR "
    }

    It "Aceita ABORTAR" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" -Score 30 -Razao "ok" -Tier "C" -ConsensusMesa "MEDIO_1"
        $line | Should Match ": ABORTAR "
    }

    It "Aceita VETAR" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "VETAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 40 -Razao "mentor_vetou" -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Match ": VETAR "
    }

    It "Aceita DRY_RUN_EXECUTAR" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "DRY_RUN_EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 75 -Razao "ok" -Tier "A" -ConsensusMesa "FORTE_3"
        $line | Should Match ": DRY_RUN_EXECUTAR "
    }
}


Describe "Format-TradeLogEntry - escape de razao" {
    It "Escapa aspas duplas em razao com backslash-quote" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
            -Regime "X" -Direction "LONG" -Score 0 `
            -Razao 'macro disse "no"' -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Match 'razao=macro disse \\"no\\"'
    }

    It "Remove pipes da razao" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
            -Regime "X" -Direction "LONG" -Score 0 `
            -Razao "score|baixo|filtro" -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Not Match "\|"
        $line | Should Match "razao=score"
    }

    It "Remove newlines da razao" {
        $razao = "linha1`nlinha2"
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
            -Regime "X" -Direction "LONG" -Score 0 `
            -Razao $razao -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Not Match "`n"
        $line | Should Match "razao=linha1"
    }
}


Describe "Format-TradeLogEntry - Score em varios tipos" {
    It "Score inteiro renderiza como inteiro (mapped to score_predicted)" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 82 `
            -Razao "ok" -Tier "A" -ConsensusMesa "FORTE_3"
        $line | Should Match "score_predicted=82(\s|$)"
    }

    It "Score float renderiza com decimal (mapped to score_predicted)" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 82.5 `
            -Razao "ok" -Tier "A" -ConsensusMesa "FORTE_3"
        $line | Should Match "score_predicted=82\.5"
    }

    It "Score zero renderiza como 0 (nao como '-', mapped to score_predicted)" {
        $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" -Score 0 `
            -Razao "ok" -Tier "D" -ConsensusMesa "CAOS"
        $line | Should Match "score_predicted=0(\s|$)"
    }
}


Describe "Format-TradeLogEntry - Tier e Consensus values" {
    It "Aceita tiers A/B/C/D" {
        foreach ($t in @("A","B","C","D")) {
            $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
                -Regime "X" -Direction "LONG" -Score 0 -Razao "x" -Tier $t -ConsensusMesa "MEDIO_2"
            $line | Should Match "tier=$t"
        }
    }

    It "Aceita consensus FORTE_3/MEDIO_2/MEDIO_1/CAOS" {
        foreach ($c in @("FORTE_3","MEDIO_2","MEDIO_1","CAOS")) {
            $line = Format-TradeLogEntry -Timestamp "10:00:00" -Market "BTC" -Decision "ABORTAR" `
                -Regime "X" -Direction "LONG" -Score 0 -Razao "x" -Tier "B" -ConsensusMesa $c
            $line | Should Match "consensus=$c"
        }
    }
}


Describe "Parse-TradeLogEntry - round-trip" {
    It "Parse de linha formatada retorna objeto com campos originais" {
        $original = Format-TradeLogEntry `
            -Timestamp "03:31:05" -Market "BTCUSDT" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 82 `
            -Razao "score_alto" -Tier "A" -ConsensusMesa "FORTE_3"
        $parsed = Parse-TradeLogEntry -Line $original
        $parsed.Timestamp | Should Be "03:31:05"
        $parsed.Market | Should Be "BTCUSDT"
        $parsed.Decision | Should Be "EXECUTAR"
        $parsed.Regime | Should Be "UP_MON"
        $parsed.Direction | Should Be "LONG"
        $parsed.Score | Should Be "82"
        $parsed.Tier | Should Be "A"
        $parsed.ConsensusMesa | Should Be "FORTE_3"
        $parsed.Razao | Should Be "score_alto"
    }

    It "Parse de linha com '-' retorna null/'-' coerente" {
        $line = Format-TradeLogEntry -Timestamp "00:00:00" -Market "X" -Decision "ABORTAR" `
            -Regime $null -Direction $null -Score $null `
            -Razao $null -Tier $null -ConsensusMesa $null
        $parsed = Parse-TradeLogEntry -Line $line
        $parsed.Regime | Should Be "-"
        $parsed.Score | Should Be "-"
        $parsed.Tier | Should Be "-"
    }

    It "Parse de linha nao-TRADE retorna null" {
        $parsed = Parse-TradeLogEntry -Line "[03:30:20] [GEM] GemScan: nada"
        $parsed | Should BeNullOrEmpty
    }

    It "Parse de linha vazia retorna null" {
        $parsed = Parse-TradeLogEntry -Line ""
        $parsed | Should BeNullOrEmpty
    }
}


Describe "Format-TradeLogEntry - DayOfWeek implicito no timestamp" {
    It "Timestamp aceita formato HH:mm:ss puro sem date" {
        $line = Format-TradeLogEntry -Timestamp "23:59:59" -Market "BTC" -Decision "ABORTAR" `
            -Regime "X" -Direction "LONG" -Score 0 -Razao "x" -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Match "^\[23:59:59\]"
    }

    It "Timestamp vazio gera timestamp atual (fallback)" {
        $line = Format-TradeLogEntry -Timestamp "" -Market "BTC" -Decision "ABORTAR" `
            -Regime "X" -Direction "LONG" -Score 0 -Razao "x" -Tier "B" -ConsensusMesa "MEDIO_2"
        # Deve gerar HH:mm:ss valido (nao "-")
        $line | Should Match "^\[\d{2}:\d{2}:\d{2}\]"
    }
}


# ── EUREKA A (2026-05-15): scanner_score vs score_predicted dual emission ─────
# Diagnose: log [TRADE] score=X era ambiguo (LLM cosmetic, nao input deterministico).
# Fix: emit AMBOS como campos separados; -Score legacy continua funcionando.

Describe "Format-TradeLogEntry - dual score (scanner_score + score_predicted)" {

    It "Emite scanner_score e score_predicted separados quando ambos passados" {
        $line = Format-TradeLogEntry `
            -Timestamp "10:00:00" -Market "BTCUSDT" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" `
            -ScannerScore 42 -ScorePredicted 60 `
            -Razao "tier_baixo" -Tier "D" -ConsensusMesa "CAOS"
        $line | Should Match "scanner_score=42"
        $line | Should Match "score_predicted=60"
    }

    It "Com so scanner_score (score_predicted=null): emite scanner_score=X score_predicted=-" {
        $line = Format-TradeLogEntry `
            -Timestamp "10:00:00" -Market "BTCUSDT" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" `
            -ScannerScore 42 -ScorePredicted $null `
            -Razao "x" -Tier "D" -ConsensusMesa "CAOS"
        $line | Should Match "scanner_score=42"
        $line | Should Match "score_predicted=-"
    }

    It "Com so score_predicted (scanner_score=null): emite scanner_score=- score_predicted=Y" {
        $line = Format-TradeLogEntry `
            -Timestamp "10:00:00" -Market "BTCUSDT" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" `
            -ScannerScore $null -ScorePredicted 75 `
            -Razao "x" -Tier "B" -ConsensusMesa "MEDIO_2"
        $line | Should Match "scanner_score=-"
        $line | Should Match "score_predicted=75"
    }

    It "Backward-compat: param legado -Score continua funcionando isolado" {
        # Quando so -Score e passado (legacy), preenche score_predicted (LLM era o exibido antes).
        $line = Format-TradeLogEntry `
            -Timestamp "10:00:00" -Market "BTCUSDT" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" -Score 82 `
            -Razao "ok" -Tier "A" -ConsensusMesa "FORTE_3"
        # Mantem regex compat para parsers legados
        $line | Should Match "score_predicted=82"
        $line | Should Match "scanner_score=-"
    }

    It "Parse-TradeLogEntry round-trip: novos campos parseiam corretamente" {
        $original = Format-TradeLogEntry `
            -Timestamp "03:31:05" -Market "BTCUSDT" -Decision "EXECUTAR" `
            -Regime "UP_MON" -Direction "LONG" `
            -ScannerScore 65 -ScorePredicted 82 `
            -Razao "score_alto" -Tier "A" -ConsensusMesa "FORTE_3"
        $parsed = Parse-TradeLogEntry -Line $original
        $parsed.ScannerScore | Should Be "65"
        $parsed.ScorePredicted | Should Be "82"
        $parsed.Tier | Should Be "A"
        $parsed.Market | Should Be "BTCUSDT"
    }

    It "Edge case: ambos null -> emite scanner_score=- score_predicted=-" {
        $line = Format-TradeLogEntry `
            -Timestamp "10:00:00" -Market "BTCUSDT" -Decision "ABORTAR" `
            -Regime "NEUTRAL" -Direction "LONG" `
            -ScannerScore $null -ScorePredicted $null `
            -Razao "x" -Tier "D" -ConsensusMesa "CAOS"
        $line | Should Match "scanner_score=-"
        $line | Should Match "score_predicted=-"
    }
}


Describe "Format-UniverseLogEntry" {

    It "Retorna string formatada com [UNIVERSE]" {
        $snap = [PSCustomObject]@{
            total_pairs = 1247
            snapshot_ts = Get-Date "2026-05-15 12:08:00"
        }
        $entry = Format-UniverseLogEntry -Snapshot $snap
        $entry | Should Match "\[UNIVERSE\]"
        $entry | Should Match "pairs=1247"
    }

    It "Inclui timestamp no formato HH:mm:ss" {
        $snap = [PSCustomObject]@{
            total_pairs = 500
            snapshot_ts = Get-Date "2026-05-15 12:08:00"
        }
        $entry = Format-UniverseLogEntry -Snapshot $snap
        $entry | Should Match "12:08:00"
    }

    It "Null snapshot nao lanca erro" {
        { Format-UniverseLogEntry -Snapshot $null } | Should Not Throw
    }
}


Describe "Format-GateQualityEntry" {

    It "Retorna string formatada com [GATE-QUALITY]" {
        $stats = [PSCustomObject]@{
            mcap_below_1m    = 421
            age_below_7d     = 38
            vol_below_500k   = 892
            spread_above_5pct = 267
        }
        $entry = Format-GateQualityEntry -GateStats $stats
        $entry | Should Match "\[GATE-QUALITY\]"
    }

    It "Inclui todas as metricas de gate" {
        $stats = [PSCustomObject]@{
            mcap_below_1m    = 421
            age_below_7d     = 38
            vol_below_500k   = 892
            spread_above_5pct = 267
        }
        $entry = Format-GateQualityEntry -GateStats $stats
        $entry | Should Match "mcap"
        $entry | Should Match "idade"
        $entry | Should Match "vol"
        $entry | Should Match "spread"
        $entry | Should Match "421"
        $entry | Should Match "38"
        $entry | Should Match "892"
        $entry | Should Match "267"
    }

    It "Null stats nao lanca erro" {
        { Format-GateQualityEntry -GateStats $null } | Should Not Throw
    }
}


Describe "Format-HitRateEntry" {

    It "Retorna string formatada com [HIT-RATE]" {
        $comp = [PSCustomObject]@{
            caught_by_scanner = 3
            total_movers      = 10
            missed            = @("DEGEN", "HAJIMI")
            direction         = "LONG"
        }
        $entry = Format-HitRateEntry -Comparison $comp
        $entry | Should Match "\[HIT-RATE LONG\]"
    }

    It "Inclui formato X/Y caught" {
        $comp = [PSCustomObject]@{
            caught_by_scanner = 3
            total_movers      = 10
            missed            = @()
            direction         = "LONG"
        }
        $entry = Format-HitRateEntry -Comparison $comp
        $entry | Should Match "3/10 caught"
    }

    It "Lista missed symbols separados por espaco" {
        $comp = [PSCustomObject]@{
            caught_by_scanner = 3
            total_movers      = 10
            missed            = @("DEGEN", "HAJIMI", "FOMO")
            direction         = "LONG"
        }
        $entry = Format-HitRateEntry -Comparison $comp
        $entry | Should Match "missed:"
        $entry | Should Match "DEGEN"
        $entry | Should Match "HAJIMI"
        $entry | Should Match "FOMO"
    }

    It "Direction SHORT eh preservado no label" {
        $comp = [PSCustomObject]@{
            caught_by_scanner = 5
            total_movers      = 15
            missed            = @()
            direction         = "SHORT"
        }
        $entry = Format-HitRateEntry -Comparison $comp
        $entry | Should Match "\[HIT-RATE SHORT\]"
    }

    It "Null comparison nao lanca erro" {
        { Format-HitRateEntry -Comparison $null } | Should Not Throw
    }
}

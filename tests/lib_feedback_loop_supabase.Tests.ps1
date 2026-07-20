# lib_feedback_loop_supabase.Tests.ps1 -- TDD espelho de trade_outcomes no Supabase.
# Pester 3.x.
#
# Objetivo: ao fechar um trade, alem de gravar journal/trade_outcomes.jsonl (local),
# espelhar o mesmo outcome na tabela manuheadfund.trade_outcomes do Supabase, para
# que runners cloud (sem disco local persistente) tenham ground-truth de atividade.
#
# Contrato:
#   - ConvertTo-SupabaseOutcome  : PURA. Mapeia schema JSONL local -> colunas Supabase.
#   - Add-TradeOutcome           : quando backend = supabase, espelha via Save-StateRecords.
#                                  Best-effort: NUNCA lanca, mas AVISA (warning) se falhar.
#                                  Quando backend = local, NAO espelha (back-compat).

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_feedback_loop.ps1")

$script:tmp = Join-Path $env:TEMP ("fbsupa_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "ConvertTo-SupabaseOutcome (pura)" {

    It "Mapeia campos do schema local para colunas Supabase" {
        $obj = [ordered]@{
            ts            = "2026-06-20T12:00:00Z"
            market        = "BTCUSDT"
            side          = "LONG"
            mode          = "TIER_A"
            entry_price   = 50000
            exit_price    = 52000
            stop_price    = 49000
            target_price  = 55000
            r             = 1.5
            pnl_usd       = 100
            duration_days = 3
            exit_reason   = "trail_stop"
            regime        = "BULL_WEAK"
            score         = 75
        }
        $row = ConvertTo-SupabaseOutcome -Outcome $obj
        $row.market       | Should Be "BTCUSDT"
        $row.side         | Should Be "LONG"
        $row.mode         | Should Be "TIER_A"
        $row.entry        | Should Be 50000
        $row.exit_price   | Should Be 52000
        $row.stop         | Should Be 49000
        $row.target       | Should Be 55000
        $row.r_multiple   | Should Be 1.5
        $row.closed_at    | Should Be "2026-06-20T12:00:00Z"
        $row.close_reason | Should Be "trail_stop"
        # 2026-07-19: pnl_percent/pnl_realized nunca eram mapeados -- coluna
        # dedicada ficava sempre em DEFAULT 0 do Postgres (dado real preso
        # so dentro de payload, nunca consultavel via SELECT direto).
        $row.pnl_realized | Should Be 100
        $row.pnl_percent  | Should Be 4  # LONG: (52000-50000)/50000*100 = 4%
    }

    It "pnl_percent inverte o sinal para SHORT (ganho quando exit < entry)" {
        $obj = [ordered]@{
            ts = "2026-06-20T12:00:00Z"; market = "ETHUSDT"; side = "SHORT"; mode = "GEM"
            entry_price = 100; exit_price = 90; stop_price = 110; target_price = 80
            r = 1; pnl_usd = 42.5; duration_days = 2; exit_reason = "target"
            regime = "BEAR_WEAK"; score = 60
        }
        $row = ConvertTo-SupabaseOutcome -Outcome $obj
        $row.pnl_realized | Should Be 42.5
        $row.pnl_percent  | Should Be 10  # SHORT: -((90-100)/100*100) = +10%
    }

    It "Preserva o objeto integral no payload (lossless, inclui pnl_usd)" {
        $obj = [ordered]@{
            ts = "2026-06-20T12:00:00Z"; market = "ETHUSDT"; side = "SHORT"; mode = "GEM"
            entry_price = 100; exit_price = 90; stop_price = 110; target_price = 80
            r = 1; pnl_usd = 42.5; duration_days = 2; exit_reason = "target"
            regime = "BEAR_WEAK"; score = 60
        }
        $row = ConvertTo-SupabaseOutcome -Outcome $obj
        $row.payload.pnl_usd       | Should Be 42.5
        $row.payload.duration_days | Should Be 2
        $row.payload.regime        | Should Be "BEAR_WEAK"
    }

    It "Funciona com PSCustomObject (vindo de ConvertFrom-Json)" {
        $json = '{"ts":"2026-06-20T12:00:00Z","market":"SOLUSDT","side":"LONG","mode":"GEM","entry_price":10,"exit_price":12,"stop_price":9,"target_price":15,"r":2,"pnl_usd":5,"duration_days":1,"exit_reason":"target","regime":"BULL","score":80}'
        $obj = $json | ConvertFrom-Json
        $row = ConvertTo-SupabaseOutcome -Outcome $obj
        $row.market     | Should Be "SOLUSDT"
        $row.r_multiple | Should Be 2
    }
}


# NOTA Pester 3.x: mocks do mesmo comando ACUMULAM entre It's do mesmo Describe.
# Por isso cada comportamento de Save-StateRecords (sucesso / no-op / throw) fica em
# seu proprio Describe, evitando vazamento de mock entre testes.

Describe "Add-TradeOutcome espelha quando backend supabase" {
    AfterEach { Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue }

    It "Chama Save-StateRecords na tabela trade_outcomes com market mapeado" {
        $global:STATE_STORE_BACKEND = "supabase"
        $script:capRec = $null
        Mock Save-StateRecords { $script:capRec = $Records } -ParameterFilter { $Table -eq "trade_outcomes" }
        $f = Join-Path $tmp "mirror_a.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "BTCUSDT" -Side "LONG" -Mode "TIER_A" `
            -EntryPrice 50000 -ExitPrice 52000 -StopPrice 49000 -TargetPrice 55000 `
            -R 1.5 -Pnl 100 -DurationDays 3 -ExitReason "trail_stop" -Regime "BULL_WEAK" -Score 75
        Assert-MockCalled Save-StateRecords -Times 1 -Exactly -Scope It -ParameterFilter { $Table -eq "trade_outcomes" }
        $script:capRec[0].market | Should Be "BTCUSDT"
    }
}

Describe "Add-TradeOutcome mira schema manuheadfund no espelho" {
    AfterEach {
        Remove-Variable -Name STATE_STORE_BACKEND, STATE_STORE_SCHEMA -Scope Global -ErrorAction SilentlyContinue
    }

    It "Schema vigente durante o Save eh manuheadfund e eh restaurado depois" {
        $global:STATE_STORE_BACKEND = "supabase"
        $global:STATE_STORE_SCHEMA = "public"   # schema global (ex: trailing) nao deve mudar
        $script:schemaDuring = $null
        Mock Save-StateRecords { $script:schemaDuring = Get-StateStoreSchema }
        $f = Join-Path $tmp "mirror_schema.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "BTCUSDT" -Side "LONG" -Mode "TIER_A" `
            -EntryPrice 1 -ExitPrice 2 -StopPrice 0.5 -TargetPrice 5 -R 1 -Pnl 1 -DurationDays 1 `
            -ExitReason "target" -Regime "BULL" -Score 60
        $script:schemaDuring | Should Be "manuheadfund"
        # schema global restaurado apos a chamada
        Get-StateStoreSchema | Should Be "public"
    }
}

Describe "Add-TradeOutcome back-compat JSONL local" {
    AfterEach { Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue }

    It "Grava sempre o JSONL local mesmo em modo supabase" {
        $global:STATE_STORE_BACKEND = "supabase"
        Mock Save-StateRecords { }
        $f = Join-Path $tmp "mirror_b.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "ETHUSDT" -Side "LONG" -Mode "GEM" `
            -EntryPrice 1 -ExitPrice 2 -StopPrice 0.5 -TargetPrice 5 -R 1 -Pnl 1 -DurationDays 1 `
            -ExitReason "target" -Regime "BULL" -Score 60
        Test-Path $f | Should Be $true
        ($f | Get-Item).Length | Should BeGreaterThan 0
    }

    It "NAO espelha quando backend = local" {
        $global:STATE_STORE_BACKEND = "local"
        Mock Save-StateRecords { }
        $f = Join-Path $tmp "mirror_c.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "SOLUSDT" -Side "LONG" -Mode "GEM" `
            -EntryPrice 10 -ExitPrice 12 -StopPrice 9 -TargetPrice 15 -R 2 -Pnl 5 -DurationDays 1 `
            -ExitReason "target" -Regime "BULL" -Score 80
        Assert-MockCalled Save-StateRecords -Times 0 -Exactly -Scope It
        Test-Path $f | Should Be $true
    }
}

Describe "Add-TradeOutcome best-effort quando espelho falha" {
    AfterEach { Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue }

    It "NAO lanca e grava o JSONL local apesar da falha no espelho" {
        $global:STATE_STORE_BACKEND = "supabase"
        Mock Save-StateRecords { throw "simulated supabase failure" }
        $f = Join-Path $tmp "mirror_d.jsonl"
        {
            Add-TradeOutcome -OutcomePath $f -Market "XRPUSDT" -Side "SHORT" -Mode "GEM" `
                -EntryPrice 1 -ExitPrice 0.9 -StopPrice 1.1 -TargetPrice 0.8 -R 1 -Pnl 2 -DurationDays 1 `
                -ExitReason "target" -Regime "BEAR" -Score 70 -WarningAction SilentlyContinue
        } | Should Not Throw
        Test-Path $f | Should Be $true
    }
}

Describe "Add-TradeOutcome avisa (nao silencioso) quando espelho falha" {
    AfterEach { Remove-Variable -Name STATE_STORE_BACKEND -Scope Global -ErrorAction SilentlyContinue }

    It "Emite Write-Warning quando o espelho Supabase falha" {
        $global:STATE_STORE_BACKEND = "supabase"
        Mock Save-StateRecords { throw "simulated supabase failure" }
        Mock Write-Warning { }
        $f = Join-Path $tmp "mirror_e.jsonl"
        Add-TradeOutcome -OutcomePath $f -Market "ADAUSDT" -Side "LONG" -Mode "GEM" `
            -EntryPrice 1 -ExitPrice 2 -StopPrice 0.5 -TargetPrice 5 -R 1 -Pnl 1 -DurationDays 1 `
            -ExitReason "target" -Regime "BULL" -Score 60
        Assert-MockCalled Write-Warning -Scope It -Times 1 -Exactly
    }
}

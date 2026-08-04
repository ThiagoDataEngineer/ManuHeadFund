# lib_trailing_source_aware.Tests.ps1 -- Pester 3.x
# TDD pra ONDA 1: source-aware fields (mode, max_days, dd_threshold_pct) + max_days enforcement.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"

# Isolar storage por test run (override TRAILING_FILE)
$script:tmpDir = Join-Path $env:TEMP ("trail_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null

# Stubs pra evitar I/O CoinEx + Telegram durante test
function CoinEx-GetTicker { param($m) return @{ last = 100 } }
function Send-TelegramAlert { param($Message) }
function Format-TgTrailStopHit { param($Pos, $CurrentPrice) return "stop $($Pos.market)" }
function Format-TgTrailPhase { param($Pos, $OldStop, $OldPhase, $CurrentPrice) return "phase $($Pos.market)" }

# Carrega lib_feedback_loop pra Add-TradeOutcome estar disponivel
. (Join-Path $agentsDir "lib_feedback_loop.ps1")

# Dot-source direto do lib_trailing (stubs CoinEx/Telegram ja definidos acima).
# $global:TRAILING_FILE isola storage; state_store desabilitado via flag.
$global:TRAILING_FILE = Join-Path $script:tmpDir "trailing_positions.json"
$global:TRAILING_USE_STATE_STORE = $false
$env:TRAILING_USE_STATE_STORE = "0"
. (Join-Path $agentsDir "lib_trailing.ps1")


Describe "Add-TrailingPosition - source-aware fields" {
    It "Mode auto-derived from Source gem -> GEM + defaults" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "GEMUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "GEMUSDT" })
        $p.mode | Should Be "GEM"
        $p.max_days | Should Be 14
        $p.dd_threshold_pct | Should Be 40.0
    }
    It "Mode auto-derived from Source tier_a -> TIER_A + DD 25%" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 -Source "tier_a"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" })
        $p.mode | Should Be "TIER_A"
        $p.dd_threshold_pct | Should Be 25.0
    }
    It "MaxDays explicit override default" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "ABC" -Side "LONG" -Entry 1 -Stop 0.9 -Target 1.3 -Source "gem" -MaxDays 30
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "ABC" })
        $p.max_days | Should Be 30
    }
    It "STANDARD mode (orchestrator legacy) sem max_days" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "STD" -Side "LONG" -Entry 1 -Stop 0.9 -Target 1.3 -Source "orchestrator"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "STD" })
        $p.mode | Should Be "STANDARD"
        $p.max_days | Should Be 0
        $p.dd_threshold_pct | Should Be 30.0
    }
}


Describe "Add-TrailingPosition - Origin (2026-07-18, motor unico de trailing)" {
    # lib_trailing_unified.ps1 (Resolve-TrailingDecision) exige
    # Position.origin.{asset_class,trade_style} -- este e o ponto onde a
    # origem do trade e conhecida (quem chama Add-TrailingPosition sabe se e
    # SPOT/FUTURES, SCALP/SWING) e precisa ser gravada, nao redescoberta
    # depois. Callers existentes (lib_trailing_orphan_detection.ps1) nao
    # passam -Origin -- precisa fallback seguro, nao quebra retrocompat.
    It "Origin explicito e gravado como esta" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "ORIGUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem" `
            -Origin @{ asset_class = "SPOT"; trade_style = "SWING" }
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "ORIGUSDT" })
        $p.origin.asset_class | Should Be "SPOT"
        $p.origin.trade_style | Should Be "SWING"
    }
    It "Origin ausente (caller legado) grava fallback UNKNOWN, nao quebra" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "LEGACYUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "LEGACYUSDT" })
        $p.origin.asset_class | Should Be "UNKNOWN"
        $p.origin.trade_style | Should Be "UNKNOWN"
    }
    It "Origin FUTURES+SCALP gravado corretamente (caso short scalp)" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "SCALPUSDT" -Side "SHORT" -Entry 100 -Stop 105 -Target 80 -Source "tier_a" `
            -Origin @{ asset_class = "FUTURES"; trade_style = "SCALP" }
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "SCALPUSDT" })
        $p.origin.asset_class | Should Be "FUTURES"
        $p.origin.trade_style | Should Be "SCALP"
    }
}


Describe "Add-TrailingPosition - birth_score (2026-07-29, avaliacao real de sinal vs resultado)" {
    # Achado: gem_executor.ps1 calculava $__birthScore (conviction ensemble +
    # bonus eixos fortes + bonus FQS) mas Add-TrailingPosition descartava --
    # so usava MentorConfidence/MesaSinal/Tier pra Add-PendingReflection
    # (que so roda com MentorVeredicto no-vazio, nunca passado pelo gem_executor).
    # Score nunca chegava a lugar persistente nenhum, so log de texto do run.
    It "BirthScore explicito e gravado em birth_score" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "BIRTHUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem" `
            -BirthScore 78.5 -BirthMesaSinal "regime=BEAR_STRONG|strong_axes=2|fqs=GEM" -BirthFqsCategory "GEM"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "BIRTHUSDT" })
        $p.birth_score | Should Be 78.5
        $p.birth_mesa_sinal | Should Be "regime=BEAR_STRONG|strong_axes=2|fqs=GEM"
        $p.birth_fqs_category | Should Be "GEM"
    }
    It "BirthScore ausente (caller legado) grava null, nao quebra" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "NOBIRTHUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "orphan_auto_register"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "NOBIRTHUSDT" })
        $p.birth_score | Should Be $null
        $p.birth_mesa_sinal | Should Be ""
    }
}

Describe "Add-TrailingPosition - sl_source/tp_source/stop_pct_used (2026-08-04, instrumentacao)" {
    # Owner pediu (estudando o Evolution Engine junto) instrumentacao ANTES de
    # qualquer auto-calibragem de stop_pct -- hoje impossivel medir se stop
    # fixo por Mode (Calculate-StopTarget, gem_executor.ps1) rende melhor ou
    # pior que pivot estrutural (Get-StructuralStopTarget, so no reparo),
    # porque a origem nunca sobrevivia ate o fechamento do trade.
    It "SlSource/TpSource/StopPctUsed explicitos sao gravados" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "INSTRUSDT" -Side "LONG" -Entry 100 -Stop 92 -Target 150 -Source "gem" `
            -SlSource "fixed_pct" -TpSource "fixed_pct" -StopPctUsed 0.08
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "INSTRUSDT" })
        $p.sl_source | Should Be "fixed_pct"
        $p.tp_source | Should Be "fixed_pct"
        $p.stop_pct_used | Should Be 0.08
    }
    It "ausentes (caller legado) gravam string vazia / zero, nao quebra" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "NOINSTRUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "orphan_auto_register"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "NOINSTRUSDT" })
        $p.sl_source | Should Be ""
        $p.tp_source | Should Be ""
        $p.stop_pct_used | Should Be 0
    }
}

Describe "Test-MaxDaysExceeded" {
    It "posicao com max_days=0 retorna false (sem limite)" {
        $pos = [PSCustomObject]@{ openedAt = "2026-01-01 00:00:00"; max_days = 0 }
        Test-MaxDaysExceeded -Pos $pos -Now ([DateTime]"2026-12-01 00:00:00") | Should Be $false
    }
    It "posicao recent com max_days=14 retorna false" {
        $opened = (Get-Date).AddDays(-5).ToString("yyyy-MM-dd HH:mm:ss")
        $pos = [PSCustomObject]@{ openedAt = $opened; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $false
    }
    It "posicao old com max_days=14 retorna true" {
        $opened = (Get-Date).AddDays(-20).ToString("yyyy-MM-dd HH:mm:ss")
        $pos = [PSCustomObject]@{ openedAt = $opened; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $true
    }
    It "posicao no limite exato (14 dias) retorna true" {
        $opened = (Get-Date).AddDays(-14).AddMinutes(-5).ToString("yyyy-MM-dd HH:mm:ss")
        $pos = [PSCustomObject]@{ openedAt = $opened; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $true
    }
    It "openedAt invalido retorna false (defensive)" {
        $pos = [PSCustomObject]@{ openedAt = "garbage"; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $false
    }
}

Describe "Close-TrailingPosition - emits feedback outcome" {
    # 2026-05-19 PM: ao fechar posicao, registra outcome em journal/trade_outcomes.jsonl
    # via Add-TradeOutcome (lib_feedback_loop). Disponibiliza dados pra learning loop.
    BeforeEach {
        $script:outcomeFile = Join-Path $script:tmpDir "trade_outcomes.jsonl"
        Remove-Item $outcomeFile -ErrorAction SilentlyContinue
    }
    It "Close-TrailingPosition de stop hit registra R-multiple negativo + exit_reason stop_atingido" {
        # Setup: open + close
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "ZUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 `
                             -Source "tier_a" -OrderId "OID1"
        # Simula close
        Close-TrailingPosition -Market "ZUSDT" -Reason "stop_atingido" -ExitPrice 95 -OutcomePath $outcomeFile
        Test-Path $outcomeFile | Should Be $true
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.market | Should Be "ZUSDT"
        $obj.exit_reason | Should Be "stop_atingido"
        $obj.r | Should Be -1   # entry 100 stop 95 = risk 5; exit 95 = -1R
    }
    It "Close de target hit registra R positivo" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "YUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 -Source "tier_a"
        Close-TrailingPosition -Market "YUSDT" -Reason "target" -ExitPrice 120 -OutcomePath $outcomeFile
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.r | Should Be 4   # entry 100 stop 95 risk 5; exit 120 gain 20 = +4R
        $obj.exit_reason | Should Be "target"
    }
    It "SHORT close: R calc espelhado" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "SUSDT" -Side "SHORT" -Entry 100 -Stop 105 -Target 80 -Source "tier_a"
        Close-TrailingPosition -Market "SUSDT" -Reason "target" -ExitPrice 80 -OutcomePath $outcomeFile
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        # SHORT entry 100, exit 80, gain 20; risk = |100-105| = 5; R = 20/5 = 4
        $obj.r | Should Be 4
    }

    # 2026-08-04: instrumentacao repassada do trailing_state ate o outcome
    # final -- e o elo que faltava pra medir sl_source/tp_source vs resultado.
    It "sl_source/tp_source/stop_pct_used sao repassados da posicao para o outcome" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "WUSDT" -Side "LONG" -Entry 100 -Stop 92 -Target 150 -Source "gem" `
            -SlSource "structural" -TpSource "fixed_pct" -StopPctUsed 0.08
        Close-TrailingPosition -Market "WUSDT" -Reason "target" -ExitPrice 150 -OutcomePath $outcomeFile
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.sl_source | Should Be "structural"
        $obj.tp_source | Should Be "fixed_pct"
        $obj.stop_pct_used | Should Be 0.08
    }
    It "posicao legada sem instrumentacao fecha normalmente (campos vazios no outcome)" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "VUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 -Source "tier_a"
        Close-TrailingPosition -Market "VUSDT" -Reason "target" -ExitPrice 120 -OutcomePath $outcomeFile
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.sl_source | Should Be ""
        $obj.tp_source | Should Be ""
        $obj.stop_pct_used | Should Be 0
    }
}

Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue

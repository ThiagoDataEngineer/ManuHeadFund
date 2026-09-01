# lib_gem_reentry_cooldown.Tests.ps1 -- TDD de Get-MinutesSinceLastStopOut /
# Test-GemReentryCooldown (agents/lib_gem_position_events.ps1)
#
# 2026-09-01: achado real (owner, extrato CoinEx) -- ARBUSDT reabriu e stopou
# 4x em 6h, gaps de 16-26min entre fechar e reabrir, -$19.62 no total. NAO
# existia guard que impedisse reabrir posicao NOVA no mesmo market logo apos
# um stop -- Get-RecentGemAddPositionCount so cobre "Add Position" (aumentar
# posicao EXISTENTE), nao "abrir do zero apos fechar". Fix: cooldown minimo
# (default 30min) apos STOPPED_OUT no mesmo market, reusando o MESMO padrao
# ja testado/em producao de Get-RecentGemAddPositionCount (mesma tabela
# gem_position_events, mesmo fail-soft, mesmo parse RoundtripKind de data).
#
# Pester 3.4 (motor real de producao/CI). Padrao de mock: Set-Item -Path
# function:X -Value {...} (mesma tecnica de lib_trailing_partial_exit.Tests.ps1).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

function Get-StateRecords { param($Table, $Filter) @() }
function Save-StateRecords { param($Table, $Records, $PrimaryKey) $true }

. (Join-Path $agentsDir "lib_gem_position_events.ps1")

Describe "Get-MinutesSinceLastStopOut" {
    It "sem evento STOPPED_OUT registrado: retorna null (nunca stopou, sem cooldown)" {
        Set-Item -Path function:Get-StateRecords -Value { param($Table, $Filter) @() }
        (Get-MinutesSinceLastStopOut -Market "ARBUSDT") | Should Be $null
    }

    It "com evento STOPPED_OUT ha 10 minutos: retorna ~10" {
        $script:tenMinAgo = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString("o")
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "ARBUSDT"; event_type = "STOPPED_OUT"; created_at = $script:tenMinAgo })
        }
        $r = Get-MinutesSinceLastStopOut -Market "ARBUSDT"
        ($r -ge 9 -and $r -le 11) | Should Be $true
    }

    It "com MULTIPLOS eventos STOPPED_OUT: usa o MAIS RECENTE (menor minutos)" {
        $script:thirtyMinAgo = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString("o")
        $script:fiveMinAgo = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString("o")
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @(
                [PSCustomObject]@{ market = "ARBUSDT"; event_type = "STOPPED_OUT"; created_at = $script:thirtyMinAgo },
                [PSCustomObject]@{ market = "ARBUSDT"; event_type = "STOPPED_OUT"; created_at = $script:fiveMinAgo }
            )
        }
        $r = Get-MinutesSinceLastStopOut -Market "ARBUSDT"
        ($r -ge 4 -and $r -le 6) | Should Be $true
    }

    It "Get-StateRecords indisponivel: fail-soft retorna null (nao bloqueia por erro de infra)" {
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
        (Get-MinutesSinceLastStopOut -Market "ARBUSDT") | Should Be $null
        function Get-StateRecords { param($Table, $Filter) @() }
    }
}

Describe "Test-GemReentryCooldown" {
    It "sem evento STOPPED_OUT: cooldown NAO ativo (allowed=true), pode entrar" {
        Set-Item -Path function:Get-StateRecords -Value { param($Table, $Filter) @() }
        $r = Test-GemReentryCooldown -Market "ARBUSDT"
        $r.allowed | Should Be $true
    }

    It "stop ha 10min, cooldown default 60min: BLOQUEIA (allowed=false)" {
        $script:tenMinAgo = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString("o")
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "ARBUSDT"; event_type = "STOPPED_OUT"; created_at = $script:tenMinAgo })
        }
        $r = Test-GemReentryCooldown -Market "ARBUSDT"
        $r.allowed | Should Be $false
        $r.reason -like "cooldown_pos_stop*" | Should Be $true
    }

    It "stop ha 75min, cooldown default 60min: LIBERA (allowed=true, ja passou o cooldown)" {
        $script:seventyFiveMinAgo = (Get-Date).ToUniversalTime().AddMinutes(-75).ToString("o")
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "ARBUSDT"; event_type = "STOPPED_OUT"; created_at = $script:seventyFiveMinAgo })
        }
        $r = Test-GemReentryCooldown -Market "ARBUSDT"
        $r.allowed | Should Be $true
    }

    It "CooldownMinutes e configuravel" {
        $script:tenMinAgo = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString("o")
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "ARBUSDT"; event_type = "STOPPED_OUT"; created_at = $script:tenMinAgo })
        }
        $r = Test-GemReentryCooldown -Market "ARBUSDT" -CooldownMinutes 5
        $r.allowed | Should Be $true
    }

    It "fail-soft: erro de infra nunca bloqueia entrada (allowed=true por seguranca)" {
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
        $r = Test-GemReentryCooldown -Market "ARBUSDT"
        $r.allowed | Should Be $true
        function Get-StateRecords { param($Table, $Filter) @() }
    }
}

Describe "Add-GemPositionEvent -- EventType STOPPED_OUT (novo, alem de OPEN/ADD)" {
    It "aceita EventType=STOPPED_OUT sem lancar excecao" {
        Set-Item -Path function:Save-StateRecords -Value { param($Table, $Records, $PrimaryKey) $true }
        { Add-GemPositionEvent -Market "ARBUSDT" -Side "LONG" -UsdSize 130 -EventType "STOPPED_OUT" } | Should Not Throw
    }
}

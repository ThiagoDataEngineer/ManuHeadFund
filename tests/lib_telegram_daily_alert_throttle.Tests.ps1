# lib_telegram_daily_alert_throttle.Tests.ps1 -- TDD
#
# Achado real 2026-08-15: com 22+ posicoes SHORT abertas em producao,
# exposure cap ("anti trade-gigante", bloqueio CORRETO de candidato ja
# posicionado) gerava um Telegram a cada bloqueio -- scanner varre a cada
# 5min, entao a mesma moeda podia disparar dezenas de alertas/hora sem
# nenhuma acao necessaria do owner. Pedido explicito: max 1 alerta por
# moeda por janela do dia (manha 06-12h, tarde 12-18h, noite 18-00h, todos
# BRT=UTC-3), silencio total na madrugada (00-06h BRT).

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_telegram.ps1")

Describe "Get-BrtDayWindow -- classifica UTC em janela do dia BRT" {
    It "09:00 UTC (06:00 BRT) -> manha (limite inferior)" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T09:00:00Z")).window | Should Be "manha"
    }
    It "14:59 UTC (11:59 BRT) -> ainda manha (limite superior)" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T14:59:00Z")).window | Should Be "manha"
    }
    It "15:00 UTC (12:00 BRT) -> tarde" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T15:00:00Z")).window | Should Be "tarde"
    }
    It "20:59 UTC (17:59 BRT) -> ainda tarde" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T20:59:00Z")).window | Should Be "tarde"
    }
    It "21:00 UTC (18:00 BRT) -> noite" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T21:00:00Z")).window | Should Be "noite"
    }
    It "02:59 UTC (23:59 BRT do dia anterior) -> ainda noite" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T02:59:00Z")).window | Should Be "noite"
    }
    It "03:00 UTC (00:00 BRT) -> madrugada (silencio)" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T03:00:00Z")).window | Should Be "madrugada"
    }
    It "08:59 UTC (05:59 BRT) -> ainda madrugada (limite superior)" {
        (Get-BrtDayWindow -UtcNow ([datetime]"2026-08-15T08:59:00Z")).window | Should Be "madrugada"
    }
}

Describe "Test-DailyMarketAlertThrottle -- max 1 alerta por moeda por janela" {
    BeforeEach {
        $script:testStatePath = Join-Path $env:TEMP "throttle_test_$((Get-Random)).json"
        $script:__dailyAlertThrottleCache = $null
    }
    AfterEach {
        if (Test-Path $script:testStatePath) { Remove-Item $script:testStatePath -Force -ErrorAction SilentlyContinue }
        $script:__dailyAlertThrottleCache = $null
    }

    It "primeiro alerta do dia/janela para uma moeda -> permite (true)" {
        $r = Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:00:00Z")
        $r | Should Be $true
    }

    It "segundo alerta na MESMA janela/moeda/motivo -> suprime (false)" {
        Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:00:00Z") | Out-Null
        $r = Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:30:00Z")
        $r | Should Be $false
    }

    It "mesma moeda em JANELA DIFERENTE do mesmo dia -> permite de novo (manha depois tarde)" {
        Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T09:00:00Z") | Out-Null   # manha
        $r = Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:00:00Z")   # tarde
        $r | Should Be $true
    }

    It "moedas DIFERENTES na mesma janela -> ambas permitidas (throttle e por moeda, nao global)" {
        Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:00:00Z") | Out-Null
        $r = Test-DailyMarketAlertThrottle -Market "ETHUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:05:00Z")
        $r | Should Be $true
    }

    It "madrugada (00-06h BRT) -> sempre suprime, mesmo no primeiro alerta do dia" {
        $r = Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T05:00:00Z")
        $r | Should Be $false
    }

    It "mesma moeda, motivos DIFERENTES (exposure_cap vs outro) -> throttle independente" {
        Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:00:00Z") | Out-Null
        $r = Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "outro_motivo" -StatePath $script:testStatePath -UtcNow ([datetime]"2026-08-15T15:01:00Z")
        $r | Should Be $true
    }

    It "StatePath invalido/sem permissao -> fail-open (permite, nao bloqueia alerta real por erro de I/O)" {
        $r = Test-DailyMarketAlertThrottle -Market "BTCUSDT" -Reason "exposure_cap" -StatePath "Z:\caminho\que\nao\existe\arquivo.json" -UtcNow ([datetime]"2026-08-15T15:00:00Z")
        $r | Should Be $true
    }
}

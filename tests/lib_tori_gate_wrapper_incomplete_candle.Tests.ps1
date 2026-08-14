# lib_tori_gate_wrapper_incomplete_candle.Tests.ps1 -- TDD
#
# Achado real 2026-08-14: Get-ToriHistoricalCandles retornava o candle 1h EM
# FORMACAO (as vezes com so 1-50min de vida, dependendo de quando o cron de
# 5min rodou dentro da hora) como se fosse o candle "atual" pro calculo de
# Get-VolumeClimax -- que compara volume atual contra a media dos 5
# anteriores, todos ja FECHADOS (60min completos). Confirmado com dado real
# em producao (2026-08-14 20:01 UTC): ACEUSDT tinha volume=53.71 no candle em
# formacao vs ~6000-22000 nos 5 anteriores (ratio=0.01); TUTUSDT 977.62 vs
# ~30000-111000 (ratio tambem proximo de zero). Auditoria de 92 avaliacoes
# reais do TORI Gate mostrou VOLUME_CLIMAX disparando so 4x -- consistente
# com esse viés estrutural (nao com volume genuinamente baixo).
#
# Fix: Get-ToriHistoricalCandles agora descarta o ultimo candle se sua idade
# (agora - timestamp) for menor que a duracao do periodo (ex: <3600s pra
# "1hour") -- garante que so candles FECHADOS entram no calculo de
# confluencia (volume climax, RSI, fractal, CHoCH, volume profile).

Describe "Get-ToriHistoricalCandles -- descarta candle em formacao" {
    BeforeAll {
        $agents = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        . (Join-Path $agents "lib_tori_confluence_detector.ps1")
        . (Join-Path $agents "lib_tori_gate_wrapper.ps1")
    }

    It "descarta o ultimo candle 1h quando sua idade e menor que 3600s (em formacao)" {
        # Candle mais recente com timestamp de "agora" (idade ~0s, claramente
        # em formacao) -- deve ser descartado, sobrando so os 9 anteriores.
        $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $closedMs = $nowMs - (2 * 3600 * 1000)  # 2h atras, bem fechado

        function Invoke-RestMethod {
            param($Uri, $Method, $TimeoutSec, $ErrorAction)
            $data = @()
            for ($i = 9; $i -ge 1; $i--) {
                $data += [PSCustomObject]@{ created_at=($closedMs - ($i * 3600 * 1000)); open=1.0; high=1.1; low=0.9; close=1.0; volume=1000.0 }
            }
            # ultimo candle: timestamp = agora (em formacao), volume baixo (parcial)
            $data += [PSCustomObject]@{ created_at=$nowMs; open=1.0; high=1.05; low=0.98; close=1.02; volume=5.0 }
            return [PSCustomObject]@{ code=0; data=$data }
        }

        $result = @(Get-ToriHistoricalCandles -Market "TESTUSDT" -Timeframe "1h" -Limit 10)
        $result.Count | Should Be 9
        $result[-1].volume | Should Be 1000.0
    }

    It "mantem o ultimo candle quando sua idade JA e maior que a duracao do periodo (genuinamente fechado)" {
        $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        # ultimo candle fechado ha 2h -- nao deve ser descartado
        $lastClosedMs = $nowMs - (2 * 3600 * 1000)

        function Invoke-RestMethod {
            param($Uri, $Method, $TimeoutSec, $ErrorAction)
            $data = @()
            for ($i = 9; $i -ge 0; $i--) {
                $data += [PSCustomObject]@{ created_at=($lastClosedMs - ($i * 3600 * 1000)); open=1.0; high=1.1; low=0.9; close=1.0; volume=1000.0 }
            }
            return [PSCustomObject]@{ code=0; data=$data }
        }

        $result = @(Get-ToriHistoricalCandles -Market "TESTUSDT" -Timeframe "1h" -Limit 10)
        $result.Count | Should Be 10
    }

    It "caso real ACEUSDT: ratio de volume climax sai de ~0.01 (bugado) para ~1.94 (correto) apos excluir candle em formacao" {
        if (-not (Get-Command Get-ConfluenceScoreEnhanced -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Dados reais capturados 2026-08-14 20:01 UTC (10 candles 1h, ACEUSDT).
        # O ultimo (as 20:00, com ~1.5min de vida) tinha volume=53.71 -- apos o
        # fix, o candle "atual" pro calculo passa a ser o de 19:00 (fechado,
        # volume=15443.84), que da ratio real ~1.94 contra a media dos 5
        # anteriores fechados.
        $volumes = @(21328.27, 22899.74, 12005.30, 11148.39, 7201.34, 6123.97, 7189.39, 8152.44, 15443.84)
        $r = Get-VolumeClimax -Volumes $volumes -Threshold 2.0
        $r.ratio | Should BeGreaterThan 1.5
        $r.ratio | Should BeLessThan 2.5
    }
}

# hit_rate_health.Tests.ps1 — TDD strict: saude do hit rate (GREEN/YELLOW/RED)
# 11+ tests: validar status, logs, consecutivos, truncamento
# UTF-8 BOM, Pester 3.x

Describe "Hit Rate Health Management" {
    # Load lib sob teste
    . "$PSScriptRoot\..\agents\lib_hit_rate.ps1"

    # Temp file para testes
    $testHistoryFile = Join-Path $env:TEMP "hit_rate_test_$$_$((Get-Random)).csv"

    BeforeEach {
        # Criar header CSV
        "timestamp,direction,rate,caught,total,universe_size" |
            Out-File -FilePath $testHistoryFile -Encoding utf8 -Force
        $global:JOURNAL_DIR = Split-Path $testHistoryFile
    }

    AfterEach {
        if (Test-Path $testHistoryFile) {
            Remove-Item $testHistoryFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Test-HitRateHealth" {
        It "retorna GREEN quando avg hit rate >= MinHitRatePct" {
            $now = Get-Date
            for ($i = 0; $i -lt 5; $i++) {
                $ts = $now.AddMinutes(-$i).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                "$ts,LONG,0.45,9,20,100" | Add-Content -Path $testHistoryFile -Encoding utf8
            }

            $result = Test-HitRateHealth -MinHitRatePct 30 -HistoryFile $testHistoryFile
            $result.health | Should Be "GREEN"
            $result.consecutive_low | Should Be 0
        }

        It "retorna GREEN quando arquivo vazio" {
            $result = Test-HitRateHealth -MinHitRatePct 30 -HistoryFile $testHistoryFile
            $result.health | Should Be "GREEN"
        }

        It "retorna YELLOW quando avg < MinHitRatePct" {
            # 4 ciclos baixos (< threshold default 5) para testar avg < min sem trigger RED
            $now = Get-Date
            for ($i = 0; $i -lt 4; $i++) {
                $ts = $now.AddMinutes(-$i).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                "$ts,LONG,0.20,4,20,100" | Add-Content -Path $testHistoryFile -Encoding utf8
            }

            $result = Test-HitRateHealth -MinHitRatePct 30 -HistoryFile $testHistoryFile
            $result.health | Should Be "YELLOW"
        }

        It "retorna RED quando >= threshold ciclos baixos no tail" {
            $now = Get-Date
            for ($i = 0; $i -lt 5; $i++) {
                $ts = $now.AddMinutes(-$i).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                "$ts,LONG,0.20,4,20,100" | Add-Content -Path $testHistoryFile -Encoding utf8
            }

            $result = Test-HitRateHealth -MinHitRatePct 30 -ConsecutiveCyclesThreshold 5 -HistoryFile $testHistoryFile
            $result.health | Should Be "RED"
        }
    }

    Context "Add-HitRateLog" {
        It "registra hit rate com timestamps em UTC ISO 8601" {
            $result = Add-HitRateLog -HitRateLong 0.45 -HitRateShort 0.35 -UniverseSize 150 -HistoryFile $testHistoryFile

            $result.hit_rate_long | Should Be 0.45
            $result.hit_rate_short | Should Be 0.35
            $result.avg_hit_rate | Should Be 0.40
            $result.timestamp | Should Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
        }

        It "grava LONG e SHORT como duas linhas separadas" {
            Add-HitRateLog -HitRateLong 0.50 -HitRateShort 0.40 -UniverseSize 200 -HistoryFile $testHistoryFile

            $lines = Get-Content $testHistoryFile | Where-Object { $_ -ne "" }
            $dataLines = $lines | Where-Object { $_ -notmatch "^timestamp" }
            # 2 linhas de dados (LONG + SHORT)
            $dataLines.Count | Should Be 2
            $dataLines[0] | Should Match "LONG"
            $dataLines[1] | Should Match "SHORT"
        }

        It "trunca arquivo a 100 registros quando exceder (rolling window)" {
            # Adicionar 50 logs iniciais
            for ($i = 0; $i -lt 50; $i++) {
                Add-HitRateLog -HitRateLong 0.40 -HitRateShort 0.35 -UniverseSize 100 -HistoryFile $testHistoryFile
            }

            # Adicionar mais 51 (total = 102 linhas de dados)
            for ($i = 0; $i -lt 51; $i++) {
                Add-HitRateLog -HitRateLong 0.45 -HitRateShort 0.40 -UniverseSize 150 -HistoryFile $testHistoryFile
            }

            $lines = Get-Content $testHistoryFile
            # Header + 100 data records = 101 lines
            ($lines.Count -le 101) | Should Be $true
        }

        It "permite custom HistoryFile path" {
            $customPath = Join-Path $env:TEMP "custom_hit_rate_$((Get-Random)).csv"
            Add-HitRateLog -HitRateLong 0.50 -HitRateShort 0.45 -HistoryFile $customPath

            Test-Path $customPath | Should Be $true
            Remove-Item $customPath -Force -ErrorAction SilentlyContinue
        }

        It "calcula avg_hit_rate como media de LONG e SHORT" {
            $result = Add-HitRateLog -HitRateLong 0.60 -HitRateShort 0.40 -UniverseSize 100 -HistoryFile $testHistoryFile
            # (0.60 + 0.40) / 2 = 0.50
            $result.avg_hit_rate | Should Be 0.50
        }

        It "registra universe_size nos dados" {
            Add-HitRateLog -HitRateLong 0.45 -HitRateShort 0.35 -UniverseSize 250 -HistoryFile $testHistoryFile

            $lines = Get-Content $testHistoryFile
            $lines[-1] | Should Match "250$"
        }
    }

    Context "Integration: health check com logs" {
        It "Test-HitRateHealth funciona com dados gravados via Add-HitRateLog" {
            # Gravar alguns logs
            Add-HitRateLog -HitRateLong 0.50 -HitRateShort 0.45 -UniverseSize 100 -HistoryFile $testHistoryFile
            Add-HitRateLog -HitRateLong 0.48 -HitRateShort 0.42 -UniverseSize 100 -HistoryFile $testHistoryFile
            Add-HitRateLog -HitRateLong 0.40 -HitRateShort 0.35 -UniverseSize 100 -HistoryFile $testHistoryFile

            $result = Test-HitRateHealth -MinHitRatePct 30 -HistoryFile $testHistoryFile
            $result.health | Should Be "GREEN"
            $result.sample_size | Should Be 6  # 3 logs x 2 (LONG+SHORT)
            $result.avg_hit_rate_pct | Should BeGreaterThan 0
        }
    }

    Context "Edge cases" {
        It "gracefully trata arquivo corrompido (retorna GREEN com reason=error)" {
            "invalid csv data" | Out-File -FilePath $testHistoryFile -Encoding utf8 -Force

            $result = Test-HitRateHealth -MinHitRatePct 30 -HistoryFile $testHistoryFile
            $result.health | Should Be "GREEN"
            $result.reason | Should Be "error_reading_file"
        }

        It "usa valores padrao quando MinHitRatePct nao especificado (30)" {
            $now = Get-Date
            "$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")),LONG,0.25,5,20,100" |
                Out-File -FilePath $testHistoryFile -Encoding utf8 -Append

            $result = Test-HitRateHealth -HistoryFile $testHistoryFile
            # 0.25 (25%) < 30% (padrao)
            $result.health | Should Be "YELLOW"
        }

        It "usa ConsecutiveCyclesThreshold padrao de 5 quando nao especificado" {
            $now = Get-Date
            for ($i = 0; $i -lt 5; $i++) {
                $ts = $now.AddMinutes(-$i).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                "$ts,LONG,0.20,4,20,100" | Add-Content -Path $testHistoryFile -Encoding utf8
            }

            $result = Test-HitRateHealth -HistoryFile $testHistoryFile
            # 5 ciclos consecutivos baixos com threshold 5 (padrao) = RED
            $result.health | Should Be "RED"
        }

        It "cria arquivo CSV se nao existir ao gravar log" {
            $newPath = Join-Path $env:TEMP "new_hit_rate_$((Get-Random)).csv"
            Remove-Item $newPath -ErrorAction SilentlyContinue

            Add-HitRateLog -HitRateLong 0.45 -HitRateShort 0.40 -HistoryFile $newPath

            Test-Path $newPath | Should Be $true
            Remove-Item $newPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Cleanup ja eh feito no AfterEach dentro do Describe

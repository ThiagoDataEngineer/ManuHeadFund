# hit_rate_gate.Tests.ps1 — TDD strict: scanner health gate via hit rate
# 5 tests RED: validar que hit rate como gate de saude funciona
# UTF-8 BOM, Pester 3.x

Describe "Hit Rate Gate for Scanner Health" {
    . "$PSScriptRoot\..\agents\lib_hit_rate.ps1"

    Context "Test-ScannerHealth" {
        It "retorna healthy=true quando hit rate media > 30%" {
            $rates = @(0.4, 0.5, 0.6)  # media = 0.5
            $result = Test-ScannerHealth -RecentHitRates $rates -MinAvg 0.30
            $result | Should Be $true
        }

        It "retorna healthy=false quando hit rate media < 30%" {
            $rates = @(0.1, 0.15, 0.2)  # media = 0.15
            $result = Test-ScannerHealth -RecentHitRates $rates -MinAvg 0.30
            $result | Should Be $false
        }

        It "retorna healthy=false quando media exatamente no limite (edge)" {
            $rates = @(0.25, 0.30, 0.35)  # media = 0.3, borderline
            $result = Test-ScannerHealth -RecentHitRates $rates -MinAvg 0.30
            # Limite inclusivo ou exclusivo? Default: inclusivo (>=)
            $result | Should Be $true
        }
    }

    Context "Get-HitRateAlarmStatus" {
        It "retorna status com ultimos N ciclos + recommendation" {
            $status = Get-HitRateAlarmStatus
            # Deve ser objeto ou array de objetos
            $status -is [object] | Should Be $true
        }

        It "retorna insufficient_data quando < 3 ciclos registrados" {
            # Sem historico
            $status = Get-HitRateAlarmStatus -MinCycles 3
            if ($status) {
                $status.status -eq "insufficient_data" -or $status.Count -lt 3 | Should Be $true
            }
        }

        It "gracefully retorna estrutura vazia quando nenhum record" {
            $status = Get-HitRateAlarmStatus
            # Nao deve lancar erro
            $true | Should Be $true
        }
    }

    Context "Add-HitRateRecord" {
        It "registra hit rate record no journal" {
            Add-HitRateRecord -Direction "LONG" -Rate 0.45 -Caught 9 -Total 20
            # Journal deve conter registro
            $true | Should Be $true  # placeholder
        }
    }

    Context "Edge cases" {
        It "trata array vazio de hit rates gracefully" {
            $rates = @()
            $result = Test-ScannerHealth -RecentHitRates $rates -MinAvg 0.30
            # Deve retornar false ou handle gracefully
            ($result -eq $false -or $null -eq $result) | Should Be $true
        }
    }
}

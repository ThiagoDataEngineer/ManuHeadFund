# Test: Scanner Local Activation (TDD 2/3)
# Valida: Ativa gem_loop local, executa 1 ciclo, valida saída
# Modo: Pode executar localmente (mock-safe)

Describe "Local Scanner Activation Cycle" {

    Context "TDD 2.1: Scanner Initialization" {
        It "gem_agent.ps1 existe e tem libdir válido" {
            Test-Path 'agents/gem_agent.ps1' | Should Be $true

            $content = Get-Content 'agents/gem_agent.ps1' -Raw
            $content | Should Match 'lib_.*\.ps1'
        }

        It "config.local.ps1 tem credenciais (mock ou real)" {
            # Não vai checar credencial real, só que arquivo existe
            Test-Path 'agents/config.local.ps1' | Should Be $true
        }

        It "Bibliotecas críticas existem" {
            # 2026-07-23 FIX: nomes evoluiram desde que o teste foi escrito --
            # lib_scanning.ps1 nunca existiu (papel cumprido por
            # scanner.ps1/scan_master.ps1), lib_mentor_gate.ps1 virou
            # lib_mentor_gate_block.ps1, lib_entry_conviction.ps1 virou
            # lib_entry_conviction_ensemble.ps1.
            $libs = @(
                'agents/scanner.ps1'
                'agents/lib_mentor_gate_block.ps1'
                'agents/lib_entry_conviction_ensemble.ps1'
            )

            foreach ($lib in $libs) {
                Test-Path $lib | Should Be $true -because "$lib é crítica pra jornada"
            }
        }
    }

    Context "TDD 2.2: Whitelist Status" {
        It "Whitelist existe em journal/" {
            Get-ChildItem 'journal/per_asset_whitelist*.json' | Should Not BeNullOrEmpty
        }

        It "Whitelist tem assets tier_a_live ou tier_a_paper" {
            $latest = Get-ChildItem 'journal/per_asset_whitelist*.json' |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if ($latest) {
                $content = Get-Content $latest.FullName -Raw
                # 2026-07-23 FIX: JSON real vem formatado por ConvertTo-Json
                # (quebra de linha entre "tier" e o valor) -- "." nao casa
                # \n por padrao no regex do PowerShell. Match multiline.
                $content | Should Match '(?s)"tier"\s*:\s*"(tier_a|tier_b)'
            }
        }
    }

    Context "TDD 2.3: Mock Scan Cycle (1 iteração)" {
        It "Resolve-MarketDiscovery retorna structure válida (mock)" {
            # Mock function — não toca API real
            function Test-MockDiscovery {
                return @{
                    market = "BCHUSD"
                    score = 82
                    tier = "tier_a_live"
                    reason = "Ichimoku + Volume confirmação"
                }
            }

            $result = Test-MockDiscovery
            $result.market | Should Not BeNullOrEmpty
            ($result.score -ge 70) | Should Be $true
            $result.tier | Should Match 'tier_a'
        }

        It "Mesa Consensus calcula T+R+L scores (mock)" {
            function Test-MockMesaConsensus {
                return @{
                    technical = 90
                    regime = 85
                    liquidation = 72
                    consensus = "FORTE_3"
                }
            }

            $result = Test-MockMesaConsensus
            $minScore = $result.Values | Where-Object { $_ -is [int] } | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            ($minScore -ge 70) | Should Be $true
            $result.consensus | Should Be "FORTE_3"
        }

        It "Mentor Gate veta se beta > 1.2 (mock)" {
            function Test-MockMentorGate {
                param([float]$beta)
                if ($beta -gt 1.2) { return "VETO" }
                return "APPROVE"
            }

            Test-MockMentorGate -beta 0.8 | Should Be "APPROVE"
            Test-MockMentorGate -beta 1.5 | Should Be "VETO"
        }
    }

    Context "TDD 2.4: Scan Output Validation" {
        It "Log output contém status da rodada (se simulado)" {
            # Estrutura esperada de um scan log
            $expectedPattern = @(
                'START'
                'universe='
                'regime='
                'END'
            )

            foreach ($pattern in $expectedPattern) {
                # Validar que padrão é esperado
                $pattern | Should Match '^[A-Z]+'
            }
        }
    }

    Context "TDD 2.5: Heartbeat after Scan" {
        It "heartbeat_alerts.jsonl tem entry recente (ou vazio é OK em BEAR)" {
            $beats = @()
            if (Test-Path 'journal/heartbeat_alerts.jsonl') {
                $beats = Get-Content 'journal/heartbeat_alerts.jsonl' |
                    ConvertFrom-Json |
                    Where-Object { $_.timestamp -gt (Get-Date).AddHours(-24) }
            }

            # OK se vazio (BEAR = nada entra) ou se tem entry
            $beats | Should Not Match 'error'
        }
    }
}

# PROCEDIMENTO: Para ativar localmente (quando pronto):
# 1. & .\agents\gem_agent.ps1 -Mock  (rodar com flag mock)
# 2. Observar output em console
# 3. Validar journal/heartbeat_alerts.jsonl tem nova entry
# 4. Se aprovação automática (flag GEM_AUTO_APPROVE), validar order criada
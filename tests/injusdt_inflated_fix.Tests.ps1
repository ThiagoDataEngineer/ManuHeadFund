# injusdt_inflated_fix.Tests.ps1 - Validar que INJUSDT nao esta mais inflado
# 
# Problemas corrigidos:
# 1. isWhitelistForced nao estava sendo setado -> Select-TopCandidates nao conseguia diferenciar
# 2. vol/volume inconsistencia -> Select-TopCandidates nao conseguia ordenar por volume
# 3. compScore nao estava sendo setado em forcados -> Select-TopCandidates nao conseguia ordenar
#
# Resultado esperado:
# - Em regime BEAR_WEAK, INJUSDT recebe tier_level=3 (rebaixado)
# - Select-TopCandidates coloca INJUSDT fora do top-N (apenas BTC anchor)
# - INJUSDT so aparece se scanner o encontrar organicamente com score alto

# Carrega libs aqui (Pester 3.x: BeforeAll nao exporta variaveis para It blocks)
$script:agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $script:agentsDir "lib_quant_whitelist.ps1")
. (Join-Path $script:agentsDir "lib_top_candidates.ps1")

Describe "INJUSDT Inflated Fix" {

    Context "isWhitelistForced field" {
        It "Merge-QuantWhitelistIntoCandidates adiciona isWhitelistForced=true aos forcados" {
            $candidates = @(
                [PSCustomObject]@{ market="ETHUSDT"; compScore=50; vol=1.5; isWhitelistForced=$false; tierLevel=99 }
            )
            
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -Mode "LIVE" `
                -AnchorMarkets @("BTCUSDT")
            
            # BTC deve estar nos resultados com isWhitelistForced=true
            $btc = $result | Where-Object { $_.market -eq "BTCUSDT" }
            $btc | Should Not BeNullOrEmpty
            $btc.isWhitelistForced | Should Be $true
        }

        It "Select-TopCandidates diferencia forcados de organicos" {
            $candidates = @(
                [PSCustomObject]@{ market="BTCUSDT"; compScore=100; vol=10; isWhitelistForced=$true; tierLevel=1 }
                [PSCustomObject]@{ market="ETHUSDT"; compScore=95; vol=8; isWhitelistForced=$false; tierLevel=99 }
                [PSCustomObject]@{ market="BNBUSDT"; compScore=90; vol=7; isWhitelistForced=$false; tierLevel=99 }
            )
            
            $result = Select-TopCandidates -Candidates $candidates -OrganicTopN 1
            
            # Resultado deve ser: BTC (forcado) + ETHUSDT (top-1 organico)
            $result.Count | Should Be 2
            $result[0].market | Should Be "BTCUSDT"
            $result[1].market | Should Be "ETHUSDT"
        }
    }

    Context "Regime-aware tier_level rebaixamento" {
        It "Get-MarketRegimeFromCache retorna regime global quando nao ha chave por-mercado" {
            # Simular regime_state.json com schema global (producao real)
            $tempDir = [System.IO.Path]::GetTempPath()
            $testFile = Join-Path $tempDir "regime_state.json"
            
            @{
                regime = "BEAR_WEAK"
                phase = "h24_p3_bear"
                bias = "BEAR_WEAK"
                current_regime = "BEAR_WEAK"
            } | ConvertTo-Json | Set-Content $testFile
            
            $regime = Get-MarketRegimeFromCache -Market "INJUSDT" -JournalDir $tempDir
            
            $regime | Should Be "BEAR_WEAK"
            
            Remove-Item $testFile -Force
        }

        It "Merge com RegimeProvider rebaixa tier_level em BEAR" {
            $regimeProvider = { param($m) "BEAR_WEAK" }
            
            $candidates = @()
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -Mode "LIVE" `
                -RegimeProvider $regimeProvider `
                -AnchorMarkets @("BTCUSDT", "INJUSDT")
            
            # BTC deve ter tier_level=1 (Tier A, nao rebaixado)
            $btc = $result | Where-Object { $_.market -eq "BTCUSDT" }
            $btc.tier_level | Should Be 1
            
            # INJUSDT deve ter tier_level=3 (rebaixado em BEAR)
            $inj = $result | Where-Object { $_.market -eq "INJUSDT" }
            $inj.tier_level | Should Be 3
        }
    }

    Context "Top-N organico real" {
        It "Select-TopCandidates com AnchorMarkets=@('BTCUSDT') coloca INJ fora do top" {
            # Simular cenario: 11 forcados (Tier A/B), 25 organicos
            $forced = @(
                "BTCUSDT", "INJUSDT", "RENDERUSDT", "CFGUSDT", "ZECUSDT",
                "PENDLEUSDT", "SUIUSDT", "SKYUSDT", "XRPUSDT", "BCHUSDT", "XMRUSDT"
            ) | ForEach-Object {
                [PSCustomObject]@{
                    market = $_
                    compScore = 100
                    vol = 5
                    isWhitelistForced = $true
                    tierLevel = if ($_ -eq "BTCUSDT") { 1 } else { 2 }
                }
            }
            
            $organic = @(1..25) | ForEach-Object {
                [PSCustomObject]@{
                    market = "ALT$_"
                    compScore = 50 + $_
                    vol = 2 + ($_/10)
                    isWhitelistForced = $false
                    tierLevel = 99
                }
            }
            
            $candidates = @($forced + $organic)
            
            # Com AnchorMarkets=@("BTCUSDT"), apenas BTC e forcado
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -AnchorMarkets @("BTCUSDT")
            
            # Contar forcados
            $forcedCount = @($result | Where-Object { $_.isWhitelistForced -eq $true }).Count
            $forcedCount | Should Be 1  # Apenas BTC
            
            # Selecionar top-20 organicos
            $topResult = Select-TopCandidates -Candidates $result -OrganicTopN 20
            
            # Resultado: BTC + 20 organicos (ALT6-ALT25, os com maior compScore)
            $topResult.Count | Should Be 21
            $topResult[0].market | Should Be "BTCUSDT"
            
            # INJUSDT nao deve estar no top
            $inj = $topResult | Where-Object { $_.market -eq "INJUSDT" }
            $inj | Should BeNullOrEmpty
        }

        It "vol field consistencia em forcados" {
            $candidates = @()
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -Mode "LIVE" `
                -AnchorMarkets @("BTCUSDT")
            
            # Todos os forcados devem ter campo 'vol' (nao 'volume')
            $btc = $result | Where-Object { $_.market -eq "BTCUSDT" }
            $btc.PSObject.Properties['vol'] | Should Not BeNullOrEmpty
            $btc.vol | Should Be 0.0
        }

        It "compScore field presente em forcados" {
            $candidates = @()
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -Mode "LIVE" `
                -AnchorMarkets @("BTCUSDT")
            
            # Todos os forcados devem ter compScore para Select-TopCandidates ordenar
            $btc = $result | Where-Object { $_.market -eq "BTCUSDT" }
            $btc.PSObject.Properties['compScore'] | Should Not BeNullOrEmpty
            $btc.compScore | Should Be 100
        }
    }

    Context "Backward compatibility" {
        It "Sem AnchorMarkets especificado, todos Tier A/B sao forcados (legacy)" {
            $candidates = @()
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -Mode "LIVE"
            
            # Sem -AnchorMarkets, deve retornar todos os Tier A/B forcados
            $forcedCount = @($result | Where-Object { $_.isWhitelistForced -eq $true }).Count
            $forcedCount | Should BeGreaterThan 0
        }

        It "AnchorMarkets=@() explicitamente desativa forcados" {
            $candidates = @()
            $result = Merge-QuantWhitelistIntoCandidates `
                -Candidates $candidates `
                -Mode "LIVE" `
                -AnchorMarkets @()
            
            # Com -AnchorMarkets @(), nenhum forcado
            $forcedCount = @($result | Where-Object { $_.isWhitelistForced -eq $true }).Count
            $forcedCount | Should Be 0
        }
    }
}

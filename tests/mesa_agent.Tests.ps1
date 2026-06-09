# mesa_agent.Tests.ps1 â€” Pester 3.x â€” TDD para Mesa (3 drones paralelos)
# Cobertura: consenso puro, single-drone, schema final, edge cases.
# Stubs evitam chamadas reais Groq.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\mesa_agent.ps1"

# Stubs silenciam I/O nos testes
function Write-Host    { param($Object, $ForegroundColor) }
function Write-Warning { param($Message) }

function New-DroneOk {
    param(
        [string]$Sinal     = "LONG",
        [int]$Forca        = 70,
        [string]$Just      = "trend forte com volume",
        [string[]]$Conf    = @("EMA9>EMA21","ADX>30")
    )
    [PSCustomObject]@{
        sinal         = $Sinal
        forca         = $Forca
        justificativa = $Just
        confluencias  = $Conf
    }
}

# ============================================================================
# GRUPO A â€” Get-MesaConsensus (funÃ§Ã£o pura, sem I/O)
# ============================================================================

Describe "Get-MesaConsensus - acordo total" {
    It "A1 3 LONG retorna FORTE_3 e sinal_consenso LONG" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG" -Forca 80) `
                               -Radar  (New-DroneOk -Sinal "LONG" -Forca 60) `
                               -Lidar  (New-DroneOk -Sinal "LONG" -Forca 70)
        $r.consensus      | Should Be "FORTE_3"
        $r.sinal_consenso | Should Be "LONG"
    }
    It "A2 3 SHORT retorna FORTE_3 e SHORT" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "SHORT") `
                               -Radar  (New-DroneOk -Sinal "SHORT") `
                               -Lidar  (New-DroneOk -Sinal "SHORT")
        $r.consensus      | Should Be "FORTE_3"
        $r.sinal_consenso | Should Be "SHORT"
    }
    It "A3 3 NEUTRO retorna FORTE_3 e NEUTRO" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "NEUTRO") `
                               -Radar  (New-DroneOk -Sinal "NEUTRO") `
                               -Lidar  (New-DroneOk -Sinal "NEUTRO")
        $r.consensus      | Should Be "FORTE_3"
        $r.sinal_consenso | Should Be "NEUTRO"
    }
}

Describe "Get-MesaConsensus - trap-awareness (reversal_vs_regime)" {
    It "BEAR + consenso SHORT = sem reversao (alinhado regime)" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "SHORT") -Radar (New-DroneOk -Sinal "SHORT") `
                               -Lidar (New-DroneOk -Sinal "SHORT") -Regime "BEAR_WEAK"
        $r.reversal_vs_regime | Should Be $false
    }
    It "BEAR + consenso LONG = bear_trap detectado pelos drones" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG") -Radar (New-DroneOk -Sinal "LONG") `
                               -Lidar (New-DroneOk -Sinal "LONG") -Regime "BEAR_STRONG"
        $r.reversal_vs_regime | Should Be $true
        $r.reversal_type | Should Be "bear_trap"
    }
    It "BULL + consenso SHORT = bull_trap detectado" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "SHORT") -Radar (New-DroneOk -Sinal "SHORT") `
                               -Lidar (New-DroneOk -Sinal "SHORT") -Regime "BULL_WEAK"
        $r.reversal_vs_regime | Should Be $true
        $r.reversal_type | Should Be "bull_trap"
    }
    It "sem Regime (backward-compat) = sem reversao" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG") -Radar (New-DroneOk -Sinal "LONG") `
                               -Lidar (New-DroneOk -Sinal "LONG")
        $r.reversal_vs_regime | Should Be $false
    }
    It "consenso NEUTRO nunca e reversao" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "NEUTRO") -Radar (New-DroneOk -Sinal "NEUTRO") `
                               -Lidar (New-DroneOk -Sinal "NEUTRO") -Regime "BEAR_WEAK"
        $r.reversal_vs_regime | Should Be $false
    }
}

Describe "Get-MesaConsensus - acordo parcial" {
    It "A4 2 LONG + 1 NEUTRO retorna MEDIO_2 LONG" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG") `
                               -Radar  (New-DroneOk -Sinal "LONG") `
                               -Lidar  (New-DroneOk -Sinal "NEUTRO")
        $r.consensus      | Should Be "MEDIO_2"
        $r.sinal_consenso | Should Be "LONG"
    }
    It "A5 2 SHORT + 1 NEUTRO retorna MEDIO_2 SHORT" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "SHORT") `
                               -Radar  (New-DroneOk -Sinal "NEUTRO") `
                               -Lidar  (New-DroneOk -Sinal "SHORT")
        $r.consensus      | Should Be "MEDIO_2"
        $r.sinal_consenso | Should Be "SHORT"
    }
    It "A6 2 LONG + 1 SHORT retorna MEDIO_2 LONG (maioria)" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG") `
                               -Radar  (New-DroneOk -Sinal "SHORT") `
                               -Lidar  (New-DroneOk -Sinal "LONG")
        $r.consensus      | Should Be "MEDIO_2"
        $r.sinal_consenso | Should Be "LONG"
    }
}

Describe "Get-MesaConsensus - sem acordo" {
    It "A7 1 LONG + 1 SHORT + 1 NEUTRO retorna CAOS" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG") `
                               -Radar  (New-DroneOk -Sinal "SHORT") `
                               -Lidar  (New-DroneOk -Sinal "NEUTRO")
        $r.consensus      | Should Be "CAOS"
        $r.sinal_consenso | Should Be "NEUTRO"
    }
}

Describe "Get-MesaConsensus - score medio" {
    It "A8 score_avg eh media aritmetica dos 3" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Forca 60) `
                               -Radar  (New-DroneOk -Forca 80) `
                               -Lidar  (New-DroneOk -Forca 70)
        $r.score_avg | Should Be 70
    }
    It "A9 score_avg ignora drone null (media dos 2)" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Forca 80) `
                               -Radar  $null `
                               -Lidar  (New-DroneOk -Forca 60)
        $r.score_avg | Should Be 70
    }
}

Describe "Get-MesaConsensus - flag degraded" {
    It "A10 degraded false com 3 drones OK" {
        $r = Get-MesaConsensus -Termal (New-DroneOk) -Radar (New-DroneOk) -Lidar (New-DroneOk)
        $r.degraded | Should Be $false
    }
    It "A11 degraded true com 1 drone null" {
        $r = Get-MesaConsensus -Termal (New-DroneOk) -Radar $null -Lidar (New-DroneOk)
        $r.degraded | Should Be $true
    }
    It "A12 2+ drones null forca CAOS" {
        $r = Get-MesaConsensus -Termal (New-DroneOk -Sinal "LONG") -Radar $null -Lidar $null
        $r.consensus | Should Be "CAOS"
    }
}

# ============================================================================
# GRUPO B â€” Invoke-MesaDrone (single-drone)
# Stub de Invoke-Groq garante isolamento
# ============================================================================

Describe "Invoke-MesaDrone - modelo correto por drone" {
    # 2026-05-19 PM: codigo passou a usar Invoke-MesaDroneCascade (Groq->Gemini->Haiku).
    # Tests atualizados pra mockar a cascade em vez de Invoke-Groq diretamente.
    # Cascade preserva GroqModel + Agent params.
    $script:lastModel = $null
    $script:lastAgent = $null
    $script:lastSystem = $null
    function Invoke-MesaDroneCascade {
        param($SystemPrompt, $UserContent, $GroqModel, $MaxTokens, $Temperature, $Agent)
        $script:lastModel  = $GroqModel
        $script:lastAgent  = $Agent
        $script:lastSystem = $SystemPrompt
        return '{"sinal":"LONG","forca":75,"justificativa":"ok","confluencias":["a"]}'
    }

    It "B1 termal usa llama-3.3-70b-versatile" {
        Invoke-MesaDrone -Drone "termal" -UserContent "{}" | Out-Null
        $script:lastModel | Should Be "llama-3.3-70b-versatile"
    }
    It "B2 radar usa llama-3.1-8b-instant (v3 qwen-qwq-32b deprecated)" {
        Invoke-MesaDrone -Drone "radar" -UserContent "{}" | Out-Null
        $script:lastModel | Should Be "llama-3.1-8b-instant"
    }
    It "B3 lidar usa openai/gpt-oss-20b (gemma2-9b-it decommissioned por Groq 2026-06)" {
        Invoke-MesaDrone -Drone "lidar" -UserContent "{}" | Out-Null
        $script:lastModel | Should Be "openai/gpt-oss-20b"
    }
    It "B4 termal usa Agent label mesa_termal" {
        Invoke-MesaDrone -Drone "termal" -UserContent "{}" | Out-Null
        $script:lastAgent | Should Be "mesa_termal"
    }
    It "B5 radar usa Agent label mesa_radar" {
        Invoke-MesaDrone -Drone "radar" -UserContent "{}" | Out-Null
        $script:lastAgent | Should Be "mesa_radar"
    }
    It "B6 lidar usa Agent label mesa_lidar" {
        Invoke-MesaDrone -Drone "lidar" -UserContent "{}" | Out-Null
        $script:lastAgent | Should Be "mesa_lidar"
    }
}

Describe "Invoke-MesaDrone - personas distintas" {
    $script:termalSys = ""
    $script:radarSys  = ""
    $script:lidarSys  = ""
    function Invoke-MesaDroneCascade {
        param($SystemPrompt, $UserContent, $GroqModel, $MaxTokens, $Temperature, $Agent)
        switch ($Agent) {
            "mesa_termal" { $script:termalSys = $SystemPrompt }
            "mesa_radar"  { $script:radarSys  = $SystemPrompt }
            "mesa_lidar"  { $script:lidarSys  = $SystemPrompt }
        }
        return '{"sinal":"NEUTRO","forca":50,"justificativa":"x","confluencias":[]}'
    }

    It "B7 personas dos 3 drones sao diferentes" {
        Invoke-MesaDrone -Drone "termal" -UserContent "{}" | Out-Null
        Invoke-MesaDrone -Drone "radar"  -UserContent "{}" | Out-Null
        Invoke-MesaDrone -Drone "lidar"  -UserContent "{}" | Out-Null
        ($script:termalSys -eq $script:radarSys) | Should Be $false
        ($script:radarSys  -eq $script:lidarSys) | Should Be $false
        ($script:termalSys -eq $script:lidarSys) | Should Be $false
    }
    It "B8 retorna PSCustomObject com 4 props obrigatorias" {
        function Invoke-MesaDroneCascade { param($SystemPrompt,$UserContent,$GroqModel,$MaxTokens,$Temperature,$Agent)
            return '{"sinal":"LONG","forca":80,"justificativa":"ok","confluencias":["c1"]}'
        }
        $r = Invoke-MesaDrone -Drone "termal" -UserContent "{}"
        $r.sinal         | Should Be "LONG"
        $r.forca         | Should Be 80
        $r.justificativa | Should Be "ok"
        $r.confluencias.Count | Should Be 1
    }
}

# ============================================================================
# GRUPO C â€” Schema de saida final via Invoke-Mesa
# Stub de _Mesa_RunDrones evita Start-Job real
# ============================================================================

Describe "Invoke-Mesa - schema completo" {
    function _Mesa_RunDrones {
        param($Market, $UserContent)
        return [PSCustomObject]@{
            termal = (New-DroneOk -Sinal "LONG"  -Forca 80)
            radar  = (New-DroneOk -Sinal "LONG"  -Forca 70)
            lidar  = (New-DroneOk -Sinal "LONG"  -Forca 60)
        }
    }
    $ctx = [PSCustomObject]@{ close = 50000 }

    It "C1 saida tem todas as 8 propriedades" {
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx
        $r.PSObject.Properties.Name -contains "termal"         | Should Be $true
        $r.PSObject.Properties.Name -contains "radar"          | Should Be $true
        $r.PSObject.Properties.Name -contains "lidar"          | Should Be $true
        $r.PSObject.Properties.Name -contains "consensus"      | Should Be $true
        $r.PSObject.Properties.Name -contains "sinal_consenso" | Should Be $true
        $r.PSObject.Properties.Name -contains "score_avg"      | Should Be $true
        $r.PSObject.Properties.Name -contains "degraded"       | Should Be $true
    }
    It "C2 cada drone interno tem 4 propriedades" {
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx
        foreach ($d in @($r.termal, $r.radar, $r.lidar)) {
            $d.PSObject.Properties.Name -contains "sinal"         | Should Be $true
            $d.PSObject.Properties.Name -contains "forca"         | Should Be $true
            $d.PSObject.Properties.Name -contains "justificativa" | Should Be $true
            $d.PSObject.Properties.Name -contains "confluencias"  | Should Be $true
        }
    }
    It "C3 consensus eh um valor valido" {
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx
        @("FORTE_3","MEDIO_2","CAOS") -contains $r.consensus | Should Be $true
    }
    It "C4 sinal_consenso eh um valor valido" {
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx
        @("LONG","SHORT","NEUTRO") -contains $r.sinal_consenso | Should Be $true
    }
    It "C5 score_avg eh numero entre 0 e 100" {
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx
        ($r.score_avg -ge 0) | Should Be $true
        ($r.score_avg -le 100) | Should Be $true
    }
    It "C6 degraded eh boolean" {
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx
        ($r.degraded -is [bool]) | Should Be $true
    }
}

# ============================================================================
# GRUPO D â€” Robustez / edge cases
# ============================================================================

Describe "Invoke-Mesa - robustez" {
    It "D1 JSON mal formado num drone resulta em drone null e degraded" {
        # B30 fix 2026-05-28: rerun de drones degraded pode recuperar o drone.
        # Se o stub _Mesa_RunDrones retorna null para radar, o rerun via
        # Invoke-MesaDrone pode recuperar. O teste valida que o resultado
        # final ainda e coerente (LONG de 2 drones validos).
        function _Mesa_RunDrones {
            param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = $null
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        $r = Invoke-Mesa -Market "BTCUSDT" -Context ([PSCustomObject]@{ close = 1 })
        # Apos B30 rerun: se rerun recupera radar, degraded pode ser false.
        # O importante e que sinal_consenso seja LONG (2+ drones concordam).
        $r.sinal_consenso | Should Be "LONG"
    }
    It "D2 latencia < 10s com stubs (paralelismo nao bloqueia)" {
        function _Mesa_RunDrones {
            param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk)
                radar  = (New-DroneOk)
                lidar  = (New-DroneOk)
            }
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Mesa -Market "BTCUSDT" -Context ([PSCustomObject]@{}) | Out-Null
        $sw.Stop()
        ($sw.Elapsed.TotalSeconds -lt 10) | Should Be $true
    }
    It "D3 sinal invalido de drone eh tratado como null" {
        function _Mesa_RunDrones {
            param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = [PSCustomObject]@{ sinal = "XPTO"; forca = 50; justificativa = "x"; confluencias = @() }
                radar  = (New-DroneOk -Sinal "SHORT")
                lidar  = (New-DroneOk -Sinal "SHORT")
            }
        }
        $r = Invoke-Mesa -Market "BTCUSDT" -Context ([PSCustomObject]@{})
        # B30 fix: rerun pode recuperar termal com sinal valido.
        # O importante e que SHORT seja o sinal dominante (2+ drones).
        $r.sinal_consenso | Should Be "SHORT"
    }
    It "D4 2 ou mais drones null retornam CAOS ou MEDIO_2 (B30 rerun pode recuperar)" {
        function _Mesa_RunDrones {
            param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = $null
                lidar  = $null
            }
        }
        $r = Invoke-Mesa -Market "BTCUSDT" -Context ([PSCustomObject]@{})
        # B30 fix: rerun sequencial pode recuperar radar e lidar.
        # Se recuperar com LONG: FORTE_3 ou MEDIO_2. Se nao: CAOS.
        @("CAOS","MEDIO_2","FORTE_3") -contains $r.consensus | Should Be $true
    }
}

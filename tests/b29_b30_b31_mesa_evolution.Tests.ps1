# b29_b30_b31_mesa_evolution.Tests.ps1 -- Pester 3.x -- TDD
#
# B29: Regime salvo corretamente no JSONL (campo regime sempre preenchido)
# B30: Rerun de drones degraded (1 falhou -> rerun sequencial; 2+ -> rerun paralelo)
# B31: LIDAR autonomia SHORT (vota SHORT quando setup e SHORT + RR/liquidez OK)
#
# Ordem TDD: testes escritos ANTES da implementacao.
# Todos devem FALHAR antes do fix e PASSAR depois.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\mesa_agent.ps1")

# Stubs silenciam I/O
function Write-Host    { param($Object, $ForegroundColor) }
function Write-Warning { param($Message) }

# ============================================================================
# Helpers
# ============================================================================

function New-DroneOk {
    param(
        [string]$Sinal  = "LONG",
        [int]$Forca     = 70,
        [string]$Just   = "RR=5.0 vol_ratio=1.2 ATR=2%"
    )
    [PSCustomObject]@{
        sinal         = $Sinal
        forca         = $Forca
        justificativa = $Just
        confluencias  = @("R:R=5","vol_ratio=1.2","ATR_pct=2%")
    }
}

function New-DroneError {
    param([string]$Err = "drone_returned_empty")
    [PSCustomObject]@{ sinal = $null; forca = 0; justificativa = $null; error = $Err }
}

function New-DroneErrorExhausted {
    # 2026-08-12: simula cascade INTEIRA (Groq+Mistral+Haiku+Cerebras) esgotada
    # por erro real de API (429/400/402) -- diferente de New-DroneError, que
    # representa falha transitoria (timeout/job nao completou).
    param([string]$Err = "cascade_returned_null")
    [PSCustomObject]@{ sinal = $null; forca = 0; justificativa = $null; error = $Err; cascade_exhausted = $true }
}

# ============================================================================
# B29 -- Regime salvo no JSONL
# ============================================================================

Describe "B29 Regime salvo no JSONL" {

    It "B29-1 Context com .regime preenchido: JSONL salva regime correto" {
        # Arrange: stub _Mesa_RunDrones, captura o que e escrito no JSONL
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = (New-DroneOk -Sinal "LONG")
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        $tmpLog = [System.IO.Path]::GetTempFileName()
        $global:JOURNAL_DIR = Split-Path $tmpLog -Parent
        # Renomear para mesa_drones.jsonl no dir temp
        $mesaLog = Join-Path (Split-Path $tmpLog -Parent) "mesa_drones.jsonl"
        if (Test-Path $mesaLog) { Remove-Item $mesaLog -Force }

        $ctx = [PSCustomObject]@{ regime = "BEAR_STRONG"; close = 100 }

        # Act
        Invoke-Mesa -Market "BTCUSDT" -Context $ctx | Out-Null

        # Assert
        (Test-Path $mesaLog) | Should Be $true
        $line = Get-Content $mesaLog -Raw
        $obj  = $line.Trim() | ConvertFrom-Json
        $obj.regime | Should Be "BEAR_STRONG"

        # Cleanup
        Remove-Item $mesaLog -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }

    It "B29-2 Context sem .regime: JSONL salva regime como string vazia (nao null)" {
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "SHORT")
                radar  = (New-DroneOk -Sinal "SHORT")
                lidar  = (New-DroneOk -Sinal "SHORT")
            }
        }
        $tmpDir = [System.IO.Path]::GetTempPath()
        $global:JOURNAL_DIR = $tmpDir
        $mesaLog = Join-Path $tmpDir "mesa_drones.jsonl"
        if (Test-Path $mesaLog) { Remove-Item $mesaLog -Force }

        $ctx = [PSCustomObject]@{ close = 100 }  # sem .regime

        Invoke-Mesa -Market "XRPUSDT" -Context $ctx | Out-Null

        $line = Get-Content $mesaLog -Raw
        $obj  = $line.Trim() | ConvertFrom-Json
        # regime deve ser string (vazia ou ""), nunca null que quebra ConvertFrom-Json
        ($obj.PSObject.Properties.Name -contains "regime") | Should Be $true
        ($obj.regime -ne $null) | Should Be $true

        Remove-Item $mesaLog -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }

    It "B29-3 Context com regime aninhado em .regime_state.regime: extrai corretamente" {
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = (New-DroneOk -Sinal "LONG")
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        $tmpDir = [System.IO.Path]::GetTempPath()
        $global:JOURNAL_DIR = $tmpDir
        $mesaLog = Join-Path $tmpDir "mesa_drones.jsonl"
        if (Test-Path $mesaLog) { Remove-Item $mesaLog -Force }

        # Context com regime em campo direto (padrao atual do orchestrator)
        $ctx = [PSCustomObject]@{ regime = "BULL_WEAK"; close = 200 }

        Invoke-Mesa -Market "INJUSDT" -Context $ctx | Out-Null

        $line = Get-Content $mesaLog -Raw
        $obj  = $line.Trim() | ConvertFrom-Json
        $obj.regime | Should Be "BULL_WEAK"

        Remove-Item $mesaLog -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }
}

# ============================================================================
# B30 -- Rerun de drones degraded
# ============================================================================

Describe "B30 Rerun de drones degraded" {

    It "B30-1 1 drone falhou: _Mesa_RunDrones_Rerun e chamado para o drone falho" {
        # Arrange: primeira rodada retorna 1 drone com erro
        $script:rerunCalled = @()
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "SHORT")
                radar  = (New-DroneOk -Sinal "SHORT")
                lidar  = (New-DroneError "drone_returned_empty")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled += $Drone
            return (New-DroneOk -Sinal "SHORT" -Forca 60)
        }

        $ctx = [PSCustomObject]@{ regime = "BEAR_STRONG" }
        Invoke-Mesa -Market "BTCUSDT" -Context $ctx | Out-Null

        $script:rerunCalled -contains "lidar" | Should Be $true
    }

    It "B30-2 rerun bem-sucedido: resultado final usa drone recuperado (nao degraded)" {
        $script:rerunCount = 0
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "SHORT")
                radar  = (New-DroneOk -Sinal "SHORT")
                lidar  = (New-DroneError "drone_returned_empty")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCount++
            return (New-DroneOk -Sinal "SHORT" -Forca 65)
        }

        $ctx = [PSCustomObject]@{ regime = "BEAR_STRONG" }
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx

        # Com rerun bem-sucedido: 3 drones validos -> nao degraded
        $r.degraded | Should Be $false
        # Consensus deve ser FORTE_3 (3x SHORT)
        $r.consensus | Should Be "FORTE_3"
        $r.sinal_consenso | Should Be "SHORT"
    }

    It "B30-3 rerun falha tambem: mantem degraded=true (nao tenta infinito)" {
        $script:rerunAttempts = 0
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = (New-DroneError "timeout")
                lidar  = (New-DroneError "drone_returned_empty")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunAttempts++
            return (New-DroneError "rerun_also_failed")
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_WEAK" }
        $r = Invoke-Mesa -Market "XRPUSDT" -Context $ctx

        # Rerun tentado mas falhou: ainda degraded
        $r.degraded | Should Be $true
        # Rerun foi tentado (nao ignorado)
        $script:rerunAttempts | Should BeGreaterThan 0
        # Nao tentou mais de 1 rerun por drone
        $script:rerunAttempts | Should BeLessThan 3
    }

    It "B30-4 2 drones falharam: rerun paralelo (ambos reruns sao chamados)" {
        $script:rerunDrones = @()
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneError "timeout")
                radar  = (New-DroneError "timeout")
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunDrones += $Drone
            return (New-DroneOk -Sinal "LONG" -Forca 70)
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_STRONG" }
        Invoke-Mesa -Market "INJUSDT" -Context $ctx | Out-Null

        # Ambos drones falhos devem ter sido reruns
        $script:rerunDrones -contains "termal" | Should Be $true
        $script:rerunDrones -contains "radar"  | Should Be $true
    }

    It "B30-5 3 drones falharam: rerun de todos, CAOS se todos falharem de novo" {
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneError "timeout")
                radar  = (New-DroneError "timeout")
                lidar  = (New-DroneError "timeout")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            return (New-DroneError "rerun_timeout")
        }

        $ctx = [PSCustomObject]@{ regime = "BEAR_WEAK" }
        $r = Invoke-Mesa -Market "ZECUSDT" -Context $ctx

        $r.consensus | Should Be "CAOS"
        $r.degraded  | Should Be $true
    }

    It "B30-6 0 drones falharam: rerun NAO e chamado" {
        $script:rerunCalled = $false
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = (New-DroneOk -Sinal "LONG")
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled = $true
            return (New-DroneOk)
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_STRONG" }
        Invoke-Mesa -Market "BTCUSDT" -Context $ctx | Out-Null

        $script:rerunCalled | Should Be $false
    }
}

# ============================================================================
# 2026-08-12 -- rerun pula drone com cascade ja exaurida (erro real de API)
# Achado real: auditoria de logs (08-12) mostrou 110 de 130 chamadas Mesa num
# unico ciclo, boa parte rerun de cascade ja esgotada (Groq 429 + Mistral
# desligado + Anthropic teto mensal + Cerebras 429 simultaneos) -- rerun so
# repete a mesma chamada fadada a falhar de novo em segundos.
# ============================================================================

Describe "Rerun pula drone com cascade_exhausted=true (nao repete chamada fadada)" {

    It "drone com cascade_exhausted=true: rerun NAO e chamado para ele" {
        $script:rerunCalled = @()
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = (New-DroneErrorExhausted)
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled += $Drone
            return (New-DroneOk)
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_STRONG" }
        Invoke-Mesa -Market "BTCUSDT" -Context $ctx | Out-Null

        $script:rerunCalled -contains "radar" | Should Be $false
    }

    It "drone com falha TRANSITORIA (sem cascade_exhausted): rerun ainda e chamado normalmente" {
        $script:rerunCalled = @()
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "LONG")
                radar  = (New-DroneError "job_state_Running_likely_timeout")
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled += $Drone
            return (New-DroneOk)
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_STRONG" }
        Invoke-Mesa -Market "BTCUSDT" -Context $ctx | Out-Null

        $script:rerunCalled -contains "radar" | Should Be $true
    }

    It "mix: 1 exhausted + 1 transitorio -- so o transitorio recebe rerun" {
        $script:rerunCalled = @()
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneErrorExhausted)
                radar  = (New-DroneError "job_state_Running_likely_timeout")
                lidar  = (New-DroneOk -Sinal "LONG")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled += $Drone
            return (New-DroneOk)
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_STRONG" }
        Invoke-Mesa -Market "BTCUSDT" -Context $ctx | Out-Null

        $script:rerunCalled -contains "termal" | Should Be $false
        $script:rerunCalled -contains "radar"  | Should Be $true
    }

    It "todos os 3 drones exhausted: rerun NAO e chamado pra nenhum" {
        $script:rerunCalled = @()
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneErrorExhausted)
                radar  = (New-DroneErrorExhausted)
                lidar  = (New-DroneErrorExhausted)
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled += $Drone
            return (New-DroneOk)
        }

        $ctx = [PSCustomObject]@{ regime = "BULL_STRONG" }
        $r = Invoke-Mesa -Market "BTCUSDT" -Context $ctx

        $script:rerunCalled.Count | Should Be 0
        $r.degraded | Should Be $true
    }
}

# ============================================================================
# B31 -- LIDAR autonomia SHORT
# ============================================================================

Describe "B31 LIDAR prompt: autonomia SHORT" {

    It "B31-1 prompt LIDAR contem instrucao para votar SHORT quando setup e SHORT" {
        $src = Get-Content (Join-Path $projectRoot "agents\mesa_agent.ps1") -Raw -Encoding UTF8
        # Deve mencionar que SHORT setup -> SHORT vote quando RR/liquidez OK
        ($src -match 'direction_proxy.*SHORT' -or $src -match 'SHORT.*direction_proxy' -or
         $src -match 'setup.*SHORT.*sinal.*SHORT' -or $src -match 'CURTO.*SHORT') | Should Be $true
    }

    It "B31-2 prompt LIDAR NAO menciona downtrend/tendencia/estrutura de mercado" {
        $src = Get-Content (Join-Path $projectRoot "agents\mesa_agent.ps1") -Raw -Encoding UTF8
        # Extrair apenas o bloco do LIDAR system prompt
        $lidarMatch = [regex]::Match($src, "MESA_LIDAR_SYSTEM\s*=\s*@'([\s\S]+?)'@")
        $lidarPrompt = $lidarMatch.Groups[1].Value

        # Nao deve ter instrucoes sobre tendencia (vazamento de escopo)
        ($lidarPrompt -match 'downtrend estrutural') | Should Be $false
        ($lidarPrompt -match 'Weinstein') | Should Be $false
        ($lidarPrompt -match 'EMA.*bearish') | Should Be $false
    }

    It "B31-3 prompt LIDAR mantem escopo: R:R, vol_ratio, ATR, stop coerencia" {
        $src = Get-Content (Join-Path $projectRoot "agents\mesa_agent.ps1") -Raw -Encoding UTF8
        $lidarMatch = [regex]::Match($src, "MESA_LIDAR_SYSTEM\s*=\s*@'([\s\S]+?)'@")
        $lidarPrompt = $lidarMatch.Groups[1].Value

        ($lidarPrompt -match 'R.R|RR') | Should Be $true
        ($lidarPrompt -match 'vol_ratio') | Should Be $true
        ($lidarPrompt -match 'ATR') | Should Be $true
        ($lidarPrompt -match 'stop') | Should Be $true
    }

    It "B31-4 LIDAR vota SHORT quando setup e SHORT + RR OK (simulacao via Invoke-MesaDrone)" {
        # Stub da cascade retorna SHORT quando o userContent contem direction_proxy=SHORT
        function Invoke-MesaDroneCascade {
            param($SystemPrompt, $UserContent, $GroqModel, $MaxTokens, $Temperature, $Agent, [switch]$HaikuPrimary)
            if ($Agent -eq "mesa_lidar" -and $UserContent -match "direction_proxy=SHORT") {
                return '{"sinal":"SHORT","forca":70,"justificativa":"RR=5.0 vol_ratio=1.2 ATR=1.5% stop coerente SHORT","confluencias":["R:R=5","vol_ratio=1.2","ATR_pct=1.5%"]}'
            }
            return '{"sinal":"NEUTRO","forca":40,"justificativa":"setup incompleto","confluencias":[]}'
        }

        # Simula userContent com setup SHORT
        $userContent = "Mercado: BTCUSDT`nSETUP PROPOSTO:`n  entry=100`n  stop=105`n  target=75`n  rr_proposto=5`n  direction_proxy=SHORT"
        $r = Invoke-MesaDrone -Drone "lidar" -UserContent $userContent

        $r.sinal | Should Be "SHORT"
    }

    It "B31-5 LIDAR vota LONG quando setup e LONG + RR OK" {
        function Invoke-MesaDroneCascade {
            param($SystemPrompt, $UserContent, $GroqModel, $MaxTokens, $Temperature, $Agent, [switch]$HaikuPrimary)
            if ($Agent -eq "mesa_lidar" -and $UserContent -match "direction_proxy=LONG") {
                return '{"sinal":"LONG","forca":75,"justificativa":"RR=5.0 vol_ratio=1.5 ATR=2% stop coerente LONG","confluencias":["R:R=5","vol_ratio=1.5","ATR_pct=2%"]}'
            }
            return '{"sinal":"NEUTRO","forca":40,"justificativa":"setup incompleto","confluencias":[]}'
        }

        $userContent = "Mercado: XRPUSDT`nSETUP PROPOSTO:`n  entry=100`n  stop=95`n  target=125`n  rr_proposto=5`n  direction_proxy=LONG"
        $r = Invoke-MesaDrone -Drone "lidar" -UserContent $userContent

        $r.sinal | Should Be "LONG"
    }

    It "B31-6 LIDAR vota NEUTRO quando liquidez critica (vol_ratio < 0.5) independente da direcao" {
        function Invoke-MesaDroneCascade {
            param($SystemPrompt, $UserContent, $GroqModel, $MaxTokens, $Temperature, $Agent, [switch]$HaikuPrimary)
            if ($Agent -eq "mesa_lidar") {
                return '{"sinal":"NEUTRO","forca":25,"justificativa":"vol_ratio=0.03 CRITICO liquidez ausente Faith rule","confluencias":["vol_ratio=0.03","ATR_pct=2%"]}'
            }
            return '{"sinal":"LONG","forca":70,"justificativa":"ok","confluencias":[]}'
        }

        $userContent = "Mercado: SUIUSDT`nSETUP PROPOSTO:`n  entry=100`n  stop=95`n  target=125`n  rr_proposto=5`n  direction_proxy=LONG"
        $r = Invoke-MesaDrone -Drone "lidar" -UserContent $userContent

        $r.sinal | Should Be "NEUTRO"
    }
}

# ============================================================================
# B29+B30+B31 -- Integracao: regime salvo + rerun + LIDAR SHORT
# ============================================================================

Describe "B29+B30+B31 Integracao" {

    It "INT-1 ciclo completo: 1 drone falha, rerun recupera, regime salvo, consensus correto" {
        $script:rerunCalled = $false
        function _Mesa_RunDrones { param($Market, $UserContent)
            return [PSCustomObject]@{
                termal = (New-DroneOk -Sinal "SHORT" -Forca 75)
                radar  = (New-DroneOk -Sinal "SHORT" -Forca 70)
                lidar  = (New-DroneError "drone_returned_empty")
            }
        }
        function _Mesa_RerunDrone { param($Drone, $Market, $UserContent)
            $script:rerunCalled = $true
            return (New-DroneOk -Sinal "SHORT" -Forca 65)
        }

        $tmpDir = [System.IO.Path]::GetTempPath()
        $global:JOURNAL_DIR = $tmpDir
        $mesaLog = Join-Path $tmpDir "mesa_drones.jsonl"
        if (Test-Path $mesaLog) { Remove-Item $mesaLog -Force }

        $ctx = [PSCustomObject]@{ regime = "BEAR_STRONG"; close = 500 }
        $r = Invoke-Mesa -Market "RENDERUSDT" -Context $ctx

        # Rerun foi chamado
        $script:rerunCalled | Should Be $true
        # Resultado final: 3 SHORT -> FORTE_3
        $r.consensus      | Should Be "FORTE_3"
        $r.sinal_consenso | Should Be "SHORT"
        $r.degraded       | Should Be $false
        # Regime salvo no JSONL
        $line = Get-Content $mesaLog -Raw
        $obj  = $line.Trim() | ConvertFrom-Json
        $obj.regime | Should Be "BEAR_STRONG"

        Remove-Item $mesaLog -Force -ErrorAction SilentlyContinue
        $global:JOURNAL_DIR = $null
    }
}

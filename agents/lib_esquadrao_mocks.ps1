# lib_esquadrao_mocks.ps1 -- Mocks de Triagem (Parte A) e Mesa (Parte B)
# Contrato compativel com o que orchestrator V6 espera consumir.
# Quando Parte A/B reais forem dot-sourced DEPOIS deste arquivo, substituem os mocks.
#
# Uso: . (Join-Path $PSScriptRoot "lib_esquadrao_mocks.ps1")   (antes de orchestrator V6)
# Depois: . (Join-Path $PSScriptRoot "triagem_agent.ps1")      (substitui Invoke-Triagem)
#         . (Join-Path $PSScriptRoot "mesa_agent.ps1")         (substitui Invoke-Mesa)

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Invoke-Triagem (mock Parte A)
# Retorna tier B fixo -- pipeline completo, sem decisao agressiva.
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
if (-not (Get-Command Invoke-Triagem -ErrorAction SilentlyContinue)) {
    function Invoke-Triagem {
        param([string]$Market, [PSCustomObject]$Context)
        return [PSCustomObject]@{
            tier            = "B"
            razao           = "mock-triagem"
            score_predicted = 65
            flags           = @()
            knowledge_cited = @()
            setup           = $null   # Parte A real preenche entry/stop/target
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Invoke-Mesa (mock Parte B)
# Retorna consensus FORTE_3 LONG -- caminho feliz para testar cascata.
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
if (-not (Get-Command Invoke-Mesa -ErrorAction SilentlyContinue)) {
    function Invoke-Mesa {
        param([string]$Market, [PSCustomObject]$Context)
        return [PSCustomObject]@{
            termal         = [PSCustomObject]@{ sinal="LONG"; forca=70; justificativa="mock-termal" }
            radar          = [PSCustomObject]@{ sinal="LONG"; forca=68; justificativa="mock-radar"  }
            lidar          = [PSCustomObject]@{ sinal="LONG"; forca=72; justificativa="mock-lidar"  }
            consensus      = "FORTE_3"
            sinal_consenso = "LONG"
            score_avg      = 70
            setup          = $null
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Get-RelevantKnowledge (mock Parte A) -- usado pelo MentorDebate via RAG
# Retorna chunks vazios para nao acoplar testes a knowledge real.
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
if (-not (Get-Command Get-RelevantKnowledge -ErrorAction SilentlyContinue)) {
    function Get-RelevantKnowledge {
        param([string]$Query, [int]$MaxChunks = 3)
        return @()
    }
}

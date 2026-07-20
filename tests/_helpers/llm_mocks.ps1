# tests/_helpers/llm_mocks.ps1 -- LLM mock infrastructure for Pester tests.
#
# Filosofia: testar logica dependente de LLM SEM queimar API call. Captura prompt
# enviado pra inspecao + retorna mock response controlada. Habilita TDD de:
#   - Mentor prompt integrity (gate slots present, forbidden phrases absent)
#   - Schema retry logic (1st invalid -> retry -> 2nd invalid -> ABORTAR)
#   - Cascade fallback behavior (primary fail -> secondary)
#
# Pattern Tauric-inspired: mock no nivel do BINDING (Invoke-Claude / Invoke-MentorCascade),
# nao no nivel de HTTP. Permite assertion sobre prompt construido.
#
# Uso:
#   . tests/_helpers/llm_mocks.ps1
#   Reset-LlmCapture
#   Mock Invoke-MentorCascade { Capture-And-Return -UserContent $UserContent -MockResponse (New-MockMentorResponse -Veredicto EXECUTAR) }
#   ... call code that triggers Invoke-MentorCascade ...
#   $capturedPrompt = Get-LlmCapture
#
# PS 5.1. UTF-8 BOM.


# ─── State (script-scoped, reset between tests) ───────────────────────────────

$script:LLM_CAPTURED_PROMPT     = ""
$script:LLM_CAPTURED_SYSTEM     = ""
$script:LLM_CALL_COUNT          = 0
$script:LLM_CAPTURED_CALLS      = @()  # historico de chamadas


function Reset-LlmCapture {
    <#
    .SYNOPSIS
    Limpa state de captura LLM. Chamar em BeforeEach de cada Describe block.
    #>
    $script:LLM_CAPTURED_PROMPT = ""
    $script:LLM_CAPTURED_SYSTEM = ""
    $script:LLM_CALL_COUNT      = 0
    $script:LLM_CAPTURED_CALLS  = @()
}


function Get-LlmCapture {
    <#
    .SYNOPSIS
    Retorna ultimo prompt capturado (UserContent enviado para Invoke-MentorCascade).
    #>
    return $script:LLM_CAPTURED_PROMPT
}


function Get-LlmCaptureCount {
    <#
    .SYNOPSIS
    Quantas chamadas LLM foram feitas desde Reset-LlmCapture.
    #>
    return $script:LLM_CALL_COUNT
}


function Get-LlmCaptureHistory {
    <#
    .SYNOPSIS
    Lista de @{system, user, n} para todas as chamadas desde reset.
    #>
    return ,$script:LLM_CAPTURED_CALLS
}


function Capture-And-Return {
    <#
    .SYNOPSIS
    Helper interno: captura prompt + incrementa counter + retorna mock response.

    .PARAMETER UserContent
    UserContent enviado (capturado).

    .PARAMETER SystemPrompt
    SystemPrompt enviado (capturado).

    .PARAMETER MockResponse
    String JSON ou string raw a retornar.
    #>
    param(
        [string] $UserContent = "",
        [string] $SystemPrompt = "",
        [Parameter(Mandatory)] [string] $MockResponse
    )
    $script:LLM_CAPTURED_PROMPT = $UserContent
    $script:LLM_CAPTURED_SYSTEM = $SystemPrompt
    $script:LLM_CALL_COUNT++
    $script:LLM_CAPTURED_CALLS += [PSCustomObject]@{
        n      = $script:LLM_CALL_COUNT
        system = $SystemPrompt
        user   = $UserContent
    }
    return $MockResponse
}


# ─── Mock response factories ──────────────────────────────────────────────────

function New-MockMentorResponse {
    <#
    .SYNOPSIS
    Gera JSON Mentor response valido para testes. Defaults sensatos, overridable.

    .PARAMETER Veredicto
    EXECUTAR / REVISAR / ABORTAR (default EXECUTAR).

    .PARAMETER Confianca
    0-100 (default 70).

    .PARAMETER Risco
    BAIXO / MEDIO / ALTO / EXTREMO (default MEDIO).

    .PARAMETER QualidadeFinal
    Texto livre (default "Setup decente com confluencia razoavel").

    .PARAMETER MotivoVeto
    Apenas se Veredicto != EXECUTAR.

    .PARAMETER LicaoAplicada
    Texto livre (default "padrao Tudor Jones: stop antes de entry").

    .PARAMETER ExtraFields
    Hashtable de campos adicionais a mergir no JSON.

    .EXAMPLE
    $r = New-MockMentorResponse -Veredicto ABORTAR -Confianca 30 -MotivoVeto "regime instavel"
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("EXECUTAR","REVISAR","ABORTAR")]
        [string] $Veredicto = "EXECUTAR",
        [int] $Confianca = 70,
        [ValidateSet("BAIXO","MEDIO","ALTO","EXTREMO")]
        [string] $Risco = "MEDIO",
        [string] $QualidadeFinal = "Setup decente com confluencia razoavel",
        [string] $MotivoVeto = "",
        [string] $LicaoAplicada = "padrao Tudor Jones: stop antes de entry",
        [hashtable] $ExtraFields = @{}
    )

    $obj = [ordered]@{
        veredicto         = $Veredicto
        confianca_mentor  = $Confianca
        risco_identificado = $Risco
        qualidade_final   = $QualidadeFinal
        motivo_veto       = $MotivoVeto
        o_que_falta       = @()
        licao_aplicada    = $LicaoAplicada
    }
    foreach ($k in $ExtraFields.Keys) { $obj[$k] = $ExtraFields[$k] }

    return ($obj | ConvertTo-Json -Compress -Depth 4)
}


function New-MockGroqResponse {
    <#
    .SYNOPSIS
    Gera string raw resposta Groq (usado por Mesa drones).

    .PARAMETER Sinal
    LONG / SHORT / NEUTRO.

    .PARAMETER Forca
    1-3 (drone strength vote).

    .PARAMETER Razao
    Texto curto justificativa.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("LONG","SHORT","NEUTRO")]
        [string] $Sinal = "LONG",
        [int] $Forca = 2,
        [string] $Razao = "RR favoravel, liquidez OK"
    )
    return "{`"sinal`":`"$Sinal`",`"forca`":$Forca,`"razao`":`"$Razao`"}"
}


# ─── Mock prompt assertion helpers ────────────────────────────────────────────

function Test-PromptContainsAllOf {
    <#
    .SYNOPSIS
    Retorna $true se prompt capturado contem TODOS os tokens listados.

    .EXAMPLE
    if (Test-PromptContainsAllOf -Tokens @("FQS=","GATE STATUS","EXECUTAR")) { ... }
    #>
    param([Parameter(Mandatory)] [string[]] $Tokens)
    $p = Get-LlmCapture
    foreach ($t in $Tokens) {
        if ($p -notlike "*$t*") { return $false }
    }
    return $true
}


function Test-PromptContainsNoneOf {
    <#
    .SYNOPSIS
    Retorna $true se prompt capturado NAO contem nenhum dos tokens (forbidden phrases).

    .EXAMPLE
    if (Test-PromptContainsNoneOf -Tokens @("Mesa pulou","FQS indisponivel")) { ... }
    #>
    param([Parameter(Mandatory)] [string[]] $Tokens)
    $p = Get-LlmCapture
    foreach ($t in $Tokens) {
        if ($p -like "*$t*") { return $false }
    }
    return $true
}

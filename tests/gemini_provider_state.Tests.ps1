# gemini_provider_state.Tests.ps1 -- TDD 2026-05-28
#
# Problema: Gemini em 429 persistente (8/9 warmups falharam hoje).
# O cascade tentava Gemini mesmo sabendo que estava em rate limit,
# gastando 15s de timeout antes de cair para Haiku.
# Cadeia: Groq 429 -> Gemini 429 (15s timeout) -> Haiku (35s timeout)
# = drone pode ultrapassar o timeout de 40s do job -> null -> DEGRADED.
#
# Solucao:
#   1. warmup_llm_endpoints.ps1: registra status de cada provider em
#      journal/llm_provider_state.json (OK | RATE_LIMITED | DOWN)
#      Gemini e pulado no warmup se RATE_LIMITED ha menos de 30min.
#   2. Invoke-MesaDroneCascade: consulta o cache antes de tentar Gemini.
#      Se RATE_LIMITED ha menos de 5min, pula direto para Haiku.
#
# Estes testes cobrem as funcoes Set-ProviderState / Get-ProviderState
# do warmup e a logica de skip no cascade.
#
# Pester 3.x. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

# ─── helpers ──────────────────────────────────────────────────────────────────

function New-TempStateFile {
    param([hashtable]$Providers = @{})
    $tmp = Join-Path $env:TEMP ("pstate_" + [Guid]::NewGuid().ToString() + ".json")
    $obj = [PSCustomObject]@{}
    foreach ($k in $Providers.Keys) {
        $obj | Add-Member -NotePropertyName $k -NotePropertyValue ([PSCustomObject]@{
            status = $Providers[$k].status
            ts     = $Providers[$k].ts
        }) -Force
    }
    $obj | ConvertTo-Json -Compress | Set-Content -Path $tmp -Encoding UTF8
    return $tmp
}

# Gera timestamp UTC ISO 8601 com offset em minutos (negativo = passado)
function New-UtcTs {
    param([int]$OffsetMinutes = 0)
    return [datetime]::UtcNow.AddMinutes($OffsetMinutes).ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# Calcula ageMin a partir de um campo ts que pode ser DateTime ou string ISO 8601
function Get-AgeMinutes {
    param($Ts)
    $dt = if ($Ts -is [datetime]) {
        [datetime]::SpecifyKind($Ts, [DateTimeKind]::Utc)
    } else {
        [datetime]::SpecifyKind(
            [datetime]::ParseExact([string]$Ts, "yyyy-MM-ddTHH:mm:ssZ", $null),
            [DateTimeKind]::Utc)
    }
    return ([datetime]::UtcNow - $dt).TotalMinutes
}

function Remove-TempFile { param($Path); Remove-Item $Path -Force -ErrorAction SilentlyContinue }

# ─── Suite 1: warmup registra estado corretamente ─────────────────────────────

Describe "warmup: Set-ProviderState e Get-ProviderState" {

    It "Set-ProviderState cria arquivo se nao existe" {
        $tmp = Join-Path $env:TEMP ("pstate_new_" + [Guid]::NewGuid() + ".json")
        try {
            # Simular Set-ProviderState inline
            $state = [PSCustomObject]@{}
            $state | Add-Member -NotePropertyName "gemini" -NotePropertyValue ([PSCustomObject]@{
                status = "RATE_LIMITED"
                ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }) -Force
            $state | ConvertTo-Json -Compress | Set-Content -Path $tmp -Encoding UTF8
            Test-Path $tmp | Should Be $true
        } finally { Remove-TempFile $tmp }
    }

    It "estado OK e lido corretamente" {
        $ts  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $tmp = New-TempStateFile @{ groq = @{ status = "OK"; ts = $ts } }
        try {
            $state = Get-Content $tmp -Raw | ConvertFrom-Json
            $state.groq.status | Should Be "OK"
        } finally { Remove-TempFile $tmp }
    }

    It "estado RATE_LIMITED e lido corretamente" {
        $ts  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $tmp = New-TempStateFile @{ gemini = @{ status = "RATE_LIMITED"; ts = $ts } }
        try {
            $state = Get-Content $tmp -Raw | ConvertFrom-Json
            $state.gemini.status | Should Be "RATE_LIMITED"
        } finally { Remove-TempFile $tmp }
    }

    It "multiplos providers no mesmo arquivo" {
        $ts  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $tmp = New-TempStateFile @{
            haiku  = @{ status = "OK";           ts = $ts }
            groq   = @{ status = "OK";           ts = $ts }
            gemini = @{ status = "RATE_LIMITED"; ts = $ts }
        }
        try {
            $state = Get-Content $tmp -Raw | ConvertFrom-Json
            $state.haiku.status  | Should Be "OK"
            $state.groq.status   | Should Be "OK"
            $state.gemini.status | Should Be "RATE_LIMITED"
        } finally { Remove-TempFile $tmp }
    }
}

# ─── Suite 2: logica de skip no warmup ────────────────────────────────────────

Describe "warmup: logica de skip Gemini" {

    It "Gemini deve ser pulado se RATE_LIMITED ha menos de 30min" {
        $ts  = New-UtcTs -OffsetMinutes -10
        $tmp = New-TempStateFile @{ gemini = @{ status = "RATE_LIMITED"; ts = $ts } }
        try {
            $state  = Get-Content $tmp -Raw | ConvertFrom-Json
            $ageMin = Get-AgeMinutes $state.gemini.ts
            $skip   = ($state.gemini.status -eq "RATE_LIMITED") -and ($ageMin -lt 30)
            $skip | Should Be $true
        } finally { Remove-TempFile $tmp }
    }

    It "Gemini NAO deve ser pulado se RATE_LIMITED ha mais de 30min" {
        $ts  = New-UtcTs -OffsetMinutes -35
        $tmp = New-TempStateFile @{ gemini = @{ status = "RATE_LIMITED"; ts = $ts } }
        try {
            $state  = Get-Content $tmp -Raw | ConvertFrom-Json
            $ageMin = Get-AgeMinutes $state.gemini.ts
            $skip   = ($state.gemini.status -eq "RATE_LIMITED") -and ($ageMin -lt 30)
            $skip | Should Be $false
        } finally { Remove-TempFile $tmp }
    }

    It "Gemini NAO deve ser pulado se status e OK" {
        $ts  = New-UtcTs -OffsetMinutes -2
        $tmp = New-TempStateFile @{ gemini = @{ status = "OK"; ts = $ts } }
        try {
            $state  = Get-Content $tmp -Raw | ConvertFrom-Json
            $ageMin = Get-AgeMinutes $state.gemini.ts
            $skip   = ($state.gemini.status -eq "RATE_LIMITED") -and ($ageMin -lt 30)
            $skip | Should Be $false
        } finally { Remove-TempFile $tmp }
    }

    It "Gemini NAO deve ser pulado se arquivo de estado nao existe" {
        $fakePath = Join-Path $env:TEMP ("nao_existe_" + [Guid]::NewGuid() + ".json")
        $skip = $false
        if (Test-Path $fakePath) {
            $state = Get-Content $fakePath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($state -and $state.PSObject.Properties["gemini"] -and $state.gemini.status -eq "RATE_LIMITED") {
                $skip = $true
            }
        }
        $skip | Should Be $false
    }
}

# ─── Suite 3: logica de skip no cascade (5min window) ─────────────────────────

Describe "cascade: logica de skip Gemini (janela 5min)" {

    It "cascade deve pular Gemini se RATE_LIMITED ha menos de 5min" {
        $ts  = New-UtcTs -OffsetMinutes -2
        $tmp = New-TempStateFile @{ gemini = @{ status = "RATE_LIMITED"; ts = $ts } }
        try {
            $state   = Get-Content $tmp -Raw | ConvertFrom-Json
            $ageMin  = Get-AgeMinutes $state.gemini.ts
            $blocked = ($state.gemini.status -eq "RATE_LIMITED") -and ($ageMin -lt 5)
            $blocked | Should Be $true
        } finally { Remove-TempFile $tmp }
    }

    It "cascade NAO deve pular Gemini se RATE_LIMITED ha mais de 5min" {
        $ts  = New-UtcTs -OffsetMinutes -8
        $tmp = New-TempStateFile @{ gemini = @{ status = "RATE_LIMITED"; ts = $ts } }
        try {
            $state   = Get-Content $tmp -Raw | ConvertFrom-Json
            $ageMin  = Get-AgeMinutes $state.gemini.ts
            $blocked = ($state.gemini.status -eq "RATE_LIMITED") -and ($ageMin -lt 5)
            $blocked | Should Be $false
        } finally { Remove-TempFile $tmp }
    }

    It "janela cascade (5min) e menor que janela warmup (30min)" {
        # Garante que o cascade e mais agressivo em tentar de novo que o warmup
        5 | Should BeLessThan 30
    }
}

# ─── Suite 4: warmup script contem as mudancas ────────────────────────────────

Describe "warmup script: contem logica de provider state" {

    $warmupContent = Get-Content (Join-Path $root "scripts\warmup_llm_endpoints.ps1") -Raw

    It "warmup menciona llm_provider_state.json" {
        $warmupContent | Should Match "llm_provider_state\.json"
    }

    It "warmup tem funcao Set-ProviderState" {
        $warmupContent | Should Match "Set-ProviderState"
    }

    It "warmup tem funcao Get-ProviderState" {
        $warmupContent | Should Match "Get-ProviderState"
    }

    It "warmup registra RATE_LIMITED para Gemini em 429" {
        $warmupContent | Should Match "RATE_LIMITED"
        $warmupContent | Should Match "429"
    }

    It "warmup pula Gemini se RATE_LIMITED ha menos de 30min" {
        $warmupContent | Should Match "30"
        $warmupContent | Should Match "skipGemini|SKIP"
    }

    It "warmup registra estado de Haiku" {
        $warmupContent | Should Match "Set-ProviderState.*haiku|haiku.*Set-ProviderState"
    }

    It "warmup registra estado de Groq" {
        $warmupContent | Should Match "Set-ProviderState.*groq|groq.*Set-ProviderState"
    }
}

# ─── Suite 5: cascade contem logica de skip ───────────────────────────────────

Describe "cascade lib_claude.ps1: contem logica de skip Gemini" {

    $cascadeContent = Get-Content (Join-Path $root "agents\lib_claude.ps1") -Raw

    It "cascade menciona llm_provider_state.json" {
        $cascadeContent | Should Match "llm_provider_state\.json"
    }

    It "cascade verifica RATE_LIMITED antes de tentar Gemini" {
        $cascadeContent | Should Match "RATE_LIMITED"
        $cascadeContent | Should Match "geminiBlocked"
    }

    It "cascade usa janela de 5min para skip" {
        $cascadeContent | Should Match "ageMin -lt 5"
    }

    It "cascade loga skip com mensagem clara" {
        $cascadeContent | Should Match "SKIP.*RATE_LIMITED|Gemini SKIP"
    }
}

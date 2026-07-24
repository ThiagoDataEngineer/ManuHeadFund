$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "tests\_helpers\llm_mocks.ps1")

Describe "Reset-LlmCapture" {
    It "Zera state apos chamada" {
        Capture-And-Return -UserContent "test" -SystemPrompt "sys" -MockResponse "x"
        (Get-LlmCaptureCount) | Should BeGreaterThan 0
        Reset-LlmCapture
        (Get-LlmCaptureCount) | Should Be 0
        (Get-LlmCapture) | Should Be ""
    }
}

Describe "Capture-And-Return" {
    BeforeEach { Reset-LlmCapture }

    It "Retorna MockResponse exato" {
        $r = Capture-And-Return -UserContent "u" -SystemPrompt "s" -MockResponse "RESPONSE"
        $r | Should Be "RESPONSE"
    }

    It "Captura UserContent acessivel via Get-LlmCapture" {
        Capture-And-Return -UserContent "MY PROMPT BODY" -MockResponse "x"
        (Get-LlmCapture) | Should Be "MY PROMPT BODY"
    }

    It "Incrementa counter a cada call" {
        Capture-And-Return -UserContent "a" -MockResponse "x"
        Capture-And-Return -UserContent "b" -MockResponse "x"
        Capture-And-Return -UserContent "c" -MockResponse "x"
        (Get-LlmCaptureCount) | Should Be 3
    }

    It "Mantem historico de todas as chamadas" {
        Capture-And-Return -UserContent "first" -SystemPrompt "S1" -MockResponse "x"
        Capture-And-Return -UserContent "second" -SystemPrompt "S2" -MockResponse "x"
        $hist = Get-LlmCaptureHistory
        $hist.Count | Should Be 2
        $hist[0].user | Should Be "first"
        $hist[1].user | Should Be "second"
        $hist[0].system | Should Be "S1"
        $hist[1].n | Should Be 2
    }
}

Describe "New-MockMentorResponse" {
    It "Default: EXECUTAR + confianca 70" {
        $r = New-MockMentorResponse
        $obj = $r | ConvertFrom-Json
        $obj.veredicto | Should Be "EXECUTAR"
        $obj.confianca_mentor | Should Be 70
        $obj.risco_identificado | Should Be "MEDIO"
    }

    It "Override veredicto + confianca" {
        $r = New-MockMentorResponse -Veredicto ABORTAR -Confianca 30 -MotivoVeto "regime ruim"
        $obj = $r | ConvertFrom-Json
        $obj.veredicto | Should Be "ABORTAR"
        $obj.confianca_mentor | Should Be 30
        $obj.motivo_veto | Should Be "regime ruim"
    }

    It "ExtraFields merge: campos custom adicionados" {
        $r = New-MockMentorResponse -ExtraFields @{ custom_field = "test_value"; another = 42 }
        $obj = $r | ConvertFrom-Json
        $obj.custom_field | Should Be "test_value"
        $obj.another | Should Be 42
    }

    It "JSON valido sempre" {
        $r = New-MockMentorResponse -Veredicto REVISAR -Confianca 55
        { $r | ConvertFrom-Json } | Should Not Throw
    }

    It "Rejects veredicto invalido (ValidateSet)" {
        $threw = $false
        try { New-MockMentorResponse -Veredicto "INVALIDO" } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "Rejects risco invalido (ValidateSet)" {
        $threw = $false
        try { New-MockMentorResponse -Risco "ULTRA_HIGH" } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe "New-MockGroqResponse" {
    It "Default: LONG forca 2" {
        $r = New-MockGroqResponse
        $obj = $r | ConvertFrom-Json
        $obj.sinal | Should Be "LONG"
        $obj.forca | Should Be 2
    }

    It "Override sinal + razao" {
        $r = New-MockGroqResponse -Sinal SHORT -Forca 3 -Razao "BREAK_DOWN clear"
        $obj = $r | ConvertFrom-Json
        $obj.sinal | Should Be "SHORT"
        $obj.razao | Should Be "BREAK_DOWN clear"
    }
}

Describe "Test-PromptContainsAllOf (assertion helper)" {
    BeforeEach { Reset-LlmCapture }

    It "True quando todos tokens presentes" {
        Capture-And-Return -UserContent "FQS=4/7 BLUE_CHIP GATE STATUS ok" -MockResponse "x"
        (Test-PromptContainsAllOf -Tokens @("FQS=","GATE STATUS")) | Should Be $true
    }

    It "False quando token ausente" {
        Capture-And-Return -UserContent "FQS=4/7 something" -MockResponse "x"
        (Test-PromptContainsAllOf -Tokens @("FQS=","GATE STATUS")) | Should Be $false
    }
}

Describe "Test-PromptContainsNoneOf (forbidden phrases)" {
    BeforeEach { Reset-LlmCapture }

    It "True quando nenhuma forbidden phrase presente" {
        Capture-And-Return -UserContent "FQS=4/7 BLUE_CHIP setup decent" -MockResponse "x"
        (Test-PromptContainsNoneOf -Tokens @("Mesa pulou","FQS indisponivel")) | Should Be $true
    }

    It "False quando uma forbidden phrase presente" {
        Capture-And-Return -UserContent "Mesa pulou neste cycle" -MockResponse "x"
        (Test-PromptContainsNoneOf -Tokens @("Mesa pulou","FQS indisponivel")) | Should Be $false
    }
}

Describe "Property: Capture-And-Return determinism" {
    BeforeEach { Reset-LlmCapture }

    It "Mesma entrada produz mesma captura" {
        $r1 = Capture-And-Return -UserContent "test" -SystemPrompt "sys" -MockResponse "X"
        Reset-LlmCapture
        $r2 = Capture-And-Return -UserContent "test" -SystemPrompt "sys" -MockResponse "X"
        $r1 | Should Be $r2
    }
}

Describe "Property: Reset is idempotent" {
    It "Multiple resets nao causam erro" {
        Reset-LlmCapture
        Reset-LlmCapture
        Reset-LlmCapture
        (Get-LlmCaptureCount) | Should Be 0
    }
}

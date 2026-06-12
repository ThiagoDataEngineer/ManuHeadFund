# lib_dashboard_crypto.Tests.ps1 - TDD criptografia do dashboard publico (2026-06-12)

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_dashboard_crypto.ps1")

Describe "Protect/Unprotect-DashboardData" {

    It "round-trip: cifra e decifra JSON identico (incl. acentos/emoji)" {
        $json = '{"capital":3657.45,"regime":"BEAR_WEAK","nota":"posições 🛡️"}'
        $env_ = Protect-DashboardData -Json $json -Password "senha-forte-123"
        $back = Unprotect-DashboardData -Envelope $env_ -Password "senha-forte-123"
        $back | Should Be $json
    }

    It "senha errada NAO decifra (GCM tag mismatch, nunca retorna lixo)" {
        $env_ = Protect-DashboardData -Json '{"x":1}' -Password "certa"
        # try/catch explicito: Should Throw do Pester 3.4 nao captura
        # MethodInvocationException de .NET de forma confiavel
        $threw = $false
        try { Unprotect-DashboardData -Envelope $env_ -Password "errada" | Out-Null } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "envelope tem s(16B)/iv(12B nonce GCM)/ct em base64 validos" {
        $env_ = Protect-DashboardData -Json '{"x":1}' -Password "p"
        ([Convert]::FromBase64String($env_.s)).Length | Should Be 16
        ([Convert]::FromBase64String($env_.iv)).Length | Should Be 12
        (([Convert]::FromBase64String($env_.ct)).Length -ge 17) | Should Be $true  # ct >= 1 + tag 16
    }

    It "salt/iv aleatorios: mesma entrada gera ciphertext diferente" {
        $a = Protect-DashboardData -Json '{"x":1}' -Password "p"
        $b = Protect-DashboardData -Json '{"x":1}' -Password "p"
        ($a.ct -ne $b.ct) | Should Be $true
        ($a.s -ne $b.s) | Should Be $true
    }

    It "ciphertext nao contem o plaintext (sanity)" {
        $env_ = Protect-DashboardData -Json '{"segredo":"capital_3657"}' -Password "p"
        ($env_.ct -notmatch "capital_3657") | Should Be $true
    }
}

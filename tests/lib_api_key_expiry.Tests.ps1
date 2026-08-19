# lib_api_key_expiry.Tests.ps1 -- TDD
#
# Achado real 2026-08-19: CoinEx API key expirou em 2026-08-17 (90 dias sem
# IP vinculado) sem NENHUM alerta -- causou phantom_reconciliation em massa
# (posicoes reais fechadas por engano) porque CoinEx-GetPendingPositions
# recebia code=4005 "access_id not exists", engolido silenciosamente.
# Owner decidiu nao vincular IP fixo (exigiria infra nova) -- fica nos 90
# dias, mas com aviso automatico com antecedencia desta vez.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_api_key_expiry.ps1")

Describe "Test-ApiKeyExpiryWarning -- calculo puro de dias restantes" {

    It "key recem-criada (0 dias) -- nao alerta, 90 dias restantes" {
        $r = Test-ApiKeyExpiryWarning -CreatedAt ([datetime]"2026-08-19") -Today ([datetime]"2026-08-19")
        $r.days_left | Should Be 90
        $r.should_warn | Should Be $false
        $r.expired | Should Be $false
    }

    It "faltando exatamente 10 dias (WarnDaysBefore default) -- comeca a alertar" {
        # criada 2026-08-19 + 90d = expira 2026-11-17; 10 dias antes = 2026-11-07
        $r = Test-ApiKeyExpiryWarning -CreatedAt ([datetime]"2026-08-19") -Today ([datetime]"2026-11-07")
        $r.days_left | Should Be 10
        $r.should_warn | Should Be $true
        $r.expired | Should Be $false
    }

    It "faltando 11 dias -- ainda nao alerta (limite exato)" {
        $r = Test-ApiKeyExpiryWarning -CreatedAt ([datetime]"2026-08-19") -Today ([datetime]"2026-11-06")
        $r.days_left | Should Be 11
        $r.should_warn | Should Be $false
    }

    It "caso real: key criada 2026-05-19 (90 dias), hoje 2026-08-19 -- ja expirada" {
        $r = Test-ApiKeyExpiryWarning -CreatedAt ([datetime]"2026-05-19") -Today ([datetime]"2026-08-19")
        $r.expired | Should Be $true
        $r.should_warn | Should Be $true
        ($r.days_left -le 0) | Should Be $true
    }

    It "WarnDaysBefore customizado (ex: 30) -- alerta mais cedo" {
        # criada 2026-08-19 + 90d = expira 2026-11-17; 2026-10-20 esta a 28 dias, dentro do piso de 30
        $r = Test-ApiKeyExpiryWarning -CreatedAt ([datetime]"2026-08-19") -Today ([datetime]"2026-10-20") -WarnDaysBefore 30
        $r.should_warn | Should Be $true
    }

    It "ValidityDays customizado (nao hardcoded 90)" {
        $r = Test-ApiKeyExpiryWarning -CreatedAt ([datetime]"2026-08-19") -ValidityDays 30 -Today ([datetime]"2026-08-19")
        $r.days_left | Should Be 30
    }
}

Describe "Get-ApiKeyExpiryDigestLines -- le registro e monta linhas do digest" {
    BeforeEach {
        $script:testRegistryPath = Join-Path $env:TEMP "api_key_expiry_test_$((Get-Random)).json"
    }
    AfterEach {
        if (Test-Path $script:testRegistryPath) { Remove-Item $script:testRegistryPath -Force -ErrorAction SilentlyContinue }
    }

    It "registro ausente -- retorna vazio (nao quebra o digest)" {
        $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath "Z:\nao\existe\arquivo.json")
        $lines.Count | Should Be 0
    }

    It "key dentro da validade, longe do vencimento -- silencio (nao polui o digest)" {
        @(@{ name="TESTKEY"; created_at="2026-08-19"; validity_days=90; renew_url="https://example.com" }) | ConvertTo-Json | Set-Content $script:testRegistryPath -Encoding UTF8
        $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath $script:testRegistryPath -Today ([datetime]"2026-08-20"))
        $lines.Count | Should Be 0
    }

    It "key perto do vencimento -- gera linha de alerta com dias restantes e URL de renovacao" {
        @(@{ name="TESTKEY"; created_at="2026-08-19"; validity_days=90; renew_url="https://example.com/apikey" }) | ConvertTo-Json | Set-Content $script:testRegistryPath -Encoding UTF8
        $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath $script:testRegistryPath -Today ([datetime]"2026-11-10"))
        $lines.Count | Should Be 1
        $lines[0] | Should Match "TESTKEY"
        $lines[0] | Should Match "https://example.com/apikey"
    }

    It "key ja expirada -- linha diz EXPIRADA explicitamente" {
        @(@{ name="TESTKEY"; created_at="2026-01-01"; validity_days=90; renew_url="https://example.com" }) | ConvertTo-Json | Set-Content $script:testRegistryPath -Encoding UTF8
        $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath $script:testRegistryPath -Today ([datetime]"2026-08-19"))
        $lines[0] | Should Match "EXPIRADA"
    }

    It "multiplas keys, so as que precisam de atencao aparecem" {
        @(
            @{ name="KEY_OK"; created_at="2026-08-19"; validity_days=90; renew_url="https://example.com" },
            @{ name="KEY_URGENTE"; created_at="2026-01-01"; validity_days=90; renew_url="https://example.com" }
        ) | ConvertTo-Json | Set-Content $script:testRegistryPath -Encoding UTF8
        $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath $script:testRegistryPath -Today ([datetime]"2026-08-19"))
        $lines.Count | Should Be 1
        $lines[0] | Should Match "KEY_URGENTE"
    }

    It "JSON malformado -- retorna aviso em vez de crashar o digest inteiro" {
        "isto nao e json valido {{{" | Set-Content $script:testRegistryPath -Encoding UTF8
        $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath $script:testRegistryPath)
        $lines.Count | Should Be 1
        $lines[0] | Should Match "malformado"
    }

    It "caso real: registro atual do projeto (journal/api_key_expiry.json) -- key criada hoje, sem alerta" {
        $realPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "Coinex_AI_USER_API\journal\api_key_expiry.json"
        if (-not (Test-Path $realPath)) {
            $realPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\api_key_expiry.json"
        }
        if (Test-Path $realPath) {
            $lines = @(Get-ApiKeyExpiryDigestLines -RegistryPath $realPath -Today ([datetime]"2026-08-19"))
            $lines.Count | Should Be 0
        }
    }
}

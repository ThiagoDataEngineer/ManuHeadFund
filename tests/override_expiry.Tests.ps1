# override_expiry.Tests.ps1 — TDD strict: expiry triggers para OVERRIDEs
# 12 tests: validar comportamento de expiração, warn, keep/disable actions
# UTF-8 BOM, Pester 3.x, PS 5.1 compatible

Describe "Override Expiry Management" {
    # Load lib sob teste
    . "$PSScriptRoot\..\agents\lib_override_expiry.ps1"

    # Setup: limpar journal entre testes
    BeforeEach {
        $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
        if (-not (Test-Path $global:JOURNAL_DIR)) {
            New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null
        }
    }

    AfterEach {
        $metaFile = Join-Path $global:JOURNAL_DIR "override_metadata.json"
        if (Test-Path $metaFile) {
            Remove-Item $metaFile -Force -ErrorAction SilentlyContinue
        }
        # Limpar variaveis globais
        Get-Variable -Name "OVERRIDE_*" -Scope Global -ErrorAction SilentlyContinue | Remove-Variable -Scope Global -Force -ErrorAction SilentlyContinue
    }

    Context "Test-OverrideExpired" {
        It "retorna expired=true, age_hours > TTL, action=disable se passado TTL" {
            $activatedAt = (Get-Date).AddHours(-48)
            $result = Test-OverrideExpired -OverrideName "TOPN" -ActivatedAt $activatedAt -TTLHours 24
            $result.expired | Should Be $true
            $result.age_hours -gt 24 | Should Be $true
            $result.action | Should Be "disable"
        }

        It "retorna expired=false, action=keep se dentro do TTL" {
            $activatedAt = (Get-Date).AddHours(-12)
            $result = Test-OverrideExpired -OverrideName "TOPN" -ActivatedAt $activatedAt -TTLHours 24
            $result.expired | Should Be $false
            $result.action | Should Be "keep"
        }

        It "retorna action=warn se entre 75% do TTL e 100% do TTL" {
            $activatedAt = (Get-Date).AddHours(-21)
            $result = Test-OverrideExpired -OverrideName "TOPN" -ActivatedAt $activatedAt -TTLHours 24
            $result.expired | Should Be $false
            $result.action | Should Be "warn"
        }

        It "retorna expired=false, age_hours=0, action=keep quando ActivatedAt null" {
            $result = Test-OverrideExpired -OverrideName "NEW" -ActivatedAt $null -TTLHours 72
            $result.expired | Should Be $false
            $result.age_hours | Should Be 0
            $result.action | Should Be "keep"
        }

        It "usa TTL padrao de 72 horas" {
            $activatedAt = (Get-Date).AddHours(-36)
            $result = Test-OverrideExpired -OverrideName "TEST" -ActivatedAt $activatedAt
            $result.expired | Should Be $false
        }

        It "retorna PSCustomObject com propriedades expired, age_hours, action" {
            $result = Test-OverrideExpired -OverrideName "OBJ" -ActivatedAt (Get-Date) -TTLHours 24
            $names = $result.PSObject.Properties.Name
            ($names -contains "expired")   | Should Be $true
            ($names -contains "age_hours") | Should Be $true
            ($names -contains "action")    | Should Be $true
        }
    }

    Context "Add-OverrideActivation" {
        It "registra override com timestamp e retorna PSCustomObject" {
            $result = Add-OverrideActivation -Name "TOPN_NEW" -Value 5 -TTLHours 24
            $result.name | Should Be "TOPN_NEW"
            $result.value | Should Be 5
            $result.ttl_hours | Should Be 24
        }

        It "seta variavel global OVERRIDE_<Name>" {
            Add-OverrideActivation -Name "GLOBAL_TEST" -Value 999 -TTLHours 24
            $global:OVERRIDE_GLOBAL_TEST | Should Be 999
        }

        It "cria arquivo override_metadata.json se nao existir" {
            Add-OverrideActivation -Name "FILE_TEST" -Value 100 -TTLHours 48
            $metaFile = Join-Path $global:JOURNAL_DIR "override_metadata.json"
            Test-Path $metaFile | Should Be $true
        }
    }

    Context "Get-OverrideMetadata" {
        It "retorna especifico quando Name fornecido" {
            Add-OverrideActivation -Name "LOOKUP_TEST" -Value 42 -TTLHours 72
            $meta = Get-OverrideMetadata -Name "LOOKUP_TEST"
            $meta -ne $null | Should Be $true
            if ($meta -ne $null) {
                $meta.name | Should Be "LOOKUP_TEST"
                $meta.value | Should Be 42
            }
        }

        It "retorna null quando nao encontrado" {
            $result = Get-OverrideMetadata -Name "NONEXISTENT_$$"
            $result | Should Be $null
        }

        It "retorna array quando Name nao especificado" {
            Add-OverrideActivation -Name "ALL1" -Value 1 -TTLHours 24
            Add-OverrideActivation -Name "ALL2" -Value 2 -TTLHours 48
            $all = Get-OverrideMetadata
            ($all -is [array]) | Should Be $true
        }

        It "calcula expired flag para cada override" {
            Add-OverrideActivation -Name "EXP_TEST" -Value 1 -TTLHours 24
            $meta = Get-OverrideMetadata -Name "EXP_TEST"
            $meta -ne $null | Should Be $true
            if ($meta -ne $null) {
                ($meta.PSObject.Properties.Name -contains "expired") | Should Be $true
            }
        }
    }

    Context "Set-OverrideWithExpiry (alias)" {
        It "funciona como alias para Add-OverrideActivation" {
            $result = Set-OverrideWithExpiry -Name "ALIAS_TEST" -Value 123 -TTLHours 48
            $result.name | Should Be "ALIAS_TEST"
            $result.value | Should Be 123
        }
    }

    Context "Edge cases" {
        It "trata arquivo corrompido gracefully" {
            $metaFile = Join-Path $global:JOURNAL_DIR "override_metadata.json"
            "{ invalid json" | Out-File $metaFile -Encoding utf8 -Force
            $result = Get-OverrideMetadata
            # Nao deve lancar excecao
            $true | Should Be $true
        }

        It "cria diretorio se nao existir" {
            # B6 fix 2026-05-20 PM6: $$ nao expande PID em PS; usar $PID e $env:TEMP
            # pra evitar leak de journal_new_test__* na raiz do projeto.
            $oldDir = $global:JOURNAL_DIR
            $global:JOURNAL_DIR = Join-Path $env:TEMP "journal_mkdir_test_${PID}_$((Get-Random))"
            try {
                Remove-Item $global:JOURNAL_DIR -Recurse -ErrorAction SilentlyContinue

                Add-OverrideActivation -Name "MKDIR_TEST" -Value 1 -TTLHours 24
                Test-Path $global:JOURNAL_DIR | Should Be $true
            } finally {
                Remove-Item $global:JOURNAL_DIR -Recurse -Force -ErrorAction SilentlyContinue
                $global:JOURNAL_DIR = $oldDir
            }
        }
    }
}

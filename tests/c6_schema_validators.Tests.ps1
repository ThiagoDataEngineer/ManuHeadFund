# C6 read-side schema validators TDD 2026-05-20 PM6+650min.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_json_contract.ps1")
. (Join-Path $projectRoot "agents\lib_schema_validators.ps1")

Describe "C6 Test-PromotionEventSchema" {
    It "Evento corretamente formatado: valid" {
        $line = '{"ts":"2026-05-20T18:00:00Z","event":"evaluated","market":"BTC","gate_eval":{"gate":"obs_to_c","passed":false,"failures":["sharpe_30d=0.5<1.0"]}}'
        $obj = $line | ConvertFrom-Json
        $r = Test-PromotionEventSchema -Event $obj
        $r.valid | Should Be $true
    }
    It "failures como string scalar (bug HYPE): invalid + violation listada" {
        $line = '{"ts":"2026-05-20T19:00:00Z","event":"evaluated","market":"HYPEUSDT","gate_eval":{"gate":"obs_to_c","passed":false,"failures":"sharpe_30d=0.6<1.0"}}'
        $obj = $line | ConvertFrom-Json
        $r = Test-PromotionEventSchema -Event $obj
        $r.valid | Should Be $false
        ($r.violations -match "failures").Count | Should BeGreaterThan 0
    }
    It "gate_eval ausente (success path simples): valid" {
        $line = '{"ts":"2026-05-20T20:00:00Z","event":"discovered","market":"BTC"}'
        $obj = $line | ConvertFrom-Json
        $r = Test-PromotionEventSchema -Event $obj
        $r.valid | Should Be $true
    }
}

Describe "C6 Invoke-PromotionPipelineAudit" {
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP "c6_audit_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    It "Arquivo com 3 entries OK + 2 buggy: report retorna counts certos" {
        $good = '{"ts":"2026-05-20T18:00:00Z","event":"evaluated","market":"BTC","gate_eval":{"failures":["a"]}}'
        $bad  = '{"ts":"2026-05-20T18:01:00Z","event":"evaluated","market":"HYPE","gate_eval":{"failures":"a"}}'
        Set-Content $tmp -Value @($good,$good,$bad,$good,$bad) -Encoding utf8
        $rep = Invoke-PromotionPipelineAudit -Path $tmp
        $rep.total_lines | Should Be 5
        $rep.valid | Should Be 3
        $rep.invalid | Should Be 2
    }
    It "Arquivo inexistente: report vazio sem throw" {
        $r = Invoke-PromotionPipelineAudit -Path (Join-Path $env:TEMP "nao_existe_$([guid]::NewGuid()).jsonl")
        $r.total_lines | Should Be 0
        $r.invalid | Should Be 0
    }
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_mentor_schema.ps1")
. (Join-Path $root "agents\lib_decision_reflection.ps1")

function _TmpReflPath {
    return (Join-Path $env:TEMP ("schtest_" + $PID + "_" + (Get-Random) + ".jsonl"))
}

function _MakeValidResponse {
    param([string]$Veredicto = "EXECUTAR", [int]$Conf = 70, [string]$Risco = "MEDIO", [string]$Motivo = "")
    $obj = [ordered]@{
        veredicto = $Veredicto
        confianca_mentor = $Conf
        risco_identificado = $Risco
    }
    if ($Motivo) { $obj.motivo_veto = $Motivo }
    elseif ($Veredicto -in @("REVISAR","ABORTAR","HARD_VETO")) { $obj.motivo_veto = "default_motivo" }
    return [PSCustomObject]$obj
}

Describe "Test-MentorOutput basic schema" {
    It "Resposta valida (EXECUTAR): passes" {
        $r = Test-MentorOutput -Response (_MakeValidResponse)
        $r.valid | Should Be $true
        $r.violations.Count | Should Be 0
    }

    It "Veredicto invalid: violation reportada" {
        $r = Test-MentorOutput -Response (_MakeValidResponse -Veredicto "MAYBE")
        $r.valid | Should Be $false
        ($r.violations -join " ") | Should Match "veredicto_invalid"
    }

    It "Confianca fora de 0-100: violation" {
        $r = Test-MentorOutput -Response (_MakeValidResponse -Conf 150)
        $r.valid | Should Be $false
        ($r.violations -join " ") | Should Match "confianca_out_of_range"
    }

    It "Risco invalid: violation" {
        $r = Test-MentorOutput -Response (_MakeValidResponse -Risco "ULTRA")
        $r.valid | Should Be $false
        ($r.violations -join " ") | Should Match "risco_invalid"
    }

    It "ABORTAR sem motivo_veto: violation" {
        $obj = [PSCustomObject]@{
            veredicto = "ABORTAR"
            confianca_mentor = 30
            risco_identificado = "ALTO"
            # motivo_veto omitted
        }
        $r = Test-MentorOutput -Response $obj
        $r.valid | Should Be $false
        ($r.violations -join " ") | Should Match "motivo_veto_required"
    }

    It "STRONG_EXECUTAR valido" {
        $r = Test-MentorOutput -Response (_MakeValidResponse -Veredicto "STRONG_EXECUTAR" -Conf 90)
        $r.valid | Should Be $true
    }

    It "HARD_VETO requires motivo" {
        $obj = [PSCustomObject]@{
            veredicto = "HARD_VETO"; confianca_mentor = 95; risco_identificado = "EXTREMO"
            motivo_veto = "regime extremo, blacklist"
        }
        $r = Test-MentorOutput -Response $obj
        $r.valid | Should Be $true
    }

    It "JSON string input parsea" {
        $json = '{"veredicto":"EXECUTAR","confianca_mentor":70,"risco_identificado":"MEDIO"}'
        $r = Test-MentorOutput -Response $json
        $r.valid | Should Be $true
    }

    It "JSON invalido: violation graceful" {
        $r = Test-MentorOutput -Response "not json"
        $r.valid | Should Be $false
        ($r.violations -join " ") | Should Match "invalid_json"
    }
}

Describe "Get-SizingTiltMultiplier" {
    BeforeAll { $script:tmpRefl = _TmpReflPath }
    AfterAll { if ($script:tmpRefl -and (Test-Path $script:tmpRefl)) { Remove-Item $script:tmpRefl -Force } }

    It "EXECUTAR retorna 1.0" {
        Get-SizingTiltMultiplier -Veredicto "EXECUTAR" -ReflectionsPath $script:tmpRefl | Should Be 1.0
    }

    It "REVISAR retorna 0.5" {
        Get-SizingTiltMultiplier -Veredicto "REVISAR" -ReflectionsPath $script:tmpRefl | Should Be 0.5
    }

    It "ABORTAR retorna 0" {
        Get-SizingTiltMultiplier -Veredicto "ABORTAR" -ReflectionsPath $script:tmpRefl | Should Be 0
    }

    It "HARD_VETO retorna 0" {
        Get-SizingTiltMultiplier -Veredicto "HARD_VETO" -ReflectionsPath $script:tmpRefl | Should Be 0
    }

    It "STRONG_EXECUTAR sem outcomes: CAPPED em 1.0" {
        # No reflections file = 0 STRONG outcomes = capped
        Get-SizingTiltMultiplier -Veredicto "STRONG_EXECUTAR" -ReflectionsPath $script:tmpRefl | Should Be 1.0
    }

    It "Unknown veredicto: retorna 0 (safe)" {
        Get-SizingTiltMultiplier -Veredicto "UNKNOWN" -ReflectionsPath $script:tmpRefl | Should Be 0
    }

    It "ForceCap=true mantem STRONG em 1.0 mesmo com outcomes" {
        $f = _TmpReflPath
        try {
            # Adiciona 35 STRONG_EXECUTAR resolved com alpha positive
            for ($i = 1; $i -le 35; $i++) {
                Add-PendingReflection -TradeId "S$i" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" `
                    -MentorVeredicto "STRONG_EXECUTAR" -ReflectionsPath $f
                Add-ResolvedReflection -TradeId "S$i" -ExitDateUtc "2026-05-25" -PnlPct 3 `
                    -AlphaVsBtc 1.5 -HoldingDays 3 -Reflection "good" -ReflectionsPath $f
            }
            # ForceCap=$true: should still be 1.0
            Get-SizingTiltMultiplier -Veredicto "STRONG_EXECUTAR" -ForceCap $true -ReflectionsPath $f | Should Be 1.0
            # ForceCap=$false (default): should be 1.5 (>= 30 outcomes)
            Get-SizingTiltMultiplier -Veredicto "STRONG_EXECUTAR" -ReflectionsPath $f | Should Be 1.5
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-StrongOutcomesCount" {
    It "Sem reflections file: 0" {
        $f = _TmpReflPath
        Get-StrongOutcomesCount -ReflectionsPath $f | Should Be 0
    }

    It "Conta apenas STRONG_EXECUTAR com alpha>0" {
        $f = _TmpReflPath
        try {
            # 2 STRONG positive
            Add-PendingReflection -TradeId "S1" -Market "BTCUSDT" -EntryDateUtc "2026-05-22" -MentorVeredicto "STRONG_EXECUTAR" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "S1" -ExitDateUtc "2026-05-25" -PnlPct 5 -AlphaVsBtc 2 -Reflection "x" -ReflectionsPath $f
            Add-PendingReflection -TradeId "S2" -Market "ETHUSDT" -EntryDateUtc "2026-05-22" -MentorVeredicto "STRONG_EXECUTAR" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "S2" -ExitDateUtc "2026-05-25" -PnlPct 3 -AlphaVsBtc 1 -Reflection "x" -ReflectionsPath $f
            # 1 STRONG negative (nao conta)
            Add-PendingReflection -TradeId "S3" -Market "DYDXUSDT" -EntryDateUtc "2026-05-22" -MentorVeredicto "STRONG_EXECUTAR" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "S3" -ExitDateUtc "2026-05-25" -PnlPct 1 -AlphaVsBtc -3 -Reflection "x" -ReflectionsPath $f
            # 1 EXECUTAR positive (NOT STRONG - nao conta)
            Add-PendingReflection -TradeId "E1" -Market "ATOMUSDT" -EntryDateUtc "2026-05-22" -MentorVeredicto "EXECUTAR" -ReflectionsPath $f
            Add-ResolvedReflection -TradeId "E1" -ExitDateUtc "2026-05-25" -PnlPct 5 -AlphaVsBtc 2 -Reflection "x" -ReflectionsPath $f

            Get-StrongOutcomesCount -ReflectionsPath $f | Should Be 2
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Invoke-MentorWithSchemaRetry" {
    It "Resposta valida 1st attempt: passes" {
        $valid = ([PSCustomObject]@{
            veredicto = "EXECUTAR"; confianca_mentor = 70; risco_identificado = "MEDIO"
        } | ConvertTo-Json -Compress)
        $mock = { param($s, $u) return $valid }
        $r = Invoke-MentorWithSchemaRetry -SystemPrompt "s" -UserContent "u" -MentorCascadeFn $mock
        $r.valid | Should Be $true
        $r.attempts | Should Be 1
        $r.forced_abortar | Should Be $false
    }

    It "Resposta invalida 1st + valida 2nd: passes attempt=2" {
        $script:_attempt = 0
        $mock = {
            param($s, $u)
            $script:_attempt++
            if ($script:_attempt -eq 1) {
                return '{"veredicto":"MAYBE","confianca_mentor":70,"risco_identificado":"MEDIO"}'
            } else {
                return '{"veredicto":"EXECUTAR","confianca_mentor":70,"risco_identificado":"MEDIO"}'
            }
        }
        $r = Invoke-MentorWithSchemaRetry -SystemPrompt "s" -UserContent "u" -MentorCascadeFn $mock
        $r.valid | Should Be $true
        $r.attempts | Should Be 2
    }

    It "Ambas attempts invalidas: force ABORTAR fallback" {
        $mock = { param($s, $u) return '{"veredicto":"INVALID"}' }
        $r = Invoke-MentorWithSchemaRetry -SystemPrompt "s" -UserContent "u" -MentorCascadeFn $mock
        $r.forced_abortar | Should Be $true
        $r.response.veredicto | Should Be "ABORTAR"
        $r.attempts | Should Be 2
    }

    It "Mentor retorna null: force ABORTAR" {
        $mock = { param($s, $u) return $null }
        $r = Invoke-MentorWithSchemaRetry -SystemPrompt "s" -UserContent "u" -MentorCascadeFn $mock
        $r.forced_abortar | Should Be $true
    }
}

Describe "Property: sizing multiplier safety bounds" {
    It "Nenhum tier retorna multiplier > 1.5" {
        foreach ($v in @("STRONG_EXECUTAR","EXECUTAR","REVISAR","ABORTAR","HARD_VETO")) {
            $m = Get-SizingTiltMultiplier -Veredicto $v -ForceCap $false -ReflectionsPath "/non_existent"
            ($m -le 1.5) | Should Be $true
            ($m -ge 0) | Should Be $true
        }
    }

    It "STRONG sem dados sempre returns <= 1.0 (safety)" {
        $m = Get-SizingTiltMultiplier -Veredicto "STRONG_EXECUTAR" -ReflectionsPath "/non_existent"
        ($m -le 1.0) | Should Be $true
    }
}

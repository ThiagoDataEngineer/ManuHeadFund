# lib_mentor_live.Tests.ps1 -- TDD para Test-MentorOverride (poder real de
# destravar gates de qualidade/sinal). Pester 3.4 / ASCII-only.
#
# Contrato NAO-NEGOCIAVEL: qualquer falha/excecao/timeout do LLM = fail-closed
# (approved=$false, gate original continua bloqueando). Sem o flag
# MENTOR_OVERRIDE_ENABLED.flag, sempre approved=$false (comportamento
# deterministico atual preservado).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_mentor_live.ps1"

Describe "Test-MentorOverride" {

    BeforeEach {
        $script:testFlagDir = Join-Path $env:TEMP ("mentorlive_" + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $script:testFlagDir -Force | Out-Null
        $script:origScriptRoot = $PSScriptRoot
    }
    AfterEach {
        if (Test-Path $script:testFlagDir) { Remove-Item $script:testFlagDir -Recurse -Force }
        Remove-Item Function:\global:Invoke-V6Cascade -ErrorAction SilentlyContinue
        $script:__mentorLiveLibsLoaded = $false
        $script:__mentorOverrideCallsThisRun = 0
    }

    Context "Sem flag MENTOR_OVERRIDE_ENABLED.flag (default hoje)" {
        It "retorna approved=false sem tentar carregar dependencias" {
            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "token_structural_quality" `
                -GateReason "teste" -Direction "LONG" -Price 100 -Change24h 3.0 -Regime "BEAR_WEAK" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
            $script:__mentorLiveLibsLoaded | Should Be $false
        }
    }

    Context "Com flag ativo -- LLM aprova o override" {
        It "retorna approved=true quando mentor.decision = APROVAR" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            function global:Invoke-V6Cascade {
                param($Market, $Context, $Setup)
                return [PSCustomObject]@{
                    decisao = "EXECUTAR"
                    motivo  = "mesa forte + mentor aprovou"
                    triagem = [PSCustomObject]@{ tier = "B" }
                    mesa    = [PSCustomObject]@{ consensus = "FORTE_3" }
                    mentor  = [PSCustomObject]@{ decision = "APROVAR"; confidence = 78 }
                }
            }
            $script:__mentorLiveLibsLoaded = $true

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "token_structural_quality" `
                -GateReason "teste" -Direction "LONG" -Price 100 -Change24h 3.0 -Regime "BEAR_WEAK" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $true
            $r.motivo | Should Match "APROVAR"
        }
    }

    Context "Com flag ativo -- LLM veta o override" {
        It "retorna approved=false quando mentor.decision = VETAR" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            function global:Invoke-V6Cascade {
                param($Market, $Context, $Setup)
                return [PSCustomObject]@{
                    decisao = "EXECUTAR"
                    motivo  = "mentor vetou"
                    triagem = [PSCustomObject]@{ tier = "C" }
                    mesa    = [PSCustomObject]@{ consensus = "FORTE_3" }
                    mentor  = [PSCustomObject]@{ decision = "VETAR"; confidence = 40 }
                }
            }
            $script:__mentorLiveLibsLoaded = $true

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "crowding" `
                -GateReason "teste" -Direction "SHORT" -Price 50 -Change24h -5.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
        }
    }

    Context "Com flag ativo -- cascade ABORTAR (Tier D ou Mesa CAOS)" {
        It "retorna approved=false quando decisao=ABORTAR" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            function global:Invoke-V6Cascade {
                param($Market, $Context, $Setup)
                return [PSCustomObject]@{
                    decisao = "ABORTAR"
                    motivo  = "tier D"
                    triagem = [PSCustomObject]@{ tier = "D" }
                    mesa    = $null
                    mentor  = $null
                }
            }
            $script:__mentorLiveLibsLoaded = $true

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "chart_pattern" `
                -GateReason "teste" -Direction "LONG" -Price 10 -Change24h 1.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
        }
    }

    Context "FAIL-CLOSED: excecao dentro da cascade" {
        It "retorna approved=false (nunca lanca excecao pro chamador)" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            function global:Invoke-V6Cascade {
                param($Market, $Context, $Setup)
                throw "erro simulado (timeout LLM, rede, etc)"
            }
            $script:__mentorLiveLibsLoaded = $true

            $script:__r = $null
            { $script:__r = Test-MentorOverride -Market "TESTUSDT" -GateTag "multi_tf_misalignment" `
                -GateReason "teste" -Direction "LONG" -Price 10 -Change24h 1.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir } | Should Not Throw
            $script:__r.approved | Should Be $false
        }
    }

    Context "Budget de overrides por ciclo" {
        It "nao chama o LLM quando budget do ciclo ja foi consumido" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_BUDGET.flag") -Encoding UTF8
            $script:callCount = 0
            function global:Invoke-V6Cascade {
                param($Market, $Context, $Setup)
                $script:callCount++
                return [PSCustomObject]@{
                    decisao = "EXECUTAR"; motivo = "ok"
                    triagem = [PSCustomObject]@{ tier = "B" }
                    mesa = $null
                    mentor = [PSCustomObject]@{ decision = "APROVAR"; confidence = 80 }
                }
            }
            $script:__mentorLiveLibsLoaded = $true

            $r1 = Test-MentorOverride -Market "A" -GateTag "crowding" -GateReason "x" -Direction "LONG" -Price 1 -Change24h 1 -Regime "NEUTRO" -FlagDir $script:testFlagDir
            $r2 = Test-MentorOverride -Market "B" -GateTag "crowding" -GateReason "x" -Direction "LONG" -Price 1 -Change24h 1 -Regime "NEUTRO" -FlagDir $script:testFlagDir

            $r1.approved | Should Be $true
            $script:callCount | Should Be 1
            $r2.approved | Should Be $false
            $r2.motivo | Should Match "budget"
        }
    }

    Context "Gate NAO elegivel (seguranca/infra) -- defesa em profundidade" {
        It "retorna approved=false mesmo com flag ativo, se GateTag nao esta na whitelist" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            function global:Invoke-V6Cascade {
                param($Market, $Context, $Setup)
                return [PSCustomObject]@{
                    decisao = "EXECUTAR"; motivo = "ok"
                    triagem = [PSCustomObject]@{ tier = "A" }
                    mesa = $null
                    mentor = [PSCustomObject]@{ decision = "APROVAR"; confidence = 90 }
                }
            }
            $script:__mentorLiveLibsLoaded = $true

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "circuit_breaker_daily_loss" `
                -GateReason "teste" -Direction "LONG" -Price 10 -Change24h 1.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
            $r.motivo | Should Match "nao elegivel"
        }
    }
}

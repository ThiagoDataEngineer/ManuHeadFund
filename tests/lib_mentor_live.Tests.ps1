# lib_mentor_live.Tests.ps1 -- TDD para Test-MentorOverride (poder real de
# destravar gates de qualidade/sinal). Pester 3.4 / ASCII-only.
#
# Contrato NAO-NEGOCIAVEL: qualquer falha/excecao/timeout do LLM = fail-closed
# (approved=$false, gate original continua bloqueando). Sem o flag
# MENTOR_OVERRIDE_ENABLED.flag, sempre approved=$false (comportamento
# deterministico atual preservado).
#
# 2026-07-25 FIX: "function global:Invoke-V6Cascade {...}" manual NAO
# sobrepoe de forma confiavel a Invoke-V6Cascade real (carregada via
# dot-source no nivel de modulo de lib_mentor_live.ps1) dentro do
# pipeline de execucao do Pester 3.4 -- confirmado em producao (run
# 30145266606: Mesa real disparou, 401 Mistral com credencial de teste,
# mesmo com "mock" definido no It). O cmdlet nativo `Mock` do Pester e'
# o mecanismo correto (funciona por scriptblock injection real no
# modulo de comando, nao redefinicao de function global simples).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_mentor_live.ps1"

Describe "Test-MentorOverride" {

    BeforeEach {
        $script:testFlagDir = Join-Path $env:TEMP ("mentorlive_" + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $script:testFlagDir -Force | Out-Null
        $script:__mentorOverrideCallsThisRun = 0
    }
    AfterEach {
        if (Test-Path $script:testFlagDir) { Remove-Item $script:testFlagDir -Recurse -Force }
        $script:__mentorOverrideCallsThisRun = 0
    }

    Context "Sem flag MENTOR_OVERRIDE_ENABLED.flag (default hoje)" {
        It "retorna approved=false (flag ausente barra ANTES de checar dependencias)" {
            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "token_structural_quality" `
                -GateReason "teste" -Direction "LONG" -Price 100 -Change24h 3.0 -Regime "BEAR_WEAK" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
            $r.motivo | Should Match "flag"
        }
    }

    Context "Com flag ativo -- LLM aprova o override" {
        It "retorna approved=true quando mentor.decision = APROVAR" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            Mock -CommandName Invoke-V6Cascade -MockWith {
                [PSCustomObject]@{
                    decisao = "EXECUTAR"
                    motivo  = "mesa forte + mentor aprovou"
                    triagem = [PSCustomObject]@{ tier = "B" }
                    mesa    = [PSCustomObject]@{ consensus = "FORTE_3" }
                    mentor  = [PSCustomObject]@{ decision = "APROVAR"; confidence = 78 }
                }
            }

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "token_structural_quality" `
                -GateReason "teste" -Direction "LONG" -Price 100 -Change24h 3.0 -Regime "BEAR_WEAK" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $true
            $r.motivo | Should Match "APROVAR"
            Assert-MockCalled -CommandName Invoke-V6Cascade -Times 1 -Exactly -Scope It
        }
    }

    Context "Com flag ativo -- LLM veta o override" {
        It "retorna approved=false quando mentor.decision = VETAR" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            Mock -CommandName Invoke-V6Cascade -MockWith {
                [PSCustomObject]@{
                    decisao = "EXECUTAR"
                    motivo  = "mentor vetou"
                    triagem = [PSCustomObject]@{ tier = "C" }
                    mesa    = [PSCustomObject]@{ consensus = "FORTE_3" }
                    mentor  = [PSCustomObject]@{ decision = "VETAR"; confidence = 40 }
                }
            }

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "crowding" `
                -GateReason "teste" -Direction "SHORT" -Price 50 -Change24h -5.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
        }
    }

    Context "Com flag ativo -- cascade ABORTAR (Tier D ou Mesa CAOS)" {
        It "retorna approved=false quando decisao=ABORTAR" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            Mock -CommandName Invoke-V6Cascade -MockWith {
                [PSCustomObject]@{
                    decisao = "ABORTAR"
                    motivo  = "tier D"
                    triagem = [PSCustomObject]@{ tier = "D" }
                    mesa    = $null
                    mentor  = $null
                }
            }

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "chart_pattern" `
                -GateReason "teste" -Direction "LONG" -Price 10 -Change24h 1.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
        }
    }

    Context "FAIL-CLOSED: excecao dentro da cascade" {
        It "retorna approved=false (nunca lanca excecao pro chamador)" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            Mock -CommandName Invoke-V6Cascade -MockWith {
                throw "erro simulado (timeout LLM, rede, etc)"
            }

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
            Mock -CommandName Invoke-V6Cascade -MockWith {
                [PSCustomObject]@{
                    decisao = "EXECUTAR"; motivo = "ok"
                    triagem = [PSCustomObject]@{ tier = "B" }
                    mesa = $null
                    mentor = [PSCustomObject]@{ decision = "APROVAR"; confidence = 80 }
                }
            }

            $r1 = Test-MentorOverride -Market "A" -GateTag "crowding" -GateReason "x" -Direction "LONG" -Price 1 -Change24h 1 -Regime "NEUTRO" -FlagDir $script:testFlagDir
            $r2 = Test-MentorOverride -Market "B" -GateTag "crowding" -GateReason "x" -Direction "LONG" -Price 1 -Change24h 1 -Regime "NEUTRO" -FlagDir $script:testFlagDir

            $r1.approved | Should Be $true
            $r2.approved | Should Be $false
            $r2.motivo | Should Match "budget"
            Assert-MockCalled -CommandName Invoke-V6Cascade -Times 1 -Exactly -Scope It
        }
    }

    Context "Gate NAO elegivel (seguranca/infra) -- defesa em profundidade" {
        It "retorna approved=false mesmo com flag ativo, se GateTag nao esta na whitelist" {
            "1" | Set-Content (Join-Path $script:testFlagDir "MENTOR_OVERRIDE_ENABLED.flag") -Encoding UTF8
            Mock -CommandName Invoke-V6Cascade -MockWith {
                [PSCustomObject]@{
                    decisao = "EXECUTAR"; motivo = "ok"
                    triagem = [PSCustomObject]@{ tier = "A" }
                    mesa = $null
                    mentor = [PSCustomObject]@{ decision = "APROVAR"; confidence = 90 }
                }
            }

            $r = Test-MentorOverride -Market "TESTUSDT" -GateTag "circuit_breaker_daily_loss" `
                -GateReason "teste" -Direction "LONG" -Price 10 -Change24h 1.0 -Regime "NEUTRO" `
                -FlagDir $script:testFlagDir
            $r.approved | Should Be $false
            $r.motivo | Should Match "nao elegivel"
            Assert-MockCalled -CommandName Invoke-V6Cascade -Times 0 -Exactly -Scope It
        }
    }
}

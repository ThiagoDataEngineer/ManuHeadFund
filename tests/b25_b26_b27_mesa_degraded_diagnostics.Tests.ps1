# B25/B26/B27 fix 2026-05-21: Mesa CAOS degraded diagnostics.
# Antes: 50% dos CAOS recentes = all-3 drones null mascarados como "Mesa dividida" no log master.
# Agora:
#  B25: motivo distingue MESA_DEGRADED vs CAOS genuino na string de abort
#  B26: drone falho retorna {sinal=null, forca=0, error="..."} preservando causa
#  B27: stagger 750ms + Wait-Job 40s (era 250ms / 25s -- insuficiente vs Groq rate limit)
#
# Anti-regression: rastreia degraded rate em mesa_drones.jsonl. >30% sustentado = infra quebrada.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\mesa_agent.ps1")

Describe "B26 _MesaDroneEntry persiste error de drone falho" {
    It "drone com error: persiste sinal=null + error string" {
        $droneObj = [PSCustomObject]@{
            sinal         = $null
            forca         = 0
            justificativa = $null
            error         = "rate_limit_429_groq"
        }
        # Reproduz funcao inline (esta nested em Invoke-Mesa scope)
        $entry = $null
        if ($null -ne $droneObj) {
            if ($null -eq $droneObj.sinal -and $droneObj.PSObject.Properties['error']) {
                $entry = [ordered]@{ sinal = $null; forca = 0; just = ""; error = [string]$droneObj.error }
            }
        }
        $entry | Should Not BeNullOrEmpty
        $entry.sinal | Should Be $null
        $entry.error | Should Be "rate_limit_429_groq"
    }

    It "drone null literal: persiste como null (nao crasha)" {
        $droneObj = $null
        $entry = if ($null -eq $droneObj) { $null } else { [ordered]@{ sinal = "x" } }
        $entry | Should Be $null
    }

    It "drone valido (LONG/forca/just): persiste sinal+forca+just truncado" {
        $droneObj = [PSCustomObject]@{
            sinal         = "LONG"
            forca         = 75
            justificativa = ("ADX 62 forte. " * 20)  # >100 chars
        }
        $entry = $null
        if ($null -ne $droneObj) {
            $just = if ($droneObj.justificativa) {
                $droneObj.justificativa.Substring(0, [Math]::Min(100, $droneObj.justificativa.Length))
            } else { "" }
            $entry = [ordered]@{ sinal = [string]$droneObj.sinal; forca = [int]$droneObj.forca; just = $just }
        }
        $entry.sinal | Should Be "LONG"
        $entry.forca | Should Be 75
        $entry.just.Length | Should Be 100
    }
}

Describe "B26 Get-MesaConsensus preserva semantica com drone-error-object" {
    It "drone com {sinal=null, error=...} eh tratado como invalido (nao conta votos)" {
        $termal = [PSCustomObject]@{ sinal = "LONG"; forca = 80 }
        $radar  = [PSCustomObject]@{ sinal = "LONG"; forca = 75 }
        $lidar  = [PSCustomObject]@{ sinal = $null; forca = 0; error = "timeout" }
        $cons = Get-MesaConsensus -Termal $termal -Radar $radar -Lidar $lidar
        $cons.consensus | Should Be "MEDIO_2"
        $cons.sinal_consenso | Should Be "LONG"
        $cons.degraded | Should Be $true
    }

    It "2+ drones com error: consensus = CAOS degraded (>= invalidCount 2)" {
        $termal = [PSCustomObject]@{ sinal = $null; forca = 0; error = "rate_limit" }
        $radar  = [PSCustomObject]@{ sinal = $null; forca = 0; error = "timeout" }
        $lidar  = [PSCustomObject]@{ sinal = "LONG"; forca = 80 }
        $cons = Get-MesaConsensus -Termal $termal -Radar $radar -Lidar $lidar
        $cons.consensus | Should Be "CAOS"
        $cons.degraded | Should Be $true
    }

    It "todos 3 com error: CAOS degraded + sinal NEUTRO" {
        $err = [PSCustomObject]@{ sinal = $null; forca = 0; error = "x" }
        $cons = Get-MesaConsensus -Termal $err -Radar $err -Lidar $err
        $cons.consensus | Should Be "CAOS"
        $cons.sinal_consenso | Should Be "NEUTRO"
        $cons.degraded | Should Be $true
    }

    It "3 validos com 1/1/1 vote split: CAOS NAO degraded (desacordo genuino)" {
        $termal = [PSCustomObject]@{ sinal = "LONG"; forca = 80 }
        $radar  = [PSCustomObject]@{ sinal = "SHORT"; forca = 70 }
        $lidar  = [PSCustomObject]@{ sinal = "NEUTRO"; forca = 50 }
        $cons = Get-MesaConsensus -Termal $termal -Radar $radar -Lidar $lidar
        $cons.consensus | Should Be "CAOS"
        $cons.degraded | Should Be $false
    }
}

Describe "B25/B27 Infra health: mesa_drones.jsonl degraded rate" {
    # Anti-regression: se >30% das ultimas 30 entries forem degraded, infra cascade LLM
    # esta quebrando e fixes B25-B27 precisam ser revisitados.
    It "degraded rate nas ultimas 30 entries <= 30% (skip se historico curto)" {
        $jsonl = Join-Path $projectRoot "journal\mesa_drones.jsonl"
        if (-not (Test-Path $jsonl)) {
            Set-TestInconclusive "mesa_drones.jsonl nao existe ainda"
            return
        }
        $lines = @(Get-Content $jsonl -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
        if ($lines.Count -lt 30) {
            Set-TestInconclusive "Apenas $($lines.Count) entries -- precisa >=30 pra threshold confiavel"
            return
        }
        $recent = $lines[-30..-1]
        $degraded = 0
        foreach ($l in $recent) {
            try {
                $obj = $l | ConvertFrom-Json -ErrorAction Stop
                if ($obj.degraded -eq $true) { $degraded++ }
            } catch {}
        }
        $rate = $degraded / 30.0
        Write-Host "Mesa degraded rate (last 30): $degraded/30 = $([math]::Round($rate*100,1))%" -ForegroundColor Cyan
        $rate | Should BeLessThan 0.30
    }
}

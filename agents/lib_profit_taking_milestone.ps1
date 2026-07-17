#requires -Version 5.1
<#
.SYNOPSIS
    Profit Taking Automático — Resgate em milestones, reinveste 90%

.DESCRIPTION
    Monitora capital
    Quando atinge milestone ($1k, $2k, $5k, $10k):
    - Resgate 10% do ganho acumulado
    - Reinveste 90% (compounding)
    - Log em wallet_withdrawals.jsonl

.EXAMPLE
    Check-MilestoneAndResgate -CurrentCapital 1050 -JournalPath "journal"
#>

# ATENCAO 2026-07-17: NAO CONECTAR sem antes implementar o TODO da linha ~78
# (Invoke-CoinExWithdrawal real). Ate la, "resgate" nao move nenhum fundo --
# so grava log. Zero callers hoje (confirmado via grep) -- arquivo mantido
# como referencia de design, nao como peca pronta pra wire. Ver tambem: meta
# de longo prazo do usuario e reinvestir enquanto o sistema calibra (6/10
# trades reais, win rate 33% no momento desta nota) -- auto-saque prematuro
# nao faz sentido antes de historico solido, independente do saque ser real.

function Check-MilestoneAndResgate {
    param(
        [decimal]$CurrentCapital,
        [string]$JournalPath = "journal",
        [switch]$SimulateOnly
    )

    $milestones = @(1000, 2000, 5000, 10000, 25000, 50000, 100000)
    $stateFile = Join-Path $JournalPath "milestone_state.json"

    # Load previous state
    $state = @{
        last_resgate_at = 0
        resgate_history = @()
        milestones_hit = @()
    }

    if (Test-Path $stateFile) {
        $state = Get-Content $stateFile | ConvertFrom-Json
        if (-not $state.resgate_history) {
            $state.resgate_history = @()
        }
        if (-not $state.milestones_hit) {
            $state.milestones_hit = @()
        }
    }

    $resgate_occurred = $false

    foreach ($milestone in $milestones) {
        # Se capital passou de milestone e ainda não foi resgatado neste nível
        if ($CurrentCapital -ge $milestone -and $state.last_resgate_at -lt $milestone) {

            # Ganho acumulado neste nível
            $ganho = $CurrentCapital - $state.last_resgate_at
            $resgate_amount = $ganho * 0.10  # Resgate 10%
            $reinvest_amount = $ganho * 0.90  # Reinveste 90%

            $record = @{
                timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                milestone = $milestone
                capital_at_milestone = $CurrentCapital
                ganho_acumulado = [math]::Round($ganho, 2)
                resgate_10_percent = [math]::Round($resgate_amount, 2)
                reinvest_90_percent = [math]::Round($reinvest_amount, 2)
                status = if($SimulateOnly) {"SIMULATED"} else {"SIMULATED_NOT_IMPLEMENTED"}
            }

            # Salvar histórico
            $state.resgate_history += $record
            $state.milestones_hit += $milestone
            $state.last_resgate_at = $milestone

            if (-not $SimulateOnly) {
                Write-Host "[MILESTONE] Atingido: $$$milestone" -ForegroundColor Green
                Write-Host "            Resgate calculado (NAO EXECUTADO -- saque real nao implementado): $($record.resgate_10_percent) USDT" -ForegroundColor Yellow
                Write-Host "            Reinvestindo (nocional): $($record.reinvest_90_percent) USDT" -ForegroundColor Cyan

                # TODO: Implementar resgate real para wallet (via Supabase ou API)
                # antes de conectar este arquivo em qualquer job -- sem isso,
                # status fica SIMULATED_NOT_IMPLEMENTED mesmo fora de -SimulateOnly.
                # . lib_coinex.ps1
                # Invoke-CoinExWithdrawal -Amount $resgate_amount -Token "USDT"
            } else {
                Write-Host "[SIMULATION] Milestone $$$milestone seria atingido" -ForegroundColor Yellow
                Write-Host "             Resgataria: $($record.resgate_10_percent) USDT" -ForegroundColor Yellow
            }

            $resgate_occurred = $true

            # Log em arquivo separado (auditoria)
            $logFile = Join-Path $JournalPath "wallet_withdrawals.jsonl"
            $record | ConvertTo-Json | Add-Content $logFile
        }
    }

    # Salvar novo state
    $state | ConvertTo-Json -Depth 5 | Out-File $stateFile -Encoding UTF8 -Force

    return @{
        resgate_occurred = $resgate_occurred
        current_capital = $CurrentCapital
        state = $state
    }
}

function Get-CompoundingStatus {
    param(
        [decimal]$StartCapital = 750,
        [decimal]$CurrentCapital,
        [string]$JournalPath = "journal"
    )

    $roi = (($CurrentCapital - $StartCapital) / $StartCapital) * 100
    $compound_factor = $CurrentCapital / $StartCapital

    $stateFile = Join-Path $JournalPath "milestone_state.json"
    $state = @{resgate_history = @()}

    if (Test-Path $stateFile) {
        $state = Get-Content $stateFile | ConvertFrom-Json
    }

    $total_resgated = if ($state.resgate_history) {
        ($state.resgate_history | Measure-Object -Property resgate_10_percent -Sum).Sum
    } else {
        0
    }

    $total_reinvested = if ($state.resgate_history) {
        ($state.resgate_history | Measure-Object -Property reinvest_90_percent -Sum).Sum
    } else {
        0
    }

    return @{
        start_capital = $StartCapital
        current_capital = [math]::Round($CurrentCapital, 2)
        roi_percent = [math]::Round($roi, 2)
        compound_factor = [math]::Round($compound_factor, 2)
        total_resgated = [math]::Round($total_resgated, 2)
        total_reinvested = [math]::Round($total_reinvested, 2)
        milestones_hit = $state.milestones_hit.Count
        timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

function Log-CompoundingDashboard {
    param(
        [decimal]$CurrentCapital = 750,
        [string]$JournalPath = "journal"
    )

    $status = Get-CompoundingStatus -CurrentCapital $CurrentCapital -JournalPath $JournalPath

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "COMPOUNDING STATUS" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green

    Write-Host "Capital: $($status.start_capital) → $($status.current_capital) USDT" -ForegroundColor Cyan
    Write-Host "ROI: +$($status.roi_percent)%" -ForegroundColor Green
    Write-Host "Compound Factor: $($status.compound_factor)x" -ForegroundColor Green
    Write-Host ""
    Write-Host "Milestones atingidos: $($status.milestones_hit)" -ForegroundColor Yellow
    Write-Host "Total resgatado: $($status.total_resgated) USDT (profit booking)" -ForegroundColor Cyan
    Write-Host "Total reinvestido: $($status.total_reinvested) USDT (compounding)" -ForegroundColor Cyan
    Write-Host ""

    return $status
}

# Export
Export-ModuleMember -Function Check-MilestoneAndResgate, Get-CompoundingStatus, Log-CompoundingDashboard

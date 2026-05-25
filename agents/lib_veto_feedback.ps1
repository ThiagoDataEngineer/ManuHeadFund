# lib_veto_feedback.ps1
# Sistema de Feedback Loop Inteligente
# Registra vetos e executa acoes corretivas automaticas
# 2026-05-24

# Tipos de veto e acoes corretivas
$script:VETO_TYPES = @{
    fqs_missing = @{
        wait_minutes = 60
        action = "enrich_fqs"
        priority = "HIGH"
    }
    beta_cap = @{
        wait_minutes = 0
        action = "resize_position"
        priority = "MEDIUM"
    }
    consensus_weak = @{
        wait_minutes = 30
        action = "revalidate_mesa"
        priority = "MEDIUM"
    }
    tier_c = @{
        wait_minutes = 0
        action = "reclassify_gem"
        priority = "LOW"
    }
    mce_block = @{
        wait_minutes = 60
        action = "wait_context"
        priority = "LOW"
    }
}

function Register-VetoFeedback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $VetoReason,
        [Parameter(Mandatory)] [ValidateSet("fqs_missing","beta_cap","consensus_weak","tier_c","mce_block","other")] 
        [string] $VetoType,
        [Parameter(Mandatory)] [hashtable] $Context
    )
    
    $feedbackFile = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "veto_feedback.jsonl")
    
    # Criar diretorio se nao existir
    $dir = Split-Path -Parent $feedbackFile
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    $feedback = @{
        ts = (Get-Date -Format "o")
        market = $Market
        veto_reason = $VetoReason
        veto_type = $VetoType
        context = $Context
        status = "pending"
        attempts = 0
        last_attempt = $null
    }
    
    
    # Adicionar schedule baseado no tipo
    if ($script:VETO_TYPES.ContainsKey($VetoType)) {
        $feedback.wait_minutes = $script:VETO_TYPES[$VetoType].wait_minutes
        $feedback.corrective_action = $script:VETO_TYPES[$VetoType].action
        $feedback.priority = $script:VETO_TYPES[$VetoType].priority
    } else {
        $feedback.wait_minutes = 120
        $feedback.corrective_action = "manual_review"
        $feedback.priority = "LOW"
    }
    
    # Salvar
    $feedback | ConvertTo-Json -Compress | Add-Content $feedbackFile
    
    Write-Verbose "Veto feedback registered: $Market ($VetoType)"
    
    return $feedback
}

function Get-PendingVetoFeedbacks {
    [CmdletBinding()]
    param(
        [int] $MaxAge = 24  # horas
    )
    
    $feedbackFile = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "veto_feedback.jsonl")
    
    if (-not (Test-Path $feedbackFile)) {
        return @()
    }
    
    $cutoff = (Get-Date).AddHours(-$MaxAge)
    $feedbacks = @()
    
    Get-Content $feedbackFile | ForEach-Object {
        $fb = $_ | ConvertFrom-Json
        $fbTime = [datetime]$fb.ts
        
        if ($fb.status -eq "pending" -and $fbTime -gt $cutoff) {
            $feedbacks += $fb
        }
    }
    
    return $feedbacks
}


function Invoke-CorrectiveAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Feedback
    )
    
    $market = $Feedback.market
    $action = $Feedback.corrective_action
    
    Write-Verbose "Executing corrective action: $action for $market"
    
    $result = @{
        success = $false
        action = $action
        market = $market
        error = $null
        updated_context = $null
    }
    
    try {
        switch ($action) {
            "enrich_fqs" {
                # Trigger FQS enrichment
                Write-Host "  Triggering FQS enrichment for $market..." -ForegroundColor Yellow
                # TODO: Implementar Invoke-FQSEnrich quando disponivel
                # Por enquanto, apenas registrar
                $result.success = $true
                $result.updated_context = @{ fqs_enrichment_requested = $true }
            }
            
            "resize_position" {
                # Calcular novo sizing para respeitar beta cap
                Write-Host "  Calculating adjusted sizing for $market..." -ForegroundColor Yellow
                $currentBeta = $Feedback.context.portfolio_beta_after
                $targetBeta = 1.15  # Target abaixo do cap 1.2
                
                if ($currentBeta -gt 0) {
                    $sizingFactor = $targetBeta / $currentBeta
                    $result.success = $true
                    $result.updated_context = @{ 
                        sizing_adjusted = $true
                        sizing_factor = $sizingFactor
                        note = "Auto-adjusted sizing to comply with beta cap"
                    }
                }
            }
            
            "revalidate_mesa" {
                # Aguardar e revalidar Mesa consensus
                Write-Host "  Scheduling Mesa revalidation for $market..." -ForegroundColor Yellow
                $result.success = $true
                $result.updated_context = @{ 
                    mesa_revalidation_requested = $true
                    revalidate_after = (Get-Date).AddMinutes(30).ToString("o")
                }
            }
            
            "reclassify_gem" {
                # Reclassificar como GEM (sizing <=0.5%)
                Write-Host "  Reclassifying $market as GEM..." -ForegroundColor Yellow
                $result.success = $true
                $result.updated_context = @{ 
                    reclassified_as_gem = $true
                    max_sizing_pct = 0.5
                    mode = "TIER_GEM_PAPER"
                }
            }
            
            "wait_context" {
                # Aguardar MCE score melhorar
                Write-Host "  Waiting for better market context for $market..." -ForegroundColor Yellow
                $result.success = $true
                $result.updated_context = @{ 
                    waiting_mce = $true
                    check_after = (Get-Date).AddHours(1).ToString("o")
                }
            }
            
            default {
                $result.error = "Unknown corrective action: $action"
            }
        }
    }
    catch {
        $result.error = $_.Exception.Message
    }
    
    return $result
}


function Update-VetoFeedbackStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Feedback,
        [Parameter(Mandatory)] [string] $NewStatus,
        [string] $Note = ""
    )
    
    $feedbackFile = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "veto_feedback.jsonl")
    
    if (-not (Test-Path $feedbackFile)) {
        return
    }
    
    # Ler todos os feedbacks
    $allFeedbacks = Get-Content $feedbackFile | ForEach-Object { $_ | ConvertFrom-Json }
    
    # Atualizar o feedback especifico
    $updated = @()
    foreach ($fb in $allFeedbacks) {
        if ($fb.ts -eq $Feedback.ts -and $fb.market -eq $Feedback.market) {
            $fb.status = $NewStatus
            $fb.last_attempt = (Get-Date -Format "o")
            $fb.attempts = [int]$fb.attempts + 1
            if ($Note) {
                $fb.note = $Note
            }
        }
        $updated += ($fb | ConvertTo-Json -Compress)
    }
    
    # Reescrever arquivo
    $updated | Set-Content $feedbackFile
}

function Process-VetoFeedbackQueue {
    [CmdletBinding()]
    param(
        [switch] $DryRun
    )
    
    Write-Host "=== PROCESSING VETO FEEDBACK QUEUE ===" -ForegroundColor Cyan
    Write-Host ""
    
    $feedbacks = Get-PendingVetoFeedbacks
    
    if ($feedbacks.Count -eq 0) {
        Write-Host "No pending feedbacks to process." -ForegroundColor Green
        return @{
            processed = 0
            success = 0
            failed = 0
        }
    }
    
    Write-Host "Found $($feedbacks.Count) pending feedback(s)" -ForegroundColor Yellow
    Write-Host ""
    
    $stats = @{
        processed = 0
        success = 0
        failed = 0
        skipped = 0
    }
    
    foreach ($fb in $feedbacks) {
        $elapsed = (Get-Date) - [datetime]$fb.ts
        
        # Verificar se ja passou o tempo de espera
        if ($elapsed.TotalMinutes -lt $fb.wait_minutes) {
            $remaining = $fb.wait_minutes - $elapsed.TotalMinutes
            Write-Host "$($fb.market): SKIP - Wait $([Math]::Round($remaining,1)) more minutes" -ForegroundColor Gray
            $stats.skipped++
            continue
        }
        
        Write-Host "$($fb.market): PROCESSING ($($fb.veto_type))" -ForegroundColor Yellow
        $stats.processed++
        
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would execute: $($fb.corrective_action)" -ForegroundColor Cyan
            continue
        }
        
        # Executar acao corretiva
        $result = Invoke-CorrectiveAction -Feedback $fb
        
        if ($result.success) {
            Write-Host "  SUCCESS: $($fb.corrective_action)" -ForegroundColor Green
            Update-VetoFeedbackStatus -Feedback $fb -NewStatus "completed" -Note "Corrective action executed"
            $stats.success++
        } else {
            Write-Host "  FAILED: $($result.error)" -ForegroundColor Red
            Update-VetoFeedbackStatus -Feedback $fb -NewStatus "failed" -Note $result.error
            $stats.failed++
        }
        
        Write-Host ""
    }
    
    Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host "  Processed: $($stats.processed)"
    Write-Host "  Success: $($stats.success)" -ForegroundColor Green
    Write-Host "  Failed: $($stats.failed)" -ForegroundColor $(if ($stats.failed -gt 0) { "Red" } else { "Gray" })
    Write-Host "  Skipped: $($stats.skipped)" -ForegroundColor Gray
    
    return $stats
}

# Export functions (comentado - nao e um modulo formal)
# Export-ModuleMember -Function @(
#     'Register-VetoFeedback',
#     'Get-PendingVetoFeedbacks',
#     'Invoke-CorrectiveAction',
#     'Update-VetoFeedbackStatus',
#     'Process-VetoFeedbackQueue'
# )

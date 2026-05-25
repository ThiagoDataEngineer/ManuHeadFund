# lib_http_error_monitor.ps1 -- Monitora erros HTTP LLM (400/429/503) com
# circuit breaker + Telegram alert se > threshold em janela rolling.
#
# Memory: feedback_monitor_400_errors.md (sem isso, bugs invisiveis tipo Mesa CAOS
# sistemico que aconteceu em 2026-05-15).
#
# Uso:
#   Register-LlmHttpError -Provider "groq" -Status 429 -Endpoint "/chat/completions"
#   $state = Get-LlmErrorState
#   if (Test-AlertThreshold -State $state -WindowMin 10 -Threshold 3) {
#       Send-TelegramAlert -Message (Format-LlmErrorAlert -State $state)
#   }
#
# State persistido em journal/llm_http_errors.json (rolling 24h window).

$LLM_ERROR_FILE = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "llm_http_errors.json")


function Get-LlmErrorState {
    [CmdletBinding()]
    param()
    if (-not (Test-Path $LLM_ERROR_FILE)) {
        return [PSCustomObject]@{
            errors = @()
            last_alert_ts = $null
        }
    }
    try {
        $raw = Get-Content $LLM_ERROR_FILE -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        return $data
    } catch {
        return [PSCustomObject]@{
            errors = @()
            last_alert_ts = $null
        }
    }
}


function Save-LlmErrorState {
    [CmdletBinding()]
    param([PSObject]$State)
    $dir = Split-Path $LLM_ERROR_FILE
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $LLM_ERROR_FILE -Encoding UTF8
}


function Register-LlmHttpError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Provider,   # groq | anthropic | gemini
        [Parameter(Mandatory)] [int]    $Status,     # 400 | 429 | 503 | etc
        [string]                $Endpoint = "",
        [string]                $Agent    = "",
        [string]                $Note     = ""
    )
    $state = Get-LlmErrorState
    if (-not $state.errors) { $state | Add-Member -NotePropertyName errors -NotePropertyValue @() -Force }

    $entry = [PSCustomObject]@{
        ts        = (Get-Date).ToString("o")
        provider  = $Provider
        status    = $Status
        endpoint  = $Endpoint
        agent     = $Agent
        note      = $Note
    }

    # Append + trim 24h
    $errs = @($state.errors)
    $errs += $entry
    $cutoff = (Get-Date).AddHours(-24)
    $errs = @($errs | Where-Object {
        try { [DateTime]::Parse($_.ts) -ge $cutoff } catch { $true }
    })

    $newState = [PSCustomObject]@{
        errors = $errs
        last_alert_ts = $state.last_alert_ts
    }
    Save-LlmErrorState -State $newState
    return $entry
}


function Test-AlertThreshold {
    [CmdletBinding()]
    param(
        [PSObject] $State,
        [int]      $WindowMin = 10,
        [int]      $Threshold = 3,
        [int]      $CooldownMin = 30
    )
    if (-not $State -or -not $State.errors) { return $false }

    # Cooldown: nao alertar se ja alertou em CooldownMin
    if ($State.last_alert_ts) {
        try {
            $lastAlert = [DateTime]::Parse($State.last_alert_ts)
            $minSinceAlert = ((Get-Date) - $lastAlert).TotalMinutes
            if ($minSinceAlert -lt $CooldownMin) {
                return $false
            }
        } catch {}
    }

    $cutoff = (Get-Date).AddMinutes(-$WindowMin)
    $recent = @($State.errors | Where-Object {
        try { [DateTime]::Parse($_.ts) -ge $cutoff } catch { $false }
    })

    return ($recent.Count -ge $Threshold)
}


function Get-LlmErrorSummary {
    [CmdletBinding()]
    param([PSObject]$State, [int]$WindowMin = 10)
    if (-not $State -or -not $State.errors) {
        return [PSCustomObject]@{
            total_window = 0
            by_provider  = @{}
            by_status    = @{}
            window_min   = $WindowMin
        }
    }
    $cutoff = (Get-Date).AddMinutes(-$WindowMin)
    $recent = @($State.errors | Where-Object {
        try { [DateTime]::Parse($_.ts) -ge $cutoff } catch { $false }
    })

    $byProvider = @{}
    $byStatus = @{}
    foreach ($e in $recent) {
        $p = $e.provider
        $s = $e.status.ToString()
        if (-not $byProvider.ContainsKey($p)) { $byProvider[$p] = 0 }
        if (-not $byStatus.ContainsKey($s))   { $byStatus[$s]   = 0 }
        $byProvider[$p] = $byProvider[$p] + 1
        $byStatus[$s]   = $byStatus[$s] + 1
    }

    return [PSCustomObject]@{
        total_window = $recent.Count
        by_provider  = $byProvider
        by_status    = $byStatus
        window_min   = $WindowMin
    }
}


function Format-LlmErrorAlert {
    [CmdletBinding()]
    param([PSObject]$State, [int]$WindowMin = 10)
    $sum = Get-LlmErrorSummary -State $State -WindowMin $WindowMin
    $e = $global:TG_EMOJI

    $byProv = ($sum.by_provider.Keys | ForEach-Object { "$($_): $($sum.by_provider[$_])" }) -join ", "
    $byStat = ($sum.by_status.Keys   | ForEach-Object { "$($_): $($sum.by_status[$_])"   }) -join ", "

    return "$($e.alert) <b>HTTP ERRORS LLM</b>`n$($sum.total_window) erros em ${WindowMin}min`n<b>Providers:</b> $byProv`n<b>Status:</b> $byStat`n<i>Mesa pode estar dando CAOS por falha API, nao por discordancia.</i>"
}


function Send-LlmErrorAlertIfDue {
    [CmdletBinding()]
    param(
        [int] $WindowMin = 10,
        [int] $Threshold = 3,
        [int] $CooldownMin = 30,
        [switch] $Enabled
    )
    if (-not $Enabled) { return $false }
    $state = Get-LlmErrorState
    if (-not (Test-AlertThreshold -State $state -WindowMin $WindowMin -Threshold $Threshold -CooldownMin $CooldownMin)) {
        return $false
    }
    $msg = Format-LlmErrorAlert -State $state -WindowMin $WindowMin
    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }
        $state.last_alert_ts = (Get-Date).ToString("o")
        Save-LlmErrorState -State $state
        return $true
    } catch {
        return $false
    }
}

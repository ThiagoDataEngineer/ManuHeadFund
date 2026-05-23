# lib_runspace_warnings.ps1 -- runtime detection de funcoes faltantes em runspace
#
# Background: `Get-Command X -ErrorAction SilentlyContinue` retorna null sem erro
# quando X nao existe -- bug invisivel. Esta lib emite WARNING + log estruturado
# quando funcao esperada esta missing, ajuda a detectar bugs estilo FQS hallucination
# em outros runspaces no futuro.
#
# Uso (replace pattern):
#   if (Get-Command Foo -ErrorAction SilentlyContinue) { Foo }
# Por:
#   if (Test-CommandAvailable "Foo" -Context "orchestrator_v6") { Foo }


function Test-CommandAvailable {
    <#
    .SYNOPSIS
        Drop-in replacement pra `if (Get-Command X -SilentlyContinue)` que loga
        warning quando funcao missing -- detecta bugs runspace-style.
    .PARAMETER Name
        Nome da funcao a verificar.
    .PARAMETER Context
        Identificador do call site (pra log).
    .PARAMETER Silent
        Se $true, nao loga warning (suprimir em casos onde missing eh esperado).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $Context = "unknown",
        [switch] $Silent
    )
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $true }

    if (-not $Silent) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else {
            $defaultPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
            $defaultPath
        }
        $logFile = Join-Path $journalDir "missing_commands.jsonl"
        try {
            @{
                timestamp  = (Get-Date).ToString('o')
                command    = $Name
                context    = $Context
                hostname   = $env:COMPUTERNAME
                runspace   = [Runspace]::DefaultRunspace.Id
            } | ConvertTo-Json -Compress | Add-Content -Path $logFile -Encoding utf8 -ErrorAction SilentlyContinue
        } catch {}
        Write-Warning "[runspace_audit] Command '$Name' missing em context '$Context'. Verifique se lib esta dot-sourced."
    }
    return $false
}


function Get-MissingCommandsReport {
    <#
    .SYNOPSIS
        Le journal/missing_commands.jsonl + sumariza por command/context (24h).
    #>
    [CmdletBinding()]
    param(
        [string] $JournalPath = "",
        [int] $LastHours = 24
    )
    if (-not $JournalPath) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
        $JournalPath = Join-Path $journalDir "missing_commands.jsonl"
    }
    if (-not (Test-Path $JournalPath)) {
        return [PSCustomObject]@{ total = 0; by_command = @{}; by_context = @{} }
    }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-$LastHours)
    $byCmd = @{}; $byCtx = @{}; $total = 0
    Get-Content $JournalPath -Encoding UTF8 | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json
            $ts = [datetime]::Parse($obj.timestamp).ToUniversalTime()
            if ($ts -lt $cutoff) { return }
            $total++
            if (-not $byCmd.ContainsKey($obj.command)) { $byCmd[$obj.command] = 0 }
            $byCmd[$obj.command]++
            if (-not $byCtx.ContainsKey($obj.context)) { $byCtx[$obj.context] = 0 }
            $byCtx[$obj.context]++
        } catch {}
    }
    return [PSCustomObject]@{
        total      = $total
        by_command = $byCmd
        by_context = $byCtx
        last_hours = $LastHours
    }
}

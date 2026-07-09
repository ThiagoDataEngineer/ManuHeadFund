# lib_boot_integrity.ps1 -- Guarda de integridade no boot dos daemons (2026-07-09)
#
# NUNCA MAIS: caso real 2026-07-08/09 -- 1 parentese extra em lib_trailing.ps1
# derrubou a lib inteira em silencio (dot-source com parse error nao define NADA),
# Show-TrailingStatus sumiu, scan_master quebrou TODO ciclo e SL trailing ficou
# morto ~20h. CI pegava, mas CI vermelho nao impede daemon local de subir.
#
# Contrato (regra 5 do projeto: fail-closed, erro = BLOCK):
#   Test-LibsParseClean  -AgentsDir d          -> @{ clean; broken=@(@{file;line;message}) }
#   Assert-BootIntegrity -DaemonName n -CriticalFunctions @(...) [-AgentsDir d] [-NoAlert]
#       -> @{ ok; broken_libs; missing_functions; message }
#   ok=$false => caller NAO deve iniciar o loop de trading (ou operar degradado explicito).
#
# PS 5.1. UTF-8 BOM.

function Test-LibsParseClean {
    [CmdletBinding()]
    param(
        [string] $AgentsDir = $PSScriptRoot
    )

    $broken = @()
    $files = @(Get-ChildItem -Path $AgentsDir -Filter "lib_*.ps1" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "backup" })

    foreach ($f in $files) {
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
        if ($errs.Count -gt 0) {
            $broken += @{
                file    = $f.Name
                line    = $errs[0].Extent.StartLineNumber
                message = $errs[0].Message
            }
        }
    }

    return @{
        clean  = (@($broken).Count -eq 0)
        broken = $broken
    }
}


function Assert-BootIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DaemonName,
        [string[]] $CriticalFunctions = @(),
        [string] $AgentsDir = $PSScriptRoot,
        [switch] $NoAlert
    )

    $parse = Test-LibsParseClean -AgentsDir $AgentsDir
    $missing = @()
    foreach ($fn in $CriticalFunctions) {
        if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
            $missing += $fn
        }
    }

    $ok = $parse.clean -and (@($missing).Count -eq 0)

    $msgParts = @()
    if (-not $parse.clean) {
        $names = @($parse.broken | ForEach-Object { "$($_.file):L$($_.line)" }) -join ", "
        $msgParts += "libs com PARSE ERROR: $names"
    }
    if (@($missing).Count -gt 0) {
        $msgParts += "funcoes criticas AUSENTES: $($missing -join ', ')"
    }
    $message = if ($ok) {
        "[$DaemonName] boot integrity OK ($(@($CriticalFunctions).Count) funcoes criticas verificadas)"
    } else {
        "[$DaemonName] BOOT INTEGRITY FAIL -- $($msgParts -join ' | ') -- daemon NAO deve operar (fail-closed)"
    }

    if (-not $ok) {
        Write-Host $message -ForegroundColor Red
        # Alerta Telegram best-effort (nao pode quebrar o proprio guard)
        if (-not $NoAlert -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
            try { Send-TelegramAlert -Message ("🚨 " + $message) | Out-Null } catch {}
        }
        # Trilha em journal pra auditoria
        try {
            $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $AgentsDir -Parent) "journal" }
            $rec = @{
                ts      = (Get-Date).ToUniversalTime().ToString("o")
                daemon  = $DaemonName
                ok      = $false
                broken  = $parse.broken
                missing = $missing
            } | ConvertTo-Json -Compress -Depth 4
            Add-Content -Path (Join-Path $journalDir "boot_integrity_failures.jsonl") -Value $rec -Encoding UTF8
        } catch {}
    } else {
        Write-Host $message -ForegroundColor Green
    }

    return @{
        ok                = $ok
        broken_libs       = $parse.broken
        missing_functions = $missing
        message           = $message
    }
}

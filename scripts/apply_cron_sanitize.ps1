# apply_cron_sanitize.ps1 - Aplica plano de saneamento de crons (rodar ELEVADO)
# 2026-06-12: troca engine powershell.exe 5.1 -> pwsh 7 nas tasks CoinEx*/ManuHeadFund*
# Usa lib_cron_sanitize (7 TDD). Log: logs/cron_sanitize_<ts>.log

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $projectRoot
. (Join-Path $projectRoot "agents\lib_cron_sanitize.ps1")

$logFile = Join-Path $projectRoot ("logs\cron_sanitize_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

$pwshExe = "C:\Users\thiag\AppData\Local\Microsoft\WindowsApps\pwsh.exe"
if (-not (Test-Path $pwshExe)) { $pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if (-not $pwshExe) { Log "ABORT: pwsh.exe nao encontrado"; exit 1 }
Log "Engine alvo: $pwshExe"

$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -match "^CoinEx|^ManuHeadFund" } | ForEach-Object {
    [PSCustomObject]@{ Name = $_.TaskName; State = "$($_.State)"; Execute = $_.Actions[0].Execute; Arguments = $_.Actions[0].Arguments }
}
$plan = Get-CronSanitizePlan -Tasks $tasks -RepoRoot $projectRoot -PwshExe $pwshExe

$applied = 0; $failed = 0
foreach ($p in $plan) {
    if ($p.Action -notin @("SWITCH_ENGINE", "REPOINT")) { Log "$($p.Action): $($p.Task) ($($p.Reason))"; continue }
    try {
        $newAction = New-ScheduledTaskAction -Execute $p.NewExecute -Argument $p.NewArguments
        Set-ScheduledTask -TaskName $p.Task -Action $newAction -ErrorAction Stop | Out-Null
        Log "APLICADO [$($p.Action)]: $($p.Task)"
        $applied++
    } catch {
        Log "FALHOU: $($p.Task) :: $($_.Exception.Message)"
        $failed++
    }
}
Log "=== DONE: $applied aplicadas, $failed falhas ==="

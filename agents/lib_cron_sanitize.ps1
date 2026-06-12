# lib_cron_sanitize.ps1 - Planejador de saneamento das scheduled tasks (2026-06-12)
# Contexto: ~20 crons CoinEx* lancavam powershell.exe 5.1 (codebase eh pwsh 7;
# UTF-8 sem BOM + ?? quebram silenciosamente) e 3 tasks FARO apontavam pra
# C:\Users\thiag\scripts (bug Split-Path do instalador faro_v3_schedule.ps1).
#
# Get-CronSanitizePlan eh PURA-testavel: IO de existencia de arquivo injetado
# via -TestPath (Pester injeta fake). Decide, nao executa.
#
# Acoes:
#   OK             - ja em pwsh com script existente; nada a fazer
#   SWITCH_ENGINE  - script existe, troca powershell.exe -> pwsh
#   REPOINT        - script ausente mas repo\scripts tem equivalente: reescreve
#                    path nos Arguments + troca engine
#   MISSING        - script ausente sem equivalente no repo (so reporta)
#   SKIP_DISABLED  - task desabilitada (nao mexe)
#   UNPARSEABLE    - sem -File reconhecivel nos Arguments (so reporta)

function Get-CronSanitizePlan {
    param(
        [Parameter(Mandatory)] [object[]] $Tasks,   # { Name, State, Execute, Arguments }
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $PwshExe,
        [scriptblock] $TestPath = { param($p) Test-Path $p }
    )

    $plan = @()
    foreach ($t in $Tasks) {
        $name = "$($t.Name)"
        $exe  = "$($t.Execute)"
        $args_ = "$($t.Arguments)"
        $isPwsh = (Split-Path $exe -Leaf) -ieq "pwsh.exe"

        if ("$($t.State)" -eq "Disabled") {
            $plan += [PSCustomObject]@{ Task = $name; Action = "SKIP_DISABLED"; NewExecute = $null; NewArguments = $null; Reason = "task desabilitada" }
            continue
        }

        if ($args_ -notmatch '(?i)-File\s+"?([^"]+\.ps1)"?') {
            $plan += [PSCustomObject]@{ Task = $name; Action = "UNPARSEABLE"; NewExecute = $null; NewArguments = $null; Reason = "sem -File nos arguments" }
            continue
        }
        $scriptPath = $Matches[1]

        if (& $TestPath $scriptPath) {
            if ($isPwsh) {
                $plan += [PSCustomObject]@{ Task = $name; Action = "OK"; NewExecute = $null; NewArguments = $null; Reason = "ja pwsh + script existe" }
            } else {
                $plan += [PSCustomObject]@{ Task = $name; Action = "SWITCH_ENGINE"; NewExecute = $PwshExe; NewArguments = $args_; Reason = "powershell 5.1 -> pwsh" }
            }
            continue
        }

        # Script ausente: tenta equivalente no repo (scripts\<nome> ou raiz)
        $leaf = Split-Path $scriptPath -Leaf
        $candidates = @((Join-Path $RepoRoot "scripts\$leaf"), (Join-Path $RepoRoot $leaf))
        $repoEquiv = $candidates | Where-Object { & $TestPath $_ } | Select-Object -First 1

        if ($repoEquiv) {
            # replace literal do path antigo pelo novo nos Arguments
            $newArgs = $args_.Replace($scriptPath, $repoEquiv)
            $plan += [PSCustomObject]@{ Task = $name; Action = "REPOINT"; NewExecute = $PwshExe; NewArguments = $newArgs; Reason = "script ausente; repo tem $leaf" }
        } else {
            $plan += [PSCustomObject]@{ Task = $name; Action = "MISSING"; NewExecute = $null; NewArguments = $null; Reason = "script ausente sem equivalente: $scriptPath" }
        }
    }
    return $plan
}

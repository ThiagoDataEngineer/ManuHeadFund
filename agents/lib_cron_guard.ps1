# lib_cron_guard.ps1 -- decisao PURA "este job deve rodar agora?"
#
# Motivo (2026-06-22): GH Actions throttla o cron */5 p/ gaps de ~30-45min e atrasa
# o minuto exato. Gates do tipo `if ($minute -eq 0)` quase nunca casam -> jobs
# diarios/semanais NUNCA rodavam. Em vez de exigir minuto exato, decidimos por
# JANELA + last-run persistido: roda no primeiro fire dentro da janela e dedup
# pelo timestamp da ultima execucao (Supabase via cron_guard.ps1).
#
# Schedules suportados (string):
#   daily:H            -> 1x/dia, no 1o fire com hora UTC >= H
#   weekly:DAY:H       -> 1x/semana, no dia DAY (Sunday..Saturday) com hora >= H
#   interval:N         -> a cada N minutos (hourly=60, every30=30, every6h=360)

function Test-CronDue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)][string]$Schedule,
        [string]$LastRunIso = "",
        [datetime]$NowUtc = ([datetime]::UtcNow)
    )

    # normaliza now para UTC
    if ($NowUtc.Kind -eq [System.DateTimeKind]::Local) { $NowUtc = $NowUtc.ToUniversalTime() }

    $last = $null
    if ($LastRunIso) {
        # InvariantCulture: o valor pode vir re-stringificado em cultura local (pt-BR
        # dd/MM/yyyy) ao round-tripar pelo Supabase -> parse culture-dependente quebrava.
        try { $last = ([datetime]::Parse($LastRunIso, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)) } catch { $last = $null }
    }

    $parts = $Schedule.Split(':')
    $type  = $parts[0].Trim().ToLower()

    switch ($type) {
        'interval' {
            if ($parts.Count -lt 2) { throw "interval requer N minutos: 'interval:60'" }
            $n = [int]$parts[1]
            if (-not $last) { return $true }
            return (($NowUtc - $last).TotalMinutes -ge $n)
        }
        'daily' {
            if ($parts.Count -lt 2) { throw "daily requer hora: 'daily:5'" }
            $h = [int]$parts[1]
            if ($NowUtc.Hour -lt $h) { return $false }
            if (-not $last) { return $true }
            # ja rodou hoje (mesma data UTC)? entao nao.
            return ($last.Date -lt $NowUtc.Date)
        }
        'weekly' {
            if ($parts.Count -lt 3) { throw "weekly requer dia e hora: 'weekly:Monday:4'" }
            $day = $parts[1].Trim()
            $h   = [int]$parts[2]
            if ("$($NowUtc.DayOfWeek)" -ne $day) { return $false }
            if ($NowUtc.Hour -lt $h) { return $false }
            if (-not $last) { return $true }
            return ($last.Date -lt $NowUtc.Date)
        }
        default { throw "Schedule desconhecido: '$Schedule'" }
    }
}

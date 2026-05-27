# lib_mentor_time_context.ps1 -- A.6 wire 2026-05-26
# Fornece UTC hour, weekday, trading session, weekend flag pro prompt Mentor.
# Trader real considera contexto temporal -- weekend low liquidity, US session
# = volatility, ASIA session = quiet drift. Mentor passa a saber tambem.
#
# PS 5.1, UTF-8 BOM.

function Get-TimeContext {
    [CmdletBinding()]
    param([DateTime] $Now = (Get-Date).ToUniversalTime())

    $utc = if ($Now.Kind -eq [DateTimeKind]::Utc) { $Now } else { $Now.ToUniversalTime() }
    $hr = $utc.Hour
    $wd = $utc.DayOfWeek.ToString()
    $isWeekend = ($wd -eq "Saturday" -or $wd -eq "Sunday")

    $session = switch ($true) {
        ($hr -ge 0 -and $hr -le 7)   { "ASIA"; break }
        ($hr -ge 8 -and $hr -le 12)  { "EU_OVERLAP"; break }
        ($hr -ge 13 -and $hr -le 21) { "US"; break }
        default                       { "LATE_US" }
    }

    return [PSCustomObject]@{
        hour_utc   = $hr
        weekday    = $wd
        session    = $session
        is_weekend = $isWeekend
        iso_utc    = $utc.ToString("o")
    }
}

function Format-TimeContextLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $TimeContext)

    $weekendTag = if ($TimeContext.is_weekend) { " WEEKEND_LOW_LIQUIDITY" } else { "" }
    $hr = "{0:00}" -f [int]$TimeContext.hour_utc
    return "time $($TimeContext.weekday) ${hr}h UTC session=$($TimeContext.session)$weekendTag"
}

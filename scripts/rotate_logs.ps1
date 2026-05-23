# rotate_logs.ps1 -- B5 fix 2026-05-20 PM6 (log rotation).
#
# Rotaciona qualquer journal/*.log >MaxBytes para journal/archive/<name>.YYYY-MM-DD.log
# e trunca o arquivo original. Sem dependencia (sem gzip pra ficar PS 5.1 puro).
#
# Cron: rodar 1x/dia 03:30 BRT (apos daily_daemon_restart 03:00).
#
# Uso:
#   pwsh -File scripts\rotate_logs.ps1
#   pwsh -File scripts\rotate_logs.ps1 -MaxBytes 5242880 -DryRun
#
# PS 5.1, UTF-8 BOM.

param(
    [int]    $MaxBytes = 5242880,   # 5 MB
    [int]    $KeepDays = 30,        # delete archives older than 30d
    [switch] $DryRun
)

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$journalDir  = Join-Path $projectRoot "journal"
$archiveDir  = Join-Path $journalDir "archive"

if (-not (Test-Path $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
}

$today = Get-Date -Format "yyyy-MM-dd"
$rotated = 0
$skipped = 0
$pruned  = 0

Get-ChildItem -Path $journalDir -Filter "*.log" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $f = $_
    if ($f.Length -lt $MaxBytes) {
        $skipped++
        return
    }
    $archiveName = "{0}.{1}.log" -f $f.BaseName, $today
    $archivePath = Join-Path $archiveDir $archiveName

    # Se ja existe archive de hoje, sufixa com hora
    if (Test-Path $archivePath) {
        $stamp = Get-Date -Format "HHmmss"
        $archiveName = "{0}.{1}_{2}.log" -f $f.BaseName, $today, $stamp
        $archivePath = Join-Path $archiveDir $archiveName
    }

    if ($DryRun) {
        Write-Host "[DRY] would rotate $($f.Name) ($([math]::Round($f.Length/1MB,2)) MB) -> $archiveName"
    } else {
        try {
            Move-Item -Path $f.FullName -Destination $archivePath -Force
            New-Item -ItemType File -Path $f.FullName -Force | Out-Null
            Write-Host "[ROTATE] $($f.Name) ($([math]::Round((Get-Item $archivePath).Length/1MB,2)) MB) -> $archiveName"
            $rotated++
        } catch {
            Write-Warning "rotate $($f.Name) FAIL: $($_.Exception.Message)"
        }
    }
}

# Prune archives older than KeepDays
$cutoff = (Get-Date).AddDays(-$KeepDays)
Get-ChildItem -Path $archiveDir -Filter "*.log" -File -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt $cutoff
} | ForEach-Object {
    if ($DryRun) {
        Write-Host "[DRY] would prune $($_.Name) ($($_.LastWriteTime.ToString('yyyy-MM-dd')))"
    } else {
        try {
            Remove-Item $_.FullName -Force
            $pruned++
        } catch {}
    }
}

Write-Host "rotated=$rotated skipped=$skipped pruned=$pruned (MaxBytes=$MaxBytes KeepDays=$KeepDays)"

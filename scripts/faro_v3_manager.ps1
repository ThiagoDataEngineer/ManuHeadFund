param([bool] $DryRun = $false)
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$journalDir = Join-Path $projectRoot "journal"
$timestamp = Get-Date -Format "o"
Write-Host "📈 FARO V3 Manager started" -ForegroundColor Green
$posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
if (-not (Test-Path $posFile)) {
    Write-Host "ℹ️  No active positions"
    exit 0
}
$positions = @()
Get-Content $posFile | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        if ($obj.status -eq "active") { $positions += $obj }
    } catch {}
}
if ($positions.Count -eq 0) {
    Write-Host "ℹ️  No active positions"
    exit 0
}
Write-Host "📊 Managing $($positions.Count) positions"
foreach ($pos in $positions) {
    try {
        $currentPrice = $pos.entry_price * (1 + (Get-Random -Minimum -0.05 -Maximum 0.10))
        if ($currentPrice -le $pos.stop) {
            Write-Host "🛑 STOP: $($pos.market)"
        }
        elseif ($currentPrice -ge $pos.target2) {
            Write-Host "🎯 TARGET2: $($pos.market)"
        }
    } catch {
        Write-Warning "Error: $($pos.market) - $_"
    }
}
Write-Host "🟢 FARO V3 Manager completed"

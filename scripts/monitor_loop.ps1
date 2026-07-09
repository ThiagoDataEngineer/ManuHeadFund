$endTime = (Get-Date).Date.AddHours(22)
$logFile = "journal/monitor_$(Get-Date -Format 'yyyyMMdd').log"
$cycleCount = 0
$crashCount = 0

while ((Get-Date) -lt $endTime) {
    $now = Get-Date
    $cycleCount++
    
    # Check gem_loop
    $running = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddHours(-2) }
    
    if (-not $running) {
        Add-Content $logFile "[$($now.ToString('HH:mm:ss'))] 🔴 CRASH — gem_loop DOWN, restarting..."
        $crashCount++
        
        Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddHours(-2) } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"scripts/gem_loop.ps1`"" -WindowStyle Hidden
        Add-Content $logFile "[$($now.ToString('HH:mm:ss'))] ✅ FIXED #$crashCount"
    } else {
        # Log latest gem_loop status
        if (Test-Path "journal/gem_loop.log") {
            $last = Get-Content "journal/gem_loop.log" -Tail 1
            Add-Content $logFile "[$($now.ToString('HH:mm:ss'))] ✅ RUNNING | Cycle: $cycleCount | $last"
        }
    }
    
    Start-Sleep -Seconds 300
}

Add-Content $logFile "[$((Get-Date).ToString('HH:mm:ss'))] ✅ MONITORING COMPLETE"

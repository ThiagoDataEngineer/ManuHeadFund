# heartbeat.Tests.ps1 -- TDD heartbeat opt-in para Telegram silencioso
# Pester 3.x, sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$global:TELEGRAM_API_BASE = "https://api.telegram.org"

# Stub Invoke-RestMethod para Send-TelegramAlert nao chamar Telegram real
function Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
}

. (Join-Path $agentsDir "lib_telegram.ps1")

Describe "Test-HeartbeatDue" {

    It "retorna true quando arquivo nao existe" {
        $tmp = Join-Path $env:TEMP ("hb_nonexistent_" + [Guid]::NewGuid().ToString() + ".txt")
        Test-HeartbeatDue -LastHeartbeatFile $tmp -IntervalMinutes 60 | Should Be $true
    }

    It "retorna true quando ultimo heartbeat foi ha mais de IntervalMinutes" {
        $tmp = Join-Path $env:TEMP ("hb_old_" + [Guid]::NewGuid().ToString() + ".txt")
        (Get-Date).AddMinutes(-90).ToString("o") | Set-Content -Path $tmp -Encoding UTF8
        Test-HeartbeatDue -LastHeartbeatFile $tmp -IntervalMinutes 60 | Should Be $true
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    It "retorna false quando heartbeat recente" {
        $tmp = Join-Path $env:TEMP ("hb_recent_" + [Guid]::NewGuid().ToString() + ".txt")
        (Get-Date).AddMinutes(-5).ToString("o") | Set-Content -Path $tmp -Encoding UTF8
        Test-HeartbeatDue -LastHeartbeatFile $tmp -IntervalMinutes 60 | Should Be $false
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    It "retorna true quando arquivo corrompido" {
        $tmp = Join-Path $env:TEMP ("hb_corrupt_" + [Guid]::NewGuid().ToString() + ".txt")
        "not-a-date" | Set-Content -Path $tmp -Encoding UTF8
        Test-HeartbeatDue -LastHeartbeatFile $tmp -IntervalMinutes 60 | Should Be $true
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

Describe "Save-HeartbeatTimestamp" {

    It "grava timestamp ISO no arquivo" {
        $tmp = Join-Path $env:TEMP ("hb_save_" + [Guid]::NewGuid().ToString() + ".txt")
        Save-HeartbeatTimestamp -LastHeartbeatFile $tmp
        (Test-Path $tmp) | Should Be $true
        $raw = Get-Content $tmp -ErrorAction SilentlyContinue | Select-Object -First 1
        # ISO format tem T no meio (ex: 2026-05-17T22:30:00...)
        $raw | Should Match "T"
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    It "cria diretorio se nao existe" {
        $dir = Join-Path $env:TEMP ("hb_dir_" + [Guid]::NewGuid().ToString())
        $tmp = Join-Path $dir "ts.txt"
        Save-HeartbeatTimestamp -LastHeartbeatFile $tmp
        (Test-Path $tmp) | Should Be $true
        Remove-Item $dir -Recurse -ErrorAction SilentlyContinue
    }
}

Describe "Format-HeartbeatMessage" {

    It "inclui HEARTBEAT na primeira linha" {
        $m = Format-HeartbeatMessage -Window "NEUTRAL" -NextMin 60 -NextTime "23:30"
        $m | Should Match "HEARTBEAT"
    }

    It "indica DRY ou LIVE conforme switch" {
        $m_dry  = Format-HeartbeatMessage -DryRun
        $m_live = Format-HeartbeatMessage
        $m_dry  | Should Match "DRY"
        $m_live | Should Match "LIVE"
    }

    It "inclui WatchCount" {
        $m = Format-HeartbeatMessage -WatchCount 8
        $m | Should Match "8 pares"
    }
}

Describe "Send-HeartbeatIfDue" {

    It "retorna false quando Enabled=false (default off)" {
        $tmp = Join-Path $env:TEMP ("hb_disabled_" + [Guid]::NewGuid().ToString() + ".txt")
        $r = Send-HeartbeatIfDue -LastHeartbeatFile $tmp -IntervalMinutes 60
        $r | Should Be $false
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    It "retorna false quando nao due (recente)" {
        $tmp = Join-Path $env:TEMP ("hb_send_recent_" + [Guid]::NewGuid().ToString() + ".txt")
        (Get-Date).AddMinutes(-5).ToString("o") | Set-Content -Path $tmp -Encoding UTF8
        $r = Send-HeartbeatIfDue -LastHeartbeatFile $tmp -IntervalMinutes 60 -Enabled
        $r | Should Be $false
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    It "retorna true e atualiza arquivo quando due+enabled" {
        $tmp = Join-Path $env:TEMP ("hb_send_due_" + [Guid]::NewGuid().ToString() + ".txt")
        # Arquivo nao existe = due
        $r = Send-HeartbeatIfDue -LastHeartbeatFile $tmp -IntervalMinutes 60 -Enabled `
            -Window "NEUTRAL" -NextMin 60 -NextTime "23:00" -WatchCount 8 -DryRun
        $r | Should Be $true
        (Test-Path $tmp) | Should Be $true
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

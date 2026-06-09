# lib_self_recovery.Tests.ps1 -- TDD Self-Recovery Engine
# 2026-06-08: Cobre funcoes puras (sem mock) + I/O wrappers (tmp files).

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_self_recovery.ps1")

Describe "Self-Recovery: Get-LogIssueType (pura)" {

    It "classifica lib_missing" {
        (Get-LogIssueType "ERROR Invoke-X nao disponivel") | Should Be "lib_missing"
    }
    It "classifica nao reconhecido como lib_missing" {
        (Get-LogIssueType "O termo 'Invoke-Y' não é reconhecido como nome") | Should Be "lib_missing"
    }
    It "classifica api_429" {
        (Get-LogIssueType "Groq API error (429): Too Many Requests") | Should Be "api_429"
    }
    It "classifica key rotacionada como api_429" {
        (Get-LogIssueType "[tech] Groq key rotacionada (429 na key atual)") | Should Be "api_429"
    }
    It "classifica daemon_dead (singleton lock)" {
        (Get-LogIssueType "[SKIP] Outro scan_master VIVO ja detem o singleton lock; este PID=2940 exit.") | Should Be "daemon_dead"
    }
    It "classifica cache_stale" {
        (Get-LogIssueType "SKIP CACHE: MOVEUSDT mesma condicao <60min") | Should Be "cache_stale"
    }
    It "classifica tori_block" {
        (Get-LogIssueType "[GEM TORI BLOCK] MOVEUSDT: tori:skip:Downtrend estrutural") | Should Be "tori_block"
    }
    It "retorna none para linha normal" {
        (Get-LogIssueType "[INFO] GemLoop iniciado. Mode=LIVE") | Should Be "none"
    }
    It "retorna none para linha vazia" {
        (Get-LogIssueType "") | Should Be "none"
    }
}

Describe "Self-Recovery: Get-CycleHealth (pura)" {

    It "saudavel quando sem issues" {
        $h = Get-CycleHealth -Issues @("none","none") -TotalSignals 3
        $h.healthy | Should Be $true
        $h.dominant_issue | Should Be "none"
    }
    It "lib_missing sempre critico (infra)" {
        $h = Get-CycleHealth -Issues @("lib_missing") -TotalSignals 5
        $h.healthy | Should Be $false
        $h.dominant_issue | Should Be "lib_missing"
    }
    It "daemon_dead sempre critico" {
        $h = Get-CycleHealth -Issues @("daemon_dead","none") -TotalSignals 0
        $h.healthy | Should Be $false
    }
    It "tori_block critico SO se domina 100% dos sinais" {
        $h = Get-CycleHealth -Issues @("tori_block","tori_block") -TotalSignals 2
        $h.healthy | Should Be $false
    }
    It "tori_block NAO critico se ha sinais que passaram" {
        $h = Get-CycleHealth -Issues @("tori_block") -TotalSignals 5
        $h.healthy | Should Be $true
    }
    It "escolhe dominante por frequencia" {
        $h = Get-CycleHealth -Issues @("api_429","api_429","cache_stale") -TotalSignals 0
        $h.dominant_issue | Should Be "api_429"
        $h.dominant_count | Should Be 2
    }
}

Describe "Self-Recovery: Get-RecoveryAction (pura)" {

    It "lib_missing -> reload_libs na 1a tentativa" {
        $a = Get-RecoveryAction -IssueType "lib_missing" -ConsecutiveCount 1
        $a.action | Should Be "reload_libs"
        $a.escalate | Should Be $false
    }
    It "lib_missing -> alert_user apos 3" {
        $a = Get-RecoveryAction -IssueType "lib_missing" -ConsecutiveCount 3
        $a.action | Should Be "alert_user"
        $a.escalate | Should Be $true
    }
    It "daemon_dead -> restart_daemon na 1a" {
        $a = Get-RecoveryAction -IssueType "daemon_dead" -ConsecutiveCount 1
        $a.action | Should Be "restart_daemon"
    }
    It "daemon_dead -> alert apos 2 (escala rapido)" {
        $a = Get-RecoveryAction -IssueType "daemon_dead" -ConsecutiveCount 2
        $a.escalate | Should Be $true
    }
    It "api_429 -> rotate_key_wait, tolera ate 5" {
        $a = Get-RecoveryAction -IssueType "api_429" -ConsecutiveCount 4
        $a.action | Should Be "rotate_key_wait"
        $a.escalate | Should Be $false
    }
    It "cache_stale -> clear_cache" {
        $a = Get-RecoveryAction -IssueType "cache_stale" -ConsecutiveCount 1
        $a.action | Should Be "clear_cache"
    }
    It "tori_block FAIL-SAFE: nunca auto-corrige (action none ate escalar)" {
        $a = Get-RecoveryAction -IssueType "tori_block" -ConsecutiveCount 1
        $a.action | Should Be "none"
    }
    It "tori_block escala apos 3 para decisao humana" {
        $a = Get-RecoveryAction -IssueType "tori_block" -ConsecutiveCount 3
        $a.action | Should Be "alert_user"
        $a.escalate | Should Be $true
    }
    It "issue desconhecido -> none" {
        $a = Get-RecoveryAction -IssueType "none" -ConsecutiveCount 1
        $a.action | Should Be "none"
    }
}

Describe "Self-Recovery: Update-RecoveryStreak (pura)" {

    It "incrementa quando mesmo issue repete" {
        $s = Update-RecoveryStreak -State @{ last_issue = "api_429"; streak = 2 } -CurrentIssue "api_429"
        $s.streak | Should Be 3
    }
    It "reseta para 1 quando issue muda" {
        $s = Update-RecoveryStreak -State @{ last_issue = "api_429"; streak = 5 } -CurrentIssue "cache_stale"
        $s.streak | Should Be 1
        $s.last_issue | Should Be "cache_stale"
    }
    It "reseta para 0 quando none (ciclo saudavel)" {
        $s = Update-RecoveryStreak -State @{ last_issue = "lib_missing"; streak = 2 } -CurrentIssue "none"
        $s.streak | Should Be 0
    }
    It "inicializa de estado nulo" {
        $s = Update-RecoveryStreak -State $null -CurrentIssue "tori_block"
        $s.streak | Should Be 1
    }
}

Describe "Self-Recovery: Test-CycleHealth (I/O)" {

    It "log inexistente -> saudavel" {
        $h = Test-CycleHealth -LogPath (Join-Path $env:TEMP "naoexiste_xyz123.log")
        $h.healthy | Should Be $true
    }
    It "detecta api_429 dominante num log real" {
        $tmp = Join-Path $env:TEMP "sr_test_429.log"
        @(
            "[INFO] cycle start",
            "[tech] Groq key rotacionada (429 na key atual)",
            "[tech] Groq falhou: 429 Too Many Requests",
            "GEM EXECUTOR -- MOVEUSDT score=55"
        ) | Set-Content -Path $tmp -Encoding UTF8
        $h = Test-CycleHealth -LogPath $tmp
        $h.dominant_issue | Should Be "api_429"
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

Describe "Self-Recovery: Invoke-AutoRecover (integracao DryRun)" {

    It "DryRun nao aplica acao mas diagnostica e persiste streak" {
        $tmpLog = Join-Path $env:TEMP "sr_int_log.log"
        $tmpState = Join-Path $env:TEMP "sr_int_state.json"
        $tmpRec = Join-Path $env:TEMP "sr_int_rec.jsonl"
        Remove-Item $tmpState,$tmpRec -Force -ErrorAction SilentlyContinue
        @(
            "[GEM TORI BLOCK] A: tori:skip:downtrend",
            "[GEM TORI BLOCK] B: tori:skip:downtrend",
            "GEM EXECUTOR -- A score=55",
            "GEM EXECUTOR -- B score=60"
        ) | Set-Content -Path $tmpLog -Encoding UTF8

        $r = Invoke-AutoRecover -LogPath $tmpLog -StatePath $tmpState -RecoveryLogPath $tmpRec -DryRun
        $r.health.dominant_issue | Should Be "tori_block"
        $r.streak | Should Be 1
        (Test-Path $tmpState) | Should Be $true
        (Test-Path $tmpRec) | Should Be $true

        Remove-Item $tmpLog,$tmpState,$tmpRec -Force -ErrorAction SilentlyContinue
    }

    It "streak acumula entre chamadas consecutivas (mesmo issue)" {
        $tmpLog = Join-Path $env:TEMP "sr_streak_log.log"
        $tmpState = Join-Path $env:TEMP "sr_streak_state.json"
        $tmpRec = Join-Path $env:TEMP "sr_streak_rec.jsonl"
        Remove-Item $tmpState,$tmpRec -Force -ErrorAction SilentlyContinue
        @(
            "[SKIP] Outro scan_master VIVO ja detem o singleton lock; este PID=1 exit."
        ) | Set-Content -Path $tmpLog -Encoding UTF8

        $r1 = Invoke-AutoRecover -LogPath $tmpLog -StatePath $tmpState -RecoveryLogPath $tmpRec -DryRun
        $r2 = Invoke-AutoRecover -LogPath $tmpLog -StatePath $tmpState -RecoveryLogPath $tmpRec -DryRun
        $r1.streak | Should Be 1
        $r2.streak | Should Be 2

        Remove-Item $tmpLog,$tmpState,$tmpRec -Force -ErrorAction SilentlyContinue
    }
}

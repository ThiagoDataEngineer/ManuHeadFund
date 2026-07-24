# B19 fix 2026-05-20 PM6+420min.
# Retry transient errors (429/503/timeout) com backoff. Hashtable shared pra contador
# (Pester scope isolation).

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_retry.ps1")

Describe "B19 Invoke-WithRetry" {
    It "Success on first try: retorna resultado, 1 tentativa" {
        $ctx = @{ n = 0 }
        $r = Invoke-WithRetry -ScriptBlock { $ctx.n++; return "ok" } -MaxAttempts 3 -BaseDelayMs 10
        $r       | Should Be "ok"
        $ctx.n   | Should Be 1
    }
    It "Success apos 2 retries: retorna resultado" {
        $ctx = @{ n = 0 }
        $r = Invoke-WithRetry -ScriptBlock {
            $ctx.n++
            if ($ctx.n -lt 3) { throw "timed out" }
            return "ok"
        } -MaxAttempts 5 -BaseDelayMs 10
        $r     | Should Be "ok"
        $ctx.n | Should Be 3
    }
    It "Fail apos MaxAttempts: rethrows" {
        # 2026-07-23 FIX: Pester 3.4.0 "{...} | Should Throw" nao captura
        # corretamente excecoes rethrows de dentro de scriptblocks aninhados.
        $ctx = @{ n = 0 }
        $threw = $false
        try {
            Invoke-WithRetry -ScriptBlock {
                $ctx.n++
                throw "timed out"
            } -MaxAttempts 3 -BaseDelayMs 10
        } catch { $threw = $true }
        $threw | Should Be $true
        $ctx.n | Should Be 3
    }
    It "Non-retriable error: throws na 1a tentativa" {
        $ctx = @{ n = 0 }
        $threw = $false
        try {
            Invoke-WithRetry -ScriptBlock {
                $ctx.n++
                throw "code 3639 Invalid Parameter"
            } -MaxAttempts 3 -BaseDelayMs 10
        } catch { $threw = $true }
        $threw | Should Be $true
        $ctx.n | Should Be 1
    }
    It "Test-CoinExRetriable: 429 e 503 sao retriaveis" {
        (Test-CoinExRetriable "HTTP 429 Too Many Requests")  | Should Be $true
        (Test-CoinExRetriable "503 Service Unavailable")      | Should Be $true
        (Test-CoinExRetriable "timed out")                    | Should Be $true
        (Test-CoinExRetriable "code 3639 Invalid Parameter")  | Should Be $false
    }
}

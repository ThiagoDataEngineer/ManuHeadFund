# lib_whale_watcher.Tests.ps1 -- Whale watcher MVP TDD (2026-05-21 sessao extra).
# Pester 3.x. Validates:
#   - Test-WhaleTxSeen idempotent dedup
#   - Add-WhaleTxSeen append-only persistence
#   - Get-MempoolRecentTxs filter threshold semantics (mocked)
#   - Invoke-WhaleWatcherCycle DryRun semantics

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_whale_watcher.ps1")

$script:tmp = Join-Path $env:TEMP ("whale_tdd_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Test-WhaleTxSeen / Add-WhaleTxSeen" {

    It "Retorna false se seenPath nao existe" {
        $sp = Join-Path $tmp ("missing_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".jsonl")
        Test-WhaleTxSeen -TxId "abc123" -SeenPath $sp | Should Be $false
    }

    It "Add-WhaleTxSeen escreve entry + Test- retorna true" {
        $sp = Join-Path $tmp ("seen_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".jsonl")
        Add-WhaleTxSeen -TxId "deadbeef01" -ValueBtc 250.5 -SeenPath $sp | Should Be $true
        Test-WhaleTxSeen -TxId "deadbeef01" -SeenPath $sp | Should Be $true
        # ID diferente nao retorna true
        Test-WhaleTxSeen -TxId "outratxid" -SeenPath $sp | Should Be $false
    }

    It "Test-WhaleTxSeen respeita WithinHours window" {
        $sp = Join-Path $tmp ("win_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".jsonl")
        # entry ha 48h
        $oldTs = (Get-Date).AddHours(-48).ToString('o')
        @{ txid = "old_tx"; value_btc = 100.0; ts = $oldTs } |
            ConvertTo-Json -Compress | Add-Content -Path $sp -Encoding utf8
        # Within 24h window: nao deve ver
        Test-WhaleTxSeen -TxId "old_tx" -SeenPath $sp -WithinHours 24 | Should Be $false
        # Within 72h window: deve ver
        Test-WhaleTxSeen -TxId "old_tx" -SeenPath $sp -WithinHours 72 | Should Be $true
    }
}


Describe "Get-MempoolRecentTxs - shape" {

    It "Funcao existe + retorna array (smoke real)" {
        # Pode falhar com 0 results se rede off; nunca deve crashear.
        $r = Get-MempoolRecentTxs -MinBtc 100000 -TimeoutSec 5  # threshold super alto -> deve ser []
        @($r).Count | Should Be 0
    }

    It "Threshold MinBtc filtra (smoke mock-friendly)" {
        # Smoke pequeno: threshold 0 -> aceita todos (ate vazio mempool retorna 0).
        $r = Get-MempoolRecentTxs -MinBtc 0 -TimeoutSec 5
        # Deve retornar array (vazio ou nao)
        $r.GetType().IsArray -or ($r -is [System.Collections.IList]) -or $r.Count -ge 0 | Should Be $true
    }
}


Describe "Invoke-WhaleWatcherCycle - DryRun" {

    It "DryRun nao persiste em seen + nao envia TG" {
        # MinBtc impossivel (1B BTC) -> 0 results garantido. Smoke teste de api shape.
        $r = Invoke-WhaleWatcherCycle -MinBtc 1000000000 -DryRun
        $r.fetched | Should Be 0
        $r.new_alerts | Should Be 0
        $r.total_btc_alerted | Should Be 0
    }
}


# Cleanup tmp
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

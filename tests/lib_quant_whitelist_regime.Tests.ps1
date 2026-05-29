# lib_quant_whitelist_regime.Tests.ps1 -- TDD regime-aware tier_level
# Item 1: Merge-QuantWhitelistIntoCandidates com -RegimeProvider
#         Get-MarketRegimeFromCache
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_quant_whitelist.ps1")

# ── Whitelist mock ────────────────────────────────────────────────────────────
$mockDir = Join-Path $env:TEMP ("qw_regime_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $mockDir -Force | Out-Null
$mockPath = Join-Path $mockDir "per_asset_whitelist_test.json"
@'
{
  "as_of": "2026-05-28",
  "TIER_A_LIVE": [
    {"market": "BTCUSDT",  "sharpe": 3.5},
    {"market": "ETHUSDT",  "sharpe": 2.1},
    {"market": "SOLUSDT",  "sharpe": 2.8}
  ],
  "TIER_B_PAPER": [],
  "TIER_C_SKIP": []
}
'@ | Out-File -FilePath $mockPath -Encoding UTF8

# ── Regime cache mock ─────────────────────────────────────────────────────────
$journalDir = Join-Path $mockDir "journal"
New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
$regimeCachePath = Join-Path $journalDir "regime_state.json"
@'
{
  "BTCUSDT":  "BEAR_STRONG",
  "ETHUSDT":  "BEAR_WEAK",
  "SOLUSDT":  "BULL_STRONG",
  "XRPUSDT":  "SIDEWAYS"
}
'@ | Out-File -FilePath $regimeCachePath -Encoding UTF8


# =============================================================================
Describe "Merge-QuantWhitelistIntoCandidates com RegimeProvider" {

    It "ativo BEAR_STRONG recebe tier_level=3" {
        $provider = { param($m) if ($m -eq "BTCUSDT") { "BEAR_STRONG" } else { $null } }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath -RegimeProvider $provider
        $btc = $merged | Where-Object { $_.market -eq "BTCUSDT" }
        $btc | Should Not BeNullOrEmpty
        $btc.tier_level | Should Be 3
    }

    It "ativo BULL_STRONG mantem tier_level=1" {
        $provider = { param($m) if ($m -eq "SOLUSDT") { "BULL_STRONG" } else { $null } }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath -RegimeProvider $provider
        $sol = $merged | Where-Object { $_.market -eq "SOLUSDT" }
        $sol | Should Not BeNullOrEmpty
        $sol.tier_level | Should Be 1
    }

    It "ativo BEAR_WEAK recebe tier_level=3" {
        $provider = { param($m) if ($m -eq "ETHUSDT") { "BEAR_WEAK" } else { $null } }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath -RegimeProvider $provider
        $eth = $merged | Where-Object { $_.market -eq "ETHUSDT" }
        $eth | Should Not BeNullOrEmpty
        $eth.tier_level | Should Be 3
    }

    It "regime null (ausente) mantem tier_level original" {
        $provider = { param($m) $null }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath -RegimeProvider $provider
        foreach ($entry in $merged) {
            $entry.tier_level | Should Be 1
        }
    }

    It "sem RegimeProvider: comportamento inalterado (backward compat)" {
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath
        $btc = $merged | Where-Object { $_.market -eq "BTCUSDT" }
        $btc | Should Not BeNullOrEmpty
        $btc.tier_level | Should Be 1
        $btc.score | Should Be 100
        $btc.marketType | Should Be "FUTURES"
    }
}


# =============================================================================
Describe "Get-MarketRegimeFromCache" {

    It "retorna regime correto quando arquivo existe" {
        $regime = Get-MarketRegimeFromCache -Market "BTCUSDT" -JournalDir $journalDir
        $regime | Should Be "BEAR_STRONG"
    }

    It "retorna null quando arquivo nao existe" {
        $emptyDir = Join-Path $env:TEMP ("qw_nofile_" + [Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $regime = Get-MarketRegimeFromCache -Market "BTCUSDT" -JournalDir $emptyDir
        $regime | Should BeNullOrEmpty
    }

    It "retorna null quando market nao esta no arquivo" {
        $regime = Get-MarketRegimeFromCache -Market "UNKNOWNUSDT" -JournalDir $journalDir
        $regime | Should BeNullOrEmpty
    }
}


# Cleanup
Remove-Item -Recurse -Force $mockDir -ErrorAction SilentlyContinue

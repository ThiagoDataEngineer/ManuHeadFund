# lib_quant_whitelist.Tests.ps1 - TDD para integracao quant whitelist
# Pester 3.x, sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_quant_whitelist.ps1")

# Cria whitelist mock temporaria
$mockDir = Join-Path $env:TEMP ("qw_test_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $mockDir -Force | Out-Null
$mockPath = Join-Path $mockDir "per_asset_whitelist_test.json"
$mockJson = @'
{
  "as_of": "2026-05-17",
  "TIER_A_LIVE": [
    {"market": "ZECUSDT", "stop_atr": 3.0, "target_atr": 3.0, "sharpe": 5.31, "pbo": 0.0}
  ],
  "TIER_B_PAPER": [
    {"market": "HYPEUSDT", "stop_atr": 3.0, "target_atr": 2.0, "sharpe": 12.23, "pbo": 0.33}
  ],
  "TIER_C_SKIP": [
    {"market": "ETHUSDT", "stop_atr": 1.0, "target_atr": 2.0, "sharpe": -0.92}
  ]
}
'@
$mockJson | Out-File -FilePath $mockPath -Encoding UTF8

Describe "Get-QuantWhitelist" {

    It "le JSON e retorna 3 tiers" {
        $wl = Get-QuantWhitelist -Path $mockPath
        $wl.TIER_A_LIVE.Count  | Should Be 1
        $wl.TIER_B_PAPER.Count | Should Be 1
        $wl.TIER_C_SKIP.Count  | Should Be 1
    }

    It "retorna empty quando path nao existe" {
        $wl = Get-QuantWhitelist -Path "C:\does_not_exist_xyz.json"
        $wl.TIER_A_LIVE.Count | Should Be 0
    }
}

Describe "Get-QuantWhitelistMarkets" {

    It "LIVE retorna so tier A" {
        $m = Get-QuantWhitelistMarkets -Mode "LIVE" -Path $mockPath
        $m | Should Be "ZECUSDT"
    }

    It "PAPER retorna A + B" {
        $m = Get-QuantWhitelistMarkets -Mode "PAPER" -Path $mockPath
        @($m).Count | Should Be 2
        ($m -contains "ZECUSDT")  | Should Be $true
        ($m -contains "HYPEUSDT") | Should Be $true
    }

    It "ALL retorna A + B + C" {
        $m = Get-QuantWhitelistMarkets -Mode "ALL" -Path $mockPath
        @($m).Count | Should Be 3
    }
}

Describe "Get-QuantWhitelistEntry" {

    It "encontra ZECUSDT" {
        $e = Get-QuantWhitelistEntry -Market "ZECUSDT" -Path $mockPath
        $e.sharpe | Should Be 5.31
    }

    It "retorna null para market desconhecido" {
        $e = Get-QuantWhitelistEntry -Market "XYZUSDT" -Path $mockPath
        $e | Should BeNullOrEmpty
    }
}

Describe "Merge-QuantWhitelistIntoCandidates" {

    It "adiciona Tier A se nao presente" {
        $cands = @(
            [PSCustomObject]@{ market = "BTCUSDT"; score = 50 }
        )
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates $cands -Mode "LIVE" -Path $mockPath
        @($merged).Count | Should Be 2
        $zec = $merged | Where-Object { $_.market -eq "ZECUSDT" }
        $zec | Should Not BeNullOrEmpty
        $zec.source | Should Be "quant_whitelist_LIVE"
    }

    It "nao duplica se ja presente" {
        $cands = @(
            [PSCustomObject]@{ market = "ZECUSDT"; score = 70 }
        )
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates $cands -Mode "LIVE" -Path $mockPath
        @($merged).Count | Should Be 1
    }

    It "no-op quando whitelist vazia" {
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" -Path "C:\nope.json"
        @($merged).Count | Should Be 0
    }

    It "FASE 4: Tier A entries tem marketType='FUTURES' (filtro downstream scan_master:668)" {
        # Lockdown anti-regression. Bug 2026-05-21 manha: Tier A merged sem marketType
        # field eram silenciosamente filtrados por Where-Object marketType -eq 'FUTURES'.
        # 4 Tier A LIVE markets (RENDER/BTC/INJ/XMR) nao rodavam orchestrator desde ?
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" -Path $mockPath
        $zec = $merged | Where-Object { $_.market -eq "ZECUSDT" }
        $zec | Should Not BeNullOrEmpty
        $zec.marketType | Should Be "FUTURES"
        # Score=100 forca ranking topo + fields scanner-compatible
        $zec.score | Should Be 100
        # change/volume defaults preenchidos pra sort/log nao quebrar
        $zec.PSObject.Properties['change'] | Should Not BeNullOrEmpty
        $zec.PSObject.Properties['volume'] | Should Not BeNullOrEmpty
    }
}

# Cleanup
Remove-Item -Recurse -Force $mockDir -ErrorAction SilentlyContinue

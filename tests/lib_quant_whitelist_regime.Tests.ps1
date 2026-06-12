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

# ── Regime cache mock: schema GLOBAL (producao real -- refresh_regime_state.ps1) ─
# Este e o formato que o sistema realmente grava em journal/regime_state.json:
# regime global, SEM chaves por-mercado. Captura o bug de 2026-05-29 onde
# Get-MarketRegimeFromCache retornava $null pra todos os markets (INJUSDT incluso).
$journalGlobalDir = Join-Path $mockDir "journal_global"
New-Item -ItemType Directory -Path $journalGlobalDir -Force | Out-Null
$regimeGlobalPath = Join-Path $journalGlobalDir "regime_state.json"
@'
{"regime":"BEAR_WEAK","phase":"h24_p3_bear","bias":"BEAR_WEAK","updated_at":"2026-05-29T06:00:02Z","source":"refresh_regime_state.ps1","current_regime":"BEAR_WEAK","prev_regime":"","changed":false}
'@ | Out-File -FilePath $regimeGlobalPath -Encoding UTF8

# ── Whitelist mock com INJUSDT (espelha producao: INJ Tier A LIVE) ────────────
$mockPathInj = Join-Path $mockDir "per_asset_whitelist_inj.json"
@'
{
  "as_of": "2026-05-29",
  "TIER_A_LIVE": [
    {"market": "INJUSDT", "sharpe": 3.88},
    {"market": "BTCUSDT", "sharpe": 3.5}
  ],
  "TIER_B_PAPER": [],
  "TIER_C_SKIP": []
}
'@ | Out-File -FilePath $mockPathInj -Encoding UTF8


# =============================================================================
Describe "Merge-QuantWhitelistIntoCandidates com RegimeProvider" {

    It "ativo BEAR_STRONG (nao-BTC) recebe tier_level=3" {
        # Regra de negocio: BTC e anchor permanente (sempre no top, nunca rebaixa).
        # Validamos o rebaixamento BEAR_STRONG com um ativo nao-anchor (SOLUSDT).
        $provider = { param($m) if ($m -eq "SOLUSDT") { "BEAR_STRONG" } else { $null } }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath -RegimeProvider $provider
        $sol = $merged | Where-Object { $_.market -eq "SOLUSDT" }
        $sol | Should Not BeNullOrEmpty
        $sol.tier_level | Should Be 3
    }

    It "BTC anchor NAO rebaixa mesmo em BEAR_STRONG (sempre no top)" {
        # Regra de negocio (2026-05-29): BTC permanece tier_level=1 em qualquer regime.
        $provider = { param($m) if ($m -eq "BTCUSDT") { "BEAR_STRONG" } else { $null } }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPath -RegimeProvider $provider
        $btc = $merged | Where-Object { $_.market -eq "BTCUSDT" }
        $btc | Should Not BeNullOrEmpty
        $btc.tier_level | Should Be 1
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


# =============================================================================
# REGRESSAO 2026-05-29: schema GLOBAL (producao real)
# Bug: refresh_regime_state.ps1 grava {regime, phase, bias, current_regime}
# (regime GLOBAL, sem chaves por-mercado). Get-MarketRegimeFromCache procurava
# apenas chaves por-mercado -> retornava $null pra TODOS os markets -> o
# rebaixamento regime-aware nunca disparava (no-op em producao). INJUSDT (e todo
# Tier A) continuava entrando tier_level=1 mesmo em mercado bear.
# Fix (Opcao A): ler regime global de .regime / .current_regime como fallback.
Describe "Get-MarketRegimeFromCache -- schema global (regressao 2026-05-29)" {

    It "le regime global do campo 'regime' quando nao ha chave por-mercado" {
        $regime = Get-MarketRegimeFromCache -Market "INJUSDT" -JournalDir $journalGlobalDir
        $regime | Should Be "BEAR_WEAK"
    }

    It "retorna o mesmo regime global para qualquer market (BTC, INJ, XYZ)" {
        (Get-MarketRegimeFromCache -Market "BTCUSDT"  -JournalDir $journalGlobalDir) | Should Be "BEAR_WEAK"
        (Get-MarketRegimeFromCache -Market "INJUSDT"  -JournalDir $journalGlobalDir) | Should Be "BEAR_WEAK"
        (Get-MarketRegimeFromCache -Market "XYZUSDT"  -JournalDir $journalGlobalDir) | Should Be "BEAR_WEAK"
    }

    It "chave por-mercado tem precedencia sobre regime global" {
        # journalDir (mock por-mercado) tem BTCUSDT=BEAR_STRONG explicito
        $regime = Get-MarketRegimeFromCache -Market "BTCUSDT" -JournalDir $journalDir
        $regime | Should Be "BEAR_STRONG"
    }
}


# =============================================================================
# INTEGRACAO 2026-05-29: INJUSDT end-to-end com cache global real
# Com o fix, INJ (Tier A LIVE) em mercado bear global deve cair para tier_level=3,
# liberando o slot. Antes do fix: tier_level=1 (no-op).
Describe "Merge-QuantWhitelistIntoCandidates -- INJUSDT cache global real" {

    It "INJUSDT cai para tier_level=3 quando regime_state global e BEAR_WEAK" {
        $provider = { param($m) Get-MarketRegimeFromCache -Market $m -JournalDir $journalGlobalDir }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj -RegimeProvider $provider
        $inj = $merged | Where-Object { $_.market -eq "INJUSDT" }
        $inj | Should Not BeNullOrEmpty
        $inj.tier_level | Should Be 3
    }

    It "Tier A nao-BTC cai para tier_level=3 em mercado bear global (BTC anchor permanece 1)" {
        # Regra de negocio (2026-05-29): BTC sempre no top (tier_level=1) em qualquer regime.
        # Os demais Tier A rebaixam para 3 em bear, liberando slots para organicos.
        $provider = { param($m) Get-MarketRegimeFromCache -Market $m -JournalDir $journalGlobalDir }
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj -RegimeProvider $provider
        foreach ($entry in $merged) {
            if ($entry.market -eq "BTCUSDT") {
                $entry.tier_level | Should Be 1
            } else {
                $entry.tier_level | Should Be 3
            }
        }
    }
}


# =============================================================================
# Item 1 (2026-05-29): -AnchorMarkets parametro restringe forcados
# Antes: todos os Tier A/B da whitelist eram forcados no top do scan,
#        monopolizando os slots (caso INJUSDT 2026-05-29).
# Agora: AnchorMarkets define EXATAMENTE quais markets sao forcados.
# Default: todos os Tier A/B (backward compat).
# Producao: AnchorMarkets=@("BTCUSDT") -- so BTC anchor, demais competem organicos.
Describe "Merge-QuantWhitelistIntoCandidates -- AnchorMarkets restringe forcados" {

    It "AnchorMarkets=@('BTCUSDT'): so BTC retorna como forcado" {
        $merged = @(Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj -AnchorMarkets @("BTCUSDT"))
        $merged.Count | Should Be 1
        $merged[0].market | Should Be "BTCUSDT"
    }

    It "AnchorMarkets vazio: nenhum forcado retornado" {
        $merged = @(Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj -AnchorMarkets @())
        $merged.Count | Should Be 0
    }

    It "AnchorMarkets nao especificado (default): backward compat -- todos Tier A/B forcados" {
        $merged = @(Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj)
        # mockPathInj tem INJUSDT + BTCUSDT em TIER_A_LIVE
        $merged.Count | Should Be 2
    }

    It "AnchorMarkets com mercado fora da whitelist: ignorado (so retorna intersecao)" {
        $merged = @(Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj -AnchorMarkets @("BTCUSDT","NOTINWHITELISTUSDT"))
        $merged.Count | Should Be 1
        $merged[0].market | Should Be "BTCUSDT"
    }

    It "AnchorMarkets preserva tier_level original do anchor" {
        $merged = @(Merge-QuantWhitelistIntoCandidates -Candidates @() -Mode "LIVE" `
            -Path $mockPathInj -AnchorMarkets @("BTCUSDT"))
        $merged[0].tier_level | Should Be 1
    }

    It "AnchorMarkets nao filtra candidatos organicos preexistentes (preserva scanner natural)" {
        # Cenario real: scanner ja achou ALT1 organicamente, BTC e anchor.
        # Whitelist tem BTC+INJ mas so BTC e anchor -> INJ NAO entra forcado;
        # ALT1 organico permanece intacto.
        $organic = @(
            [PSCustomObject]@{ market = "ALT1USDT"; score = 75; change = 5.0; volume = 100000 }
        )
        $merged = @(Merge-QuantWhitelistIntoCandidates -Candidates $organic -Mode "LIVE" `
            -Path $mockPathInj -AnchorMarkets @("BTCUSDT"))
        $merged.Count | Should Be 2
        ($merged | ForEach-Object { $_.market }) -contains "ALT1USDT" | Should Be $true
        ($merged | ForEach-Object { $_.market }) -contains "BTCUSDT"  | Should Be $true
        ($merged | ForEach-Object { $_.market }) -contains "INJUSDT"  | Should Be $false
    }
}


# Cleanup
Remove-Item -Recurse -Force $mockDir -ErrorAction SilentlyContinue

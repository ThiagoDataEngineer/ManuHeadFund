# lib_fundamental_quality.Tests.ps1 -- TDD-first Fundamental Quality Score.
# Pester 3.x.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_fundamental_quality.ps1")

$script:tmp = Join-Path $env:TEMP ("fqs_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Get-FundamentalScore - inputs" {
    It "Market unknown retorna FQS=0 e categoria AVOID" {
        $r = Get-FundamentalScore -Market "FAKEUSDT" -RegistryPath (Join-Path $tmp "empty.json")
        $r.fqs | Should Be 0
        $r.category | Should Be "AVOID"
    }
    It "BTC (sem burn, mas capped + age + utility + recovery) retorna FQS 6 BLUE_CHIP" {
        # BTC nao tem burn (halving e supply schedule diferente). Score 6/7 = BLUE_CHIP.
        $reg = Join-Path $tmp "reg1.json"
        @{
            BTCUSDT = @{
                age_years = 16; supply_capped = $true; burn_active = $false;
                utility_score = 1.0; concentration_top10 = 0.10;
                recovered_2021_ath = $true; listing_years = 8
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "BTCUSDT" -RegistryPath $reg
        $r.fqs | Should Be 6
        $r.category | Should Be "BLUE_CHIP"
    }
    It "Asset com TODOS 7 sinais positivos retorna FQS 7 BLUE_CHIP" {
        $reg = Join-Path $tmp "regfull.json"
        @{
            FULLUSDT = @{
                age_years = 10; supply_capped = $true; burn_active = $true;
                utility_score = 1.0; concentration_top10 = 0.10;
                recovered_2021_ath = $true; listing_years = 5
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "FULLUSDT" -RegistryPath $reg
        $r.fqs | Should Be 7
        $r.category | Should Be "BLUE_CHIP"
    }
    It "Asset jovem (1y) supply unlimited concentrated = FQS baixo SPECULATIVE" {
        $reg = Join-Path $tmp "reg2.json"
        @{
            VAPORUSDT = @{
                age_years = 1; supply_capped = $false; burn_active = $false;
                utility_score = 0.1; concentration_top10 = 0.75;
                recovered_2021_ath = $false; listing_years = 0.5
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "VAPORUSDT" -RegistryPath $reg
        ($r.fqs -le 2) | Should Be $true
        ($r.category -in @("AVOID","SPECULATIVE")) | Should Be $true
    }
    It "Mid quality: alguns sinais positivos = QUALITY 4-5" {
        $reg = Join-Path $tmp "reg3.json"
        @{
            MIDUSDT = @{
                age_years = 5; supply_capped = $true; burn_active = $true;
                utility_score = 0.6; concentration_top10 = 0.4;
                recovered_2021_ath = $false; listing_years = 3
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "MIDUSDT" -RegistryPath $reg
        ($r.fqs -ge 4 -and $r.fqs -le 6) | Should Be $true
    }
}


Describe "FQS V1.5 - 3 refinos criticos" {
    It "Refino A: Token jovem (<2y) com cycle_resilience N/A nao penaliza" {
        $reg = Join-Path $tmp "young.json"
        # HYPE-like: jovem, capped, burn, utility, recovered_2021_ath FALSE pq jovem
        @{
            YOUNGUSDT = @{
                age_years = 1.5; supply_capped = $true; burn_active = $true;
                utility_score = 0.8; concentration_top10 = 0.40;
                recovered_2021_ath = $false; listing_years = 1
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "YOUNGUSDT" -RegistryPath $reg
        # V1.0 daria FQS 4 (sem age_3+, sem recovered, sem listing); V1.5 da +1 por young_NA_cycle = 5
        ($r.fqs -ge 5) | Should Be $true
        ($r.reasons -contains "young_NA_cycle") | Should Be $true
    }
    It "Refino B: ETH-like uncapped + burn_net_deflation = supply_discipline OK" {
        $reg = Join-Path $tmp "eth.json"
        @{
            ETHUSDT = @{
                age_years = 10; supply_capped = $false; burn_net_deflation = $true;
                burn_active = $true; utility_score = 1.0; concentration_top10 = 0.25;
                recovered_2021_ath = $false; listing_years = 7
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "ETHUSDT" -RegistryPath $reg
        # V1.0: 5 (sem supply_capped); V1.5: 6 (burn_net_deflation pega) = BLUE_CHIP
        ($r.fqs -ge 6) | Should Be $true
        ($r.reasons -contains "burn_net_deflation") | Should Be $true
        $r.category | Should Be "BLUE_CHIP"
    }
    It "Refino C: concentration_insider_pct override concentration_top10 (CEX wallets excluded)" {
        $reg = Join-Path $tmp "cex.json"
        # Token com 70% em CEX wallets (custodial = OK) MAS insider real = 20%
        @{
            CEXOKUSDT = @{
                age_years = 5; supply_capped = $true; burn_active = $true;
                utility_score = 0.7;
                concentration_top10 = 0.70;       # high (inclui CEX)
                concentration_insider_pct = 0.20; # low (insider/team real)
                recovered_2021_ath = $true; listing_years = 4
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "CEXOKUSDT" -RegistryPath $reg
        # V1.0 falharia concentration (0.70 > 0.50); V1.5 usa insider 0.20 OK
        ($r.reasons -contains "concentration_ok") | Should Be $true
        ($r.fqs -ge 6) | Should Be $true
    }
    It "Backward compat: registry sem campos novos funciona como V1" {
        $reg = Join-Path $tmp "compat.json"
        @{
            OLDUSDT = @{
                age_years = 5; supply_capped = $true; burn_active = $true;
                utility_score = 0.7; concentration_top10 = 0.30;
                recovered_2021_ath = $true; listing_years = 4
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "OLDUSDT" -RegistryPath $reg
        $r.fqs | Should Be 7
        $r.category | Should Be "BLUE_CHIP"
    }
}


Describe "Test-FundamentalQualityGate" {
    BeforeEach {
        $script:gateReg = Join-Path $tmp "gate_reg.json"
        @{
            BLUEUSDT = @{ age_years=10; supply_capped=$true; burn_active=$true; utility_score=1.0; concentration_top10=0.15; recovered_2021_ath=$true; listing_years=5 }
            QUALUSDT = @{ age_years=4; supply_capped=$true; burn_active=$false; utility_score=0.7; concentration_top10=0.35; recovered_2021_ath=$false; listing_years=2 }
            SPECUSDT = @{ age_years=4; supply_capped=$true; burn_active=$false; utility_score=0.3; concentration_top10=0.55; recovered_2021_ath=$false; listing_years=1 }
            AVDUSDT  = @{ age_years=0.3; supply_capped=$false; burn_active=$false; utility_score=0; concentration_top10=0.85; recovered_2021_ath=$false; listing_years=0.2 }
        } | ConvertTo-Json -Depth 5 | Out-File $gateReg -Encoding utf8
    }
    It "BLUE_CHIP passa em qualquer tier" {
        Test-FundamentalQualityGate -Market "BLUEUSDT" -TargetTier "TIER_A_LIVE" -RegistryPath $gateReg | Should Be $true
        Test-FundamentalQualityGate -Market "BLUEUSDT" -TargetTier "GEM" -RegistryPath $gateReg | Should Be $true
    }
    It "QUALITY passa Tier B + Tier A LIVE seletivo" {
        Test-FundamentalQualityGate -Market "QUALUSDT" -TargetTier "TIER_B_PAPER" -RegistryPath $gateReg | Should Be $true
        Test-FundamentalQualityGate -Market "QUALUSDT" -TargetTier "TIER_A_LIVE" -RegistryPath $gateReg | Should Be $true
    }
    It "SPECULATIVE so passa GEM" {
        Test-FundamentalQualityGate -Market "SPECUSDT" -TargetTier "GEM" -RegistryPath $gateReg | Should Be $true
        Test-FundamentalQualityGate -Market "SPECUSDT" -TargetTier "TIER_A_LIVE" -RegistryPath $gateReg | Should Be $false
        Test-FundamentalQualityGate -Market "SPECUSDT" -TargetTier "TIER_B_PAPER" -RegistryPath $gateReg | Should Be $false
    }
    It "AVOID nunca passa" {
        Test-FundamentalQualityGate -Market "AVDUSDT" -TargetTier "GEM" -RegistryPath $gateReg | Should Be $false
        Test-FundamentalQualityGate -Market "AVDUSDT" -TargetTier "TIER_A_LIVE" -RegistryPath $gateReg | Should Be $false
    }
}

Describe "FQS V1.6 - cycle resilience refinado" {
    # V1.6: recovered_2021_ath aceita 3 paths:
    # 1. recovered_2021_ath_source == 'manual_override_*' -> respeita o boolean explicito
    # 2. recovered_2021_ath == True -> direto OK
    # 3. recovered_2021_ath == False MAS current_price/ath_all_time >= 0.5 -> "recovered_partial" OK
    # 4. Tudo False -> nao recovered
    $tmp16 = Join-Path $env:TEMP "fqs16_$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tmp16 -Force | Out-Null

    It "Manual override sobrescreve CoinGecko False (BTC case)" {
        $reg = Join-Path $tmp16 "btc.json"
        @{
            BTCUSDT = @{
                age_years = 16; supply_capped = $true; burn_active = $false;
                utility_score = 1.0; concentration_top10 = 0.10;
                recovered_2021_ath = $true;
                recovered_2021_ath_source = "manual_override_semantic_match_2021";
                listing_years = 8
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "BTCUSDT" -RegistryPath $reg
        ($r.reasons -contains "recovered_ath") | Should Be $true
    }
    It "Partial recovery (>=50% ATH) com price+ath_all_time conta como recovered" {
        $reg = Join-Path $tmp16 "partial.json"
        @{
            ETHUSDT = @{
                age_years = 10; supply_capped = $false; burn_net_deflation = $true;
                burn_active = $true; utility_score = 1.0; concentration_top10 = 0.25;
                recovered_2021_ath = $false;
                current_price_usd = 2500;
                ath_all_time_usd = 4800;
                listing_years = 8
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        # 2500/4800 = 0.52 >= 0.5 -> recovered_partial OK
        $r = Get-FundamentalScore -Market "ETHUSDT" -RegistryPath $reg
        ($r.reasons -contains "recovered_ath" -or $r.reasons -contains "recovered_partial") | Should Be $true
    }
    It "Recovery <50% NAO conta" {
        $reg = Join-Path $tmp16 "no_recov.json"
        @{
            NORECOVERY = @{
                age_years = 5; supply_capped = $false; burn_active = $false;
                utility_score = 0.3; concentration_top10 = 0.4;
                recovered_2021_ath = $false;
                current_price_usd = 100;
                ath_all_time_usd = 500;
                listing_years = 3
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        # 100/500 = 0.20 < 0.5 -> NAO recovered
        $r = Get-FundamentalScore -Market "NORECOVERY" -RegistryPath $reg
        ($r.reasons -contains "recovered_ath") | Should Be $false
        ($r.reasons -contains "recovered_partial") | Should Be $false
    }
    It "Young token (age<2) ainda bonus N/A cycle (V1.5 mantido)" {
        $reg = Join-Path $tmp16 "young.json"
        @{
            YOUNGUSDT = @{
                age_years = 1; supply_capped = $true; burn_active = $true;
                utility_score = 0.8; concentration_top10 = 0.40;
                recovered_2021_ath = $false; listing_years = 1
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "YOUNGUSDT" -RegistryPath $reg
        ($r.reasons -contains "young_NA_cycle") | Should Be $true
    }

    Remove-Item $tmp16 -Recurse -Force -ErrorAction SilentlyContinue
}


Describe "FQS 2026-08-19 -- overlay Supabase coin_registry_dynamic" {
    # coin_registry.json (curadoria manual, git) so cobre ~68 moedas -- travava
    # LONG FUTURES em coins liquidas reais (LINK/ADA/AVAX/etc) so por AUSENCIA
    # de cadastro. coin_registry_dynamic (Supabase, alimentado por
    # coingecko_enrichment.py --supabase) cobre o resto com dado fresco.
    $tmpDyn = Join-Path $env:TEMP ("fqs_dyn_$([guid]::NewGuid())")
    New-Item -ItemType Directory -Path $tmpDyn -Force | Out-Null

    AfterEach {
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
    }

    It "Market AUSENTE do estatico mas presente no dynamic usa dado do Supabase" {
        Set-Item function:Get-StateRecords -Value {
            param($Table, $Filter)
            return @([PSCustomObject]@{
                market = "LINKUSDT"; age_years = 12; supply_capped = $false
                recovered_2021_ath = $true; current_price_usd = 25.0; ath_all_time_usd = 53.0
            })
        }
        $reg = Join-Path $tmpDyn "empty.json"
        "{}" | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "LINKUSDT" -RegistryPath $reg
        $r.reason | Should Not Be "market_not_in_registry"
        ($r.reasons -contains "age_3y+") | Should Be $true
        ($r.reasons -contains "recovered_ath") | Should Be $true
    }

    It "Market presente no estatico: campos curados (burn_active/utility_score) vencem, dynamic so preenche o resto" {
        Set-Item function:Get-StateRecords -Value {
            param($Table, $Filter)
            return @([PSCustomObject]@{
                market = "MIXUSDT"; age_years = 999; supply_capped = $false
            })
        }
        $reg = Join-Path $tmpDyn "mixed.json"
        @{
            MIXUSDT = @{
                age_years = 5; supply_capped = $true; burn_active = $true
                utility_score = 0.9; concentration_top10 = 0.2
                recovered_2021_ath = $true; listing_years = 4
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "MIXUSDT" -RegistryPath $reg
        # age_years=5 do estatico deve vencer, NAO 999 do dynamic
        $r.details.age_years | Should Be 5
        $r.details.supply_capped | Should Be $true
    }

    It "Market ausente dos dois continua AVOID (comportamento pre-existente preservado)" {
        Set-Item function:Get-StateRecords -Value {
            param($Table, $Filter)
            return @()
        }
        $reg = Join-Path $tmpDyn "empty2.json"
        "{}" | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "NOWHEREUSDT" -RegistryPath $reg
        $r.fqs | Should Be 0
        $r.category | Should Be "AVOID"
        $r.reason | Should Be "market_not_in_registry"
    }

    It "Falha no Supabase (excecao) nao quebra o gate -- segue so com estatico" {
        Set-Item function:Get-StateRecords -Value {
            param($Table, $Filter)
            throw "Supabase indisponivel"
        }
        $reg = Join-Path $tmpDyn "staticonly.json"
        @{
            SAFEUSDT = @{
                age_years = 4; supply_capped = $true; burn_active = $true
                utility_score = 0.9; concentration_top10 = 0.2
                recovered_2021_ath = $true; listing_years = 3
            }
        } | ConvertTo-Json -Depth 5 | Out-File $reg -Encoding utf8
        $r = Get-FundamentalScore -Market "SAFEUSDT" -RegistryPath $reg
        $r.category | Should Be "BLUE_CHIP"
    }

    Remove-Item $tmpDyn -Recurse -Force -ErrorAction SilentlyContinue
}


Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

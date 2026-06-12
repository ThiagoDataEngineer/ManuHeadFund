# validate_fqs_registry.ps1
# Valida e reporta gaps no FQS Registry
# Uso: .\validate_fqs_registry.ps1

param(
    [string]$RegistryPath = "C:\Users\thiag\Coinex_AI_USER_API\journal\coin_registry.json",
    [string]$OutputPath = "C:\Users\thiag\Coinex_AI_USER_API\FQS_REGISTRY_VALIDATION_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
)

# Carregar registry
$registry = Get-Content $RegistryPath | ConvertFrom-Json
$assets = $registry.PSObject.Properties | Where-Object { $_.Name -ne "_meta" }

# Campos obrigatórios para cada tier
$tier_a_required = @("age_years", "supply_capped", "burn_active", "utility_score", "concentration_top10", "recovered_2021_ath", "listing_years")
$tier_b_required = @("age_years", "supply_capped", "burn_active", "utility_score", "concentration_top10", "recovered_2021_ath", "listing_years")
$tier_c_required = @("age_years", "supply_capped", "utility_score", "concentration_top10")

# Análise
$analysis = @{
    total_assets = 0
    complete = @()
    partial = @()
    minimal = @()
    gaps = @()
    tier_distribution = @{
        tier_a = 0
        tier_b = 0
        tier_c = 0
        tier_d = 0
    }
}

foreach ($asset in $assets) {
    $symbol = $asset.Name
    $data = $asset.Value
    
    $analysis.total_assets++
    
    # Contar campos presentes
    $fields_present = 0
    $required_fields = @()
    
    foreach ($field in $tier_a_required) {
        if ($data.PSObject.Properties.Name -contains $field) {
            $fields_present++
        } else {
            $required_fields += $field
        }
    }
    
    # Classificar
    if ($fields_present -eq 7) {
        $analysis.complete += $symbol
        
        # Determinar tier baseado em utility_score
        $utility = $data.utility_score
        if ($utility -ge 0.8) {
            $analysis.tier_distribution.tier_a++
        } else {
            $analysis.tier_distribution.tier_b++
        }
    } elseif ($fields_present -ge 3) {
        $analysis.partial += @{
            symbol = $symbol
            fields_present = $fields_present
            missing = $required_fields
        }
        $analysis.tier_distribution.tier_c++
    } else {
        $analysis.minimal += @{
            symbol = $symbol
            fields_present = $fields_present
            missing = $required_fields
        }
        $analysis.tier_distribution.tier_d++
    }
    
    # Detectar gaps específicos
    if (-not $data.PSObject.Properties.Name -contains "age_years") {
        $analysis.gaps += @{
            symbol = $symbol
            gap_type = "missing_age_years"
            severity = "HIGH"
        }
    }
    
    if (-not $data.PSObject.Properties.Name -contains "utility_score") {
        $analysis.gaps += @{
            symbol = $symbol
            gap_type = "missing_utility_score"
            severity = "HIGH"
        }
    }
    
    if (-not $data.PSObject.Properties.Name -contains "concentration_top10") {
        $analysis.gaps += @{
            symbol = $symbol
            gap_type = "missing_concentration"
            severity = "MEDIUM"
        }
    }
}

# Gerar relatório
$report = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    registry_path = $RegistryPath
    summary = @{
        total_assets = $analysis.total_assets
        complete_count = $analysis.complete.Count
        complete_pct = [math]::Round(($analysis.complete.Count / $analysis.total_assets) * 100, 1)
        partial_count = $analysis.partial.Count
        partial_pct = [math]::Round(($analysis.partial.Count / $analysis.total_assets) * 100, 1)
        minimal_count = $analysis.minimal.Count
        minimal_pct = [math]::Round(($analysis.minimal.Count / $analysis.total_assets) * 100, 1)
        total_gaps = $analysis.gaps.Count
    }
    tier_distribution = $analysis.tier_distribution
    complete_assets = $analysis.complete
    partial_assets = $analysis.partial
    minimal_assets = $analysis.minimal
    gaps = $analysis.gaps
    recommendations = @(
        "1. Adicionar 3 ativos faltantes: IDUSDT, IOUSDT, FETUSDT ✅ DONE"
        "2. Completar dados parciais via CoinGecko API para 18 ativos"
        "3. Validar ativos novos (<1 ano) antes de Tier B"
        "4. Implementar validação automática de age_years >= 1y para Tier B em bear phase"
        "5. Criar pipeline de enrich para ativos meme/especulativos"
    )
}

# Salvar relatório
$report | ConvertTo-Json -Depth 10 | Out-File $OutputPath -Encoding UTF8

Write-Host "✅ Validação completa!"
Write-Host "📊 Relatório salvo em: $OutputPath"
Write-Host ""
Write-Host "RESUMO:"
Write-Host "  Total de ativos: $($report.summary.total_assets)"
Write-Host "  Completos: $($report.summary.complete_count) ($($report.summary.complete_pct)%)"
Write-Host "  Parciais: $($report.summary.partial_count) ($($report.summary.partial_pct)%)"
Write-Host "  Mínimos: $($report.summary.minimal_count) ($($report.summary.minimal_pct)%)"
Write-Host "  Total de gaps: $($report.summary.total_gaps)"
Write-Host ""
Write-Host "DISTRIBUIÇÃO POR TIER:"
Write-Host "  Tier A: $($report.tier_distribution.tier_a)"
Write-Host "  Tier B: $($report.tier_distribution.tier_b)"
Write-Host "  Tier C: $($report.tier_distribution.tier_c)"
Write-Host "  Tier D: $($report.tier_distribution.tier_d)"

# lib_macro_audit.ps1 -- Auditoria de pesos adaptativos runtime
# Verifica se WEIGHTS_BULL/BEAR/NEUTRAL sao REALMENTE consumidos em decisao,
# nao apenas declarados em config. Procura evidencia textual no orchestrator.
# Uso: . (Join-Path $PSScriptRoot "lib_macro_audit.ps1"); Test-AdaptiveWeightsRotation

function Test-AdaptiveWeightsRotation {
    param(
        [string]$ConfigPath        = (Join-Path $PSScriptRoot "config.ps1"),
        [string]$OrchestratorPath  = (Join-Path $PSScriptRoot "orchestrator.ps1"),
        [object]$ForceMacroBias    = $null     # injeta bias para teste; default = chama Get-MacroContext
    )

    # â”€â”€ 1. Carregar tabelas de pesos do config.ps1 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $cfgRaw = Get-Content $ConfigPath -Raw -ErrorAction Stop

    $weightsByRegime = @{
        BULL    = $null
        NEUTRAL = $null
        BEAR    = $null
    }

    # Parse simples: regex captura @{ Tech=...; Chain=...; Sent=...; Fund=... }
    foreach ($key in @('BULL','NEUTRAL','BEAR')) {
        $pattern = '(?m)^\$WEIGHTS_' + $key + '\s*=\s*@\{\s*(?<body>[^}]+)\}'
        $match   = [regex]::Match($cfgRaw, $pattern)
        if ($match.Success) {
            $body = $match.Groups['body'].Value
            $hash = @{}
            foreach ($pair in $body -split ';') {
                $kv = $pair -split '='
                if ($kv.Count -eq 2) {
                    $name = $kv[0].Trim()
                    $val  = $kv[1].Trim()
                    $num  = 0.0
                    if ([double]::TryParse($val, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
                        $hash[$name] = $num
                    }
                }
            }
            $weightsByRegime[$key] = $hash
        }
    }

    # â”€â”€ 2. Detectar evidencia de USO REAL no orchestrator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $orchRaw = Get-Content $OrchestratorPath -Raw -ErrorAction Stop

    # Procura padroes "$w.Tech", "$w.Fund", etc multiplicando score
    $usagePatterns = @(
        '\$w\.Tech\s*\*',
        '\$w\.Chain\s*\*',
        '\$w\.Sent\s*\*',
        '\$w\.Fund\s*\*',
        '\*\s*\$w\.Tech',
        '\*\s*\$w\.Chain',
        '\*\s*\$w\.Sent',
        '\*\s*\$w\.Fund'
    )

    $rotationEvidence = @()
    $orchLines = $orchRaw -split "`n"
    for ($i = 0; $i -lt $orchLines.Count; $i++) {
        foreach ($pat in $usagePatterns) {
            if ($orchLines[$i] -match $pat) {
                $rotationEvidence += [PSCustomObject]@{
                    line    = $i + 1
                    snippet = $orchLines[$i].Trim()
                    pattern = $pat
                }
                break
            }
        }
    }

    # Detecta switch de regime: macro_bias -> pesos
    # Tolerante a braces internos (cada caso usa { ... }):
    $switchPattern = '(?ms)switch\s*\(\s*\$macro\.macro_bias\s*\).*?WEIGHTS_BULL.*?WEIGHTS_BEAR'
    $hasSwitch = [regex]::IsMatch($orchRaw, $switchPattern)

    # â”€â”€ 3. Validar que pesos DIFEREM entre regimes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $weightsActuallyDiffer = $false
    if ($weightsByRegime.BULL -and $weightsByRegime.BEAR) {
        foreach ($k in @('Tech','Chain','Sent','Fund')) {
            if ($weightsByRegime.BULL[$k] -ne $weightsByRegime.BEAR[$k]) {
                $weightsActuallyDiffer = $true
                break
            }
        }
    }

    # â”€â”€ 4. Determinar bias atual (cache 24h ou forced) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $currentBias = "NEUTRAL"
    if ($ForceMacroBias) {
        $currentBias = $ForceMacroBias
    } else {
        try {
            $macroLib = Join-Path $PSScriptRoot "lib_macro.ps1"
            if (Test-Path $macroLib) {
                . $macroLib
                $ctx = Get-MacroContext
                if ($ctx -and $ctx.macro_bias) { $currentBias = $ctx.macro_bias }
            }
        } catch {
            $currentBias = "NEUTRAL (fallback)"
        }
    }

    $currentlyUsing = switch -Regex ($currentBias) {
        'BULLISH' { 'BULL' }
        'BEARISH' { 'BEAR' }
        default   { 'NEUTRAL' }
    }

    # â”€â”€ 5. Veredito â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $adaptiveActive = (
        $rotationEvidence.Count -ge 4 -and
        $hasSwitch -and
        $weightsActuallyDiffer
    )

    return [PSCustomObject]@{
        adaptive_active        = $adaptiveActive
        weights_by_regime      = $weightsByRegime
        currently_using        = $currentlyUsing
        current_macro_bias     = $currentBias
        rotation_evidence      = $rotationEvidence
        evidence_count         = $rotationEvidence.Count
        has_regime_switch      = $hasSwitch
        weights_actually_differ = $weightsActuallyDiffer
        verdict                = if ($adaptiveActive) {
            "ROTATION_ACTIVE: pesos rotacionam por regime e SAO consumidos em score ponderado"
        } else {
            "INFORMATIONAL_ONLY: tabelas existem mas nao ha evidencia de uso em scoring"
        }
    }
}

function Get-AdaptiveWeightsReport {
    param([object]$AuditResult)

    if (-not $AuditResult) {
        $AuditResult = Test-AdaptiveWeightsRotation
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Audit Pesos Adaptativos Runtime")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Veredito:** $($AuditResult.verdict)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- adaptive_active: $($AuditResult.adaptive_active)")
    [void]$sb.AppendLine("- has_regime_switch: $($AuditResult.has_regime_switch)")
    [void]$sb.AppendLine("- weights_actually_differ: $($AuditResult.weights_actually_differ)")
    [void]$sb.AppendLine("- evidence_count: $($AuditResult.evidence_count)")
    [void]$sb.AppendLine("- currently_using: $($AuditResult.currently_using) (bias=$($AuditResult.current_macro_bias))")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Pesos por Regime")
    foreach ($k in @('BULL','NEUTRAL','BEAR')) {
        $w = $AuditResult.weights_by_regime[$k]
        if ($w) {
            [void]$sb.AppendLine("- ${k}: Tech=$($w.Tech) Chain=$($w.Chain) Sent=$($w.Sent) Fund=$($w.Fund)")
        }
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Evidencia de Rotation (orchestrator.ps1)")
    foreach ($e in $AuditResult.rotation_evidence) {
        [void]$sb.AppendLine("- L$($e.line): ``$($e.snippet)``")
    }
    return $sb.ToString()
}

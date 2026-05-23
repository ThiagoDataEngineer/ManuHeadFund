# lib_mentor_schema.ps1 -- Schema-first Mentor output + 5-tier veredicto + sizing tilt cap.
#
# E1 (2026-05-22, Tauric-inspired):
#   1. Expande veredicto 3-tier -> 5-tier:
#        STRONG_EXECUTAR  -> sizing 1.5x  (HIGH confidence)
#        EXECUTAR          -> sizing 1.0x  (NORMAL)
#        REVISAR           -> sizing 0.5x paper-only (DOUBT)
#        ABORTAR           -> skip
#        HARD_VETO         -> skip + blacklist 24h
#   2. Schema validation: campos required + types + ranges
#   3. Sizing tilt cap: STRONG_EXECUTAR amplifier 1.5x CAPPED em 1.0x ate 30+ outcomes
#      historicamente validarem accuracy STRONG. Anti-overconfidence guard.
#   4. Retry-on-violation: 1st invalid -> re-prompt; 2nd invalid -> force ABORTAR safe.
#
# Operacao:
#   - Test-MentorOutput: valida + retorna {valid, violations[]}
#   - Get-SizingTiltMultiplier: lookup tier -> multiplier (com cap se outcomes < 30)
#   - Get-StrongOutcomesCount: le ledger pra contar STRONG outcomes validados
#
# Fail-soft: schema validation falha -> default ABORTAR conservador.
#
# PS 5.1. UTF-8 BOM.


$script:MENTOR_VEREDICTO_VALID = @("STRONG_EXECUTAR","EXECUTAR","REVISAR","ABORTAR","HARD_VETO")
$script:MENTOR_RISCO_VALID     = @("BAIXO","MEDIO","ALTO","EXTREMO")

# Sizing multiplier per tier
$script:MENTOR_SIZING_MAP = @{
    "STRONG_EXECUTAR" = 1.5
    "EXECUTAR"        = 1.0
    "REVISAR"         = 0.5
    "ABORTAR"         = 0.0
    "HARD_VETO"       = 0.0
}

# STRONG tier cap: only after N validated outcomes
$script:STRONG_MIN_OUTCOMES_FOR_TILT = 30


function Test-MentorOutput {
    <#
    .SYNOPSIS
    Valida resposta Mentor contra schema 5-tier. Retorna PSCustomObject @{valid, violations}.

    .DESCRIPTION
    Schema:
      veredicto         (enum, required)
      confianca_mentor  (int 0-100, required)
      risco_identificado (enum, required)
      mentor_mensagem   (string max 600, optional)
      motivo_veto       (string, optional, exigido se veredicto in REVISAR/ABORTAR/HARD_VETO)
      knowledge_cited   (array, optional)

    .PARAMETER Response
    PSCustomObject (parsed from JSON) ou string JSON.

    .EXAMPLE
    $r = Test-MentorOutput -Response $parsed
    if (-not $r.valid) { Write-Host "Schema violations: $($r.violations -join ', ')" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Response
    )

    $obj = $Response
    if ($obj -is [string]) {
        try { $obj = $Response | ConvertFrom-Json -ErrorAction Stop }
        catch {
            return [PSCustomObject]@{
                valid = $false
                violations = @("invalid_json: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))")
            }
        }
    }

    $violations = @()

    # veredicto (required + enum)
    if (-not $obj.PSObject.Properties['veredicto']) {
        $violations += "veredicto_missing"
    } elseif ($script:MENTOR_VEREDICTO_VALID -notcontains $obj.veredicto) {
        $violations += "veredicto_invalid: '$($obj.veredicto)' not in $($script:MENTOR_VEREDICTO_VALID -join '|')"
    }

    # confianca_mentor (required, int, 0-100)
    if (-not $obj.PSObject.Properties['confianca_mentor']) {
        $violations += "confianca_missing"
    } else {
        try {
            $c = [int]$obj.confianca_mentor
            if ($c -lt 0 -or $c -gt 100) {
                $violations += "confianca_out_of_range: $c (must be 0-100)"
            }
        } catch {
            $violations += "confianca_not_int: $($obj.confianca_mentor)"
        }
    }

    # risco_identificado (required + enum)
    if (-not $obj.PSObject.Properties['risco_identificado']) {
        $violations += "risco_missing"
    } elseif ($script:MENTOR_RISCO_VALID -notcontains $obj.risco_identificado) {
        $violations += "risco_invalid: '$($obj.risco_identificado)' not in $($script:MENTOR_RISCO_VALID -join '|')"
    }

    # mentor_mensagem max length
    if ($obj.PSObject.Properties['mentor_mensagem'] -and $obj.mentor_mensagem) {
        if ($obj.mentor_mensagem.Length -gt 600) {
            $violations += "mentor_mensagem_too_long: $($obj.mentor_mensagem.Length) chars (max 600)"
        }
    }

    # motivo_veto required if veredicto != EXECUTAR/STRONG_EXECUTAR
    if ($obj.PSObject.Properties['veredicto'] -and `
        $obj.veredicto -in @("REVISAR","ABORTAR","HARD_VETO")) {
        if (-not $obj.PSObject.Properties['motivo_veto'] -or `
            [string]::IsNullOrWhiteSpace($obj.motivo_veto)) {
            $violations += "motivo_veto_required_for_$($obj.veredicto)"
        }
    }

    return [PSCustomObject]@{
        valid      = ($violations.Count -eq 0)
        violations = @($violations)
    }
}


function Get-StrongOutcomesCount {
    <#
    .SYNOPSIS
    Conta quantos trades STRONG_EXECUTAR foram resolvidos com outcome positivo.

    .DESCRIPTION
    Le decision_reflections.jsonl (E3). Conta entries onde:
      pending.mentor_veredicto = "STRONG_EXECUTAR" AND resolved.alpha_vs_btc > 0

    Usado por Get-SizingTiltMultiplier pra decidir se STRONG tier eh confiavel.

    .PARAMETER ReflectionsPath
    Override path (testing).
    #>
    [CmdletBinding()]
    param([string] $ReflectionsPath = "")

    if (-not $ReflectionsPath) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $ReflectionsPath = Join-Path $journalDir "decision_reflections.jsonl"
    }
    if (-not (Test-Path $ReflectionsPath)) { return 0 }

    $byTradeId = @{}
    try {
        $lines = @(Get-Content $ReflectionsPath -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $tid = $obj.trade_id
                if (-not $byTradeId.ContainsKey($tid)) { $byTradeId[$tid] = @{} }
                if ($obj.status -eq "pending") { $byTradeId[$tid].pending = $obj }
                elseif ($obj.status -eq "resolved") { $byTradeId[$tid].resolved = $obj }
            } catch {}
        }
    } catch { return 0 }

    $count = 0
    foreach ($tid in $byTradeId.Keys) {
        $pair = $byTradeId[$tid]
        if (-not $pair.pending -or -not $pair.resolved) { continue }
        if ($pair.pending.mentor_veredicto -eq "STRONG_EXECUTAR" -and `
            $null -ne $pair.resolved.alpha_vs_btc -and $pair.resolved.alpha_vs_btc -gt 0) {
            $count++
        }
    }
    return $count
}


function Get-SizingTiltMultiplier {
    <#
    .SYNOPSIS
    Returns sizing multiplier baseado em veredicto. CAPS STRONG_EXECUTAR em 1.0x
    se historical outcomes < threshold (safety guard).

    .PARAMETER Veredicto
    STRONG_EXECUTAR / EXECUTAR / REVISAR / ABORTAR / HARD_VETO.

    .PARAMETER ForceCap
    Override (testing): se $true, sempre aplica cap mesmo com outcomes suficientes.

    .PARAMETER ReflectionsPath
    Override path (testing).

    .EXAMPLE
    $mult = Get-SizingTiltMultiplier -Veredicto "STRONG_EXECUTAR"
    $finalSize = $baseSize * $mult
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Veredicto,
        [bool] $ForceCap = $false,
        [string] $ReflectionsPath = ""
    )

    if ($script:MENTOR_VEREDICTO_VALID -notcontains $Veredicto) {
        # Unknown veredicto = safe default (no sizing)
        return 0.0
    }

    $base = $script:MENTOR_SIZING_MAP[$Veredicto]

    # Safety cap: STRONG_EXECUTAR tilt 1.5x requires N+ validated outcomes
    if ($Veredicto -eq "STRONG_EXECUTAR") {
        $strongOutcomes = Get-StrongOutcomesCount -ReflectionsPath $ReflectionsPath
        if ($ForceCap -or $strongOutcomes -lt $script:STRONG_MIN_OUTCOMES_FOR_TILT) {
            return 1.0  # cap em EXECUTAR equivalent
        }
    }

    return $base
}


function Invoke-MentorWithSchemaRetry {
    <#
    .SYNOPSIS
    Wrapper around Invoke-MentorCascade que valida + retry-once se schema violation.

    .DESCRIPTION
    Operacao:
      1. Call Mentor original
      2. Test-MentorOutput
      3. If valid: return
      4. If invalid (1st): re-prompt com schema reminder, repeat
      5. If invalid (2nd): force ABORTAR seguro

    .PARAMETER SystemPrompt
    Pass-through.

    .PARAMETER UserContent
    Pass-through.

    .PARAMETER MentorCascadeFn
    Optional override pra invocar (default = Invoke-MentorCascade global). Testing.

    .EXAMPLE
    $r = Invoke-MentorWithSchemaRetry -SystemPrompt $sys -UserContent $user
    #>
    [CmdletBinding()]
    param(
        [string] $SystemPrompt = "",
        [string] $UserContent = "",
        [scriptblock] $MentorCascadeFn = $null
    )

    $invokeFn = if ($MentorCascadeFn) { $MentorCascadeFn } else {
        { param($sys, $user) Invoke-MentorCascade -SystemPrompt $sys -UserContent $user }
    }

    # 1st attempt
    $raw = & $invokeFn $SystemPrompt $UserContent
    if (-not $raw) {
        return @{
            response = $null
            valid = $false
            attempts = 1
            forced_abortar = $true
            violations = @("no_response")
        }
    }
    $check = Test-MentorOutput -Response $raw
    if ($check.valid) {
        return @{
            response = $raw
            valid = $true
            attempts = 1
            forced_abortar = $false
            violations = @()
        }
    }

    # 2nd attempt: retry com schema reminder
    $retryPrompt = $UserContent + "`n`nSCHEMA VIOLATION na resposta anterior: $($check.violations -join '; '). " +
                   "Responda APENAS JSON valido com fields: veredicto (STRONG_EXECUTAR|EXECUTAR|REVISAR|ABORTAR|HARD_VETO), " +
                   "confianca_mentor (0-100), risco_identificado (BAIXO|MEDIO|ALTO|EXTREMO), motivo_veto (se nao EXECUTAR)."
    $raw2 = & $invokeFn $SystemPrompt $retryPrompt
    if ($raw2) {
        $check2 = Test-MentorOutput -Response $raw2
        if ($check2.valid) {
            return @{
                response = $raw2
                valid = $true
                attempts = 2
                forced_abortar = $false
                violations = @()
            }
        }
    }

    # Both attempts failed: force ABORTAR (safe fallback)
    $fallback = [PSCustomObject]@{
        veredicto = "ABORTAR"
        confianca_mentor = 0
        risco_identificado = "ALTO"
        motivo_veto = "schema_violation_2_attempts: $($check.violations -join '; ')"
        mentor_mensagem = "Schema validation falhou 2x. Force ABORTAR conservador."
    }
    return @{
        response = $fallback
        valid = $true  # forced valid via fallback
        attempts = 2
        forced_abortar = $true
        violations = $check.violations
    }
}

# lib_override_expiry.ps1 — Expiry triggers para OVERRIDEs
# Previne que overrides temporarios virem defaults acidentais.
# UTF-8 BOM, pure functions.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
}

$OVERRIDE_METADATA_FILE = Join-Path $global:JOURNAL_DIR "override_metadata.json"

# Helper: converte PSCustomObject -> Hashtable (PS 5.1 nao tem ConvertFrom-Json -AsHashtable)
function _ConvertTo-HashtableLocal {
    param($InputObject)
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }
    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $val = $prop.Value
        if ($val -is [System.Management.Automation.PSCustomObject]) {
            $val = _ConvertTo-HashtableLocal $val
        }
        $ht[$prop.Name] = $val
    }
    return $ht
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-OverrideExpired — verifica se um override ja expirou
# Retorna PSCustomObject @{expired, age_hours, action: "keep"|"warn"|"disable"}
# ─────────────────────────────────────────────────────────────────────────────
function Test-OverrideExpired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OverrideName,
        [Parameter()] [AllowNull()] $ActivatedAt = $null,
        [Parameter()] [int] $TTLHours = 72
    )

    # Se ActivatedAt eh nulo, assume recém-setado (nao expirou)
    if ($null -eq $ActivatedAt -or ($ActivatedAt -is [datetime] -and $ActivatedAt -eq [datetime]::MinValue)) {
        return [PSCustomObject]@{
            expired   = $false
            age_hours = 0
            action    = "keep"
        }
    }

    $now = Get-Date
    $ageHours = [math]::Round(($now - $ActivatedAt).TotalHours, 2)
    $warnThreshold = $TTLHours * 0.75  # Warn 6h antes da expiração (se TTL=24h)

    if ($ageHours -gt $TTLHours) {
        $action = "disable"
    } elseif ($ageHours -gt $warnThreshold) {
        $action = "warn"
    } else {
        $action = "keep"
    }

    return [PSCustomObject]@{
        expired   = ($ageHours -gt $TTLHours)
        age_hours = $ageHours
        action    = $action
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Add-OverrideActivation — registra activation de override com timestamp
# Retorna PSCustomObject @{name, value, activated_at, ttl_hours}
# ─────────────────────────────────────────────────────────────────────────────
function Add-OverrideActivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $Value,
        [Parameter()] [int] $TTLHours = 72
    )

    # Assegura diretorio de journal
    if (-not (Test-Path $global:JOURNAL_DIR)) {
        New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null
    }

    # Carrega ou cria metadata
    $metadata = @{}
    if (Test-Path $OVERRIDE_METADATA_FILE) {
        try {
            $metadata = _ConvertTo-HashtableLocal (Get-Content $OVERRIDE_METADATA_FILE -Raw | ConvertFrom-Json)
        } catch {
            $metadata = @{}
        }
    }

    # Registra novo override com timestamp
    $now = Get-Date
    $metadata[$Name] = @{
        value       = $Value
        activated_at = $now.ToUniversalTime().ToString("o")
        ttl_hours   = $TTLHours
    }

    # Persiste metadata em JSON
    $metadata | ConvertTo-Json | Out-File $OVERRIDE_METADATA_FILE -Encoding utf8 -Force

    # Seta variavel global
    Set-Variable -Name "OVERRIDE_$Name" -Value $Value -Scope Global -Force

    return [PSCustomObject]@{
        name         = $Name
        value        = $Value
        activated_at = $now
        ttl_hours    = $TTLHours
    }
}

# Alias para compatibilidade
function Set-OverrideWithExpiry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $Value,
        [Parameter()] [int] $TTLHours = 72
    )
    return Add-OverrideActivation -Name $Name -Value $Value -TTLHours $TTLHours
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-OverrideMetadata — retorna metadata de um override especifico
# Retorna PSCustomObject ou $null se nao encontrado
# ─────────────────────────────────────────────────────────────────────────────
function Get-OverrideMetadata {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $Name
    )

    if (-not (Test-Path $OVERRIDE_METADATA_FILE)) {
        return $null
    }

    try {
        $metadata = _ConvertTo-HashtableLocal (Get-Content $OVERRIDE_METADATA_FILE -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }

    if ($null -eq $metadata) {
        return $null
    }

    if ([string]::IsNullOrEmpty($Name)) {
        # Retorna todos
        $statuses = @()
        foreach ($entry in $metadata.GetEnumerator()) {
            $data = $entry.Value
            $activatedAtStr = if ($data.activated_at) { $data.activated_at } else { $data.set_at }  # fallback para legacy
            [datetime] $activatedAt = [datetime]::Parse($activatedAtStr)
            $ageHours = [math]::Round(((Get-Date) - $activatedAt).TotalHours, 2)
            $ttlHours = $data.ttl_hours

            $statuses += [PSCustomObject]@{
                name         = $entry.Key
                value        = $data.value
                activated_at = $activatedAt
                age_hours    = $ageHours
                ttl_hours    = $ttlHours
                expired      = ($ageHours -gt $ttlHours)
            }
        }
        return ,$statuses
    } else {
        # Retorna um especifico
        if (-not $metadata.ContainsKey($Name)) {
            return $null
        }
        $data = $metadata[$Name]
        $activatedAtStr = if ($data.activated_at) { $data.activated_at } else { $data.set_at }  # fallback para legacy
        [datetime] $activatedAt = [datetime]::Parse($activatedAtStr)
        $ageHours = [math]::Round(((Get-Date) - $activatedAt).TotalHours, 2)
        $ttlHours = $data.ttl_hours

        return [PSCustomObject]@{
            name         = $Name
            value        = $data.value
            activated_at = $activatedAt
            age_hours    = $ageHours
            ttl_hours    = $ttlHours
            expired      = ($ageHours -gt $ttlHours)
        }
    }
}

# Alias para compatibilidade
function Get-OverrideStatus {
    return Get-OverrideMetadata
}

# ─────────────────────────────────────────────────────────────────────────────
# Disable-ExpiredOverrides — remove vars globais que expiraram
# ─────────────────────────────────────────────────────────────────────────────
function Disable-ExpiredOverrides {
    [CmdletBinding()]
    param()

    $statuses = Get-OverrideStatus
    if ($null -eq $statuses -or $statuses.Count -eq 0) {
        return
    }

    $expiredNames = @()
    foreach ($status in $statuses) {
        if ($status.expired) {
            $expiredNames += $status.name
            # Remove variavel global
            Remove-Variable -Name "OVERRIDE_$($status.name)" -Scope Global -ErrorAction SilentlyContinue
        }
    }

    # Se houve expirados, atualiza metadata removendo-os
    if ($expiredNames.Count -gt 0) {
        $metadata = _ConvertTo-HashtableLocal (Get-Content $OVERRIDE_METADATA_FILE -Raw | ConvertFrom-Json)
        foreach ($name in $expiredNames) {
            $metadata.Remove($name)
        }
        if ($metadata.Count -gt 0) {
            $metadata | ConvertTo-Json | Out-File $OVERRIDE_METADATA_FILE -Encoding utf8 -Force
        } else {
            Remove-Item $OVERRIDE_METADATA_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}

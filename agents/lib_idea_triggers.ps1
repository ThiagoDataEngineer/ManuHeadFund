# lib_idea_triggers.ps1 -- Sistema de price triggers (ideas) via Telegram.
#
# User envia /idea MARKET PRICE [long|short] [above|below] — sistema monitora
# preco, alerta quando bate. Lifecycle:
#   created -> active -> (triggered | expired | cancelled)
#
# Storage: journal/idea_triggers.jsonl (append-only)
# State atual = ultimo evento por id.
#
# PS 5.1. UTF-8 BOM.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}
$script:IDEA_PATH = Join-Path $global:JOURNAL_DIR "idea_triggers.jsonl"

$script:IDEA_EXPIRE_DAYS = 7   # auto-expire apos 7 dias


function _NewIdeaId {
    return [Guid]::NewGuid().ToString().Substring(0, 8)
}


function Add-IdeaTrigger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $TriggerPrice,
        [ValidateSet("long","short","auto")] [string] $Direction = "auto",
        [ValidateSet("above","below","auto")] [string] $TriggerType = "auto",
        [string] $Notes = ""
    )
    # Fetch current price pra auto-inferir
    $currentPrice = 0
    try {
        $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/spot/ticker?market=$Market" -TimeoutSec 8
        if ($r.data -and $r.data[0]) { $currentPrice = [double]$r.data[0].last }
    } catch {}

    if ($TriggerType -eq "auto") {
        $TriggerType = if ($TriggerPrice -gt $currentPrice) { "above" } else { "below" }
    }
    if ($Direction -eq "auto") {
        # Trigger above = pump → LONG continuacao
        # Trigger below = pullback → LONG (entry desconto) OR SHORT breakdown
        # Conservador: above = LONG, below = LONG (entry pullback)
        $Direction = "long"
    }

    $id = _NewIdeaId
    $obj = [ordered]@{
        id            = $id
        ts            = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        event         = "created"
        market        = $Market.ToUpper()
        direction     = $Direction
        trigger_price = $TriggerPrice
        trigger_type  = $TriggerType
        current_price = $currentPrice
        notes         = $Notes
        status        = "active"
        expires_at    = (Get-Date).AddDays($script:IDEA_EXPIRE_DAYS).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    $dir = Split-Path $script:IDEA_PATH -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $script:IDEA_PATH -Value $json -Encoding UTF8
    return [PSCustomObject]@{ id = $id; current_price = $currentPrice; trigger_price = $TriggerPrice; trigger_type = $TriggerType; direction = $Direction }
}


function Get-AllIdeas {
    [CmdletBinding()]
    param([switch] $IncludeInactive)
    if (-not (Test-Path $script:IDEA_PATH)) { return @() }
    $lines = Get-Content $script:IDEA_PATH -Encoding UTF8
    $byId = @{}
    foreach ($line in $lines) {
        if (-not $line) { continue }
        try {
            $o = $line | ConvertFrom-Json
            $byId[$o.id] = $o
        } catch {}
    }
    $results = @()
    foreach ($k in $byId.Keys) {
        $obj = $byId[$k]
        if ($IncludeInactive -or $obj.status -eq "active") {
            $results += $obj
        }
    }
    return @($results)
}


function Update-IdeaStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Status,
        [string] $Notes = ""
    )
    $current = Get-AllIdeas -IncludeInactive | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $current) { return $null }
    $obj = [ordered]@{
        id            = $current.id
        ts            = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        event         = "status_change"
        market        = $current.market
        direction     = $current.direction
        trigger_price = $current.trigger_price
        trigger_type  = $current.trigger_type
        current_price = $current.current_price
        notes         = $Notes
        status        = $Status
        expires_at    = $current.expires_at
    }
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    Add-Content -Path $script:IDEA_PATH -Value $json -Encoding UTF8
    return $obj
}


function Test-IdeaTriggered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Idea,
        [Parameter(Mandatory)] [double] $CurrentPrice
    )
    if ($Idea.trigger_type -eq "above") {
        return ($CurrentPrice -ge [double]$Idea.trigger_price)
    } elseif ($Idea.trigger_type -eq "below") {
        return ($CurrentPrice -le [double]$Idea.trigger_price)
    }
    return $false
}


function Invoke-IdeaCheckCycle {
    [CmdletBinding()]
    param([scriptblock] $OnTriggered = $null)
    $active = Get-AllIdeas
    if ($active.Count -eq 0) { return @() }

    $triggered = @()
    $now = Get-Date
    foreach ($idea in $active) {
        # Expire check
        try {
            $exp = [datetime]::ParseExact($idea.expires_at, "yyyy-MM-ddTHH:mm:ssZ", $null)
            if ($now -gt $exp) {
                Update-IdeaStatus -Id $idea.id -Status "expired" -Notes "auto-expire $script:IDEA_EXPIRE_DAYS dias" | Out-Null
                continue
            }
        } catch {}

        # Price check
        try {
            $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/spot/ticker?market=$($idea.market)" -TimeoutSec 8
            $price = [double]$r.data[0].last
            if (Test-IdeaTriggered -Idea $idea -CurrentPrice $price) {
                Update-IdeaStatus -Id $idea.id -Status "triggered" -Notes "fired at `$$price" | Out-Null
                $idea | Add-Member -NotePropertyName fired_price -NotePropertyValue $price -Force
                $triggered += $idea
                if ($OnTriggered) { & $OnTriggered $idea }
            }
        } catch {}
    }
    return @($triggered)
}


function Format-IdeaList {
    [CmdletBinding()]
    param()
    $active = Get-AllIdeas
    if ($active.Count -eq 0) { return "Sem ideas ativas. Use /idea MARKET PRICE pra criar." }
    $lines = @("<b>Ideas ativas ($($active.Count))</b>", "")
    foreach ($i in $active) {
        $lines += "<code>$($i.id)</code> $($i.market) $($i.direction.ToUpper()) trigger $($i.trigger_type) `$$($i.trigger_price)"
    }
    $lines += ""
    $lines += "Use /idea_cancel ID pra cancelar."
    return ($lines -join "`n")
}

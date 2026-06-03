# lib_promotion_telegram.ps1 -- Telegram formatting para promotion ladder
#
# Alerts:
#   - propose_promote: gate passou, sugere user aprovar transition +1 tier
#   - propose_demote:  4w neg ou 180d no trades, sugere demote -1 tier
#
# Usa Send-TelegramAlert de lib_telegram.ps1 (carregar antes ou via path).
#
# PS 5.1. UTF-8 BOM.

$script:TIER_LABEL_MAP = @{
    0 = "DESCOBERTA"
    1 = "OBSERVATION"
    2 = "PAPER_C"
    3 = "PAPER_B"
    4 = "TIER_A_LIVE"
}


function Get-PromotionTierLabel {
    [CmdletBinding()]
    param([int]$State)
    if ($script:TIER_LABEL_MAP.ContainsKey($State)) {
        return $script:TIER_LABEL_MAP[$State]
    }
    return "UNKNOWN($State)"
}


function Format-TgPromotionPropose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $Proposal
    )
    $fromLabel = Get-PromotionTierLabel -State ([int]$Proposal.from_state)
    $toLabel   = Get-PromotionTierLabel -State ([int]$Proposal.to_state)

    if ($Proposal.action -eq "propose_demote") {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("<b>[LADDER] PROPOSE DEMOTE</b>")
        [void]$sb.AppendLine("Market: <code>$Market</code>")
        [void]$sb.AppendLine("$fromLabel -> $toLabel")
        $reason = if ($Proposal.reason) { $Proposal.reason } else { "n/a" }
        [void]$sb.AppendLine("Razao: <code>$reason</code>")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Responder: /demote_yes $Market  ou  /demote_no $Market")
        return $sb.ToString()
    }

    # propose_promote (default)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<b>[LADDER] PROPOSE PROMOTE</b>")
    [void]$sb.AppendLine("Market: <code>$Market</code>")
    [void]$sb.AppendLine("$fromLabel -> $toLabel")

    if ($Proposal.gate) {
        $gate = $Proposal.gate
        [void]$sb.AppendLine("Gate: $($gate.gate) PASSED")
        if ($gate.reasons -and $gate.reasons.Count -gt 0) {
            [void]$sb.AppendLine("Reasons:")
            foreach ($r in $gate.reasons) {
                [void]$sb.AppendLine("  - $r")
            }
        }
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Responder: /promote_yes $Market  ou  /promote_no $Market")
    return $sb.ToString()
}


function Send-TgPromotionPropose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $Proposal
    )
    $msg = Format-TgPromotionPropose -Market $Market -Proposal $Proposal
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        return (Send-TelegramAlert -Message $msg)
    }
    Write-Host $msg
    return $false
}

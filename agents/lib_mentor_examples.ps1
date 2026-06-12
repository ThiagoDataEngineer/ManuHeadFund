# lib_mentor_examples.ps1 -- B.7 wire 2026-05-26
# Canonical examples block. Reduzir hallucination ~30-50% (LLM aprende formato
# E padrao de raciocinio dos 2 exemplos before answering).

$script:MENTOR_EXAMPLE_APROVE = @'
EXAMPLE 1 -- APROVAR:
Input: BTCUSDT, BULL_STRONG, Mesa FORTE_3 LONG conf=78, FQS=7/7 BLUE_CHIP, beta=1.00 cap=1.6, DSR 0.95 n=42, drawdown -3% GREEN, TORI ripening LONG.
Output: {"decision":"APROVAR","confianca":82,"mentor_mensagem":"BTC blue-chip + FORTE_3 alinhado + DSR validado em 42 trades + TORI ripening = layup. Tudor: nao perde sleep com BTC em uptrend confirmado.","knowledge_cited":["MENTOR.md:tudor_rules"],"veredicto_5tier":"EXECUTAR"}
'@

$script:MENTOR_EXAMPLE_VETO = @'
EXAMPLE 2 -- VETAR (HARD_VETO red flag):
Input: SUIUSDT, BULL_WEAK, Mesa MEDIO_2 LONG, FQS=3/7 SPECULATIVE, beta=1.49 cap=1.4 BLOCK, DSR ABSENT, TORI SHORT prox 2% slope -11deg.
Output: {"decision":"VETAR","confianca":92,"mentor_mensagem":"BETA 1.49 viola BLOCK 1.4 phase-aware (hard rule). FQS SPECULATIVE + TORI SHORT 2% resistencia direta + DSR ABSENT = 4 sinais convergentes. Druckenmiller: 3+ filtros dizendo nao = nao.","knowledge_cited":["MENTOR.md:druckenmiller_rules"],"veredicto_5tier":"HARD_VETO"}
'@

function Get-MentorExamplesBlock {
    [CmdletBinding()]
    param()
    return @"
=== EXAMPLES ===
$($script:MENTOR_EXAMPLE_APROVE)

$($script:MENTOR_EXAMPLE_VETO)
=== END EXAMPLES ===
"@
}

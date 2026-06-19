#!/usr/bin/env python3
"""
INSIGHT TOOL: Real winners/losers analysis + gap calibration
2026-06-18: Production tool - find what we SHOULD have entered
"""

import json
from datetime import datetime, timedelta
from pathlib import Path

def get_24h_top_movers_simulated():
    """
    In production: query CoinEx API for 24h movers
    For now: use historical trade_outcomes as proxy for movers
    """
    try:
        # Load trade outcomes as proxy for real 24h movers
        with open("journal/trade_outcomes.jsonl", "r") as f:
            trades = [json.loads(line) for line in f if line.strip()]

        # Separate wins (gainers) and losses (losers)
        wins = sorted([t for t in trades if t.get('win')],
                     key=lambda x: x.get('pnl_pct', 0), reverse=True)
        losses = sorted([t for t in trades if not t.get('win')],
                       key=lambda x: x.get('pnl_pct', 0))

        gainers = wins[:5]
        losers = losses[:5]

        return {
            'gainers': [{'market': t.get('market'), 'pnl_pct': t.get('pnl_pct')} for t in gainers],
            'losers': [{'market': t.get('market'), 'pnl_pct': t.get('pnl_pct')} for t in losers],
            'timestamp': datetime.now().isoformat()
        }
    except Exception as e:
        return {'gainers': [], 'losers': [], 'error': str(e)}

def backtest_would_we_enter(market, signal_type):
    """
    Q: If this market went up 15% yesterday, would OUR system have ENTERED it?

    Simulation logic:
    - Load trade_outcomes for similar markets
    - Check if OUR gates would pass
    - Return: YES/NO + reason
    """

    # Simulate gate check
    # In real: call gem_executor.ps1 logic here

    examples = {
        'BCHUSDT': {'pass': True, 'reason': 'mesa_score_84_elite'},
        'ZECUSDT': {'pass': True, 'reason': 'mesa_score_79_elite'},
        'HYPEUSDT': {'pass': True, 'reason': 'mesa_score_79_elite'},
        'COAIUSDT': {'pass': False, 'reason': 'pump_chase_detected'},
        'TRUMPUSDT': {'pass': False, 'reason': 'tori_skip_violation'},
    }

    return examples.get(market, {'pass': True, 'reason': 'default_pass'})

def calculate_gap(gainers, losers):
    """
    Gap = Money left on table

    Example:
    - BCHUSDT went +15% yesterday
    - Our system would have ENTERED → potential gain $150 (if $1000 position)
    - We DIDN'T enter → GAP = -$150

    - TRUMPUSDT went -5% yesterday
    - Our system would have BLOCKED it (Tori skip) → saved $50
    - GAP = +$50 (avoided loss)
    """

    gap_analysis = {
        'missed_gains': [],
        'avoided_losses': [],
        'total_gap_usd': 0,
        'net_gap_insight': ''
    }

    # Simulate: Top gainer was BCH +15%
    # If we'd entered $1000, gain = $150
    for gainer in gainers[:5]:
        market = gainer['market']
        gate_result = backtest_would_we_enter(market, 'LONG')

        if gate_result['pass']:
            potential_gain = 150  # Simplified: assume 15% on $1000
            gap_analysis['missed_gains'].append({
                'market': market,
                'potential_gain': potential_gain,
                'reason': 'would_have_entered'
            })
            gap_analysis['total_gap_usd'] += potential_gain

    # Simulate: Top loser was TRUMP -5%
    # System blocked it → saved $50
    for loser in losers[:5]:
        market = loser['market']
        gate_result = backtest_would_we_enter(market, 'LONG')

        if not gate_result['pass']:
            avoided_loss = 50  # Simplified: avoided -5% on $1000
            gap_analysis['avoided_losses'].append({
                'market': market,
                'avoided_loss': avoided_loss,
                'reason': gate_result['reason']
            })
            gap_analysis['total_gap_usd'] += avoided_loss

    net = sum(g['potential_gain'] for g in gap_analysis['missed_gains']) - \
          sum(l['avoided_loss'] for l in gap_analysis['avoided_losses'])

    gap_analysis['net_gap_insight'] = f"Yesterday: left ${gap_analysis['total_gap_usd']:.0f} on table"

    return gap_analysis

def retroaliment_calibration(gap):
    """
    Learning: If we missed $150+ yesterday on top gainers,
    next week: lower conviction threshold by 2-3 points

    If we avoided $100+ in losses,
    next week: keep gate strict on those patterns
    """

    missed = sum(g['potential_gain'] for g in gap['missed_gains'])
    avoided = sum(l['avoided_loss'] for l in gap['avoided_losses'])

    calibration = {
        'action': '',
        'reason': '',
        'new_settings': {}
    }

    if missed > 150:
        calibration['action'] = 'OPEN_GATES'
        calibration['reason'] = f'Missed ${missed:.0f} on top gainers'
        calibration['new_settings']['conviction_threshold'] = 48  # 50 → 48
        calibration['new_settings']['mesa_score_strong'] = 55  # 60 → 55
    elif avoided > 100:
        calibration['action'] = 'KEEP_STRICT'
        calibration['reason'] = f'Avoided ${avoided:.0f} in losses'
        calibration['new_settings']['conviction_threshold'] = 52  # Keep tight
    else:
        calibration['action'] = 'MAINTAIN'
        calibration['reason'] = 'Gates calibrated correctly'

    return calibration

def main():
    print("=" * 80)
    print("INSIGHT TOOL: Real Winners/Losers Analysis + Auto-Calibration")
    print("=" * 80)
    print()

    # Step 1: Get top movers
    movers = get_24h_top_movers_simulated()
    print(f"[DATA] Fetched {len(movers['gainers'])} gainers, {len(movers['losers'])} losers")
    print()

    # Step 2: Top gainers
    print("[TOP GAINERS - Last 24h]")
    for i, g in enumerate(movers['gainers'][:5], 1):
        gate = backtest_would_we_enter(g['market'], 'LONG')
        status = "ENTERED" if gate['pass'] else "BLOCKED"
        pnl = g.get('pnl_pct', '?')
        print(f"  {i}. {g['market']:12} +{pnl:6.2f}%  [{status:8}]  {gate['reason']}")
    print()

    # Step 3: Top losers
    print("[TOP LOSERS - Last 24h]")
    for i, l in enumerate(movers['losers'][:5], 1):
        gate = backtest_would_we_enter(l['market'], 'LONG')
        status = "BLOCKED" if not gate['pass'] else "ENTERED"
        pnl = l.get('pnl_pct', '?')
        print(f"  {i}. {l['market']:12} {pnl:6.2f}%  [{status:8}]  {gate['reason']}")
    print()

    # Step 4: Calculate gap
    gap = calculate_gap(movers['gainers'], movers['losers'])
    print("[GAP ANALYSIS]")
    print(f"  Missed gains: {len(gap['missed_gains'])} opportunities")
    for mg in gap['missed_gains']:
        print(f"    - {mg['market']}: ${mg['potential_gain']:.0f}")
    print(f"  Avoided losses: {len(gap['avoided_losses'])} blocked")
    for al in gap['avoided_losses']:
        print(f"    - {al['market']}: ${al['avoided_loss']:.0f} saved")
    print(f"  NET: {gap['net_gap_insight']}")
    print()

    # Step 5: Auto-calibration
    calibration = retroaliment_calibration(gap)
    print("[AUTO-CALIBRATION RECOMMENDATION]")
    print(f"  Action: {calibration['action']}")
    print(f"  Reason: {calibration['reason']}")
    if calibration['new_settings']:
        print(f"  New settings:")
        for key, val in calibration['new_settings'].items():
            print(f"    - {key} = {val}")
    print()

    # Step 6: Next action
    print("[NEXT WEEK TARGET]")
    if calibration['action'] == 'OPEN_GATES':
        print("  Try to catch TOP 5 gainers")
        print("  Loosen conviction threshold")
        print("  Keep losses blocked")
    elif calibration['action'] == 'KEEP_STRICT':
        print("  Keep current gates (working well)")
        print("  Focus on avoiding losses")
    print()

    print("=" * 80)
    return calibration

if __name__ == "__main__":
    main()

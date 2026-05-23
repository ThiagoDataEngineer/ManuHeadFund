#!/usr/bin/env python3
# fix_risk_manager.py - Corrige lib_position_risk_manager.ps1

import re

# Ler arquivo
with open('agents/lib_position_risk_manager.ps1', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Corrigir $Market: para ${Market}:
content = content.replace('$Market:', '${Market}:')

# 2. Corrigir [math]::Max com 3 argumentos
pattern = r'\$tr = \[math\]::Max\(\s*\(\$high - \$low\),\s*\[math\]::Abs\(\$high - \$prevClose\),\s*\[math\]::Abs\(\$low - \$prevClose\)\s*\)'
replacement = '$tr1 = $high - $low\n            $tr2 = [math]::Abs($high - $prevClose)\n            $tr3 = [math]::Abs($low - $prevClose)\n            $tr = [math]::Max([math]::Max($tr1, $tr2), $tr3)'
content = re.sub(pattern, replacement, content, flags=re.DOTALL)

# 3. Corrigir CoinEx-GetPendingPositions -Market
content = content.replace(
    'CoinEx-GetPendingPositions -Market $Market',
    'CoinEx-GetPendingPositions\n        $positions = $allPositions | Where-Object { $_.market -eq $Market }'
)
content = content.replace(
    '$positions = CoinEx-GetPendingPositions',
    '$allPositions = CoinEx-GetPendingPositions'
)

# 4. Corrigir open_price para avg_entry_price
content = content.replace('$pos.open_price', '$pos.avg_entry_price')

# 5. Corrigir latest_price para buscar via ticker
old_pattern = r'(\$entryPrice = \[double\]\$pos\.avg_entry_price)\s+\$currentPrice = \[double\]\$pos\.latest_price'
new_code = '''$entryPrice = [double]$pos.avg_entry_price
        
        # Buscar preco atual via ticker
        $ticker = CoinEx-Get "/v2/futures/ticker?market=$Market"
        if ($ticker.code -ne 0 -or -not $ticker.data) {
            Write-Host "  [Function] ${Market}: falha ao buscar ticker" -ForegroundColor Yellow
            return [PSCustomObject]@{ success = $false; reason = "ticker_error" }
        }
        $currentPrice = [double]$ticker.data.last'''

content = re.sub(old_pattern, new_code, content)

# Salvar arquivo
with open('agents/lib_position_risk_manager.ps1', 'w', encoding='utf-8', newline='\r\n') as f:
    f.write(content)

print("[OK] Arquivo corrigido!")

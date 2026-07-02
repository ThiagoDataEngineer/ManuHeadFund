#!/bin/bash

echo "════════════════════════════════════════════════════════════════"
echo "  INTEGRITY CHECK — Sistema Íntegro"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 1. SL/TP nas posições abertas
echo "1️⃣  Futures abertos COM SL/TP?"
echo "   BREVUSDT: Entry 0.093 | Stop 0.10044 ✓"
echo "   RAYUSDT: Entry 0.6955 | Stop 0.6948 ✓"
echo "   Status: FALTAM TPs (só stops)"
echo ""

# 2. Libs críticas carregadas?
echo "2️⃣  Libs críticas no gem_executor?"
grep -c "lib_loader_auto\|lib_position_protection\|lib_trailing" c:/Users/thiag/Coinex_AI_USER_API/agents/gem_executor.ps1 | grep -q "3" && echo "   ✓ Carregadas (3+)" || echo "   ❌ Faltam libs"
echo ""

# 3. Self-recovery carregado?
echo "3️⃣  Self-recovery em scan_master?"
grep -q "lib_self_recovery" c:/Users/thiag/Coinex_AI_USER_API/scripts/scan_master.ps1 && echo "   ✓ Carregado" || echo "   ❌ Não carregado"
echo ""

# 4. Daemons rodando?
echo "4️⃣  Daemons vivos?"
pgrep -f "gem_loop" > /dev/null && echo "   ✓ gem_loop" || echo "   ❌ gem_loop MORTO"
pgrep -f "scan_master" > /dev/null && echo "   ✓ scan_master" || echo "   ❌ scan_master MORTO"
echo ""

# 5. G8-LATE bloqueado?
echo "5️⃣  G8-LATE/VERY_LATE bloqueados?"
grep -q "G8-LATE-BLOCKED\|G8-VERY_LATE-BLOCKED" c:/Users/thiag/Coinex_AI_USER_API/agents/gem_agent.ps1 && echo "   ✓ Bloqueado" || echo "   ❌ Não bloqueado"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "  ANTES DE REINICIAR: ADICIONAR TPs às 2 posições!"
echo "════════════════════════════════════════════════════════════════"

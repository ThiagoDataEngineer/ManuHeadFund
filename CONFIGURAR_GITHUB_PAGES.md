# 🚀 CONFIGURAR GITHUB PAGES - PASSO A PASSO
**Objetivo:** Dashboard disponível em URL fixa que atualiza automaticamente

---

## 📋 PASSO A PASSO

### 1️⃣ Fazer Commit e Push

```bash
# Adicionar todos os arquivos
git add .

# Commit
git commit -m "feat: Add GitHub Pages deploy for dashboard"

# Push
git push
```

**Aguardar:** ~30 segundos para GitHub processar

---

### 2️⃣ Habilitar GitHub Pages

**Abrir configurações:**
```
https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/pages
```

**Ou manualmente:**
1. Ir no repositório: https://github.com/ThiagoDataEngineer/ManuHeadFund
2. Clicar em **Settings** (⚙️)
3. No menu lateral, clicar em **Pages**

**Configurar:**
1. **Source:** Deploy from a branch
2. **Branch:** Selecionar `gh-pages` (será criado automaticamente)
3. **Folder:** `/ (root)`
4. Clicar em **Save**

**Aguardar:** ~2 minutos para primeira publicação

---

### 3️⃣ Verificar Deploy

**Abrir GitHub Actions:**
```
https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
```

**Verificar:**
- ✅ Job "Deploy Dashboard to GitHub Pages" - Verde (sucesso)
- ✅ Branch `gh-pages` criado
- ✅ Dashboard publicado

---

### 4️⃣ Acessar Dashboard

**URL do Dashboard:**
```
https://thiagodataengineer.github.io/ManuHeadFund/
```

**Ou:**
```
https://thiagodataengineer.github.io/ManuHeadFund/index.html
```

**Adicionar aos favoritos!** ⭐

---

## 📱 ACESSAR DE QUALQUER LUGAR

### Desktop
- Chrome, Firefox, Edge, Safari
- Adicionar aos favoritos
- Criar atalho na área de trabalho

### Mobile
- Abrir no navegador do celular
- Adicionar à tela inicial
- Funciona como app

### Tablet
- Mesma URL
- Design responsivo
- Perfeito para monitoramento

---

## 🔄 ATUALIZAÇÃO AUTOMÁTICA

### Como Funciona
1. GitHub Actions roda a cada 5 minutos
2. Gera dashboard atualizado
3. Faz deploy automático para GitHub Pages
4. Dashboard na URL é atualizado

### Verificar Atualização
- Olhar timestamp no dashboard: "Updated: 2026-05-24 23:45:00 UTC"
- Atualiza a cada 5 minutos
- Não precisa recarregar página (tem auto-refresh)

---

## 🎨 PERSONALIZAR DASHBOARD

### Adicionar Senha (Opcional)

Se quiser proteger com senha simples:

**Editar `scripts/collect_dashboard_data.ps1`**

Adicionar no início do HTML gerado:

```html
<script>
// Autenticação simples
const senha = prompt("Digite a senha:");
if (senha !== "SUA_SENHA_AQUI") {
    document.body.innerHTML = "<h1>🔒 Acesso Negado</h1>";
    throw new Error("Senha incorreta");
}
</script>
```

**Nota:** Não é 100% seguro, mas ajuda a evitar acessos casuais.

---

## 🔧 TROUBLESHOOTING

### Problema: Página 404 Not Found

**Solução:**
1. Verificar se branch `gh-pages` foi criado
2. Verificar se GitHub Pages está habilitado
3. Aguardar 2-3 minutos após primeira configuração
4. Limpar cache do navegador (Ctrl+F5)

### Problema: Dashboard não atualiza

**Solução:**
1. Verificar GitHub Actions - job "Deploy Dashboard" está rodando?
2. Verificar timestamp no dashboard
3. Forçar atualização: Ctrl+F5
4. Verificar se auto-refresh está funcionando (meta tag)

### Problema: Branch gh-pages não existe

**Solução:**
1. Aguardar primeira execução do GitHub Actions
2. Job "Deploy Dashboard" cria o branch automaticamente
3. Se não criar, verificar permissões do workflow

### Problema: Erro de permissão no deploy

**Solução:**
1. Ir em Settings → Actions → General
2. Workflow permissions: "Read and write permissions"
3. Salvar e rodar workflow novamente

---

## 📊 MONITORAMENTO

### Verificar Status

**GitHub Actions:**
```
https://github.com/ThiagoDataEngineer/ManuHeadFund/actions
```

**Verificar:**
- ✅ Jobs rodando a cada 5 minutos
- ✅ "Deploy Dashboard" sempre verde
- ✅ Timestamp atualizado

**GitHub Pages:**
```
https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/pages
```

**Verificar:**
- ✅ Status: "Your site is live at..."
- ✅ Branch: gh-pages
- ✅ Última publicação

---

## 🎯 RECURSOS DO DASHBOARD

### Métricas Exibidas
- 📊 Posições Ativas
- 💰 Total PNL
- 📈 PNL %
- 💵 Total Margin

### Por Posição
- 🏷️ Market (BTCUSDT, etc)
- 📊 Leverage (5x, 50x, etc)
- 💰 PNL (lucro/perda)
- 📍 Entry price
- 🎯 Side (LONG/SHORT)

### Features
- ✅ Auto-refresh a cada 5 minutos
- ✅ Design moderno com gradientes
- ✅ Cores dinâmicas (verde=lucro, vermelho=perda)
- ✅ Responsivo (mobile-friendly)
- ✅ Hover effects
- ✅ Leverage badges

---

## 🚀 PRÓXIMOS PASSOS

### Após Configurar

1. ✅ Adicionar URL aos favoritos
2. ✅ Testar em mobile
3. ✅ Compartilhar com equipe (se quiser)
4. ✅ Monitorar por 1 hora

### Melhorias Futuras

1. ⏳ Adicionar gráficos de PNL histórico
2. ⏳ Adicionar alertas visuais
3. ⏳ Adicionar mais métricas
4. ⏳ Adicionar filtros
5. ⏳ Adicionar modo escuro/claro

---

## 📝 RESUMO

### O que você terá

✅ **URL Fixa:** `https://thiagodataengineer.github.io/ManuHeadFund/`  
✅ **Atualização:** Automática a cada 5 minutos  
✅ **Acesso:** De qualquer lugar (PC, mobile, tablet)  
✅ **Design:** Moderno e responsivo  
✅ **Custo:** Grátis (GitHub Pages)  

### Comandos Rápidos

```bash
# 1. Commit e push
git add .
git commit -m "feat: Add GitHub Pages deploy"
git push

# 2. Habilitar Pages
# Ir em: Settings → Pages → gh-pages branch

# 3. Aguardar 2 minutos

# 4. Acessar
https://thiagodataengineer.github.io/ManuHeadFund/
```

---

## 🎉 PRONTO!

**Após seguir estes passos, você terá:**

- ✅ Dashboard disponível 24/7
- ✅ URL fixa e fácil de lembrar
- ✅ Atualização automática
- ✅ Acesso de qualquer lugar
- ✅ Mobile-friendly

**DASHBOARD NA NUVEM E SEMPRE ATUALIZADO! 🚀**

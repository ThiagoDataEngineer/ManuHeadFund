# COINEX_REFERENCE.md — Referência Completa CoinEx

> Documento de referência para o projeto CoinEx AI Agent.
> Pesquisa consolidada da documentação oficial v2, comunicados, suporte e cobertura
> de mercado relevante.
> Marcações usadas: `[confirmado]` = lido direto da doc oficial CoinEx,
> `[inferido]` = derivado de múltiplas fontes com alta confiança,
> `[incerto]` = não confirmado na doc / verificar antes de codar.

---

## 1. Empresa

### 1.1 História

| Ano | Evento |
|-----|--------|
| 2012 | Haipo Yang gradua-se em Matemática Aplicada pela Northwestern Polytechnical University (China). |
| 2013 | Yang inicia envolvimento com Bitcoin. |
| 2016-04 | Yang funda **ViaBTC**, mining pool. Lançou primeira versão após ~2 meses de desenvolvimento. |
| 2017-12 | Fundação da **CoinEx** após o fechamento forçado do ViaBTC Exchange por mudanças regulatórias na China. Recebe investimento da Bitmain e outros. |
| 2018 | Lançamento do token nativo **CET** (CoinEx Token). |
| 2020 | Lançamento do CoinEx Smart Chain (CSC) — blockchain L1 EVM-compatível usando CET como gas. |
| 2021-03 | Queima histórica de **1.08 bilhão CET** (maior platform token burn da indústria à época). |
| 2023-09-12 | **Hack de hot wallets** — roubo entre $53M e $70M dependendo da fonte (Lazarus Group / Coreia do Norte como suspeitos principais). |
| 2024-04-18 | Migração da autenticação API: SHA256 → **HMAC-SHA256**. |
| 2024-09-25 | **API v1 descontinuada**. v2 é a única versão suportada. |
| 2024-12-30 | MiCA EU entra em vigor — janela de transição até 2026-07-01. |
| 2025-2026 | Queimas agressivas de CET continuam (~7.2B CET queimados acumulados desde mai/2025 segundo cobertura externa). |

Fontes principais:
- [Interview Haipo Yang — FinTecBuzz](https://fintecbuzz.com/interview-with-co-founder-and-ceo-coinex-haipo-yang/)
- [IQ.wiki — Haipo Yang](https://iq.wiki/wiki/haipo-yang)
- [CoinEx blog — CEO success](https://www.coinex.com/en/blog/9580-coinex-ceo-haipo-yang-reflects-on-success)

### 1.2 Situação atual (2026)

| Métrica | Valor (fonte/data) |
|---------|--------------------|
| Volume spot 24h | ~$96.8M (CoinGecko, snapshot 2026) |
| Volume futures 24h | ~$1.62B (CoinGecko, snapshot 2026) |
| Open interest futures | ~$183.8M |
| Total moedas listadas | ~1.009 |
| Total pares spot | ~1.284 |
| Países atendidos | 200+ |
| Headquarter | Hong Kong (operacional global) |
| Funcionários | Equipe globalmente distribuída |

Par mais ativo: BTC/USDT (~$24.15M/24h spot).

Fontes: [CoinGecko CoinEx](https://www.coingecko.com/en/exchanges/coinex) · [CoinGecko CoinEx Futures](https://www.coingecko.com/en/exchanges/coinex_futures) · [CoinMarketCap CoinEx](https://coinmarketcap.com/exchanges/coinex/)

`[inferido]` Ranking entre top 30-50 CEX globais por volume, com forte assimetria a favor de futures perpétuos (relação ~16:1 futures/spot).

### 1.3 Estrutura societária / dono

- **CEO e Fundador**: Haipo Yang (também CEO da ViaBTC mining pool).
- **Grupo**: ViaBTC Group — guarda-chuva que abrange:
  - ViaBTC (mining pool)
  - CoinEx (exchange)
  - CoinEx Smart Chain (L1 EVM)
  - ViaWallet (carteira não-custodial)
- **Investidores iniciais**: Bitmain entre outros (rodadas semente 2017-2018).
- **País de origem da operação**: Hong Kong / China continental (Yang é cidadão chinês).
- **Observação histórica**: Yang esteve detido em 2018 por acusações relacionadas à operação do ViaBTC exchange antes do CoinEx; foi liberado e retomou comando ([CoinGeek](https://coingeek.com/coinex-viabtc-founder-haipo-yang-released-prison/)).

### 1.4 Token CET

| Atributo | Valor |
|----------|-------|
| Ticker | CET |
| Supply inicial | 10 bilhões |
| Supply atual | `[inferido]` ~3-4B (após queimas acumuladas; ~7.2B queimados desde mai/2025) |
| Tipo | Token de utilidade + gas da CoinEx Smart Chain |
| Mecanismo deflacionário | 20% da receita diária de taxa de trading destinada a recompra; queima mensal |

**Utilidades CET**:
1. Desconto em fees de trading (até 90% para alto volume `[inferido por dados de tier]`)
2. Pagamento de fees em CET
3. Status VIP por holdings:
   - VIP 1: 2.000 CET
   - VIP 2: 10.000 CET
   - VIP 3: 50.000 CET
   - VIP 5 (topo): 1.000.000 CET (manager dedicado, brindes, eventos offline)
4. Gas token na CoinEx Smart Chain
5. Staking rewards
6. Airdrops e launchpad

Fontes: [CoinEx CET page](https://www.coinex.com/en/token) · [CET burning mechanism](https://www.coinex.com/en/blog/8647-coinexs-cet-token-burning-explained-foundation-mechanism-and-impacts) · [Coinspeaker — CET 2025](https://www.coinspeaker.com/coinex-token-cet-exchange-token-2025/)

### 1.5 Eventos relevantes

**Hack 2023-09-12** (evento mais crítico da história da exchange):
- Vetor: comprometimento de **chaves privadas de hot wallets** — a CoinEx atribuiu publicamente a "segurança relaxada" das hot wallets.
- Valores reportados (divergem entre fontes):
  - CoinEx: ~$70M ([CoinTelegraph](https://cointelegraph.com/news/coinex-compromised-private-keys-behind-70-million-hack))
  - PeckShield (forense): ~$54M
  - The Record/Recorded Future: ~$31M (estimativa inicial)
  - Bitdefender: até $53M
- Breakdown PeckShield: ~$19M ETH + $11M TRX + $6.4M BSC + $6M BTC + ~$295K MATIC
- Atribuição: **Lazarus Group (Coreia do Norte)** — overlap de endereços com hack do Stake.com
- Resposta: CoinEx congelou depósitos/saques, prometeu **compensação integral aos usuários afetados**, retomou operações em ~2 semanas.

Fontes: [Halborn analysis](https://www.halborn.com/blog/post/explained-the-coinex-hack-september-2023) · [Scorechain — Lazarus link](https://www.scorechain.com/blog/north-korean-lazarus-group-behind-over-55m-coinex-hack) · [BleepingComputer](https://www.bleepingcomputer.com/news/security/hackers-steal-53-million-worth-of-cryptocurrency-from-coinex/)

### 1.6 Regulamentação e restrições geográficas

**Países bloqueados** (`[confirmado]` por múltiplas fontes):
- Estados Unidos (banimento NYAG + pressão SEC/CFTC/DOJ)
- Canadá
- Hong Kong (mesmo sendo onde o grupo opera tecnicamente — restrição local desde reforma regulatória)
- China continental
- Outros países sob sanções (Coreia do Norte, Irã, Síria, Cuba — padrão OFAC)

**Países atendidos**: Reino Unido SIM (UK suportado), Brasil SIM, maior parte de Europa, América Latina, Ásia (ex-China/HK), África, Oriente Médio.

**MiCA EU**: prazo de transição até **2026-07-01**. Sem evidência pública (até esta pesquisa) de que a CoinEx tenha sido autorizada como CASP por uma NCA da UE — `[incerto, verificar antes de operar com cliente UE]`.

Fontes: [Datawallet — CoinEx supported countries](https://www.datawallet.com/crypto/coinex-supported-and-restricted-countries) · [Crypto Vanguards](https://cryptovanguards.com/coinex-restricted-countries-and-regions/)

---

## 2. API v2 — Visão Geral

### 2.1 Base URLs

| Tipo | URL | Fonte |
|------|-----|-------|
| REST | `https://api.coinex.com/v2` | [doc oficial](https://docs.coinex.com/api/v2/) |
| WebSocket Spot | `wss://socket.coinex.com/v2/spot` | doc oficial |
| WebSocket Futures | `wss://socket.coinex.com/v2/futures` | doc oficial |
| Documentação | https://docs.coinex.com/api/v2/ | — |

### 2.2 Autenticação (HMAC-SHA256)

`[confirmado]` desde 2024-04-18, CoinEx usa **HMAC-SHA256** (substituiu o SHA256 puro do v1).

**Geração de chaves**: criar par `access_id` + `secret_key` no painel API da conta. **Nunca transmitir o secret_key em requisições.**

**Headers obrigatórios em todas as chamadas autenticadas**:
```
X-COINEX-KEY:       <access_id>
X-COINEX-SIGN:      <hmac_sha256_signature_em_hex_lowercase>
X-COINEX-TIMESTAMP: <unix_ms>
```

**Cálculo da assinatura (HTTP)**:
```
prepared_str = method + request_path + body + timestamp
signature    = HMAC_SHA256(secret_key, prepared_str).hex().lower()
```

- `method`: maiúsculas (`GET`, `POST`)
- `request_path`: caminho com query string já encodada (ex.: `/v2/spot/balance?market=BTCUSDT`)
- `body`: string JSON exata enviada (vazia em GET)
- `timestamp`: mesmo valor enviado no header `X-COINEX-TIMESTAMP`
- output: hex lowercase, 64 caracteres

**Para WebSocket**: chamar o método `server.sign` passando `(access_id, signed_str, timestamp)`, onde `signed_str = HMAC_SHA256(secret_key, timestamp)`.

Exemplo de cabeçalho real:
```
GET /v2/assets/spot/balance HTTP/1.1
Host: api.coinex.com
X-COINEX-KEY: 4DA36FFC61334695...
X-COINEX-SIGN: 78dccd55b1...
X-COINEX-TIMESTAMP: 1700490703564
```

Fonte: [Authorization doc](https://docs.coinex.com/api/v2/authorization)

### 2.3 Rate limits

**Por IP**: `[confirmado]` 400 req/s — limite alto que raramente vira gargalo.

**Por conta (UID-based)** — categoria de dois ciclos:
- **Short Cycle**: independente por conta (main + sub separadas)
- **Long Cycle**: cota compartilhada entre main + todas sub-accounts (janela 1H-24H)

**Spot trading**:

| Categoria | Limite | Endpoints |
|-----------|--------|-----------|
| Place/edit orders | 30 req/s | put-order, put-stop-order, edit-order, batch put |
| Cancel orders | 60 req/s | cancel-order, cancel-stop-order |
| Cancel all/batch | 40 req/s | cancel-all, cancel-batch |
| Query orders | 50 req/s | list-pending, get-order-status |
| Order history | 10 req/s | list-finished-order |
| Account ops | 10 req/s | transfer, set, margin operations |
| Account queries | 10 req/s | balance, fee-rate, sub-account |

**Futures trading**:

| Categoria | Limite | Endpoints |
|-----------|--------|-----------|
| Place/edit | 20 req/s | put-order, put-stop-order |
| Cancel | 40 req/s | cancel-order |
| Cancel all/batch | 20 req/s | cancel-all |
| Query | 50 req/s | list-pending |
| Order history | 10 req/s | list-finished |
| Account queries | 10 req/s | balance, position |

**Batch weighting**: uma requisição batch consome cota igual ao número de sub-requests (batch de 5 = 5 unidades).

**Long Cycle penalty**: se padrão de uso "abusivo" (volume + qualidade), entra em modo de penalidade — taxas reduzidas mas **cancelamento preservado** (garantia de saída).

Fonte: [Rate Limit doc](https://docs.coinex.com/api/v2/rate-limit)

### 2.4 Convenções de erro

`code = 0` → sucesso. Outros códigos relevantes:

| Código | Significado | Estratégia |
|--------|-------------|------------|
| 3008 | Service busy — retry later | Retry com backoff exponencial (300ms → 1s → 3s) |
| 3109 | Saldo insuficiente | Falha permanente — não retry |
| 3127 | Quantidade abaixo do mínimo | Falha permanente — ajustar min_amount |
| 3606 | Preço fora do range permitido | Falha — recalcular preço de referência |
| 3610 | Não pode cancelar em Call Auction | Aguardar fim da sessão |
| 3612-3619 | Issues de price deviation / depth | Recalcular ou abortar |
| 3620 | Market order indisponível (depth baixa) | Trocar para limit |
| 3621 | Ordem não pôde executar totalmente — cancelada | Esperado em FOK |
| 3622 | Rejeitada por maker-only | Esperado em post-only |
| 3627-3629 | Depth insuficiente para o size | Reduzir size |
| 3638 | Apenas maker-only durante período de proteção | Aguardar ou usar maker-only |
| 3639 | Parâmetros incorretos | Falha permanente — corrigir payload |
| 4005-4008 | Auth failures | Verificar credencial / clock skew |
| 4006, 4017 | Signature issues | Refazer assinatura |
| 4007 | IP restricted | Whitelist IP |
| 4018 | Endpoint deprecated | Migrar |
| 4115-4159 | Trading restrictions | Análise caso-a-caso |
| 4213 | Rate limited | Backoff exponencial |
| 4512 | Permission denied | API key sem escopo |

**WebSocket**: erros 20001-24002 (spot) e 30001-34002 (futures).

**Estratégia de retry recomendada** (`[inferido]` boas práticas + doc):
- `4213` e `3008`: exponencial 300ms → 600ms → 1.2s → ... max 30s
- `4005-4008/4017`: NÃO retry — clock skew ou credencial inválida
- `3109/3127/3606/3639`: NÃO retry — fix no caller
- Timeout de rede: 3 retries com jitter

Fonte: [Error doc](https://docs.coinex.com/api/v2/error)

### 2.5 Versionamento

- **v1**: descontinuada em 2024-09-25 — `[confirmado]` removida
- **v2**: única versão suportada — em desenvolvimento ativo
- Changelog público: [docs.coinex.com/api/v2/changelog](https://docs.coinex.com/api/v2/changelog)

Mudanças notáveis 2024-2026:
- 2024-04-18: HMAC-SHA256
- 2024-07-18: parâmetro `stp_mode` (self-trade prevention) adicionado
- 2024-08-22: edit-order otimizado (não mais cancel-and-replace)
- 2024-09-12: fix precisão de timestamp em futures market
- 2025-01-09: rate limit de batch passa a contar por sub-requests
- 2025-04-16: AMM liquidity pool endpoints
- 2025-08-14: batch modify de ordens (spot + futures)
- 2025-11-13: referral rebate endpoints
- 2025-12-18: TP/SL múltiplos por posição (até 20)

---

## 3. SPOT — Endpoints

### 3.1 Market data (públicos, sem autenticação)

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/spot/market` | Status do market + config (precision, fees, flags trading) |
| GET | `/spot/market-ticker` | Ticker (last, high, low, vol, change) |
| GET | `/spot/market-depth` | Order book (depth) |
| GET | `/spot/market-deals` | Trades recentes |
| GET | `/spot/market-kline` | Candlesticks |
| GET | `/spot/market-index` | Index price |

**Parâmetro principal**: `market` (opcional, string) — até 10 markets vírgula-separados, vazio retorna todos.

**Tipo de kline / intervalos suportados** `[inferido]`: `1min`, `3min`, `5min`, `15min`, `30min`, `1hour`, `2hour`, `4hour`, `6hour`, `12hour`, `1day`, `3day`, `1week`.

### 3.2 Account (autenticado)

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/assets/spot/balance` | Saldo na conta spot |
| GET | `/assets/margin/balance` | Saldo margin |
| GET | `/assets/futures/balance` | Saldo futures |
| GET | `/assets/financial/balance` | Saldo financial (yield/savings) |
| GET | `/assets/credit/info` | Info credit account |
| GET | `/assets/credit/balance` | Saldo credit account |
| GET | `/assets/spot/transaction-history` | Histórico de movimentações |

Endpoints account (subaccounts/fee rate) — `[incerto]` paths exatos não confirmados na pesquisa; consultar [docs.coinex.com/api/v2/account](https://docs.coinex.com/api/v2/) seção Account.

### 3.3 Orders (autenticado)

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/spot/order` | Place order (limit/market/maker_only/ioc/fok) |
| POST | `/spot/stop-order` | Place stop order |
| POST | `/spot/batch-order` | Batch place orders (até 100 sub-requests) |
| POST | `/spot/batch-stop-order` | Batch place stop orders |
| POST | `/spot/modify-order` | Modify order |
| POST | `/spot/modify-stop-order` | Modify stop order |
| POST | `/spot/modify-batch-order` | Batch modify |
| POST | `/spot/cancel-order` | Cancel single |
| POST | `/spot/cancel-all-order` | Cancel todas |
| POST | `/spot/cancel-stop-order` | Cancel stop |
| POST | `/spot/cancel-batch-order` | Batch cancel |
| POST | `/spot/cancel-batch-stop-order` | Batch cancel stop |
| GET | `/spot/pending-order` | Listar ordens abertas |
| GET | `/spot/finished-order` | Listar ordens concluídas |
| GET | `/spot/pending-stop-order` | Stop orders abertos |
| GET | `/spot/finished-stop-order` | Stop orders concluídos |
| GET | `/spot/user-deals` | Histórico de execuções |

> Nota: paths exatos seguem o padrão `/spot/<recurso>`. A URL da documentação tem o sufixo `http/<nome-da-página>` (ex: `/spot/order/http/put-order` é a página de docs; o path real do endpoint é `POST /spot/order`). `[confirmado]` para put-order, put-stop-order, adjust-position-leverage. `[inferido]` para os demais com base no padrão de nomenclatura.

### 3.4 Order types

| Type | Descrição | Requer `price`? |
|------|-----------|------------------|
| `limit` | Limit order tradicional | Sim |
| `market` | Market order | Não |
| `maker_only` | Post-only — cancela se cruzar o book | Sim |
| `ioc` | Immediate-or-Cancel | Sim |
| `fok` | Fill-or-Kill | Sim |

`[confirmado]` via enumeration page.

**STP (Self-Trade Prevention) modes**:
- `ct` (Cancel Taker): cancela a taker leg
- `cm` (Cancel Maker): cancela a maker leg
- `both`: cancela ambas

### 3.5 Place Order — payload exemplo

```http
POST /v2/spot/order
Content-Type: application/json
X-COINEX-KEY: ...
X-COINEX-SIGN: ...
X-COINEX-TIMESTAMP: 1700490703564

{
  "market": "BTCUSDT",
  "market_type": "SPOT",        // ou "MARGIN"
  "side": "buy",                 // buy | sell
  "type": "limit",               // limit|market|maker_only|ioc|fok
  "amount": "0.001",
  "price": "65000.5",
  "client_id": "myorder-001",
  "is_hide": false,
  "stp_mode": "ct"
}
```

Resposta inclui: `order_id`, `market`, `market_type`, `side`, `type`, `amount`, `price`, `unfilled_amount`, `filled_amount`, `filled_value`, `client_id`, `base_fee`, `quote_fee`, `discount_fee`, `maker_fee_rate`, `taker_fee_rate`, `last_filled_amount`, `last_filled_price`, `created_at`, `updated_at`.

### 3.6 Precision rules — onde consultar

Resposta do `GET /spot/market` contém:

```json
{
  "market": "BTCUSDT",
  "base_ccy": "BTC",
  "quote_ccy": "USDT",
  "base_ccy_precision": 8,        // casas decimais do amount
  "quote_ccy_precision": 2,       // casas decimais do price
  "min_amount": "0.0005",
  "maker_fee_rate": "0.002",
  "taker_fee_rate": "0.002",
  "is_amm_available": true,
  "is_margin_available": true,
  "is_pre_market_trading_available": true,
  "is_api_trading_available": true,
  "status": "online"
}
```

**Atenção crítica para o projeto** (ver §10.2): SPOT não tem campo `tick_size` na resposta — apenas `base_ccy_precision` (amount decimals) e `quote_ccy_precision` (price decimals). Para sub-dollar tokens, `quote_ccy_precision` pode chegar a 6, 8 ou mais casas. Já FUTURES tem campo `tick_size` explícito (ver §4).

### 3.7 Trading pairs

`GET /spot/market` sem parâmetros retorna todos os pares ativos. Filtros úteis: `status == "online"` e `is_api_trading_available == true`.

---

## 4. FUTURES — Endpoints

### 4.1 Market data (públicos)

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/futures/market` | Status + config (contract_type, fees, leverage, tick_size) |
| GET | `/futures/market-ticker` | Ticker |
| GET | `/futures/market-depth` | Order book |
| GET | `/futures/market-deals` | Trades recentes |
| GET | `/futures/market-kline` | Candlesticks |
| GET | `/futures/market-index` | Index price |
| GET | `/futures/market-funding-rate` | Funding rate atual |
| GET | `/futures/market-funding-rate-history` | Histórico funding |
| GET | `/futures/market-premium-history` | Premium index histórico |
| GET | `/futures/market-position-level` | Tabela de tiers de leverage / risk |
| GET | `/futures/market-liquidation-history` | Liquidações recentes |
| GET | `/futures/market-basis-history` | Basis (futures vs spot) histórico |

`[confirmado]` via listagem da página `/futures/market/http/list-market`.

### 4.2 Account / Position (autenticado)

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/assets/futures/balance` | Saldo futures |
| GET | `/futures/pending-position` | Posições abertas |
| GET | `/futures/finished-position` | Posições históricas |
| POST | `/futures/close-position` | Fechar posição |
| POST | `/futures/adjust-position-margin` | Ajustar margin (add/remove) |
| POST | `/futures/adjust-position-leverage` | Ajustar leverage + margin_mode |
| POST | `/futures/set-position-stop-loss` | Set SL na posição |
| POST | `/futures/set-position-take-profit` | Set TP na posição |
| POST | `/futures/modify-position-stop-loss` | Modificar SL existente |
| POST | `/futures/modify-position-take-profit` | Modificar TP existente |
| POST | `/futures/cancel-position-stop-loss` | Cancelar SL |
| POST | `/futures/cancel-position-take-profit` | Cancelar TP |
| GET | `/futures/position-margin-history` | Histórico de ajuste margin |
| GET | `/futures/position-funding-history` | Funding payments histórico |
| GET | `/futures/position-adl-history` | Auto-deleverage events |
| GET | `/futures/position-settle-history` | Settlement records |

### 4.3 Orders

Estrutura espelha SPOT (ver §3.3) mas com path `/futures/...`:

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/futures/order` | Place order |
| POST | `/futures/stop-order` | Place stop |
| POST | `/futures/batch-order` | Batch place |
| POST | `/futures/batch-stop-order` | Batch place stop |
| POST | `/futures/modify-order` | Modify |
| POST | `/futures/modify-stop-order` | Modify stop |
| POST | `/futures/modify-batch-order` | Batch modify |
| POST | `/futures/cancel-order` | Cancel |
| POST | `/futures/cancel-all-order` | Cancel all |
| POST | `/futures/cancel-stop-order` | Cancel stop |
| POST | `/futures/cancel-batch-order` | Batch cancel |
| POST | `/futures/cancel-batch-stop-order` | Batch cancel stop |
| POST | `/futures/cancel-order-by-client-id` | Cancel by client_id |
| POST | `/futures/cancel-stop-order-by-client-id` | Cancel stop by client_id |
| GET | `/futures/order-status` | Status de uma ordem |
| GET | `/futures/multi-order-status` | Status batch |
| GET | `/futures/pending-order` | Ordens abertas |
| GET | `/futures/finished-order` | Ordens concluídas |
| GET | `/futures/pending-stop-order` | Stop orders abertos |
| GET | `/futures/finished-stop-order` | Stop orders concluídos |
| GET | `/futures/user-deals` | Histórico de execuções |

### 4.4 Position management — set leverage + margin mode

`[confirmado]` `POST /futures/adjust-position-leverage` é o ponto único onde se define **leverage** e **margin_mode** (isolated/cross):

```http
POST /v2/futures/adjust-position-leverage
{
  "market": "BTCUSDT",
  "market_type": "FUTURES",
  "margin_mode": "cross",     // "isolated" ou "cross"
  "leverage": 10
}
```

Resposta:
```json
{
  "code": 0,
  "data": { "margin_mode": "cross", "leverage": 10 },
  "message": "OK"
}
```

> **Importante**: margin_mode é setado por par e por direção em isolated. Em cross, o margin é compartilhado entre todas as posições.

### 4.5 Funding rate history

```
GET /futures/market-funding-rate-history?market=BTCUSDT&start_time=...&end_time=...&limit=100
```

Retorna lista de eventos de funding (timestamp, rate, mark price no settle). `[inferido]` periodicidade default 8h.

### 4.6 Liquidation history

```
GET /futures/market-liquidation-history?market=BTCUSDT&start_time=...&limit=100
```

### 4.7 Order types (futures)

Mesma enumeração: `limit`, `market`, `maker_only`, `ioc`, `fok` para ordens regulares.

**Conditional / Stop orders** (via `/futures/stop-order`):
- `trigger_price`: preço de disparo
- `trigger_price_type`: `latest_price` | `mark_price` | `index_price` `[confirmado]`
- `type` do conditional pode ser `limit` ou `market` após trigger

**TP/SL nativos por posição** (via `set-position-stop-loss` / `set-position-take-profit`):
- Suportam múltiplas ordens por posição (até **20** por SL e por TP desde 2025-12-18)
- Type field: `take_profit_type` e `stop_loss_type` aceitam `latest_price` | `mark_price` | `index_price`

**Trailing stop**: `[incerto]` — não há evidência de endpoint dedicado de trailing stop em v2; comportamento equivalente exige loop client-side ajustando o SL.

**OCO**: `[incerto]` — não documentado nativamente; reproduzir via TP+SL na posição.

---

## 5. MARGIN — Endpoints

### 5.1 Suporte v2

CoinEx tem dois "produtos margin":
- **Spot Margin** (alavancagem na conta spot via empréstimo) — `market_type: MARGIN` nos endpoints de spot order
- **Futures Margin** (alavancagem natural de contratos perp) — `market_type: FUTURES`

`[confirmado]` v2 expõe endpoints de borrow/repay para SPOT MARGIN, mas **NÃO** expõe endpoint para alternar entre isolated vs cross em spot margin (ver §5.4 e §10.1).

### 5.2 Borrow / Repay (Spot Margin)

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/assets/margin/borrow` | Pedir empréstimo |
| POST | `/assets/margin/repay` | Repagar empréstimo |
| GET | `/assets/margin/borrow-history` | Histórico de empréstimos |
| GET | `/assets/margin/interest-limit` | Limite de borrow + taxa de juros |

Resposta de borrow contém: `borrow_id`, `market`, `ccy`, `daily_interest_rate`, `expired_at`, `borrow_amount`, `to_repaid_amount`, `status`.

### 5.3 Account info / risk ratio

- `GET /assets/margin/balance` retorna saldo, frozen, debt, risk ratio por par.
- Status do loan: `loan` | `debt` | `liquidated` | `finish` (ver enum §2.5/§3.4).

### 5.4 GAP CRÍTICO — Margin mode em SPOT MARGIN

**Status pesquisa**:
- **NÃO existe** `[confirmado]` endpoint v2 público para configurar isolated vs cross em spot margin.
- O `margin_mode` enum (`isolated`/`cross`) só é aceito como parâmetro em **`/futures/adjust-position-leverage`**.
- Em SPOT MARGIN, a CoinEx opera por padrão em modo **isolated por par** (cada par tem sua conta margin separada com risk ratio próprio).
- O changelog de 2024-2026 NÃO menciona introdução de margin-mode endpoint para spot.

**Implicações para o projeto** (ver §10.1):
- O modelo SPOT MARGIN da CoinEx é estruturalmente isolated-by-pair — não há "cross spot margin" exposto na API.
- Para alternar entre spot e margin no SPOT, basta usar `market_type: "SPOT"` vs `market_type: "MARGIN"` no `/spot/order`.
- A configuração inicial da conta margin (habilitar margin trading) é feita **manualmente na UI** antes de qualquer chamada API.

`[inferido com alta confiança]` baseado em: doc oficial, enumeration page, e ausência total de changelog mencionando isolated/cross para spot.

---

## 6. ASSETS — Endpoints

### 6.1 Depósito

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/assets/deposit-address` | Endereço de depósito |
| POST | `/assets/update-deposit-address` | Renovar/atualizar endereço |
| GET | `/assets/deposit-history` | Histórico de depósitos |

Status enum: `processing` | `confirming` | `cancelled` | `finished` | `too_small` | `exception`.

### 6.2 Saque

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/assets/withdraw` | Submeter saque |
| POST | `/assets/cancel-withdraw` | Cancelar saque |
| GET | `/assets/withdraw-history` | Histórico |

Status: `created` | `audit_required` | `audited` | `processing` | `confirming` | `finished` | `cancelled` | `cancellation_failed` | `failed`.

### 6.3 Transfers

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/assets/transfer` | Transferir entre wallets (spot/margin/futures/financial) |
| GET | `/assets/transfer-history` | Histórico |
| POST | `/assets/sub-spot-transfer` `[inferido]` | Transfer main↔sub |
| GET | `/assets/sub-spot-transfer-history` `[inferido]` | Histórico sub-transfer |

**Regra**: em `/assets/transfer`, **uma das pontas (origem OU destino) precisa ser a conta SPOT** — não dá para transferir direto margin→futures, tem que passar por spot.

### 6.4 Coin / network info

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/assets/deposit-withdraw-config` | Config de uma moeda específica (precision, fee, min, networks) |
| GET | `/assets/all-deposit-withdraw-config` | Lista completa |
| GET | `/assets/info` | Coin info (descrição, networks) |

Fonte: [Deposit/Withdrawal docs](https://docs.coinex.com/api/v2/assets/deposit-withdrawal/http/list-deposit-history)

---

## 7. WebSocket

### 7.1 Endpoints

| Tipo | URL |
|------|-----|
| Spot | `wss://socket.coinex.com/v2/spot` |
| Futures | `wss://socket.coinex.com/v2/futures` |

### 7.2 Modelo de subscription

Mensagens são JSON-RPC-like: `{ "method": "...", "params": {...}, "id": <int> }`.

**Public channels** (sem auth):
- `depth.subscribe` — order book
- `kline.subscribe` — candles
- `deals.subscribe` — trades
- `state.subscribe` / `bbo.subscribe` — ticker / best bid-ask
- `index.subscribe` (futures) — index price
- `funding.subscribe` (futures) — funding updates

**Private channels** (requerem `server.sign` primeiro):
- `order.subscribe` — atualizações de ordens do usuário (push em tempo real)
- `asset.subscribe` — atualizações de saldo
- `position.subscribe` (futures) — atualizações de posições
- `stop.subscribe` — atualizações de stop orders

### 7.3 Autenticação WebSocket

```json
{
  "method": "server.sign",
  "params": {
    "access_id": "...",
    "signed_str": "HMAC_SHA256(secret_key, timestamp).hex()",
    "timestamp": 1700490703564
  },
  "id": 1
}
```

Após `code: 0`, pode chamar os métodos `.subscribe` privados.

### 7.4 Heartbeat / Reconnect

`[inferido]` Padrão CoinEx — ping a cada **30s**. Sem resposta em 60s → drop connection.

Estratégia: ping no client a cada 25-30s + reconnect com backoff exponencial em caso de drop.

### 7.5 Diferenças vs REST

- WS é **push-based** — necessário para HFT / scalp.
- Latência: tipicamente <50ms vs ~100-300ms REST.
- Alguns dados só vêm por WS de forma agregada (ex.: incremental depth updates).
- WS NÃO substitui REST para operações de placement em alta frequência (REST tem rate limit mais alto para place/cancel).

---

## 8. Fees

### 8.1 Spot trading fees

| Volume 30d / Tier | Maker | Taker |
|-------------------|-------|-------|
| Base (sem tier) | 0.20% | 0.20% |
| VIP 1+ standard | 0.16% | 0.20% |
| 30d vol ≥ $5M | 0.096% | 0.12% |
| 30d vol ≥ $15M | 0.02% | 0.04% |
| VIP 5 / market maker | até negativos ou 0.00% | depende do programa MM |

Fonte: [TradersUnion CoinEx fees](https://tradersunion.com/brokers/crypto/view/coinex/fees/) · [CoinEx Fees](https://www.coinex.com/en/fees)

### 8.2 Futures trading fees

| Tier | Maker | Taker |
|------|-------|-------|
| Base | 0.03% | 0.05% |
| VIP 5 | 0.02% | 0.04% |
| Market Maker Pro | até negativo | conforme programa |

### 8.3 Desconto CET

- Pagamento de fee em CET → desconto **20-30%** `[inferido]` em modo padrão.
- High volume + CET stack: efetivo pode chegar a "até 90%" de desconto vs base (segundo material de marketing CoinEx).
- VIP status (por CET holdings) acumula com discount de volume.

### 8.4 Withdrawal fees

Fee por moeda + network — consultar via:
```
GET /assets/deposit-withdraw-config?ccy=BTC
```
Retorna `withdraw_fee`, `min_withdraw_amount`, `precision`, networks suportadas.

### 8.5 Funding rate (futures)

- Frequência: **8h** (00:00, 08:00, 16:00 UTC)
- Range típico: -0.375% a +0.375%
- Pago de longs para shorts (ou vice-versa) conforme premium.
- Custo efetivo de carry: `funding_rate × position_size × frequencia`.

---

## 9. Restrições geográficas e KYC

### 9.1 Países bloqueados

| País | Status |
|------|--------|
| Estados Unidos | Bloqueado (NYAG ban 2023, pressão SEC/CFTC) |
| Canadá | Bloqueado |
| Hong Kong | Bloqueado |
| China continental | Bloqueado |
| Reino Unido | Permitido `[confirmado por Datawallet]` |
| Brasil | Permitido |
| União Europeia | Permitido (`[incerto]` status MiCA pós-2026-07-01) |
| Coreia do Norte, Irã, Síria, Cuba | Bloqueado (OFAC/sanções) |

### 9.2 Tiers de KYC

| Tier | Withdraw limit 24h | Requisitos |
|------|--------------------|-----------|
| No KYC | $10k/dia ou $50k/mês `[fonte: cobertura externa, verificar]` | apenas email |
| Primary ID | $1.000.000 | ID emitido por governo |
| Advanced ID | $5.000.000 | ID + comprovante residência (se diferente do ID) |

Fonte: [CoinEx AML/KYC Policy](https://support.coinex.com/hc/en-us/articles/27436563672601-AML-KYC-Policy)

### 9.3 Conformidade

- **MiCA EU**: prazo final 2026-07-01. `[incerto]` — sem registro público de autorização CASP CoinEx até esta pesquisa.
- **FATF Travel Rule**: cumprimento para saques acima de threshold.
- **AML/CTF**: política publicada, monitoramento on-chain via parceiros (Chainalysis/Elliptic — `[inferido]`).

---

## 10. Gaps específicos do projeto CoinEx AI Agent

### 10.1 Margin Isolated em SPOT — gap arquitetural

**Status**:
- `[confirmado]` NÃO existe endpoint v2 para configurar isolated/cross em SPOT MARGIN.
- O `margin_mode` enum (`isolated`/`cross`) **só é aceito** em `/futures/adjust-position-leverage`.
- O CoinEx spot margin opera estruturalmente como **isolated-by-pair** — cada par tem sua conta margin independente com risk ratio próprio.

**Pesquisa em v1 legacy**:
- v1 foi descontinuada 2024-09-25. Não há mais documentação ativa.
- `[inferido]` v1 também não tinha endpoint dedicado de margin-mode para spot — sempre foi isolated-by-pair.

**Roadmap público / outras corretoras**:
- Binance suporta cross margin spot via endpoint dedicado — modelo distinto.
- CoinEx não publicou roadmap explícito de introdução de "cross spot margin" via API v2.

**Workaround documentado**:
1. Habilitar margin trading **manualmente na UI** antes de operar (one-time setup por par).
2. Em código, usar `market_type: "MARGIN"` no `/spot/order` — o modelo isolated-por-par é automático.
3. Para "ajustar margin mode" pré-trade, NÃO TEM como — é fixo na natureza do produto.
4. Para FUTURES (onde existe a flexibilidade), chamar `/futures/adjust-position-leverage` **antes** de abrir posição, passando `margin_mode` desejado.

**Recomendação para o agente**:
- Tratar "margin mode isolated" como **assertion** (verificar que está habilitado), não como ação configurável via API em spot.
- Para futures, integrar `adjust-position-leverage` como step pre-trade obrigatório quando margin_mode atual difere do desejado.

### 10.2 Sub-dollar Precision (bug AIUSDT documentado no projeto)

**Sintoma reportado**: AIUSDT gerou stop -85% e alvo invertido (-0.2%) — esperado seria -50%/+200%.

**Modelo CoinEx de precision**:

**SPOT** (`GET /spot/market`):
- `base_ccy_precision`: número de casas decimais para o **amount** (tipicamente 0-8)
- `quote_ccy_precision`: número de casas decimais para o **price** (tipicamente 2-8)
- **NÃO HÁ `tick_size` em spot** — o incremento de preço é `10^(-quote_ccy_precision)`
- **NÃO HÁ `step_size` em spot** — o incremento de amount é `10^(-base_ccy_precision)`
- `min_amount`: amount mínimo em string decimal (ex: `"0.0005"`)

**FUTURES** (`GET /futures/market`):
- `base_ccy_precision`: casas decimais do amount
- `quote_ccy_precision`: casas decimais do price
- **TEM `tick_size`** explícito em string (ex: `"0.5"`) — diferente do spot
- `min_amount`: idem

**Sub-dollar exemplos esperados** `[inferido]`:
- BTCUSDT: `quote_ccy_precision: 2`, `tick_size: "0.5"` → preço em incrementos de $0.50
- AIUSDT (token sub-dólar): `quote_ccy_precision: 6` ou `8` → preço em incrementos de $0.000001 ou menor
- Tokens micro-cap (preço $0.00001 ou menor): `quote_ccy_precision: 10+` é plausível

**Hipóteses para o bug AIUSDT**:
1. **Conversão decimal → float**: se o código faz `Math.Round(price, precision)` usando float, ocorre erro de representação em precisões altas (≥ 6 casas). Solução: usar `decimal` em todas as operações.
2. **Confusão SPOT vs FUTURES**: spot não tem tick_size; se o código tenta ler `tick_size` em resposta spot e cai em default 0, todos os ajustes batem em $0 → preços nonsense.
3. **Notação científica**: se a corretora retornar `"1e-7"` em algum campo (raro mas possível em payloads JSON), o parser pode interpretar errado se assumir decimal puro.
4. **Order side invertido**: stop -85% e alvo -0.2% para um LONG sugere que stop e take_profit foram swap-trocados na construção da ordem — pode ser bug de lógica antes do envio à API, não da API em si.

**Diagnóstico recomendado**:
1. Logar o payload exato enviado ao `/spot/order` e a resposta antes do trade.
2. Confirmar via `GET /spot/market?market=AIUSDT` o valor de `quote_ccy_precision`.
3. Validar localmente que `target_price = entry × (1 + target_pct)` e `stop_price = entry × (1 - stop_pct)` para LONG, com **decimal** não float.
4. Verificar se `side` está consistente entre stop e take-profit (ambos `sell` para fechar LONG).

### 10.3 Order types disponíveis end-to-end (tabela final)

O que o projeto pode usar **hoje** via v2:

| Funcionalidade | Spot | Futures | Endpoint / Mecanismo |
|----------------|------|---------|----------------------|
| Limit | Sim | Sim | `type: "limit"` |
| Market | Sim | Sim | `type: "market"` |
| Post-only (maker_only) | Sim | Sim | `type: "maker_only"` |
| IOC | Sim | Sim | `type: "ioc"` |
| FOK | Sim | Sim | `type: "fok"` |
| Stop / Conditional | Sim (`/spot/stop-order`) | Sim (`/futures/stop-order`) | trigger_price + trigger_price_type |
| Stop-Limit | Sim (stop-order com `type: limit`) | Sim | combinação |
| Take-Profit nativo posição | NÃO `[inferido]` (só spot order com TP-limit manual) | **Sim** (set-position-take-profit, múltiplos por posição até 20) | `/futures/set-position-take-profit` |
| Stop-Loss nativo posição | NÃO `[inferido]` | **Sim** (set-position-stop-loss, até 20) | `/futures/set-position-stop-loss` |
| Trailing Stop | NÃO documentado | NÃO documentado em v2 `[incerto]` | requer loop client-side |
| OCO (One-Cancels-Other) | NÃO documentado | NÃO documentado | TP+SL na posição em futures aproxima |
| Iceberg | `is_hide: true` flag | `is_hide: true` flag | parcial — esconde da depth, não fatiamento |

**Conclusão**: para o agente fazer trade gerenciado com SL+TP atômico, **futures é superior ao spot na CoinEx** porque tem TP/SL nativos vinculados à posição. Em spot, o agente precisa criar e gerenciar duas ordens condicionais separadas (uma stop para SL, uma limit para TP) e cancelar a sobrevivente quando uma executa.

---

## 11. Comparação rápida CoinEx vs concorrência

**Pontos fortes**:
- **Listagens early**: forte presença em micro-caps e tokens de "ciclo cedo" antes de Binance/OKX listarem (relevante para o módulo GemScan do projeto).
- **Taxas competitivas**: spot 0.20% base é mediana; com CET + volume desce rápido. Futures 0.03%/0.05% é competitivo.
- **API v2 limpa**: HMAC-SHA256, JSON em todos os payloads, rate limits altos por IP (400/s).
- **CSC (CoinEx Smart Chain)**: integra wallet ↔ exchange para usuários que operam ambos.
- **Sem KYC obrigatório** para volumes baixos (atrai usuários ocidentais que evitam KYC pesado).

**Pontos fracos**:
- **Liquidez secundária**: BTC/ETH OK, mas micro-caps têm spreads largos e slippage real >2% em vol < $500k (relevante para o módulo MICRO_LIQUIDITY do projeto).
- **Histórico de hack 2023**: $70M roubados — apesar de ressarcimento, sinal de maturidade de security operations limitada à época.
- **Documentação técnica**: organizada mas com lacunas (alguns endpoints precisam ser inferidos da sidebar; sem changelog detalhado de breaking changes em payload).
- **Sem acesso US**: limita corredor de capital e arbitragem.
- **Margin spot menos flexível**: sem cross spot margin (ver §10.1).
- **MiCA status incerto**: risco regulatório para usuários UE pós-julho-2026.

**Quando usar CoinEx vs alternativa**:
- **Use CoinEx**: pesca de micro-caps recém-listados, futures perpétuos em altcoins menores, baixo custo por trade em estratégias de volume médio.
- **Considere alternativa**: ordens institucionais > $1M (liquidez), operações regulatorialmente sensíveis, necessidade de OCO/trailing nativos.

---

## 12. Links oficiais

- Documentação REST: https://docs.coinex.com/api/v2/
- Authentication: https://docs.coinex.com/api/v2/authorization
- Rate Limit: https://docs.coinex.com/api/v2/rate-limit
- Error codes: https://docs.coinex.com/api/v2/error
- Enumerations: https://docs.coinex.com/api/v2/enum
- Changelog: https://docs.coinex.com/api/v2/changelog
- Integration Guide: https://docs.coinex.com/api/v2/guide
- Help Center: https://support.coinex.com/hc/en-us
- Announcements: https://announcement.coinex.com/hc/en-us
- CoinEx home: https://www.coinex.com
- CET token: https://www.coinex.com/en/token
- Fees: https://www.coinex.com/en/fees
- AML/KYC Policy: https://support.coinex.com/hc/en-us/articles/27436563672601

---

## 13. Apêndice: Lista exaustiva de endpoints v2

Consolidação de tudo mapeado nesta pesquisa.

### Spot — Market (público)

| Método | Path | Auth | Rate cat. | Descrição |
|--------|------|------|-----------|-----------|
| GET | `/spot/market` | Não | público | Market info + precision |
| GET | `/spot/market-ticker` | Não | público | Ticker |
| GET | `/spot/market-depth` | Não | público | Order book |
| GET | `/spot/market-deals` | Não | público | Trades recentes |
| GET | `/spot/market-kline` | Não | público | Candles |
| GET | `/spot/market-index` | Não | público | Index price |

### Spot — Order (autenticado)

| Método | Path | Auth | Rate cat. | Descrição |
|--------|------|------|-----------|-----------|
| POST | `/spot/order` | Sim | 30/s | Place order |
| POST | `/spot/stop-order` | Sim | 30/s | Place stop |
| POST | `/spot/batch-order` | Sim | 30/s (N) | Batch place |
| POST | `/spot/batch-stop-order` | Sim | 30/s (N) | Batch place stop |
| POST | `/spot/modify-order` | Sim | 30/s | Modify |
| POST | `/spot/modify-stop-order` | Sim | 30/s | Modify stop |
| POST | `/spot/modify-batch-order` | Sim | 30/s (N) | Batch modify |
| POST | `/spot/cancel-order` | Sim | 60/s | Cancel |
| POST | `/spot/cancel-all-order` | Sim | 40/s | Cancel all |
| POST | `/spot/cancel-stop-order` | Sim | 60/s | Cancel stop |
| POST | `/spot/cancel-batch-order` | Sim | 40/s (N) | Batch cancel |
| POST | `/spot/cancel-batch-stop-order` | Sim | 40/s (N) | Batch cancel stop |
| GET | `/spot/pending-order` | Sim | 50/s | Open orders |
| GET | `/spot/finished-order` | Sim | 10/s | Filled orders |
| GET | `/spot/pending-stop-order` | Sim | 50/s | Open stop orders |
| GET | `/spot/finished-stop-order` | Sim | 10/s | Filled stop orders |
| GET | `/spot/user-deals` | Sim | 10/s | Execution history |

### Futures — Market (público)

| Método | Path | Auth | Rate cat. | Descrição |
|--------|------|------|-----------|-----------|
| GET | `/futures/market` | Não | público | Contract info + tick_size |
| GET | `/futures/market-ticker` | Não | público | Ticker |
| GET | `/futures/market-depth` | Não | público | Order book |
| GET | `/futures/market-deals` | Não | público | Trades |
| GET | `/futures/market-kline` | Não | público | Candles |
| GET | `/futures/market-index` | Não | público | Index price |
| GET | `/futures/market-funding-rate` | Não | público | Funding atual |
| GET | `/futures/market-funding-rate-history` | Não | público | Funding histórico |
| GET | `/futures/market-premium-history` | Não | público | Premium index |
| GET | `/futures/market-position-level` | Não | público | Tiers leverage/risk |
| GET | `/futures/market-liquidation-history` | Não | público | Liquidações |
| GET | `/futures/market-basis-history` | Não | público | Basis futures-spot |

### Futures — Order

| Método | Path | Auth | Rate cat. | Descrição |
|--------|------|------|-----------|-----------|
| POST | `/futures/order` | Sim | 20/s | Place |
| POST | `/futures/stop-order` | Sim | 20/s | Place stop |
| POST | `/futures/batch-order` | Sim | 20/s (N) | Batch place |
| POST | `/futures/batch-stop-order` | Sim | 20/s (N) | Batch place stop |
| POST | `/futures/modify-order` | Sim | 20/s | Modify |
| POST | `/futures/modify-stop-order` | Sim | 20/s | Modify stop |
| POST | `/futures/modify-batch-order` | Sim | 20/s (N) | Batch modify |
| POST | `/futures/cancel-order` | Sim | 40/s | Cancel |
| POST | `/futures/cancel-all-order` | Sim | 20/s | Cancel all |
| POST | `/futures/cancel-stop-order` | Sim | 40/s | Cancel stop |
| POST | `/futures/cancel-batch-order` | Sim | 20/s (N) | Batch cancel |
| POST | `/futures/cancel-batch-stop-order` | Sim | 20/s (N) | Batch cancel stop |
| POST | `/futures/cancel-order-by-client-id` | Sim | 40/s | Cancel by client_id |
| POST | `/futures/cancel-stop-order-by-client-id` | Sim | 40/s | Cancel stop by client_id |
| GET | `/futures/order-status` | Sim | 50/s | Status |
| GET | `/futures/multi-order-status` | Sim | 50/s | Batch status |
| GET | `/futures/pending-order` | Sim | 50/s | Open orders |
| GET | `/futures/finished-order` | Sim | 10/s | Filled orders |
| GET | `/futures/pending-stop-order` | Sim | 50/s | Open stop orders |
| GET | `/futures/finished-stop-order` | Sim | 10/s | Filled stop orders |
| GET | `/futures/user-deals` | Sim | 10/s | Execution history |

### Futures — Position

| Método | Path | Auth | Descrição |
|--------|------|------|-----------|
| GET | `/futures/pending-position` | Sim | Posições abertas |
| GET | `/futures/finished-position` | Sim | Posições históricas |
| POST | `/futures/close-position` | Sim | Fechar posição |
| POST | `/futures/adjust-position-margin` | Sim | Add/remove margin |
| POST | `/futures/adjust-position-leverage` | Sim | Set leverage + margin_mode |
| POST | `/futures/set-position-stop-loss` | Sim | Set SL (até 20 por posição) |
| POST | `/futures/set-position-take-profit` | Sim | Set TP (até 20 por posição) |
| POST | `/futures/modify-position-stop-loss` | Sim | Modify SL |
| POST | `/futures/modify-position-take-profit` | Sim | Modify TP |
| POST | `/futures/cancel-position-stop-loss` | Sim | Cancel SL |
| POST | `/futures/cancel-position-take-profit` | Sim | Cancel TP |
| GET | `/futures/position-margin-history` | Sim | Margin changes |
| GET | `/futures/position-funding-history` | Sim | Funding payments |
| GET | `/futures/position-adl-history` | Sim | ADL events |
| GET | `/futures/position-settle-history` | Sim | Settlements |

### Assets — Balance & Margin

| Método | Path | Auth | Descrição |
|--------|------|------|-----------|
| GET | `/assets/spot/balance` | Sim | Spot balance |
| GET | `/assets/futures/balance` | Sim | Futures balance |
| GET | `/assets/margin/balance` | Sim | Margin balance |
| GET | `/assets/financial/balance` | Sim | Financial balance |
| GET | `/assets/credit/info` | Sim | Credit info |
| GET | `/assets/credit/balance` | Sim | Credit balance |
| GET | `/assets/amm/liquidity` | Sim | AMM liquidity |
| GET | `/assets/spot/transaction-history` | Sim | Transaction history |
| POST | `/assets/margin/borrow` | Sim | Borrow |
| POST | `/assets/margin/repay` | Sim | Repay |
| GET | `/assets/margin/borrow-history` | Sim | Borrow history |
| GET | `/assets/margin/interest-limit` | Sim | Interest rate + limit |

### Assets — Deposit & Withdrawal

| Método | Path | Auth | Descrição |
|--------|------|------|-----------|
| GET | `/assets/deposit-address` | Sim | Deposit address |
| POST | `/assets/update-deposit-address` | Sim | Refresh address |
| GET | `/assets/deposit-history` | Sim | Deposit records |
| POST | `/assets/withdraw` | Sim | Submit withdraw |
| POST | `/assets/cancel-withdraw` | Sim | Cancel withdraw |
| GET | `/assets/withdraw-history` | Sim | Withdraw records |
| GET | `/assets/deposit-withdraw-config` | Não/Sim | Config per coin |
| GET | `/assets/all-deposit-withdraw-config` | Não/Sim | All coin config |
| GET | `/assets/info` | Sim | Coin info |

### Assets — Transfer

| Método | Path | Auth | Descrição |
|--------|------|------|-----------|
| POST | `/assets/transfer` | Sim | Inter-account transfer |
| GET | `/assets/transfer-history` | Sim | Transfer history |

### Account

| Método | Path | Auth | Descrição |
|--------|------|------|-----------|
| GET | `/account/info` `[inferido]` | Sim | Account info |
| GET | `/account/fee-rate` `[inferido]` | Sim | Trading fee rate |
| GET | `/account/sub-account/list` `[inferido]` | Sim | List subaccounts |
| POST | `/account/sub-account/create` `[inferido]` | Sim | Create subaccount |
| POST | `/account/sub-account/transfer` `[inferido]` | Sim | Sub transfer |

> Os endpoints de Account marcados `[inferido]` seguem o padrão da doc mas paths exatos precisam ser confirmados na seção [Account da doc oficial](https://docs.coinex.com/api/v2/) antes de codar.

### WebSocket — Methods

| Tipo | Method | Auth | Descrição |
|------|--------|------|-----------|
| Auth | `server.sign` | — | Sign para canais privados |
| Public | `depth.subscribe` | Não | Order book updates |
| Public | `kline.subscribe` | Não | Candle updates |
| Public | `deals.subscribe` | Não | Trade updates |
| Public | `state.subscribe` | Não | Ticker updates |
| Public | `bbo.subscribe` | Não | Best bid-ask |
| Public | `index.subscribe` (futures) | Não | Index price |
| Public | `funding.subscribe` (futures) | Não | Funding updates |
| Private | `order.subscribe` | Sim | Order updates |
| Private | `asset.subscribe` | Sim | Balance updates |
| Private | `position.subscribe` (futures) | Sim | Position updates |
| Private | `stop.subscribe` | Sim | Stop order updates |

---

## Notas finais para o agente

1. **Pre-trade checklist** (gerado dessa pesquisa):
   - `GET /spot/market?market={pair}` → cachear `base_ccy_precision` e `quote_ccy_precision`
   - Para futures: `GET /futures/market?market={pair}` → cachear `tick_size` + precisions
   - Para futures: chamar `/futures/adjust-position-leverage` antes de abrir posição
   - Validar `min_amount` antes de enviar order

2. **Para SL+TP atômico**: preferir **futures** quando estratégia exigir múltiplos níveis de saída (até 20 TPs por posição em futures).

3. **Para sub-dollar tokens**: SEMPRE usar tipo `decimal` (Scala `BigDecimal`, TypeScript bignumber.js). NUNCA float/double. Casas decimais podem chegar a 8-10 em quote_ccy_precision.

4. **Reconexão WS**: implementar ping a cada 25s + reconnect com backoff exponencial. Re-subscrever todos os canais após reconnect.

5. **Rate limit safety**: manter buffer de 80% do limite oficial — picos esporádicos podem trigger long-cycle penalty que reduz drasticamente cota por 1-24h.

6. **Auditoria de erros**: logar `code` + `message` + payload enviado em toda chamada que falha — códigos 3xxx e 4xxx têm semântica específica documentada.

7. **MiCA EU**: monitorar status de autorização CASP da CoinEx antes de 2026-07-01 caso o agente tenha usuários UE.

8. **Hack 2023 contexto**: a CoinEx melhorou security pós-incidente mas hot wallets continuam sendo vetor. Recomendação: limitar saldo na exchange ao necessário operacional + saques periódicos para cold storage.

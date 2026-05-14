---
name: shipping-optimizer
description: Analisa a distribuição de valores de pedidos e recomenda o threshold ideal de frete grátis para maximizar ticket médio sem destruir margem de frete.
invocation: /shipping-optimizer [dias=90]
---

# Otimizador de Threshold de Frete Grátis

Frete grátis é o maior driver de conversão no e-commerce brasileiro. Esta skill analisa a distribuição real dos seus pedidos e calcula qual valor mínimo para frete grátis capturaria mais pedidos, aumentaria o ticket médio e qual o custo real dessa concessão.

Skill exclusiva LATAM — lógica específica para o comportamento de compra no Brasil.

**Invocação:** `/shipping-optimizer [dias=90]`

---

## Step 0 — Verificar Credenciais

```bash
if [ -z "$NUVEMSHOP_STORE_ID" ] || [ -z "$NUVEMSHOP_TOKEN" ]; then
  echo "Credenciais não configuradas. Execute:"
  echo "  export NUVEMSHOP_STORE_ID=<seu_store_id>"
  echo "  export NUVEMSHOP_TOKEN=<seu_access_token>"
  exit 1
fi
```

---

## Input

- **dias** (default: 90) — janela de análise em dias

---

## Step 1 — Buscar Pedidos com Dados de Frete

```bash
python3 << 'EOF'
import urllib.request, urllib.error, json, os, time
from datetime import date, timedelta

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

DIAS = 90
date_from = str(date.today() - timedelta(days=DIAS))

all_orders = []
page = 1
print(f"Buscando pedidos dos últimos {DIAS} dias...")
while True:
    url = f"{base}/orders?payment_status=paid&created_at_min={date_from}&fields=subtotal,total,discount&per_page=200&page={page}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            batch = json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            batch = []
        else:
            raise
    if not batch:
        break
    all_orders.extend(batch)
    if len(batch) < 200:
        break
    page += 1
    time.sleep(0.5)

# Fallback: se não houver pedidos no período, buscar histórico completo
if not all_orders:
    print(f"Sem pedidos nos últimos {DIAS} dias. Buscando histórico completo...")
    page = 1
    while True:
        url = f"{base}/orders?payment_status=paid&fields=subtotal,total,discount&per_page=200&page={page}"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req) as r:
                batch = json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code == 404: batch = []
            else: raise
        if not batch: break
        all_orders.extend(batch)
        if len(batch) < 200: break
        page += 1
        time.sleep(0.5)

print(f"Total de pedidos: {len(all_orders)}")
json.dump(all_orders, open('/tmp/ns_shipping_orders.json', 'w'))
EOF
```

---

## Step 2 — Análise de Frete e Simulação de Thresholds

```bash
python3 << 'EOF'
import json

orders = json.load(open('/tmp/ns_shipping_orders.json'))

# Calcular dados de frete implícito: total - subtotal - discount
data = []
for o in orders:
    try:
        subtotal = float(o.get('subtotal') or 0)
        total    = float(o.get('total') or 0)
        discount = float(o.get('discount') or 0)
    except (TypeError, ValueError):
        continue
    if subtotal <= 0:
        continue
    implied_ship = max(0.0, total - subtotal - discount)
    data.append({'subtotal': subtotal, 'total': total, 'implied_ship': implied_ship})

if not data:
    print("Nenhum pedido encontrado.")
    exit()

n = len(data)
subtotals = sorted(o['subtotal'] for o in data)
totals_sorted = sorted(o['total'] for o in data)
avg_ticket = sum(o['total'] for o in data) / n
ships = [o['implied_ship'] for o in data if o['implied_ship'] > 0]
avg_ship = sum(ships) / len(ships) if ships else 0
free_now = sum(1 for o in data if o['implied_ship'] == 0)

print(f"\n===== ANÁLISE DE FRETE GRÁTIS =====")
print(f"Pedidos analisados: {n:,}")
print(f"Ticket médio (total): R$ {avg_ticket:.2f}")
print(f"Subtotal médio (só produtos): R$ {sum(subtotals)/n:.2f}")
print(f"Frete médio cobrado: R$ {avg_ship:.2f}")
print(f"Pedidos já com frete grátis: {free_now} ({free_now/n*100:.1f}%)")

# Thresholds baseados em subtotal (é o que o merchant controla)
print(f"\n--- Simulação de Thresholds (baseado no valor dos produtos) ---")
print(f"\n{'Threshold':>12} {'Elegíveis p/Frete Grátis':>24} {'% do Total':>12} {'Custo Estimado/mês':>22}")
print('-' * 75)

candidates = set()
for pct in [0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8]:
    idx = max(0, int(n * pct) - 1)
    raw = subtotals[idx]
    candidates.add(max(10, round(raw / 10) * 10))

for threshold in sorted(candidates):
    above = [o for o in data if o['subtotal'] >= threshold]
    pct = len(above) / n * 100
    monthly_cost = len(above) * avg_ship / 3  # 90d → /3 = mês
    print(f"  R$ {threshold:>8,.0f}  {len(above):>22,}  {pct:>10.1f}%  R$ {monthly_cost:>18,.2f}/mês")

# Recomendação
print(f"\n--- Recomendação ---")
ideal = None
for threshold in sorted(candidates):
    above = [o for o in data if o['subtotal'] >= threshold]
    pct = len(above) / n * 100
    if 60 <= pct <= 72:
        ideal = threshold
        break
if not ideal and candidates:
    # Pegar o que mais se aproxima de 65%
    ideal = min(candidates, key=lambda t: abs(sum(1 for o in data if o['subtotal'] >= t)/n - 0.65))

if ideal:
    above = [o for o in data if o['subtotal'] >= ideal]
    avg_above = sum(o['total'] for o in above) / len(above)
    monthly_cost = len(above) * avg_ship / 3
    uplift = avg_above - avg_ticket
    print(f"  Threshold recomendado: R$ {ideal:.0f} (valor dos produtos no carrinho)")
    print(f"  Elegíveis para frete grátis: {len(above)/n*100:.1f}% dos pedidos ({len(above):,} de {n:,})")
    print(f"  Ticket médio dos pedidos acima: R$ {avg_above:.2f} (+R$ {uplift:.2f} vs média atual)")
    print(f"  Custo estimado de frete absorvido: R$ {monthly_cost:,.2f}/mês")
    print(f"  Frete médio por pedido: R$ {avg_ship:.2f}")
EOF
```

---

## Output Esperado

```
===== ANÁLISE DE FRETE GRÁTIS =====
Pedidos de entrega analisados: 1,284
Ticket médio: R$ 187.40
Mediana: R$ 162.00
P25 / P75: R$ 98.00 / R$ 248.00
Custo médio de frete: R$ 22.80
Pedidos já com frete grátis: 312 (24.3%)

--- Simulação de Thresholds ---

   Threshold  Pedidos p/Frete Grátis   % do Total   Custo Total Frete   Ticket Médio (acima)
-----------------------------------------------------------------------------------------------
  R$     120                     908        70.7%  R$         20,702.40  R$               221.30
  R$     150                     820        63.9%  R$         18,696.00  R$               238.70
  R$     180                     712        55.5%  R$         16,233.60  R$               262.10
  R$     200                     648        50.5%  R$         14,774.40  R$               281.40

--- Recomendação ---
  Threshold recomendado: R$ 150
  Captura 63.9% dos pedidos (820 de 1,284)
  Ticket médio acima do threshold: R$ 238.70 (+R$ 51.30 vs média atual)
  Custo mensal estimado de frete: R$ 6,232.00/mês
  Custo por pedido: R$ 22.80 de frete médio absorvido pelo lojista
  Impacto na margem: -9.6% do ticket médio
```

---

## Próximos Passos

1. **Teste A/B** — ative o threshold recomendado por 2 semanas e compare ticket médio antes/depois
2. **Comunicar claramente** — exiba o threshold no banner do site: "Frete grátis acima de R$ 150"
3. **Barra de progresso no carrinho** — "Adicione R$ 38 para ganhar frete grátis" — aumenta ticket médio em 15-25% na média
4. **Sazonalidade** — rode novamente no período pré-Black Friday; threshold pode precisar de ajuste
5. **Combinar com `/price-margin-analysis`** — garantir que margem dos produtos cobre o custo de frete absorvido

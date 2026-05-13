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
import urllib.request, json, os, time
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
    url = f"{base}/orders?payment_status=paid&created_at_min={date_from}&fields=total,shipping_cost_customer,shipping_cost_owner,shipping_pickup_type&per_page=200&page={page}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as r:
        batch = json.loads(r.read())
    if not batch:
        break
    all_orders.extend(batch)
    if len(batch) < 200:
        break
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
from collections import defaultdict

orders = json.load(open('/tmp/ns_shipping_orders.json'))

# Filtrar apenas pedidos com entrega (não retirada)
delivery_orders = []
for o in orders:
    if o.get('shipping_pickup_type') == 'pickup':
        continue
    try:
        total = float(o.get('total', 0) or 0)
        shipping_customer = float(o.get('shipping_cost_customer', 0) or 0)
        shipping_owner    = float(o.get('shipping_cost_owner', 0) or 0)
    except (TypeError, ValueError):
        continue
    if total > 0:
        delivery_orders.append({
            'total': total,
            'shipping_customer': shipping_customer,
            'shipping_owner': shipping_owner,
            'paid_shipping': shipping_customer > 0
        })

if not delivery_orders:
    print("Nenhum pedido de entrega encontrado.")
    exit()

totals = sorted([o['total'] for o in delivery_orders])
n = len(delivery_orders)
avg_ticket = sum(totals) / n
median_ticket = totals[n // 2]
p25 = totals[n // 4]
p75 = totals[3 * n // 4]

avg_shipping_cost = sum(o['shipping_owner'] for o in delivery_orders if o['shipping_owner'] > 0)
count_with_cost = sum(1 for o in delivery_orders if o['shipping_owner'] > 0)
avg_shipping_cost = avg_shipping_cost / count_with_cost if count_with_cost > 0 else 0

# Pedidos que já recebem frete grátis
free_shipping_now = sum(1 for o in delivery_orders if not o['paid_shipping'])

print(f"\n===== ANÁLISE DE FRETE GRÁTIS =====")
print(f"Pedidos de entrega analisados: {n:,}")
print(f"Ticket médio: R$ {avg_ticket:.2f}")
print(f"Mediana: R$ {median_ticket:.2f}")
print(f"P25 / P75: R$ {p25:.2f} / R$ {p75:.2f}")
print(f"Custo médio de frete (quando pago pelo lojista): R$ {avg_shipping_cost:.2f}")
print(f"Pedidos já com frete grátis: {free_shipping_now} ({free_shipping_now/n*100:.1f}%)")

# Simular thresholds
print(f"\n--- Simulação de Thresholds ---")
print(f"\n{'Threshold':>12} {'Pedidos p/Frete Grátis':>22} {'% do Total':>12} {'Custo Total Frete':>20} {'Ticket Médio (acima)':>22}")
print('-' * 95)

# Candidatos inteligentes: percentis e valores redondos próximos
candidates = set()
for pct in [0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8]:
    raw = totals[int(n * pct)]
    # Arredondar para múltiplo de 10 mais próximo
    candidates.add(round(raw / 10) * 10)

for threshold in sorted(candidates):
    above = [o for o in delivery_orders if o['total'] >= threshold]
    pct = len(above) / n * 100
    total_freight_cost = len(above) * avg_shipping_cost
    avg_above = sum(o['total'] for o in above) / len(above) if above else 0

    print(f"  R$ {threshold:>8,.0f}  {len(above):>20,}  {pct:>10.1f}%  R$ {total_freight_cost:>16,.2f}  R$ {avg_above:>19,.2f}")

# Recomendação automática
print(f"\n--- Recomendação ---")
# Buscar threshold que captura ~65-70% dos pedidos com custo razoável
ideal = None
for threshold in sorted(candidates):
    above = [o for o in delivery_orders if o['total'] >= threshold]
    pct = len(above) / n * 100
    if 60 <= pct <= 72:
        ideal = threshold
        break

if ideal:
    above = [o for o in delivery_orders if o['total'] >= ideal]
    extra_cost = len(above) * avg_shipping_cost
    avg_above = sum(o['total'] for o in above) / len(above)
    uplift = avg_above - avg_ticket
    print(f"  Threshold recomendado: R$ {ideal:.0f}")
    print(f"  Captura {len(above)/n*100:.1f}% dos pedidos ({len(above):,} de {n:,})")
    print(f"  Ticket médio acima do threshold: R$ {avg_above:.2f} (+R$ {uplift:.2f} vs média atual)")
    print(f"  Custo mensal estimado de frete: R$ {extra_cost/3:,.2f}/mês (baseado em 90d)")
    print(f"  Custo por pedido: R$ {avg_shipping_cost:.2f} de frete médio absorvido pelo lojista")
    margin_impact = avg_shipping_cost / avg_above * 100
    print(f"  Impacto na margem: -{margin_impact:.1f}% do ticket médio")
else:
    print(f"  Experimente threshold entre R$ {p75:.0f} e R$ {p75*1.1:.0f} para capturar os 70% maiores pedidos")
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

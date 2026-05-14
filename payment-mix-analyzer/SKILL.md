---
name: payment-mix-analyzer
description: Compara CVR e ticket médio por meio de pagamento (PIX, boleto, cartão parcelado) nos últimos N dias. Skill exclusiva LATAM.
invocation: /payment-mix-analyzer [dias=90]
---

# Analisador PIX vs Parcelamento

Compara volume, ticket médio e participação no GMV por meio de pagamento nos últimos N dias. Identifica qual mix de pagamento está convertendo mais e onde há oportunidade (ex: promover PIX, ajustar parcelas disponíveis).

Skill exclusiva LATAM — sem equivalente no ecossistema Shopify/EUA.

**Invocação:** `/payment-mix-analyzer [dias=90]`

---

## Step 0 — Verificar Credenciais

```bash
if [ -z "$NUVEMSHOP_STORE_ID" ] || [ -z "$NUVEMSHOP_TOKEN" ]; then
  echo "Credenciais não configuradas. Execute:"
  echo "  export NUVEMSHOP_STORE_ID=<seu_store_id>"
  echo "  export NUVEMSHOP_TOKEN=<seu_access_token>"
  echo "Como obter: Admin da loja > Potencializar > Aplicativos sob medida"
  exit 1
fi
```

---

## Input

- **dias** (default: 90) — janela de análise em dias a partir de hoje

---

## Step 1 — Buscar Pedidos Pagos

```bash
BASE="https://api.tiendanube.com/2025-03/$NUVEMSHOP_STORE_ID"
DIAS=90
DATE_FROM=$(python3 -c "from datetime import date, timedelta; print(date.today() - timedelta(days=$DIAS))")

python3 << EOF
import urllib.request, urllib.error, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {
    'Authentication': f"bearer {token}",
    'User-Agent': 'ClaudeSkill (contato@loja.com)'
}

all_orders = []
page = 1

while True:
    url = f"{base}/orders?payment_status=paid&created_at_min=$DATE_FROM&fields=total,payment_details,created_at&per_page=200&page={page}"
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
    print(f"  Página {page}: {len(batch)} pedidos (total: {len(all_orders)})")
    if len(batch) < 200:
        break
    page += 1
    time.sleep(0.5)

json.dump(all_orders, open('/tmp/ns_orders_payment.json', 'w'))
print(f"Total de pedidos pagos: {len(all_orders)}")
EOF
```

---

## Step 2 — Análise por Meio de Pagamento

```bash
python3 << 'EOF'
import json
from collections import defaultdict

orders = json.load(open('/tmp/ns_orders_payment.json'))

groups = defaultdict(lambda: {'count': 0, 'gmv': 0.0})

for o in orders:
    pd = o.get('payment_details', {}) or {}
    method = pd.get('method', 'unknown') or 'unknown'
    installments = pd.get('installments', 1) or 1

    # Agrupar parcelamento em faixas
    if method in ('credit_card', 'cartao', 'card'):
        if installments == 1:
            key = 'Cartão 1x (à vista)'
        elif installments <= 3:
            key = 'Cartão 2-3x'
        elif installments <= 6:
            key = 'Cartão 4-6x'
        else:
            key = f'Cartão 7-{installments}x'
    elif method in ('pix', 'PIX'):
        key = 'PIX'
    elif method in ('boleto', 'boleto_bancario', 'bank_slip'):
        key = 'Boleto Bancário'
    else:
        key = method.replace('_', ' ').title()

    try:
        total = float(o.get('total', 0))
    except (TypeError, ValueError):
        total = 0.0

    groups[key]['count'] += 1
    groups[key]['gmv'] += total

total_orders = len(orders)
total_gmv = sum(g['gmv'] for g in groups.values())

# Ordenar por GMV
sorted_groups = sorted(groups.items(), key=lambda x: x[1]['gmv'], reverse=True)

print(f"\n{'Meio de Pagamento':<25} {'Pedidos':>8} {'% Pedidos':>10} {'GMV (R$)':>14} {'% GMV':>8} {'Ticket Médio':>14}")
print('-' * 85)
for key, data in sorted_groups:
    pct_orders = data['count'] / total_orders * 100 if total_orders else 0
    pct_gmv = data['gmv'] / total_gmv * 100 if total_gmv else 0
    avg_ticket = data['gmv'] / data['count'] if data['count'] else 0
    print(f"{key:<25} {data['count']:>8,} {pct_orders:>9.1f}% {data['gmv']:>13,.2f} {pct_gmv:>7.1f}% {avg_ticket:>13,.2f}")

print('-' * 85)
print(f"{'TOTAL':<25} {total_orders:>8,} {'100.0%':>10} {total_gmv:>13,.2f} {'100.0%':>8} {total_gmv/total_orders:>13,.2f}")

# Insights automáticos
print("\n--- Insights ---")
top = sorted_groups[0][0]
print(f"Meio dominante: {top} ({sorted_groups[0][1]['count']/total_orders*100:.1f}% dos pedidos)")

# Comparar ticket PIX vs parcelado
pix_data = groups.get('PIX', {})
parcelado_data = {k: v for k, v in groups.items() if 'Cartão 4' in k or 'Cartão 7' in k}
if pix_data and parcelado_data:
    pix_avg = pix_data['gmv'] / pix_data['count'] if pix_data['count'] else 0
    parc_total = sum(v['count'] for v in parcelado_data.values())
    parc_gmv = sum(v['gmv'] for v in parcelado_data.values())
    parc_avg = parc_gmv / parc_total if parc_total else 0
    if parc_avg > pix_avg:
        print(f"Ticket parcelado (4x+) é {parc_avg/pix_avg:.1f}x maior que PIX (R$ {parc_avg:.0f} vs R$ {pix_avg:.0f})")
        print("  → Considere oferecer desconto no PIX para aumentar margem em pedidos grandes")
    else:
        print(f"PIX tem ticket similar ou maior que parcelado — bom sinal para oferta de desconto à vista")
EOF
```

---

## Output Esperado

```
Meio de Pagamento         Pedidos  % Pedidos       GMV (R$)    % GMV  Ticket Médio
-------------------------------------------------------------------------------------
Cartão 4-6x                   412      28.3%     82,400.00    35.2%       200.00
PIX                           380      26.1%     57,000.00    24.3%       150.00
Cartão 1x (à vista)           290      19.9%     29,000.00    12.4%       100.00
Boleto Bancário               210      14.4%     21,000.00     9.0%       100.00
Cartão 2-3x                   164      11.3%     44,280.00    18.9%       270.00
-------------------------------------------------------------------------------------
TOTAL                        1456     100.0%    233,680.00   100.0%       160.50

--- Insights ---
Meio dominante: Cartão 4-6x (28.3% dos pedidos)
Ticket parcelado (4x+) é 1.5x maior que PIX (R$ 200 vs R$ 150)
  → Considere oferecer desconto no PIX para aumentar margem em pedidos grandes
```

---

## Próximos Passos

1. **Desconto PIX** — se ticket médio PIX < parcelado: ofereça 5-10% de desconto para PIX e meça impacto
2. **Limitar parcelamento** — se muitos pedidos em 10-12x: analise se margem cobre custo de parcelamento
3. **Período comparativo** — rode novamente com `dias=30` e compare com `dias=90` para ver tendência
4. **Segmentar por categoria** — cruzar meio de pagamento com categoria de produto (tickets altos vs baixos)
5. **Combinar com `/abandonment-analysis`** — ver se taxa de abandono varia por método de pagamento

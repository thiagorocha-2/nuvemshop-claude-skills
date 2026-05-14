---
name: cross-sell-recommender
description: Identifica os 3 melhores cross-sells para cada produto baseado em dados reais de co-compra dos últimos 90 dias.
invocation: /cross-sell-recommender [top_n=20] [dias=90]
---

# Cross-sell por Co-compra

Analisa pedidos reais para descobrir quais produtos são comprados juntos com mais frequência. Gera sugestões de cross-sell para os N produtos mais vendidos — prontas para colar na PDP ou configurar na automação de WhatsApp.

**Invocação:** `/cross-sell-recommender [top_n=20] [dias=90]`

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

- **top_n** (default: 20) — número de produtos âncora para analisar
- **dias** (default: 90) — janela de análise em dias

---

## Step 1 — Buscar Pedidos com Line Items

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
print(f"Buscando pedidos pagos dos últimos {DIAS} dias...")
while True:
    url = f"{base}/orders?payment_status=paid&created_at_min={date_from}&fields=products&per_page=200&page={page}"
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

print(f"Total de pedidos: {len(all_orders)}")
# Filtrar só pedidos com múltiplos produtos (relevante para cross-sell)
multi = [o for o in all_orders if len(o.get('products') or []) > 1]
print(f"Pedidos com 2+ produtos: {len(multi)} ({len(multi)/len(all_orders)*100:.1f}%)")

json.dump(all_orders, open('/tmp/ns_crosssell_orders.json', 'w'))
EOF
```

---

## Step 2 — Calcular Matriz de Co-compra

```bash
python3 << 'EOF'
import json
from collections import defaultdict, Counter
from itertools import combinations

TOP_N = 20  # ajustar conforme input

orders = json.load(open('/tmp/ns_crosssell_orders.json'))

# Mapear product_id -> nome
product_names = {}
for o in orders:
    for p in (o.get('products') or []):
        pid = str(p.get('product_id', ''))
        name = p.get('name', {})
        if isinstance(name, dict):
            name = name.get('pt', name.get('es', pid))
        if pid and pid not in product_names:
            product_names[pid] = str(name)[:50]

# Contar vendas por produto
product_sales = Counter()
for o in orders:
    for p in (o.get('products') or []):
        pid = str(p.get('product_id', ''))
        product_sales[pid] += int(p.get('quantity', 1))

# Top N produtos por volume de vendas
top_products = [pid for pid, _ in product_sales.most_common(TOP_N)]

# Matriz de co-ocorrência
cooccurrence = defaultdict(Counter)  # pid_a -> {pid_b: count}

for o in orders:
    pids = list(set(str(p.get('product_id', '')) for p in (o.get('products') or []) if p.get('product_id')))
    for a, b in combinations(pids, 2):
        cooccurrence[a][b] += 1
        cooccurrence[b][a] += 1

# Gerar recomendações para top produtos
recommendations = {}
for pid in top_products:
    if pid not in cooccurrence:
        continue
    # Excluir o próprio produto
    others = [(p2, count) for p2, count in cooccurrence[pid].most_common(10) if p2 != pid]
    if others:
        total_anchor_orders = product_sales[pid]
        recs = []
        for p2, count in others[:3]:
            pct = count / total_anchor_orders * 100
            recs.append({
                'product_id': p2,
                'name': product_names.get(p2, p2),
                'co_purchases': count,
                'pct_of_anchor_orders': round(pct, 1)
            })
        recommendations[pid] = {
            'name': product_names.get(pid, pid),
            'total_sales': total_anchor_orders,
            'recommendations': recs
        }

json.dump(recommendations, open('/tmp/ns_crosssell_recs.json', 'w'))

# Output formatado
print(f"\n===== RECOMENDAÇÕES DE CROSS-SELL (Top {TOP_N} produtos) =====\n")
for pid, data in recommendations.items():
    print(f"📦 {data['name']:<50} ({data['total_sales']:,} vendas)")
    for r in data['recommendations']:
        print(f"   → {r['name']:<48} {r['co_purchases']:>4}x junto ({r['pct_of_anchor_orders']}% dos pedidos)")
    print()

print(f"Arquivo salvo: /tmp/ns_crosssell_recs.json")
print(f"Use este JSON para configurar 'Produtos Relacionados' no painel Nuvemshop")
EOF
```

---

## Output Esperado

```
===== RECOMENDAÇÕES DE CROSS-SELL (Top 20 produtos) =====

📦 Tênis Running X Branco                          (342 vendas)
   → Meia Esportiva Cano Longo (pack 3)              89x junto (26.0% dos pedidos)
   → Palmilha Amortecedora Premium                   67x junto (19.6% dos pedidos)
   → Garrafa Squeeze 1L                              45x junto (13.2% dos pedidos)

📦 Camiseta Básica Preta                           (289 vendas)
   → Calça Moletom Slim                             112x junto (38.8% dos pedidos)
   → Cinto Elástico Masculino                        54x junto (18.7% dos pedidos)
   → Meias Pack 5 pares                              41x junto (14.2% dos pedidos)

📦 Mochila Urbana 20L Cinza                        (198 vendas)
   → Cadeado Retrátil                                78x junto (39.4% dos pedidos)
   → Capinha de Chuva p/ Mochila                     52x junto (26.3% dos pedidos)
   → Organizador de Cabos                            38x junto (19.2% dos pedidos)
```

---

## Próximos Passos

1. **Configurar na PDP** — acesse "Produtos relacionados" no admin Nuvemshop para cada produto âncora
2. **Post-checkout upsell** — configure automação de WhatsApp pós-compra sugerindo o cross-sell mais forte
3. **Bundle/Kit** — se 2 produtos aparecem juntos em > 30% dos pedidos, crie um kit com desconto
4. **Atualizar trimestral** — co-compras mudam com sazonalidade (ex: verão vs inverno)
5. **Combinar com `/rfm-segmentation`** — sugerir cross-sell específico por segmento RFM

---
name: stockout-predictor
description: Calcula velocity de vendas por SKU nos últimos 30 dias e estima quantos dias de estoque restam. Lista produtos que vão zerar em menos de 14 dias.
invocation: /stockout-predictor [dias_alerta=14]
---

# Previsão de Ruptura de Estoque

Calcula a velocidade de vendas de cada SKU nos últimos 30 dias e estima quantos dias de estoque restam. Gera lista de alerta para produtos que vão zerar antes do threshold definido.

**Invocação:** `/stockout-predictor [dias_alerta=14]`

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

- **dias_alerta** (default: 14) — threshold em dias; produtos com menos que isso entram no alerta

---

## Step 1 — Calcular Velocity de Vendas por Produto

```bash
python3 << 'EOF'
import urllib.request, json, os, time
from datetime import date, timedelta
from collections import defaultdict

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

date_from = str(date.today() - timedelta(days=30))
sold = defaultdict(int)  # product_id -> units sold in 30d

print(f"Calculando velocity de vendas (últimos 30 dias)...")
page = 1
while True:
    url = f"{base}/orders?payment_status=paid&created_at_min={date_from}&fields=products&per_page=200&page={page}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as r:
        batch = json.loads(r.read())
    if not batch:
        break
    for o in batch:
        for p in (o.get('products') or []):
            pid = str(p.get('product_id', ''))
            vid = str(p.get('variant_id', ''))
            key = f"{pid}:{vid}" if vid else pid
            sold[key] += int(p.get('quantity', 1))
    if len(batch) < 200:
        break
    page += 1
    time.sleep(0.5)

# Top produtos por velocity
top_products = sorted(sold.items(), key=lambda x: -x[1])
print(f"Produtos com vendas nos últimos 30d: {len(top_products)}")

json.dump({'sold': dict(sold), 'top': top_products[:100]}, open('/tmp/ns_velocity.json', 'w'))
EOF
```

---

## Step 2 — Buscar Estoque dos Produtos Mais Vendidos

```bash
python3 << 'EOF'
import urllib.request, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

velocity_data = json.load(open('/tmp/ns_velocity.json'))
top_pairs = velocity_data['top']

# Extrair product_ids únicos
product_ids = list(set(pair[0].split(':')[0] for pair in top_pairs))[:100]

print(f"Buscando estoque de {len(product_ids)} produtos...")
products_info = {}

for pid in product_ids:
    url = f"{base}/products/{pid}?fields=id,name,variants"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            p = json.loads(r.read())
        products_info[pid] = p
    except Exception as e:
        print(f"  Erro ao buscar produto {pid}: {e}")
    time.sleep(0.5)  # 2 req/s max

json.dump(products_info, open('/tmp/ns_products_stock.json', 'w'))
print(f"Dados de estoque coletados: {len(products_info)} produtos")
EOF
```

---

## Step 3 — Calcular Dias Restantes e Gerar Alerta

```bash
python3 << 'EOF'
import json
from datetime import date

DIAS_ALERTA = 14  # ajustar conforme input

velocity_data = json.load(open('/tmp/ns_velocity.json'))
products_info = json.load(open('/tmp/ns_products_stock.json'))
sold = velocity_data['sold']

results = []

for pid, p in products_info.items():
    name = p.get('name', {})
    if isinstance(name, dict):
        name = name.get('pt', name.get('es', f'Produto {pid}'))
    
    for v in (p.get('variants') or []):
        vid = str(v.get('id', ''))
        key = f"{pid}:{vid}"
        key_simple = pid
        
        units_sold = sold.get(key, sold.get(key_simple, 0))
        daily_velocity = units_sold / 30.0
        
        stock = v.get('stock')
        stock_managed = v.get('stock_management', False)
        
        if not stock_managed or stock is None:
            continue  # estoque infinito ou não gerenciado
        
        try:
            stock = int(stock)
        except (TypeError, ValueError):
            continue
        
        if daily_velocity > 0:
            days_left = stock / daily_velocity
        elif stock == 0:
            days_left = 0
        else:
            days_left = 999  # sem vendas recentes

        variant_name = ''
        for val in (v.get('values') or []):
            if isinstance(val, dict):
                pt = val.get('pt', val.get('es', ''))
                if pt:
                    variant_name = pt
                    break

        full_name = f"{name} — {variant_name}" if variant_name else name
        
        results.append({
            'name': full_name[:55],
            'pid': pid,
            'vid': vid,
            'stock': stock,
            'sold_30d': units_sold,
            'daily_velocity': round(daily_velocity, 2),
            'days_left': round(days_left, 1)
        })

# Ordenar por urgência
results.sort(key=lambda x: x['days_left'])

# Alertas críticos
critical = [r for r in results if r['days_left'] <= DIAS_ALERTA]
warning  = [r for r in results if DIAS_ALERTA < r['days_left'] <= DIAS_ALERTA * 2]
ok       = [r for r in results if r['days_left'] > DIAS_ALERTA * 2 and r['days_left'] < 999]
zeroed   = [r for r in results if r['days_left'] == 0]

print(f"\n===== PREVISÃO DE RUPTURA DE ESTOQUE =====")
print(f"Threshold de alerta: {DIAS_ALERTA} dias\n")

if zeroed:
    print(f"🔴 ESTOQUE ZERADO AGORA ({len(zeroed)} SKUs):")
    for r in zeroed[:10]:
        print(f"   {r['name']:<55} estoque: 0  ({r['sold_30d']} vendas/30d)")

if critical:
    print(f"\n🔴 RISCO CRÍTICO — menos de {DIAS_ALERTA} dias ({len(critical)} SKUs):")
    print(f"  {'Produto':<55} {'Estoque':>8} {'Vendas/30d':>11} {'Dias Restantes':>15}")
    print('  ' + '-' * 93)
    for r in critical[:20]:
        print(f"  {r['name']:<55} {r['stock']:>8} {r['sold_30d']:>11} {r['days_left']:>15.1f}")

if warning:
    print(f"\n🟡 ATENÇÃO — {DIAS_ALERTA}-{DIAS_ALERTA*2} dias ({len(warning)} SKUs):")
    for r in warning[:10]:
        print(f"  {r['name']:<55} {r['stock']:>8} {r['sold_30d']:>11} {r['days_left']:>15.1f}")

print(f"\nResumo: {len(zeroed)} zerados | {len(critical)} críticos | {len(warning)} em atenção | {len(ok)} OK")
EOF
```

---

## Output Esperado

```
===== PREVISÃO DE RUPTURA DE ESTOQUE =====
Threshold de alerta: 14 dias

🔴 RISCO CRÍTICO — menos de 14 dias (6 SKUs):
  Produto                                                 Estoque  Vendas/30d  Dias Restantes
  -------------------------------------------------------------------------------------------
  Camiseta Básica Preta M                                      18          44             12.3
  Tênis Running X Branco 42                                     8          22             10.9
  Calça Jeans Slim 38                                          24          58              8.7
  Mochila Urbana Cinza                                          3          12              7.5
  Suplemento Whey 1kg Chocolate                                 5          22              6.8
  Fone Bluetooth Pro                                            2          14              4.3

Resumo: 0 zerados | 6 críticos | 12 em atenção | 47 OK
```

---

## Próximos Passos

1. **Pausar anúncios** — para SKUs críticos com menos de 7 dias, pause campanhas antes de zerar
2. **Reposição urgente** — envie lista de críticos ao fornecedor imediatamente
3. **Agendar alerta semanal** — rode toda segunda-feira como parte da rotina operacional
4. **Combinar com `/cross-sell-recommender`** — se SKU vai ficar OOS, identifique substituto para oferecer
5. **Estoque de segurança** — considere aumentar estoque mínimo para SKUs com velocity > 1 unidade/dia

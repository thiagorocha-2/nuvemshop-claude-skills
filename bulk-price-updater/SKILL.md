---
name: bulk-price-updater
description: Atualiza preços e custos em massa com lógica de markup percentual. Resolve o maior pain point de catálogos grandes — o campo de custo enterrado em cada variante. Aplica via API após confirmação.
invocation: /bulk-price-updater [categoria_id=todas] [ajuste_pct=0] [campo=preco|custo|ambos]
---

# Atualizador de Preços e Custos em Massa

O campo de custo na Nuvemshop fica dentro de cada variante individual — impossível de atualizar manualmente em catálogos de 1.000+ variantes. Esta skill busca todos os produtos, exibe a tabela atual de preço/custo/markup e aplica o ajuste proporcional via API após confirmação.

**Invocação:** `/bulk-price-updater [categoria_id=todas] [ajuste_pct=0] [campo=preco|custo|ambos]`

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

- **categoria_id** (default: todas) — filtrar por categoria; use `/product-description-rewriter` para listar IDs
- **ajuste_pct** (default: 0) — percentual de ajuste, ex: `15` para +15%, `-10` para -10%
- **campo** (default: ambos) — `preco` (só price), `custo` (só cost), `ambos` (price + cost proporcionalmente)

**Antes de continuar, confirmar com o merchant:**
> "Qual o ajuste percentual? (ex: +15% para cobrir inflação) E qual campo: preço, custo ou ambos? Posso filtrar por categoria específica ou aplicar em todo o catálogo."

---

## Step 1 — Buscar Todos os Produtos com Variantes

```bash
python3 << 'EOF'
import urllib.request, urllib.error, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

CATEGORIA_ID = None  # substituir por int se filtrar por categoria

all_products = []
page = 1
print("Buscando produtos e variantes...")
while True:
    url = f"{base}/products?published=true&per_page=200&page={page}&fields=id,name,variants"
    if CATEGORIA_ID:
        url += f"&category_id={CATEGORIA_ID}"
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
    all_products.extend(batch)
    if len(batch) < 200:
        break
    page += 1
    time.sleep(0.5)

json.dump(all_products, open('/tmp/ns_bulk_products.json', 'w'))

# Contar variantes
total_variants = sum(len(p.get('variants') or []) for p in all_products)
sem_custo = sum(
    1 for p in all_products
    for v in (p.get('variants') or [])
    if not v.get('cost')
)
print(f"Produtos: {len(all_products)} | Variantes: {total_variants} | Sem custo: {sem_custo}")
EOF
```

---

## Step 2 — Exibir Tabela Atual e Calcular Ajuste

```bash
python3 << 'EOF'
import json

AJUSTE_PCT = 15   # ajustar conforme input do merchant
CAMPO = 'ambos'   # 'preco', 'custo' ou 'ambos'

products = json.load(open('/tmp/ns_bulk_products.json'))

rows = []
for p in products:
    name = p.get('name', {})
    if isinstance(name, dict):
        name = name.get('pt', name.get('es', f"Produto {p['id']}"))

    for v in (p.get('variants') or []):
        try:
            price = float(v.get('price') or 0)
        except (TypeError, ValueError):
            price = 0.0

        try:
            cost = float(v.get('cost') or 0)
        except (TypeError, ValueError):
            cost = 0.0

        if price <= 0:
            continue

        markup = (price - cost) / cost * 100 if cost > 0 else None
        margin = (price - cost) / price * 100 if price > 0 else None

        new_price = round(price * (1 + AJUSTE_PCT / 100), 2) if CAMPO in ('preco', 'ambos') else price
        new_cost  = round(cost  * (1 + AJUSTE_PCT / 100), 2) if CAMPO in ('custo', 'ambos') and cost > 0 else cost

        variant_label = ''
        for val in (v.get('values') or []):
            if isinstance(val, dict):
                pt = val.get('pt', val.get('es', ''))
                if pt:
                    variant_label = pt
                    break

        full_name = f"{str(name)[:40]} — {variant_label}" if variant_label else str(name)[:50]

        rows.append({
            'product_id': p['id'],
            'variant_id': v['id'],
            'name': full_name[:52],
            'price': price,
            'cost': cost,
            'markup': markup,
            'margin': margin,
            'new_price': new_price,
            'new_cost': new_cost,
        })

json.dump(rows, open('/tmp/ns_bulk_updates.json', 'w'))

print(f"\n===== PREVIEW DE AJUSTE — {AJUSTE_PCT:+}% em {CAMPO.upper()} =====\n")
print(f"{'Produto':<52} {'Preço Atual':>12} {'Novo Preço':>11} {'Custo Atual':>12} {'Novo Custo':>11} {'Markup':>7}")
print('-' * 113)

for r in rows[:20]:
    markup_str = f"{r['markup']:.0f}%" if r['markup'] is not None else "—"
    print(f"{r['name']:<52} {r['price']:>12.2f} {r['new_price']:>11.2f} {r['cost']:>12.2f} {r['new_cost']:>11.2f} {markup_str:>7}")

if len(rows) > 20:
    print(f"... e mais {len(rows) - 20} variantes")

print(f"\nTotal de variantes a atualizar: {len(rows)}")
print(f"Variantes sem custo cadastrado: {sum(1 for r in rows if r['cost'] == 0)}")
print(f"\nDeseja aplicar o ajuste em todas as {len(rows)} variantes? (confirme antes do Step 3)")
EOF
```

---

## Step 3 — Aplicar via API (após confirmação)

**Aguardar confirmação do merchant antes de executar este step.**

```bash
python3 << 'EOF'
import json, urllib.request, urllib.error, time, os

BASE = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
TOKEN = os.environ['NUVEMSHOP_TOKEN']
CAMPO = 'ambos'  # ajustar: 'preco', 'custo' ou 'ambos'

rows = json.load(open('/tmp/ns_bulk_updates.json'))

# Agrupar por produto para minimizar chamadas API
from collections import defaultdict
by_product = defaultdict(list)
for r in rows:
    by_product[r['product_id']].append(r)

success, errors = 0, []

for pid, variants in by_product.items():
    # Montar payload de variantes
    variants_payload = []
    for r in variants:
        v = {'id': r['variant_id']}
        if CAMPO in ('preco', 'ambos'):
            v['price'] = str(r['new_price'])
        if CAMPO in ('custo', 'ambos') and r['cost'] > 0:
            v['cost'] = str(r['new_cost'])
        variants_payload.append(v)

    payload = json.dumps({'variants': variants_payload}).encode()
    req = urllib.request.Request(
        f"{BASE}/products/{pid}",
        data=payload,
        method='PUT',
        headers={
            'Authentication': f"bearer {TOKEN}",
            'User-Agent': 'ClaudeSkill (contato@loja.com)',
            'Content-Type': 'application/json'
        }
    )
    try:
        with urllib.request.urlopen(req) as r_resp:
            if r_resp.status == 200:
                success += len(variants)
                name = variants[0]['name'][:40]
                print(f"  ✓ {name} ({len(variants)} variantes)")
    except Exception as e:
        errors.append(f"Produto {pid}: {e}")

    time.sleep(0.6)

print(f"\nResultado: {success} variantes atualizadas, {len(errors)} erros")
if errors:
    for e in errors:
        print(f"  ✗ {e}")
EOF
```

---

## Output Esperado

```
===== PREVIEW DE AJUSTE — +15% em AMBOS =====

Produto                              Preço Atual  Novo Preço  Custo Atual  Novo Custo   Markup
-----------------------------------------------------------------------------------------------------------------
Camiseta Básica Preta — M                  89.90      103.39        45.00       51.75    100%
Camiseta Básica Preta — G                  89.90      103.39        45.00       51.75    100%
Tênis Running X — 42                      349.00      401.35       180.00      207.00     94%
Mochila Urbana — Cinza                    289.00      332.35       140.00      161.00    106%
... e mais 1.392 variantes

Total de variantes a atualizar: 1.396
Variantes sem custo cadastrado: 0

Deseja aplicar o ajuste em todas as 1.396 variantes?
```

---

## Próximos Passos

1. **Rodar `/price-margin-analysis`** após o ajuste para confirmar que margem ficou dentro do target
2. **Filtrar por categoria** — apply inflation adjustment apenas em produtos de fornecedor específico
3. **Ajuste assimétrico** — preço +15% mas custo +12% (aumenta margem) — altere os percentuais individualmente
4. **Salvar planilha antes** — exporte a tabela do Step 2 como CSV para auditoria pré-mudança
5. **Programar revisão trimestral** — rode novamente a cada 3 meses em contexto de inflação alta (AR/BR)

---
name: price-margin-analysis
description: Identifica produtos com desconto 20%+ onde a margem está abaixo de 30%. Detecta desconto empilhado comendo lucro sem crescer volume.
invocation: /price-margin-analysis [desconto_min=20] [margem_max=30]
---

# Análise de Preço + Margem

Detecta produtos onde desconto e margem baixa se combinam de forma perigosa — você está vendendo mais barato E com pouca margem ao mesmo tempo. Requer que o campo `custo` (cost) esteja preenchido nos produtos.

**Invocação:** `/price-margin-analysis [desconto_min=20] [margem_max=30]`

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

- **desconto_min** (default: 20) — desconto mínimo em % para filtrar (promotional_price vs price)
- **margem_max** (default: 30) — margem máxima em % abaixo da qual o produto entra no alerta

**Pré-requisito:** O campo `Custo` deve estar preenchido nos produtos no admin Nuvemshop.

---

## Step 1 — Buscar Todos os Produtos com Variantes

```bash
python3 << 'EOF'
import urllib.request, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

all_products = []
page = 1
print("Buscando produtos...")
while True:
    url = f"{base}/products?published=true&per_page=250&page={page}&fields=id,name,variants"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as r:
        batch = json.loads(r.read())
    if not batch:
        break
    all_products.extend(batch)
    if len(batch) < 250:
        break
    page += 1
    time.sleep(0.5)

print(f"Produtos encontrados: {len(all_products)}")
json.dump(all_products, open('/tmp/ns_products_margin.json', 'w'))
EOF
```

---

## Step 2 — Calcular Desconto e Margem

```bash
python3 << 'EOF'
import json

DESCONTO_MIN = 20  # ajustar conforme input
MARGEM_MAX   = 30  # ajustar conforme input

products = json.load(open('/tmp/ns_products_margin.json'))

alerts = []
sem_custo = 0
sem_desconto = 0
ok_count = 0

for p in products:
    name = p.get('name', {})
    if isinstance(name, dict):
        name = name.get('pt', name.get('es', f"Produto {p['id']}"))

    for v in (p.get('variants') or []):
        try:
            price = float(v.get('price', 0) or 0)
        except (TypeError, ValueError):
            continue
        if price <= 0:
            continue

        promo  = v.get('promotional_price')
        cost   = v.get('cost')

        # Verificar desconto
        if promo is not None:
            try:
                promo = float(promo)
                discount_pct = (price - promo) / price * 100
                effective_price = promo
            except (TypeError, ValueError):
                discount_pct = 0
                effective_price = price
        else:
            discount_pct = 0
            effective_price = price

        # Verificar custo
        if cost is None:
            sem_custo += 1
            continue  # não podemos calcular margem sem custo

        try:
            cost = float(cost)
        except (TypeError, ValueError):
            sem_custo += 1
            continue

        margin_pct = (effective_price - cost) / effective_price * 100 if effective_price > 0 else 0

        variant_label = ''
        for val in (v.get('values') or []):
            if isinstance(val, dict):
                pt = val.get('pt', val.get('es', ''))
                if pt:
                    variant_label = pt
                    break

        full_name = f"{name} — {variant_label}" if variant_label else name

        if discount_pct >= DESCONTO_MIN and margin_pct < MARGEM_MAX:
            alerts.append({
                'name': full_name[:60],
                'price': price,
                'promo': promo or price,
                'cost': cost,
                'discount_pct': round(discount_pct, 1),
                'margin_pct': round(margin_pct, 1),
                'margin_abs': round(effective_price - cost, 2),
                'severity': 'CRÍTICO' if margin_pct < 10 else 'ALTO' if margin_pct < 20 else 'MÉDIO'
            })
        elif discount_pct >= DESCONTO_MIN or margin_pct < MARGEM_MAX:
            ok_count += 1  # só um dos critérios
        else:
            ok_count += 1

# Ordenar por margem (pior primeiro)
alerts.sort(key=lambda x: x['margin_pct'])

print(f"\n===== ANÁLISE DE PREÇO + MARGEM =====")
print(f"Critérios: desconto ≥ {DESCONTO_MIN}% E margem < {MARGEM_MAX}%\n")
print(f"Produtos sem custo preenchido: {sem_custo} (não analisados)")
print(f"Alertas encontrados: {len(alerts)}\n")

if not alerts:
    print("✓ Nenhum produto com desconto alto + margem baixa simultaneamente.")
else:
    print(f"{'Produto':<60} {'Preço':>7} {'Promo':>7} {'Custo':>7} {'Desc%':>7} {'Marg%':>7} {'R$/un':>7} {'Alerta':>8}")
    print('-' * 120)
    for a in alerts:
        print(f"{a['name']:<60} {a['price']:>7.2f} {a['promo']:>7.2f} {a['cost']:>7.2f} {a['discount_pct']:>6.1f}% {a['margin_pct']:>6.1f}% {a['margin_abs']:>7.2f} {a['severity']:>8}")

print(f"\n--- Resumo ---")
criticos = [a for a in alerts if a['severity'] == 'CRÍTICO']
altos    = [a for a in alerts if a['severity'] == 'ALTO']
medios   = [a for a in alerts if a['severity'] == 'MÉDIO']
print(f"  CRÍTICO (margem < 10%): {len(criticos)} SKUs")
print(f"  ALTO (margem 10-20%):   {len(altos)} SKUs")
print(f"  MÉDIO (margem 20-30%):  {len(medios)} SKUs")

if criticos:
    perda = sum(a['promo'] - a['cost'] for a in criticos)
    print(f"\n  ⚠ SKUs críticos estão gerando apenas R$ {perda:.2f} de margem total (pré-frete e impostos)")
    print("  Ação recomendada: remover desconto ou rever custo de aquisição")
EOF
```

---

## Output Esperado

```
===== ANÁLISE DE PREÇO + MARGEM =====
Critérios: desconto ≥ 20% E margem < 30%

Produtos sem custo preenchido: 34 (não analisados)
Alertas encontrados: 8

Produto                                                      Preço   Promo   Custo   Desc%   Marg%   R$/un   Alerta
------------------------------------------------------------------------------------------------------------------------
Fone Bluetooth X — Branco                                   199.90  149.90  148.00   25.0%    1.3%    1.90  CRÍTICO
Tênis Urban Slim 42 — Preto                                 349.00  259.00  250.00   25.8%    3.5%    9.00  CRÍTICO
Mochila Adventure 30L — Cinza                               289.00  219.00  188.00   24.2%   14.2%   31.00     ALTO
Camiseta Dry-Fit P — Verde                                   89.90   69.90   58.00   22.2%   17.0%   11.90     ALTO
```

---

## Próximos Passos

1. **Remover desconto** nos SKUs com margem < 5% — você está pagando pra vender
2. **Renegociar custo** com fornecedor antes de manter desconto alto
3. **Verificar custo real** — inclua frete de entrada, impostos e taxas de marketplace
4. **Preencher custo** nos produtos sem esse campo — rode `/price-margin-analysis` de novo
5. **Monitorar mensalmente** — descontos sazonais (Black Friday, Dia das Mães) podem criar armadilhas temporárias

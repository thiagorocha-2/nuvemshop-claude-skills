---
name: abandonment-analysis
description: Analisa taxa de abandono de checkout e motivos de cancelamento. Identifica quais produtos concentram as perdas e sugere correções.
invocation: /abandonment-analysis [dias=30]
---

# Análise de Abandono e Cancelamento

Analisa por que pedidos falham — taxa de abandono de checkout, motivos de cancelamento, e quais SKUs concentram as perdas. Ajuda a priorizar onde agir primeiro para recuperar receita perdida.

**Invocação:** `/abandonment-analysis [dias=30]`

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

- **dias** (default: 30) — janela de análise em dias a partir de hoje

---

## Step 1 — Buscar Pedidos por Status

```bash
python3 << 'EOF'
import urllib.request, json, os, time
from datetime import date, timedelta

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

DIAS = 30  # ajustar conforme input
date_from = str(date.today() - timedelta(days=DIAS))

def fetch_orders(extra_params, label):
    all_orders = []
    page = 1
    while True:
        url = f"{base}/orders?{extra_params}&created_at_min={date_from}&fields=status,payment_status,cancel_reason,total,products,created_at&per_page=200&page={page}"
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
    print(f"  {label}: {len(all_orders)}")
    return all_orders

print(f"Buscando pedidos desde {date_from}...")
paid     = fetch_orders("payment_status=paid", "Pagos")
abandoned = fetch_orders("payment_status=abandoned", "Abandonados")
cancelled = fetch_orders("status=cancelled", "Cancelados")
pending   = fetch_orders("payment_status=pending", "Aguardando pagamento")

all_data = {
    'paid': paid,
    'abandoned': abandoned,
    'cancelled': cancelled,
    'pending': pending
}
json.dump(all_data, open('/tmp/ns_abandonment.json', 'w'))
EOF
```

---

## Step 2 — Análise Completa

```bash
python3 << 'EOF'
import json
from collections import defaultdict, Counter

data = json.load(open('/tmp/ns_abandonment.json'))

paid      = data['paid']
abandoned = data['abandoned']
cancelled = data['cancelled']
pending   = data['pending']

total = len(paid) + len(abandoned) + len(cancelled) + len(pending)

def gmv(orders):
    return sum(float(o.get('total', 0) or 0) for o in orders)

# --- Funil de Pedidos ---
print("\n===== FUNIL DE PEDIDOS =====")
print(f"{'Status':<28} {'Pedidos':>8} {'% Total':>9} {'GMV (R$)':>14}")
print('-' * 63)
for label, orders in [('Pagos ✓', paid), ('Aguardando pagamento', pending),
                       ('Abandonados ✗', abandoned), ('Cancelados ✗', cancelled)]:
    pct = len(orders) / total * 100 if total else 0
    print(f"{label:<28} {len(orders):>8,} {pct:>8.1f}% {gmv(orders):>13,.2f}")
print('-' * 63)
print(f"{'TOTAL':<28} {total:>8,}   100.0%  {gmv(paid+pending+abandoned+cancelled):>13,.2f}")

# Receita perdida (estimativa)
receita_perdida = gmv(abandoned) + gmv(cancelled)
print(f"\nReceita perdida (abandonos + cancelamentos): R$ {receita_perdida:,.2f}")

# --- Motivos de Cancelamento ---
print("\n===== MOTIVOS DE CANCELAMENTO =====")
reasons = Counter(o.get('cancel_reason', 'não informado') or 'não informado' for o in cancelled)
reason_labels = {
    'customer': 'Solicitado pelo cliente',
    'fraud': 'Fraude detectada',
    'inventory': 'Falta de estoque',
    'other': 'Outros / não informado',
    'não informado': 'Não informado'
}
for reason, count in reasons.most_common():
    label = reason_labels.get(reason, reason)
    pct = count / len(cancelled) * 100 if cancelled else 0
    print(f"  {label:<30} {count:>5} ({pct:.1f}%)")

# --- Produtos Mais Frequentes em Cancelamentos ---
print("\n===== PRODUTOS EM PEDIDOS CANCELADOS (top 10) =====")
prod_cancel = Counter()
for o in cancelled:
    for p in (o.get('products') or []):
        pid = p.get('product_id')
        name = p.get('name', {})
        if isinstance(name, dict):
            name = name.get('pt', name.get('es', str(pid)))
        prod_cancel[(pid, name[:40])] += p.get('quantity', 1)

for (pid, name), qty in prod_cancel.most_common(10):
    print(f"  {name:<40} {qty:>5} unidades canceladas")

# --- Produtos em Pedidos Abandonados ---
print("\n===== PRODUTOS EM CARRINHOS ABANDONADOS (top 10) =====")
prod_abandon = Counter()
for o in abandoned:
    for p in (o.get('products') or []):
        pid = p.get('product_id')
        name = p.get('name', {})
        if isinstance(name, dict):
            name = name.get('pt', name.get('es', str(pid)))
        prod_abandon[(pid, name[:40])] += p.get('quantity', 1)

for (pid, name), qty in prod_abandon.most_common(10):
    print(f"  {name:<40} {qty:>5} unidades em carrinhos abandonados")

# --- Recomendações ---
print("\n===== RECOMENDAÇÕES =====")
abandon_rate = len(abandoned) / (len(paid) + len(abandoned)) * 100 if (paid or abandoned) else 0
print(f"Taxa de abandono: {abandon_rate:.1f}%")
if abandon_rate > 30:
    print("  ⚠ Alta taxa de abandono. Verifique:")
    print("    - Custo de frete aparecendo tarde no checkout")
    print("    - Falta de opções de pagamento populares (PIX, parcelamento)")
    print("    - Processo de cadastro obrigatório")
elif abandon_rate > 15:
    print("  → Taxa moderada. Foque em recuperação via WhatsApp automático")
else:
    print("  ✓ Taxa de abandono saudável (< 15%)")

if reasons.get('inventory', 0) > len(cancelled) * 0.15:
    print("  ⚠ Muitos cancelamentos por estoque. Rode /stockout-predictor para antecipar rupturas")
EOF
```

---

## Output Esperado

```
===== FUNIL DE PEDIDOS =====
Status                       Pedidos   % Total       GMV (R$)
---------------------------------------------------------------
Pagos ✓                          892      67.4%     178,400.00
Aguardando pagamento              98       7.4%       9,800.00
Abandonados ✗                    218      16.5%      32,700.00
Cancelados ✗                     116       8.8%      14,500.00
---------------------------------------------------------------
TOTAL                           1324     100.0%     235,400.00

Receita perdida (abandonos + cancelamentos): R$ 47,200.00

===== MOTIVOS DE CANCELAMENTO =====
  Solicitado pelo cliente          58 (50.0%)
  Falta de estoque                 31 (26.7%)
  Fraude detectada                 18 (15.5%)
  Não informado                     9 (7.8%)
```

---

## Próximos Passos

1. **Recuperação de carrinho** — ative mensagem automática no WhatsApp Business para carrinhos abandonados
2. **Estoque** — se "Falta de estoque" > 20% dos cancelamentos, rode `/stockout-predictor`
3. **Checkout** — revise se frete é exibido antes do cadastro
4. **Período maior** — rode com `dias=90` para separar sazonalidade de tendência estrutural
5. **Combinar com `/payment-mix-analyzer`** — identificar se algum método de pagamento tem mais abandono

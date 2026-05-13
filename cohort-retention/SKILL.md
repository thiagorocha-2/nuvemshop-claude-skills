---
name: cohort-retention
description: Mostra qual % dos clientes que compraram em cada mês voltou a comprar. Identifica qual safra de clientes tem maior retenção.
invocation: /cohort-retention [meses=6]
---

# Analisador de Cohort de Retenção

Agrupa clientes pelo mês em que fizeram a primeira compra (cohort) e calcula quantos voltaram a comprar nos meses seguintes. Identifica se sua retenção está melhorando ou piorando ao longo do tempo.

**Invocação:** `/cohort-retention [meses=6]`

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

- **meses** (default: 6) — quantos meses de histórico analisar

---

## Step 1 — Buscar Todos os Pedidos Pagos

```bash
python3 << 'EOF'
import urllib.request, json, os, time
from datetime import date, timedelta

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

MESES = 6
date_from = str(date.today() - timedelta(days=MESES * 31))

all_orders = []
page = 1
print(f"Buscando pedidos dos últimos {MESES} meses...")
while True:
    url = f"{base}/orders?payment_status=paid&created_at_min={date_from}&fields=customer,created_at&per_page=200&page={page}"
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

print(f"Total de pedidos pagos: {len(all_orders)}")
json.dump(all_orders, open('/tmp/ns_cohort_orders.json', 'w'))
EOF
```

---

## Step 2 — Calcular Cohorts

```bash
python3 << 'EOF'
import json
from datetime import datetime, date
from collections import defaultdict

orders = json.load(open('/tmp/ns_cohort_orders.json'))

# Agrupar pedidos por cliente
customer_orders = defaultdict(list)
for o in orders:
    cust = o.get('customer') or {}
    cid = str(cust.get('id', ''))
    if not cid:
        continue
    dt = datetime.fromisoformat(o['created_at'][:10]).date()
    customer_orders[cid].append(dt)

# Para cada cliente, determinar mês da primeira compra (cohort) e meses subsequentes
cohort_data = defaultdict(lambda: defaultdict(set))  # cohort_month -> month_offset -> set of customers

for cid, dates in customer_orders.items():
    dates.sort()
    first = dates[0]
    first_month = (first.year, first.month)

    cohort_data[first_month][0].add(cid)  # mês 0 = sempre

    for d in dates[1:]:  # pedidos subsequentes
        month_offset = (d.year - first.year) * 12 + (d.month - first.month)
        if month_offset > 0:
            cohort_data[first_month][month_offset].add(cid)

# Ordenar cohorts
sorted_cohorts = sorted(cohort_data.keys())
max_offset = 6

print(f"\n===== RETENÇÃO POR COHORT =====")
print(f"(% de clientes da cohort que fizeram nova compra no mês X)\n")

# Header
header = f"{'Cohort':<12} {'Novos':>6}"
for i in range(1, max_offset + 1):
    header += f" {'M+'+str(i):>6}"
print(header)
print('-' * (12 + 7 + max_offset * 7))

for month in sorted_cohorts[-6:]:  # últimos 6 cohorts
    label = f"{month[0]}-{month[1]:02d}"
    base_count = len(cohort_data[month][0])
    row = f"{label:<12} {base_count:>6}"
    for offset in range(1, max_offset + 1):
        returning = len(cohort_data[month][offset])
        pct = returning / base_count * 100 if base_count > 0 else 0
        if pct > 0:
            row += f" {pct:>5.1f}%"
        else:
            row += f" {'—':>6}"
    print(row)

# Análise de tendência
print(f"\n--- Insights ---")
if len(sorted_cohorts) >= 2:
    recent = sorted_cohorts[-1]
    older  = sorted_cohorts[-3] if len(sorted_cohorts) >= 3 else sorted_cohorts[0]

    recent_m1 = len(cohort_data[recent].get(1, set()))
    recent_m0 = len(cohort_data[recent][0])
    older_m1  = len(cohort_data[older].get(1, set()))
    older_m0  = len(cohort_data[older][0])

    r_pct = recent_m1 / recent_m0 * 100 if recent_m0 > 0 else 0
    o_pct = older_m1  / older_m0  * 100 if older_m0  > 0 else 0

    trend = "melhorando" if r_pct > o_pct else "piorando" if r_pct < o_pct else "estável"
    print(f"  Retenção no M+1: cohort recente {r_pct:.1f}% vs cohort anterior {o_pct:.1f}% → {trend}")

    total_customers = len(customer_orders)
    repeat_customers = sum(1 for dates in customer_orders.values() if len(dates) > 1)
    print(f"  Taxa de recompra geral: {repeat_customers/total_customers*100:.1f}% ({repeat_customers:,} de {total_customers:,} clientes compraram 2+ vezes)")

print(f"\nNota: meses recentes têm menos tempo para acumular recompras — interprete M+1, M+2 com cautela para cohorts dos últimos 2 meses")
EOF
```

---

## Output Esperado

```
===== RETENÇÃO POR COHORT =====
(% de clientes da cohort que fizeram nova compra no mês X)

Cohort        Novos   M+1    M+2    M+3    M+4    M+5    M+6
--------------------------------------------------------------
2025-11         342  12.3%   8.5%   6.1%   4.2%   3.8%   2.9%
2025-12         418  11.7%   7.9%   5.8%   4.0%   3.1%    —
2026-01         389  13.2%   8.1%   6.4%   4.8%    —      —
2026-02         427  14.1%   9.2%   6.9%    —      —      —
2026-03         512  15.8%  10.4%    —      —      —      —
2026-04         498  16.2%    —      —      —      —      —

--- Insights ---
  Retenção no M+1: cohort recente 16.2% vs cohort anterior 12.3% → melhorando
  Taxa de recompra geral: 18.4% (731 de 3,974 clientes compraram 2+ vezes)
```

---

## Próximos Passos

1. **Meta de M+1** — benchmark e-commerce LATAM: M+1 > 15% é bom. Se abaixo, revise comunicação pós-compra
2. **Fluxo de pós-compra** — ative sequência de WhatsApp/email nos dias 7, 14 e 30 após a primeira compra
3. **Segmentar por canal** — se possível, filtre cohorts por canal de aquisição para identificar qual fonte traz clientes mais recorrentes
4. **Combinar com `/rfm-segmentation`** — clientes "Em Risco" são cohorts antigas com retenção caindo
5. **Aumentar janela** — rode com `meses=12` para ver curva de retenção de longo prazo

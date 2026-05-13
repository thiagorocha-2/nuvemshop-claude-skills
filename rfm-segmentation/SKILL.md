---
name: rfm-segmentation
description: Classifica clientes em segmentos RFM (Campeões, Em Risco, Dormentes, etc.) e exporta CSV pronto para WhatsApp Business, RD Station ou HubSpot.
invocation: /rfm-segmentation
---

# Segmentação RFM para WhatsApp

Classifica sua base de clientes em segmentos por **R**ecência (última compra), **F**requência (quantas vezes comprou) e **V**alor (quanto gastou). Exporta CSV pronto para importar no WhatsApp Business, RD Station, HubSpot ou qualquer ferramenta de CRM/automação.

Skill LATAM-first: foco em WhatsApp como canal de reativação, não e-mail.

**Invocação:** `/rfm-segmentation`

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

Nenhum parâmetro necessário. A skill usa janela padrão de 12 meses para RFM.

---

## Step 1 — Buscar Todos os Pedidos (últimos 12 meses)

```bash
python3 << 'EOF'
import urllib.request, json, os, time
from datetime import date, timedelta

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

date_from = str(date.today() - timedelta(days=365))
all_orders = []
page = 1

print(f"Buscando pedidos desde {date_from}...")
while True:
    url = f"{base}/orders?payment_status=paid&created_at_min={date_from}&fields=customer,total,created_at&per_page=200&page={page}"
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

json.dump(all_orders, open('/tmp/ns_rfm_orders.json', 'w'))
print(f"Total de pedidos pagos (12m): {len(all_orders)}")
EOF
```

---

## Step 2 — Buscar Dados dos Clientes

```bash
python3 << 'EOF'
import urllib.request, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

all_customers = []
page = 1

print("Buscando clientes...")
while True:
    url = f"{base}/customers?fields=id,name,email,phone,total_spent,accepts_marketing&per_page=250&page={page}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as r:
        batch = json.loads(r.read())
    if not batch:
        break
    all_customers.extend(batch)
    if len(batch) < 250:
        break
    page += 1
    time.sleep(0.5)

json.dump(all_customers, open('/tmp/ns_rfm_customers.json', 'w'))
print(f"Total de clientes: {len(all_customers)}")
EOF
```

---

## Step 3 — Calcular RFM e Gerar Segmentos

```bash
python3 << 'EOF'
import json, csv, os
from datetime import date, datetime
from collections import defaultdict

orders = json.load(open('/tmp/ns_rfm_orders.json'))
customers_list = json.load(open('/tmp/ns_rfm_customers.json'))
customers = {str(c['id']): c for c in customers_list}

today = date.today()

# Agregar pedidos por cliente
rfm_data = defaultdict(lambda: {'last_order': None, 'count': 0, 'total': 0.0})

for o in orders:
    cust = o.get('customer') or {}
    cid = str(cust.get('id', ''))
    if not cid:
        continue
    order_date = datetime.fromisoformat(o['created_at'][:10]).date()
    if rfm_data[cid]['last_order'] is None or order_date > rfm_data[cid]['last_order']:
        rfm_data[cid]['last_order'] = order_date
    rfm_data[cid]['count'] += 1
    try:
        rfm_data[cid]['total'] += float(o.get('total', 0))
    except (TypeError, ValueError):
        pass

# Calcular percentis para scoring
totals = sorted([d['total'] for d in rfm_data.values()])
p25 = totals[len(totals)//4] if totals else 0
p75 = totals[3*len(totals)//4] if totals else 0

def classify(cid, data):
    days_since = (today - data['last_order']).days if data['last_order'] else 999
    freq = data['count']
    val = data['total']

    # Segmentação RFM simplificada
    if days_since <= 30 and freq >= 3 and val >= p75:
        return 'Campeão'
    elif days_since <= 60 and freq >= 2:
        return 'Cliente Fiel'
    elif days_since <= 30 and freq == 1:
        return 'Novo Cliente'
    elif days_since > 90 and freq >= 2:
        return 'Em Risco'
    elif days_since > 180 and freq == 1:
        return 'Dormente'
    elif days_since > 90 and freq == 1:
        return 'Precisa Atenção'
    else:
        return 'Em Desenvolvimento'

rows = []
segment_counts = defaultdict(int)

for cid, data in rfm_data.items():
    segment = classify(cid, data)
    segment_counts[segment] += 1
    cust = customers.get(cid, {})
    name = cust.get('name', '')
    email = cust.get('email', '')
    phone = cust.get('phone', '')
    accepts = cust.get('accepts_marketing', False)
    days_since = (today - data['last_order']).days if data['last_order'] else 999

    rows.append({
        'customer_id': cid,
        'nome': name,
        'email': email,
        'telefone': phone,
        'accepts_marketing': 'sim' if accepts else 'não',
        'segmento': segment,
        'ultima_compra_dias': days_since,
        'num_pedidos': data['count'],
        'total_gasto': f"{data['total']:.2f}"
    })

# Exportar CSV
output_path = os.path.expanduser('~/Downloads/rfm_segmentation.csv')
with open(output_path, 'w', newline='', encoding='utf-8-sig') as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

# Resumo
print(f"\n{'Segmento':<25} {'Clientes':>10} {'% Base':>8}")
print('-' * 47)
total = len(rows)
for seg, count in sorted(segment_counts.items(), key=lambda x: -x[1]):
    print(f"{seg:<25} {count:>10,} {count/total*100:>7.1f}%")
print('-' * 47)
print(f"{'TOTAL':<25} {total:>10,}   100.0%")
print(f"\nArquivo exportado: {output_path}")
print(f"Clientes com telefone: {sum(1 for r in rows if r['telefone'])}")
print(f"Com opt-in marketing: {sum(1 for r in rows if r['accepts_marketing']=='sim')}")
EOF
```

---

## Output Esperado

```
Segmento                  Clientes    % Base
-----------------------------------------------
Cliente Fiel                  1,240    31.2%
Em Desenvolvimento            1,180    29.7%
Precisa Atenção                 640    16.1%
Em Risco                        490    12.3%
Campeão                         218     5.5%
Dormente                        142     3.6%
Novo Cliente                     64     1.6%
-----------------------------------------------
TOTAL                         3,974   100.0%

Arquivo exportado: ~/Downloads/rfm_segmentation.csv
Clientes com telefone: 2,891
Com opt-in marketing: 1,432
```

---

## Sugestões de Campanha por Segmento

| Segmento | Ação Recomendada | Canal |
|----------|-----------------|-------|
| Campeão | Programa VIP, acesso antecipado a lançamentos | WhatsApp pessoal |
| Em Risco | "Sentimos sua falta" + cupom 15% | WhatsApp + Email |
| Dormente | Oferta agressiva 25% ou reativação por frete grátis | Email / SMS |
| Novo Cliente | Onboarding: próxima compra 10% off | WhatsApp automação |
| Cliente Fiel | Cross-sell baseado em histórico | WhatsApp |

---

## Próximos Passos

1. **Importar no WhatsApp Business** — filtrar CSV por `telefone` não vazio + `accepts_marketing=sim`
2. **Importar no RD Station/HubSpot** — usar campo `segmento` para criar listas dinâmicas
3. **Rodar mensalmente** — segmentos mudam; recomendado re-executar todo mês
4. **Combinar com `/cross-sell-recommender`** — personalizar oferta por segmento com produto certo
5. **Focar nos "Em Risco"** — são ex-compradores ativos; menor CAC de recuperação

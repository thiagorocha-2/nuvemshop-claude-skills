---
name: daily-digest
description: Briefing executivo diário da loja — GMV da semana vs semana anterior, pedidos pendentes, SKUs críticos, cancelamentos recentes. Tudo em uma chamada, em 30 segundos.
invocation: /daily-digest
---

# Daily Digest — Briefing Executivo Diário

Briefing completo da loja que você lê em 30 segundos toda manhã. GMV desta semana vs semana passada, pedidos em risco, estoque crítico, cancelamentos — tudo agregado em uma única chamada sem precisar abrir o admin.

**Invocação:** `/daily-digest`

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

Nenhum parâmetro necessário. Analisa automaticamente os últimos 14 dias comparando semana atual com semana anterior.

---

## Step 1 — Coletar Dados (pedidos + estoque)

```bash
python3 << 'EOF'
import urllib.request, urllib.error, json, os, time
from datetime import date, timedelta
from collections import defaultdict, Counter

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

today = date.today()
week_start = today - timedelta(days=today.weekday())  # segunda-feira desta semana
prev_week_start = week_start - timedelta(days=7)
date_from_14d = str(today - timedelta(days=14))

def fetch(params, label):
    results = []
    page = 1
    while True:
        url = f"{base}/orders?{params}&per_page=200&page={page}"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req) as r:
                batch = json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code == 404: batch = []
            else: raise
        if not batch: break
        results.extend(batch)
        if len(batch) < 200: break
        page += 1
        time.sleep(0.4)
    return results

# Pedidos pagos (14 dias)
paid = fetch(
    f"payment_status=paid&created_at_min={date_from_14d}"
    f"&fields=total,created_at,products",
    "pagos"
)

# Pedidos pendentes
pending = fetch(
    f"payment_status=pending&created_at_min={date_from_14d}"
    f"&fields=total,created_at",
    "pendentes"
)

# Cancelamentos recentes (7 dias)
date_from_7d = str(today - timedelta(days=7))
cancelled = fetch(
    f"status=cancelled&created_at_min={date_from_7d}"
    f"&fields=total,created_at,cancel_reason,products",
    "cancelados"
)

# Produtos com velocity + estoque crítico
products_raw = []
page = 1
while True:
    url = f"{base}/products?published=true&per_page=200&page={page}&fields=id,name,variants"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            batch = json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404: batch = []
        else: raise
    if not batch: break
    products_raw.extend(batch)
    if len(batch) < 200: break
    page += 1
    time.sleep(0.4)

json.dump({
    'paid': paid,
    'pending': pending,
    'cancelled': cancelled,
    'products': products_raw,
    'today': str(today),
    'week_start': str(week_start),
    'prev_week_start': str(prev_week_start),
}, open('/tmp/ns_digest.json', 'w'))

print(f"Dados coletados: {len(paid)} pagos | {len(pending)} pendentes | {len(cancelled)} cancelados | {len(products_raw)} produtos")
EOF
```

---

## Step 2 — Gerar Briefing

```bash
python3 << 'EOF'
import json
from datetime import date, datetime
from collections import defaultdict, Counter

data = json.load(open('/tmp/ns_digest.json'))
paid      = data['paid']
pending   = data['pending']
cancelled = data['cancelled']
products  = data['products']
today_str = data['today']
week_start_str = data['week_start']
prev_week_start_str = data['prev_week_start']

today          = datetime.strptime(today_str, '%Y-%m-%d').date()
week_start     = datetime.strptime(week_start_str, '%Y-%m-%d').date()
prev_week_start = datetime.strptime(prev_week_start_str, '%Y-%m-%d').date()

def order_date(o):
    return datetime.fromisoformat(o['created_at'][:10]).date()

def gmv(orders):
    return sum(float(o.get('total') or 0) for o in orders)

# Semana atual vs semana anterior
this_week  = [o for o in paid if order_date(o) >= week_start]
last_week  = [o for o in paid if prev_week_start <= order_date(o) < week_start]

gmv_this  = gmv(this_week)
gmv_last  = gmv(last_week)
gmv_delta = ((gmv_this - gmv_last) / gmv_last * 100) if gmv_last > 0 else 0
delta_sym  = '▲' if gmv_delta >= 0 else '▼'
delta_color = '+' if gmv_delta >= 0 else ''

# Top produtos (semana atual)
prod_sales = Counter()
prod_names = {}
for o in this_week:
    for p in (o.get('products') or []):
        pid = str(p.get('product_id', ''))
        name = p.get('name', {})
        if isinstance(name, dict): name = name.get('pt', name.get('es', pid))
        prod_sales[pid] += p.get('quantity', 1)
        prod_names[pid] = str(name)[:40]

# Estoque crítico (produtos com stock_management=true e stock <= 5 com alguma venda)
stock_alerts = []
for p in products:
    pname = p.get('name', {})
    if isinstance(pname, dict): pname = pname.get('pt', pname.get('es', ''))
    for v in (p.get('variants') or []):
        if not v.get('stock_management'): continue
        try:
            stock = int(v.get('stock') or 0)
        except (TypeError, ValueError):
            stock = 0
        if stock <= 5:
            vlabel = ''
            for val in (v.get('values') or []):
                if isinstance(val, dict):
                    pt = val.get('pt', val.get('es', ''))
                    if pt: vlabel = pt; break
            label = f"{str(pname)[:35]} — {vlabel}" if vlabel else str(pname)[:45]
            stock_alerts.append((label, stock))

stock_alerts.sort(key=lambda x: x[1])

# Cancelamentos por motivo
cancel_reasons = Counter(o.get('cancel_reason') or 'não informado' for o in cancelled)
reason_labels = {'customer': 'cliente', 'fraud': 'fraude', 'inventory': 'estoque',
                 'other': 'outros', 'refund': 'reembolso', 'não informado': 'sem motivo'}

# GMV pendente em risco
pending_gmv = gmv(pending)

# OUTPUT
print(f"\n{'=' * 55}")
print(f"  DAILY DIGEST — {today.strftime('%A, %d/%m/%Y').upper()}")
print(f"{'=' * 55}\n")

# GMV
print(f"📊 GMV DESTA SEMANA")
print(f"   R$ {gmv_this:,.2f}  {delta_sym} {delta_color}{gmv_delta:.1f}% vs semana passada")
print(f"   ({len(this_week)} pedidos pagos | semana passada: R$ {gmv_last:,.2f}, {len(last_week)} pedidos)\n")

# Top produtos
if prod_sales:
    print(f"🏆 TOP PRODUTOS (semana)")
    for pid, qty in prod_sales.most_common(5):
        print(f"   {prod_names.get(pid, pid):<42} {qty:>4} un.")
    print()

# Pendentes
if pending:
    print(f"⏳ PAGAMENTOS PENDENTES")
    print(f"   {len(pending)} pedidos aguardando pagamento — R$ {pending_gmv:,.2f} em risco")
    print(f"   → Ative recuperação via WhatsApp para recuperar parte desse valor\n")

# Cancelamentos
if cancelled:
    top_reason = cancel_reasons.most_common(1)[0]
    reason_str = reason_labels.get(top_reason[0], top_reason[0])
    print(f"❌ CANCELAMENTOS (últimos 7 dias)")
    print(f"   {len(cancelled)} cancelamentos | Principal motivo: {reason_str} ({top_reason[1]}x)")
    cancel_gmv = gmv(cancelled)
    print(f"   Receita perdida: R$ {cancel_gmv:,.2f}\n")

# Estoque crítico
if stock_alerts:
    print(f"⚠️  ESTOQUE CRÍTICO (≤ 5 unidades)")
    for label, stock in stock_alerts[:8]:
        status = "ZERADO" if stock == 0 else f"{stock} un."
        indicator = "🔴" if stock == 0 else "🟡"
        print(f"   {indicator} {label:<48} {status}")
    if len(stock_alerts) > 8:
        print(f"   ... e mais {len(stock_alerts) - 8} SKUs")
    print()

# Recomendações automáticas
print(f"💡 AÇÕES RECOMENDADAS HOJE")
if gmv_delta < -10:
    print(f"   1. GMV caiu {abs(gmv_delta):.1f}% — verifique se há produtos fora do ar ou problemas no checkout")
if stock_alerts:
    zeros = [s for s in stock_alerts if s[1] == 0]
    if zeros:
        print(f"   {'2' if gmv_delta < -10 else '1'}. {len(zeros)} SKU(s) com estoque zerado publicado — repor ou despublicar")
if pending_gmv > gmv_this * 0.3:
    print(f"   {'3' if stock_alerts else '2'}. Pagamentos pendentes = {pending_gmv/gmv_this*100:.0f}% do GMV desta semana — ative recuperação WhatsApp")

print(f"\n{'=' * 55}")
EOF
```

---

## Output Esperado

```
=======================================================
  DAILY DIGEST — QUARTA-FEIRA, 14/05/2026
=======================================================

📊 GMV DESTA SEMANA
   R$ 12.840,00  ▲ +18.3% vs semana passada
   (87 pedidos pagos | semana passada: R$ 10.853,00, 74 pedidos)

🏆 TOP PRODUTOS (semana)
   Camiseta Básica Preta                                28 un.
   Tênis Running X Branco 42                            19 un.
   Mochila Urbana Cinza                                 14 un.
   Calça Jeans Slim 38                                  11 un.
   Suplemento Whey 1kg Chocolate                         9 un.

⏳ PAGAMENTOS PENDENTES
   12 pedidos aguardando pagamento — R$ 1.080,00 em risco
   → Ative recuperação via WhatsApp para recuperar parte desse valor

❌ CANCELAMENTOS (últimos 7 dias)
   4 cancelamentos | Principal motivo: reembolso (3x)
   Receita perdida: R$ 356,00

⚠️  ESTOQUE CRÍTICO (≤ 5 unidades)
   🔴 Camiseta Básica Preta — M                           ZERADO
   🟡 Mochila Urbana Cinza                                2 un.
   🟡 Tênis Running X Branco — 42                         3 un.

💡 AÇÕES RECOMENDADAS HOJE
   1. 1 SKU com estoque zerado publicado — repor ou despublicar
   2. Pagamentos pendentes = 8% do GMV desta semana — ative recuperação WhatsApp

=======================================================
```

---

## Próximos Passos

1. **Rodar toda manhã** — adicione ao ritual diário antes de abrir o admin
2. **Alertas de estoque** — cruzar com `/stockout-predictor` para ver dias restantes de cada SKU crítico
3. **Investigar queda de GMV** — se delta negativo, rodar `/abandonment-analysis` para ver onde os pedidos estão falhando
4. **Recuperar pendentes** — lista de pedidos aguardando pagamento é input direto para campanha WhatsApp
5. **Combinar com `/rfm-segmentation`** — ver se a queda de GMV é de segmentos específicos (ex: clientes em risco parando de comprar)

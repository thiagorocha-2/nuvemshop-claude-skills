---
name: catalog-health
description: Diagnóstico completo do catálogo — detecta produtos publicados sem foto, sem descrição, sem SEO, e variantes publicadas com estoque zerado. Gera lista de ações prioritárias.
invocation: /catalog-health
---

# Diagnóstico de Saúde do Catálogo

Varredura completa do catálogo via API para encontrar os problemas que prejudicam conversão e SEO mas que ninguém percebe no dia a dia — produtos publicados sem foto, sem descrição, sem meta tags, e variantes visíveis com estoque zerado. Gera lista de ações prioritárias por impacto.

**Invocação:** `/catalog-health`

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

Nenhum parâmetro necessário. A skill analisa todos os produtos publicados.

---

## Step 1 — Buscar Catálogo Completo

```bash
python3 << 'EOF'
import urllib.request, urllib.error, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

all_products = []
page = 1
print("Varrendo catálogo publicado...")
while True:
    url = (f"{base}/products?published=true&per_page=200&page={page}"
           f"&fields=id,name,images,description,seo_title,seo_description,variants")
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

json.dump(all_products, open('/tmp/ns_catalog_health.json', 'w'))
print(f"Produtos publicados: {len(all_products)}")
EOF
```

---

## Step 2 — Diagnóstico de Saúde

```bash
python3 << 'EOF'
import json, re
from collections import defaultdict

products = json.load(open('/tmp/ns_catalog_health.json'))

issues = defaultdict(list)

for p in products:
    pid = p['id']
    name = p.get('name', {})
    if isinstance(name, dict):
        name = name.get('pt', name.get('es', f'Produto {pid}'))
    name = str(name)[:55]

    # 1. Sem imagem
    images = p.get('images') or []
    if not images:
        issues['sem_imagem'].append(name)

    # 2. Sem descrição (ou descrição muito curta)
    desc = p.get('description', {})
    if isinstance(desc, dict):
        desc = desc.get('pt', desc.get('es', '')) or ''
    clean_desc = re.sub(r'<[^>]+>', '', str(desc)).strip()
    if len(clean_desc) < 30:
        issues['sem_descricao'].append(name)

    # 3. Sem seo_title
    seo_title = p.get('seo_title', '')
    if isinstance(seo_title, dict):
        seo_title = seo_title.get('pt', seo_title.get('es', '')) or ''
    if not str(seo_title).strip():
        issues['sem_seo_title'].append(name)

    # 4. Sem seo_description
    seo_desc = p.get('seo_description', '')
    if isinstance(seo_desc, dict):
        seo_desc = seo_desc.get('pt', seo_desc.get('es', '')) or ''
    if not str(seo_desc).strip():
        issues['sem_seo_desc'].append(name)

    # 5. Variantes publicadas com estoque 0
    for v in (p.get('variants') or []):
        stock_managed = v.get('stock_management', False)
        if not stock_managed:
            continue
        try:
            stock = int(v.get('stock') or 0)
        except (TypeError, ValueError):
            stock = 0

        if stock == 0:
            variant_label = ''
            for val in (v.get('values') or []):
                if isinstance(val, dict):
                    pt = val.get('pt', val.get('es', ''))
                    if pt:
                        variant_label = pt
                        break
            label = f"{name} — {variant_label}" if variant_label else name
            issues['estoque_zerado'].append(label[:60])

    # 6. Sem custo cadastrado (pelo menos uma variante)
    sem_custo = any(not v.get('cost') for v in (p.get('variants') or []))
    if sem_custo:
        issues['sem_custo'].append(name)

n = len(products)

print(f"\n===== DIAGNÓSTICO DE SAÚDE DO CATÁLOGO =====")
print(f"Produtos publicados analisados: {n}\n")

severity = {
    'estoque_zerado': ('🔴', 'Variantes publicadas com estoque 0 (invisível p/ cliente, prejudica SEO)'),
    'sem_imagem':     ('🔴', 'Produtos sem nenhuma imagem'),
    'sem_descricao':  ('🟡', 'Produtos sem descrição (< 30 chars)'),
    'sem_seo_title':  ('🟡', 'Produtos sem seo_title'),
    'sem_seo_desc':   ('🟡', 'Produtos sem seo_description'),
    'sem_custo':      ('⚪', 'Produtos com ao menos 1 variante sem custo cadastrado'),
}

total_issues = 0
for key, (icon, label) in severity.items():
    items = issues[key]
    if not items:
        print(f"  ✅ {label}: OK")
        continue
    total_issues += len(items)
    print(f"\n{icon} {label}: {len(items)}")
    for item in items[:10]:
        print(f"    • {item}")
    if len(items) > 10:
        print(f"    ... e mais {len(items) - 10}")

print(f"\n{'=' * 50}")
print(f"Total de problemas encontrados: {total_issues}")

# Prioridade de ação
print(f"\n--- Ordem de Prioridade ---")
if issues['sem_imagem']:
    print(f"1. ⚡ Urgente: {len(issues['sem_imagem'])} produto(s) sem foto — não convertem")
if issues['estoque_zerado']:
    print(f"2. ⚡ Urgente: {len(issues['estoque_zerado'])} variante(s) com estoque 0 publicadas — esconder ou repor")
if issues['sem_seo_title']:
    print(f"3. 📈 SEO: {len(issues['sem_seo_title'])} produto(s) sem seo_title — rode /seo-meta-generator")
if issues['sem_descricao']:
    print(f"4. ✍ Conteúdo: {len(issues['sem_descricao'])} produto(s) sem descrição — rode /product-description-rewriter")
if issues['sem_custo']:
    print(f"5. 💰 Margem: {len(issues['sem_custo'])} produto(s) sem custo — preencha para usar /price-margin-analysis")
EOF
```

---

## Output Esperado

```
===== DIAGNÓSTICO DE SAÚDE DO CATÁLOGO =====
Produtos publicados analisados: 209

🔴 Variantes publicadas com estoque 0 (invisível p/ cliente, prejudica SEO): 14
    • Top em linho ECO Preto — P
    • Top em linho ECO Preto — M
    • Kimono em linho ECO Azul Royal — GG
    ... e mais 11

🔴 Produtos sem nenhuma imagem: 0
  ✅ OK

🟡 Produtos sem descrição (< 30 chars): 12
    • Camiseta Basic Off White
    • Short sustentável em linho
    ... e mais 10

🟡 Produtos sem seo_title: 38
    • Maiô Body Regata recorte tela Marrom
    • Conjunto: Top Meia Taça + Calcinha Asa delta Cinza
    ... e mais 36

🟡 Produtos sem seo_description: 38

⚪ Produtos com ao menos 1 variante sem custo cadastrado: 67

==================================================
Total de problemas encontrados: 102

--- Ordem de Prioridade ---
1. ⚡ Urgente: 14 variantes com estoque 0 publicadas — esconder ou repor
2. 📈 SEO: 38 produtos sem seo_title — rode /seo-meta-generator
3. ✍ Conteúdo: 12 produtos sem descrição — rode /product-description-rewriter
4. 💰 Margem: 67 produtos sem custo — preencha para usar /price-margin-analysis
```

---

## Próximos Passos

1. **Esconder variantes com estoque 0** — no admin: Produtos → [produto] → Variantes → desmarcar "publicado"
2. **Rodar `/seo-meta-generator`** — para resolver os produtos sem seo_title em lote
3. **Rodar `/product-description-rewriter`** — para os produtos sem descrição
4. **Preencher custo** — habilita `/price-margin-analysis` e `/bulk-price-updater`
5. **Agendar semanalmente** — rode toda segunda-feira como checklist operacional da loja

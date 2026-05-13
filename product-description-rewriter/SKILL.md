---
name: product-description-rewriter
description: Reescreve as descrições de todos os produtos de uma categoria com a voz da marca, em PT-BR ou ES. N SKUs, um prompt, aplicação via API após confirmação.
invocation: /product-description-rewriter <category_id> [palavras=100] [idioma=pt-BR]
---

# Reescritor de Descrições de Produtos

Busca todos os produtos de uma categoria, reescreve as descrições com a voz da marca (fornecida por você) e aplica via API após confirmação. 60 SKUs, um prompt.

**Invocação:** `/product-description-rewriter <category_id> [palavras=100] [idioma=pt-BR]`

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

- **category_id** (obrigatório) — ID da categoria no admin Nuvemshop
  - Para listar categorias: `GET /categories`
- **palavras** (default: 100) — tamanho alvo das descrições em palavras
- **idioma** (default: pt-BR) — idioma de escrita (`pt-BR` ou `es`)

**Voz da marca (perguntar ao merchant antes de prosseguir):**
> "Antes de reescrever, me conte em 2-3 frases: qual é o tom da sua marca? (ex: técnico e preciso / descontraído e próximo / premium e aspiracional)"

---

## Step 1 — Listar Categorias Disponíveis

Se o merchant não souber o category_id:

```bash
python3 << 'EOF'
import urllib.request, json, os

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

req = urllib.request.Request(f"{base}/categories?fields=id,name,product_count&per_page=250", headers=headers)
with urllib.request.urlopen(req) as r:
    cats = json.loads(r.read())

print(f"\n{'ID':>8}  {'Categoria':<40} {'Produtos':>9}")
print('-' * 62)
for c in cats:
    name = c.get('name', {})
    if isinstance(name, dict):
        name = name.get('pt', name.get('es', str(c['id'])))
    print(f"{c['id']:>8}  {name:<40} {c.get('product_count', '?'):>9}")
EOF
```

---

## Step 2 — Buscar Produtos da Categoria

```bash
CATEGORY_ID=123  # substituir pelo ID informado

python3 << EOF
import urllib.request, json, os, time

base = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
token = os.environ['NUVEMSHOP_TOKEN']
headers = {'Authentication': f"bearer {token}", 'User-Agent': 'ClaudeSkill (contato@loja.com)'}

products = []
page = 1
while True:
    url = f"{base}/products?category_id=$CATEGORY_ID&published=true&fields=id,name,description&per_page=250&page={page}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as r:
        batch = json.loads(r.read())
    if not batch:
        break
    products.extend(batch)
    if len(batch) < 250:
        break
    page += 1
    time.sleep(0.5)

json.dump(products, open('/tmp/ns_desc_products.json', 'w'))
print(f"Produtos encontrados na categoria: {len(products)}")

# Preview dos 5 primeiros
for p in products[:5]:
    name = p.get('name', {})
    if isinstance(name, dict): name = name.get('pt', name.get('es', ''))
    desc = p.get('description', {})
    if isinstance(desc, dict): desc = desc.get('pt', desc.get('es', '')) or ''
    has_desc = bool(desc and len(str(desc).strip()) > 20)
    print(f"  - {name[:50]} | descrição atual: {'OK' if has_desc else 'VAZIA/CURTA'}")
EOF
```

---

## Step 3 — Reescrever Descrições com Claude

Com os produtos em `/tmp/ns_desc_products.json` e a voz da marca fornecida, gerar novas descrições:

**Instruções de geração para cada produto:**

```
Para cada produto:
1. Leia o nome e a descrição atual (se existir)
2. Escreva uma nova descrição em [idioma] com aproximadamente [palavras] palavras
3. Aplique a voz da marca: [tom fornecido pelo merchant]
4. Estrutura: [benefício principal] → [características técnicas relevantes] → [CTA ou uso]
5. Evite: adjetivos genéricos ("incrível", "fantástico", "de qualidade"), clichês, repetição do nome do produto na primeira frase
6. Inclua: 1-2 palavras-chave naturais de busca no texto
7. Formato: HTML simples com <p> tags — sem <h2> ou listas longas

Salve o resultado como JSON:
[{"id": 123, "name": "...", "new_description": "<p>...</p>"}]
```

Salvar em `/tmp/ns_desc_updates.json`

---

## Step 4 — Preview para Confirmação

```bash
python3 << 'EOF'
import json

products = {str(p['id']): p for p in json.load(open('/tmp/ns_desc_products.json'))}
updates = json.load(open('/tmp/ns_desc_updates.json'))

print(f"\nPreview das descrições reescritas ({len(updates)} produtos):\n")
for i, u in enumerate(updates[:5], 1):
    pid = str(u['id'])
    p = products.get(pid, {})
    old_name = p.get('name', {})
    if isinstance(old_name, dict): old_name = old_name.get('pt', old_name.get('es', ''))

    old_desc = p.get('description', {})
    if isinstance(old_desc, dict): old_desc = old_desc.get('pt', old_desc.get('es', '')) or ''
    old_desc = str(old_desc).replace('<p>', '').replace('</p>', ' ').strip()[:120]

    new_desc = u.get('new_description', '').replace('<p>', '').replace('</p>', ' ').strip()[:120]

    print(f"[{i}] {old_name}")
    print(f"  Antes:  {old_desc or '(vazia)'}...")
    print(f"  Depois: {new_desc}...")
    print()

print(f"... e mais {max(0, len(updates)-5)} produtos")
print(f"\nDeseja aplicar todas as {len(updates)} descrições? (confirme antes do Step 5)")
EOF
```

**Aguardar confirmação do merchant antes de continuar.**

---

## Step 5 — Aplicar via API (após confirmação)

```bash
python3 << 'EOF'
import json, urllib.request, time, os

BASE = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
TOKEN = os.environ['NUVEMSHOP_TOKEN']
IDIOMA = 'pt'  # ajustar: 'pt' para pt-BR, 'es' para espanhol

updates = json.load(open('/tmp/ns_desc_updates.json'))
success, errors = 0, []

for u in updates:
    payload = json.dumps({
        "description": {IDIOMA: u['new_description']}
    }).encode()

    req = urllib.request.Request(
        f"{BASE}/products/{u['id']}",
        data=payload,
        method='PUT',
        headers={
            'Authentication': f"bearer {TOKEN}",
            'User-Agent': 'ClaudeSkill (contato@loja.com)',
            'Content-Type': 'application/json'
        }
    )
    try:
        with urllib.request.urlopen(req) as r:
            if r.status == 200:
                success += 1
                print(f"  ✓ {u.get('name', u['id'])[:50]}")
    except Exception as e:
        errors.append(f"{u.get('name', u['id'])}: {e}")

    time.sleep(0.6)

print(f"\nResultado: {success} produtos atualizados, {len(errors)} erros")
if errors:
    for e in errors: print(f"  ✗ {e}")
EOF
```

---

## Próximos Passos

1. **Combinar com `/seo-meta-generator`** — após reescrever descrições, regere os meta texts
2. **Testar em lote pequeno primeiro** — na primeira vez, aplique em 5-10 produtos e revise manualmente
3. **Salvar a voz da marca** — documente o tom confirmado para reutilizar em próximas sessões
4. **Priorizar produtos sem descrição** — rode com `?description_min=false` para focar nos mais carentes
5. **Repetir por categoria** — cada categoria pode ter tom levemente diferente (ex: esporte vs casual)

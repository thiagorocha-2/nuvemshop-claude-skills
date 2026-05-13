---
name: seo-meta-generator
description: Gera meta titles e descriptions otimizados para os produtos mais vendidos da loja Nuvemshop e aplica via API.
invocation: /seo-meta-generator [quantidade] [idioma]
---

# Gerador de SEO Local

Gera `seo_title` (≤70 chars) e `seo_description` (≤320 chars) otimizados para os N produtos mais vendidos da sua loja, com foco em palavras-chave de busca local (PT-BR ou ES), e aplica diretamente via API após confirmação.

**Invocação:** `/seo-meta-generator [quantidade=50] [idioma=pt-BR]`

---

## Step 0 — Verificar Credenciais

Antes de qualquer coisa, verificar se as variáveis de ambiente estão configuradas:

```bash
if [ -z "$NUVEMSHOP_STORE_ID" ] || [ -z "$NUVEMSHOP_TOKEN" ]; then
  echo "Credenciais não configuradas. Execute:"
  echo ""
  echo "  export NUVEMSHOP_STORE_ID=<seu_store_id>"
  echo "  export NUVEMSHOP_TOKEN=<seu_access_token>"
  echo ""
  echo "Como obter:"
  echo "  1. Acesse: https://partners.nuvemshop.com.br"
  echo "  2. Crie um app (ou use um existente)"
  echo "  3. Instale o app na sua loja para gerar o access_token"
  echo "  4. O store_id aparece na URL do admin: /admin/[STORE_ID]/"
  exit 1
fi
echo "Credenciais OK. Store ID: $NUVEMSHOP_STORE_ID"
```

---

## Input

- **quantidade** (default: 50) — número de produtos a processar
- **idioma** (default: pt-BR) — `pt-BR` para Portuguese/Brasil ou `es` para Español

---

## Step 1 — Buscar Produtos Mais Vendidos

```bash
BASE="https://api.tiendanube.com/2025-03/$NUVEMSHOP_STORE_ID"

curl -s "$BASE/products?sort=best_selling&per_page=50&fields=id,name,description,seo_title,seo_description&published=true" \
  -H "Authentication: bearer $NUVEMSHOP_TOKEN" \
  -H "User-Agent: ClaudeSkill (contato@loja.com)" \
  > /tmp/ns_products.json

python3 -c "
import json
products = json.load(open('/tmp/ns_products.json'))
print(f'Produtos encontrados: {len(products)}')
for i, p in enumerate(products[:5], 1):
    name = p.get('name', {})
    title = name.get('pt', name.get('es', str(name))) if isinstance(name, dict) else str(name)
    has_seo = bool(p.get('seo_title'))
    print(f'  {i}. {title[:50]} | SEO atual: {\"✓\" if has_seo else \"vazio\"}')
print('  ...')
"
```

---

## Step 2 — Gerar SEO com Claude

Com os dados dos produtos em `/tmp/ns_products.json`, gerar os textos para cada produto seguindo estas regras:

**seo_title (máx 70 chars):**
- Formato: `[Nome do produto] | [Benefício ou categoria] – [Nome da loja]`
- Incluir palavra-chave principal no início
- Evitar artigos desnecessários
- Contar caracteres com `len(title)` antes de usar

**seo_description (máx 320 chars):**
- Primeira frase: benefício principal + palavra-chave
- Segunda frase: CTA ou diferencial (frete grátis, parcelamento, entrega rápida)
- Tom: direto, sem adjetivos genéricos ("incrível", "fantástico")
- Contar caracteres antes de usar

Salvar output como `/tmp/ns_seo_updates.json`:
```json
[
  {
    "id": 12345,
    "name": "Nome do produto",
    "seo_title": "Tênis Running X | Corrida e Academia – MinhaLoja",
    "seo_description": "Tênis para corrida com amortecimento de alta performance. Disponível em 8 cores, entrega em 24h e parcele em até 12x sem juros."
  }
]
```

---

## Step 3 — Preview Antes de Aplicar

Mostrar tabela de preview para confirmação do merchant:

```bash
python3 -c "
import json
updates = json.load(open('/tmp/ns_seo_updates.json'))
print(f'{'#':<3} {'Produto':<35} {'seo_title (chars)':<55} {'seo_desc (chars)':<30}')
print('-' * 125)
for i, u in enumerate(updates, 1):
    title = u['seo_title']
    desc = u['seo_description']
    ok_t = '✓' if len(title) <= 70 else f'⚠ {len(title)}'
    ok_d = '✓' if len(desc) <= 320 else f'⚠ {len(desc)}'
    print(f'{i:<3} {u[\"name\"][:34]:<35} {title[:52]:<52} [{ok_t}]  {desc[:27]:<27} [{ok_d}]')
"
```

**Aguardar confirmação do merchant antes de continuar para o Step 4.**

---

## Step 4 — Aplicar via API (após confirmação)

```bash
python3 << 'EOF'
import json, urllib.request, time, os

BASE = f"https://api.tiendanube.com/2025-03/{os.environ['NUVEMSHOP_STORE_ID']}"
TOKEN = os.environ['NUVEMSHOP_TOKEN']
updates = json.load(open('/tmp/ns_seo_updates.json'))

success, errors = 0, []

for u in updates:
    payload = json.dumps({
        "seo_title": u["seo_title"],
        "seo_description": u["seo_description"]
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
                print(f"  ✓ {u['name'][:50]}")
            else:
                errors.append(u['name'])
    except Exception as e:
        errors.append(f"{u['name']}: {e}")

    time.sleep(0.5)  # respeitar rate limit (2 req/s)

print(f"\nResultado: {success} produtos atualizados, {len(errors)} erros")
if errors:
    print("Erros:", errors)
EOF
```

---

## Output Esperado

```
Resultado: 48 produtos atualizados, 2 erros

Produtos com seo_title vazio antes: 43
Produtos com seo_description vazio antes: 31
```

---

## Próximos Passos

1. **Verificar no admin** — acesse Produtos no painel Nuvemshop e confirme os metadados
2. **Priorizar por impressões** — se tiver Google Search Console, cruzar com produtos de maior impressão mas baixo CTR
3. **Rodar mensalmente** — novos produtos ficam sem SEO; agendar revisão regular
4. **Combinar com `/product-description-rewriter`** — descrições ricas melhoram a geração de seo_description

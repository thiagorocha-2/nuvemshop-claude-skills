#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}Configurar credenciais Nuvemshop${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Onde encontrar suas credenciais:"
echo ""
echo "  Store ID  → URL do admin da sua loja:"
echo "              https://www.nuvemshop.com.br/admin/[STORE_ID]/..."
echo ""
echo "  Token     → Crie um app em: https://partners.nuvemshop.com.br"
echo "              Após instalar o app na sua loja, copie o access_token"
echo ""
echo "  Precisa de ajuda? Leia o guia completo:"
echo "  https://github.com/thiagorocha-2/nuvemshop-claude-skills/blob/main/CREDENTIALS.md"
echo ""

# Solicitar credenciais
read -r -p "Cole seu Store ID: " store_id
if [ -z "$store_id" ]; then
  echo "Store ID não pode ser vazio."
  exit 1
fi

read -r -s -p "Cole seu Access Token (oculto): " token
echo ""
if [ -z "$token" ]; then
  echo "Token não pode ser vazio."
  exit 1
fi

# Detectar shell profile
if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ]; then
  PROFILE="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ] || [ "$SHELL" = "/bin/bash" ]; then
  PROFILE="$HOME/.bashrc"
  # macOS usa .bash_profile
  [ "$(uname)" = "Darwin" ] && PROFILE="$HOME/.bash_profile"
else
  PROFILE="$HOME/.profile"
fi

# Verificar se já existe
MARKER="# Nuvemshop Claude Skills"
if grep -q "$MARKER" "$PROFILE" 2>/dev/null; then
  echo ""
  echo -e "${YELLOW}Credenciais existentes detectadas em $PROFILE.${NC}"
  read -r -p "Sobrescrever? [s/N] " overwrite
  if [[ ! "$overwrite" =~ ^[Ss]$ ]]; then
    echo "Cancelado. Atualize manualmente em $PROFILE."
    exit 0
  fi
  # Remover bloco anterior
  # Usar Python para remoção segura do bloco
  python3 -c "
import re
with open('$PROFILE', 'r') as f:
    content = f.read()
# Remove o bloco entre os marcadores
cleaned = re.sub(r'\n$MARKER.*?# /Nuvemshop Claude Skills\n', '\n', content, flags=re.DOTALL)
with open('$PROFILE', 'w') as f:
    f.write(cleaned)
"
fi

# Adicionar ao profile
cat >> "$PROFILE" << EOF

$MARKER
export NUVEMSHOP_STORE_ID="$store_id"
export NUVEMSHOP_TOKEN="$token"
# /Nuvemshop Claude Skills
EOF

echo ""
echo -e "${GREEN}✓ Credenciais salvas em $PROFILE${NC}"
echo ""
echo "Para ativar na sessão atual, execute:"
echo ""
echo "  source $PROFILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}Tudo pronto! Skills disponíveis no Claude Code:${NC}"
echo ""
echo "  /payment-mix-analyzer         PIX vs Parcelamento"
echo "  /rfm-segmentation             Segmentação RFM → WhatsApp"
echo "  /stockout-predictor           Previsão de ruptura de estoque"
echo "  /shipping-optimizer           Threshold de frete grátis"
echo "  /cross-sell-recommender       Cross-sell por co-compra"
echo "  /abandonment-analysis         Abandono e cancelamento"
echo "  /cohort-retention             Retenção por cohort"
echo "  /price-margin-analysis        Preço + Margem"
echo "  /seo-meta-generator           SEO local"
echo "  /product-description-rewriter Reescritor de descrições"
echo ""

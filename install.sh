#!/bin/bash
set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SKILLS_DIR="$HOME/.claude/skills"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

SKILLS=(
  "abandonment-analysis"
  "cohort-retention"
  "cross-sell-recommender"
  "payment-mix-analyzer"
  "price-margin-analysis"
  "product-description-rewriter"
  "rfm-segmentation"
  "seo-meta-generator"
  "shipping-optimizer"
  "stockout-predictor"
)

echo ""
echo -e "${BOLD}Nuvemshop Claude Skills${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verificar Claude Code
if ! command -v claude &> /dev/null; then
  echo -e "${YELLOW}Aviso: Claude Code (CLI) não encontrado no PATH.${NC}"
  echo "Instale em: https://claude.ai/download"
  echo "A instalação das skills continuará mesmo assim."
  echo ""
fi

# Criar diretório de skills se não existir
mkdir -p "$SKILLS_DIR"

installed=0
updated=0
errors=0

for skill in "${SKILLS[@]}"; do
  src="$SOURCE_DIR/$skill"
  dest="$SKILLS_DIR/$skill"

  if [ ! -d "$src" ]; then
    echo -e "  ${RED}✗${NC} $skill — não encontrado em $src"
    ((errors++)) || true
    continue
  fi

  if [ -d "$dest" ]; then
    cp -r "$src/." "$dest/"
    echo -e "  ${YELLOW}↻${NC} $skill (atualizado)"
    ((updated++)) || true
  else
    cp -r "$src" "$SKILLS_DIR/"
    echo -e "  ${GREEN}+${NC} $skill"
    ((installed++)) || true
  fi
done

echo ""
echo -e "${GREEN}✓ $installed instaladas, $updated atualizadas${NC}${errors:+, ${RED}${errors} erros${NC}}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Configurar credenciais
bash "$SOURCE_DIR/setup-credentials.sh"

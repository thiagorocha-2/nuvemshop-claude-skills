#!/bin/bash
set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

SKILLS_DIR="$HOME/.claude/skills"

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
echo -e "${BOLD}Nuvemshop Claude Skills — Desinstalar${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}As seguintes skills serão removidas de $SKILLS_DIR:${NC}"
echo ""

found=()
for skill in "${SKILLS[@]}"; do
  dest="$SKILLS_DIR/$skill"
  if [ -d "$dest" ]; then
    echo "  - $skill"
    found+=("$skill")
  fi
done

if [ ${#found[@]} -eq 0 ]; then
  echo "  Nenhuma skill Nuvemshop encontrada."
  exit 0
fi

echo ""
read -r -p "Confirmar remoção? [s/N] " confirm
if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
  echo "Cancelado."
  exit 0
fi

echo ""
for skill in "${found[@]}"; do
  rm -rf "$SKILLS_DIR/$skill"
  echo -e "  ${RED}✗${NC} $skill removida"
done

echo ""
echo -e "${GREEN}✓ Skills removidas.${NC}"
echo ""
echo "As variáveis de ambiente (NUVEMSHOP_STORE_ID, NUVEMSHOP_TOKEN)"
echo "não foram alteradas. Remova manualmente do seu ~/.zshrc ou ~/.bashrc se desejar."
echo ""

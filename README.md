# Nuvemshop Claude Skills

> Projeto pessoal de [Thiago Rocha](https://github.com/thiagorocha-2). Não é um produto oficial da Nuvemshop.

10 skills para o Claude Code que conectam diretamente na API da sua loja Nuvemshop. Análises que antes levavam horas, em 2 minutos.

## Instalação

```bash
git clone https://github.com/thiagorocha-2/nuvemshop-claude-skills.git
cd nuvemshop-claude-skills
bash install.sh
bash setup-credentials.sh
```

Pronto. Abra o Claude Code e use `/payment-mix-analyzer` para começar.

## Pré-requisitos

- [Claude Code](https://claude.ai/download) instalado
- Uma loja Nuvemshop com acesso à API ([como obter](#credenciais))

## Skills disponíveis

| Skill | O que faz |
|-------|-----------|
| `/payment-mix-analyzer` | Compara PIX, boleto e cartão parcelado: ticket médio e % do GMV por método |
| `/rfm-segmentation` | Classifica clientes em Campeões / Em Risco / Dormentes. Exporta CSV para WhatsApp |
| `/stockout-predictor` | Calcula velocity de vendas por SKU e prevê quais vão zerar em menos de 14 dias |
| `/shipping-optimizer` | Encontra o threshold de frete grátis que maximiza ticket médio sem destruir margem |
| `/cross-sell-recommender` | Identifica os 3 melhores cross-sells por produto com base em co-compra real |
| `/abandonment-analysis` | Analisa taxa de abandono de checkout e motivos de cancelamento |
| `/cohort-retention` | Mostra qual % dos clientes de cada mês voltou a comprar nos meses seguintes |
| `/price-margin-analysis` | Detecta produtos com desconto alto e margem baixa simultaneamente |
| `/seo-meta-generator` | Gera e aplica meta titles e descriptions para os produtos mais vendidos |
| `/product-description-rewriter` | Reescreve descrições de uma categoria inteira com a voz da sua marca |

## Credenciais

Você vai precisar de um **Store ID** e um **Access Token**. Leva cerca de 5 minutos na primeira vez.

→ **[Guia completo passo a passo](CREDENTIALS.md)**

O token **não expira** — configure uma vez e esqueça.

## Como usar

Após a instalação, abra o Claude Code em qualquer diretório e chame a skill:

```
/payment-mix-analyzer dias=90
```

```
/rfm-segmentation
```

```
/stockout-predictor dias_alerta=7
```

Cada skill tem um Step 0 que verifica suas credenciais e instrui o que fazer se estiverem ausentes.

## Atualizar

```bash
cd nuvemshop-claude-skills
git pull
bash install.sh
```

## Desinstalar

```bash
bash uninstall.sh
```

## Licença

MIT — use, modifique e distribua livremente.

---

Feito por [Thiago Rocha](https://github.com/thiagorocha-2) · Não afiliado à Nuvemshop S.A.

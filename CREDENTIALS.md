# Como obter suas credenciais Nuvemshop

Para usar as skills você precisa de duas informações: **Store ID** e **Access Token**.

---

## 1. Store ID

O Store ID aparece diretamente na URL do painel admin da sua loja:

```
https://www.nuvemshop.com.br/admin/[STORE_ID]/...
```

Exemplo: se a URL for `.../admin/892341/...`, seu Store ID é `892341`.

---

## 2. Access Token

O Access Token exige criar um aplicativo no Portal de Parceiros. São 5 passos, leva cerca de 5 minutos.

### Passo 1 — Criar conta no Portal de Parceiros

Acesse **https://partners.nuvemshop.com.br** e crie uma conta gratuita.

> Não precisa ser uma conta de agência ou empresa — qualquer e-mail funciona.

---

### Passo 2 — Criar um aplicativo

1. No painel, clique em **"Criar aplicativo"**
2. Preencha:
   - **Nome:** qualquer nome (ex: `Claude Skills`)
   - **Distribuição:** selecione **"Para seus clientes"**
   - **URL de redirecionamento:** cole exatamente isso:
     ```
     https://httpbin.org/get
     ```
3. Salve o aplicativo

---

### Passo 3 — Copiar client_id e client_secret

1. No dashboard do aplicativo, vá em **"Desenvolver e testar"**
2. Copie o **`client_id`** e o **`client_secret`** — você vai precisar em breve

---

### Passo 4 — Instalar o app na sua loja e capturar o código

1. No dashboard do aplicativo, clique em **"Instalar aplicativo"**
2. Faça login com a conta da sua loja quando solicitado
3. Clique em **"Aceitar e começar a usar"**
4. Você será redirecionado para uma URL parecida com esta:

   ```
   https://httpbin.org/get?code=abc123xyz&shop_id=892341
   ```

5. **Anote os dois valores:**
   - `code` → o código de autorização (válido por 5 minutos)
   - `shop_id` → confirma seu Store ID

---

### Passo 5 — Trocar o código pelo Access Token

No terminal, rode o comando abaixo substituindo os valores:

```bash
curl -s -X POST https://www.tiendanube.com/oauth/token \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "SEU_CLIENT_ID",
    "client_secret": "SEU_CLIENT_SECRET",
    "code": "CODIGO_DA_URL"
  }'
```

A resposta será algo como:

```json
{
  "access_token": "abcdef1234567890abcdef1234567890",
  "token_type": "bearer",
  "scope": "...",
  "user_id": 892341
}
```

- **`access_token`** → seu token de acesso
- **`user_id`** → confirma seu Store ID

> O token **não expira**. Configure uma vez e use para sempre.

---

## Configurando as credenciais

Depois de ter o Store ID e o Access Token, rode:

```bash
bash setup-credentials.sh
```

Ou exporte manualmente:

```bash
export NUVEMSHOP_STORE_ID=892341
export NUVEMSHOP_TOKEN=abcdef1234567890abcdef1234567890
```

---

## Problemas comuns

**"O código expirou"**
O código de autorização do Passo 4 é válido por apenas 5 minutos. Se expirar, repita o Passo 4 para gerar um novo e execute o Passo 5 imediatamente.

**"Erro 401 nas chamadas da API"**
Verifique se o token está correto:
```bash
curl -s "https://api.tiendanube.com/2025-03/$NUVEMSHOP_STORE_ID/orders?per_page=1" \
  -H "Authentication: bearer $NUVEMSHOP_TOKEN" \
  -H "User-Agent: ClaudeSkill (test)"
```
Se retornar `{"code": 401}`, o token está inválido — repita o processo do Passo 4.

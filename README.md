# Hermes Stack — multi-usuário com LiteLLM + Nginx

Stack Docker Compose enxuta que coloca **3 chats Hermes independentes** + **3 dashboards admin** atrás de um Nginx com Basic Auth, todos compartilhando um proxy **LiteLLM** centralizado para o provedor LLM.

```
            ┌────────────────────────── porta 80 (host) ─────────────────────────────┐
            │   Nginx  (reverse proxy + basic auth + sub_filter)                     │
            │   ├── /litellm/   → LiteLLM (API + UI admin)        sem auth           │
            │   ├── /chat01..03/→ hermes-webui   user_0X          auth user_0X       │
            │   └── /dash01..03/→ hermes-dashboard user_0X        auth user_0X       │
            └────────────────────────────────────────────────────────────────────────┘
                                       │
   ┌───────────────────────────────────┼───────────────────────────────────┐
   │                                   │                                   │
   ▼ (por usuário 01/02/03)            ▼                                   ▼
 ┌─────────────────┐         ┌──────────────────────┐          ┌─────────────────────┐
 │  hermes-webui-  │         │  hermes-dashboard-   │          │   hermes-agent-     │
 │     user_0X     │         │      user_0X         │          │      user_0X        │
 │  (chat UI 8787) │         │ (admin dash 9119)    │          │   (gateway run)     │
 └────────┬────────┘         └──────────┬───────────┘          └──────────┬──────────┘
          │                             │                                 │
          └───── hermes-home-user_0X (volume compartilhado) ───────────────┘
                                       │
                                       │  OPENAI_API_KEY = virtual key
                                       │  OPENAI_BASE_URL = litellm:4000
                                       ▼
                               ┌──────────────┐
                               │   LiteLLM    │  ← proxy OpenAI-compatible
                               │    :4000     │  ← /litellm/ui admin
                               └──────┬───────┘
                                      │
                         ┌────────────┴───────────────┐
                         ▼                            ▼
                ┌──────────────────┐         ┌────────────────────┐
                │ Postgres 16      │         │ Provider real      │
                │ (litellm-db)     │         │ Gemini / OpenAI /  │
                │ virtual keys     │         │ Anthropic / etc.   │
                └──────────────────┘         └────────────────────┘
```

---

## Componentes

| Serviço | Imagem | Versão | Função |
|---|---|---|---|
| `litellm-db` | `postgres` | `16-alpine` | Banco do LiteLLM (virtual keys, audit, spend tracking). |
| `litellm` | `docker.litellm.ai/berriai/litellm-database` | `v1.85.0` | Proxy OpenAI-compatible. UI admin em `/litellm/ui`. |
| `hermes-agent-user_0X` | `nousresearch/hermes-agent` | `v2026.5.16` | Agente Hermes em `gateway run`. Publica o código-fonte do pacote `hermes` no volume `/opt/hermes` para a WebUI consumir. |
| `hermes-webui-user_0X` | `ghcr.io/nesquena/hermes-webui` | `0.51.92` | Chat UI. Auto-instala o pacote `hermes` do volume compartilhado no primeiro boot (`HERMES_WEBUI_AUTO_INSTALL=1`). |
| `hermes-dashboard-user_0X` | `nousresearch/hermes-agent` | `v2026.5.16` | Dashboard admin (`hermes dashboard --host 0.0.0.0 --port 9119 --insecure --no-open`). Compartilha `hermes-home-user_0X` com o agente do mesmo usuário, então mostra sessões, memória, skills e config em tempo real. |
| `nginx` | `nginx` | `1.27-alpine` (base) | Reverse proxy. Dockerfile customizado adiciona `apache2-utils` e gera os `.htpasswd` em bcrypt no startup, lendo as variáveis `NGINX_USER_0X` / `NGINX_PASS_0X` do `.env`. |

### Funcionalidades

- **Multi-usuário isolado** — cada usuário tem seu próprio `hermes-agent`, sua própria `hermes-webui`, seu próprio diretório de estado e sua própria **virtual key** do LiteLLM. Conversas e histórico não cruzam entre `user_01`, `user_02` e `user_03`.
- **Provider centralizado** — todos os agentes batem no LiteLLM, que fala com o provider real (Gemini por padrão). Trocar de provider é uma edição em [litellm/litellm_config.yaml](litellm/litellm_config.yaml) sem mexer nos agentes.
- **Billing/limit por usuário** — virtual keys do LiteLLM permitem definir budget, rate-limit e logs por usuário direto pela UI admin.
- **Autenticação na borda** — Basic Auth em bcrypt configurado por usuário no Nginx; senhas vivem só no `.env`, nunca em disco fora do container.
- **Versões cravadas** — nenhuma tag `:latest`. Upgrades exigem alteração explícita no Compose, facilitando rollback.
- **Sub-path routing** — uma só porta (`80`) expõe 7 rotas distintas. `sub_filter` reescreve caminhos absolutos no HTML pra que assets das WebUIs e do Dashboard funcionem sob `/chat01..03/` e `/dash01..03/`.
- **Dashboard admin por usuário** — `/dash01..03/` exibe o painel oficial do Hermes (`hermes dashboard`), permitindo inspecionar memória, skills, sessões e configuração de cada usuário sem precisar entrar no container.
- **YAML anchors** — `&hermes-agent-base`, `&hermes-dashboard-base`, `&hermes-webui-base` e `&litellm-inference` eliminam duplicação no [docker-compose.yml](docker-compose.yml).

---

## Layout do repositório

```
hermes-stack-nesquena/
├── docker-compose.yml          # 11 services + 1 rede + 7 volumes
├── .env.example                # template — copiar para .env
├── litellm/
│   └── litellm_config.yaml     # model_list + general_settings
└── nginx/
    ├── Dockerfile              # nginx:1.27-alpine + apache2-utils
    ├── docker-entrypoint.sh    # gera .htpasswd (bcrypt) no boot
    └── nginx.conf              # rotas /litellm/, /chat01..03/, /dash01..03/
```

---

## Instalação

### Pré-requisitos

- Docker Engine ≥ 24.x
- Docker Compose v2 (já vem com o Docker Desktop / `docker compose` plugin)
- Chave do provider (ex.: `GEMINI_API_KEY` em [aistudio.google.com](https://aistudio.google.com/app/apikey))
- Linux/macOS — no Windows recomendado WSL2

### 1. Clonar e preparar o `.env`

```sh
git clone <este-repo> hermes-stack-nesquena
cd hermes-stack-nesquena
cp .env.example .env
```

Edite `.env` e preencha **obrigatoriamente**:

| Variável | O quê |
|---|---|
| `HERMES_UID` / `HERMES_GID` | `id -u` e `id -g` no host (Linux); 501/20 no macOS. |
| `LITELLM_POSTGRES_PASSWORD` | Senha do Postgres. |
| `LITELLM_MASTER_KEY` | Login da UI admin do LiteLLM. Deve começar com `sk-`. |
| `LITELLM_SALT_KEY` | Entropy extra pro hash das virtual keys. Também `sk-...`. |
| `GEMINI_API_KEY` | Chave do provider (ou ajuste o `litellm_config.yaml` p/ outro). |
| `NGINX_PASS_01..03` | Senhas dos 3 usuários do Basic Auth. |

> **Deixe `LITELLM_USER_0X_API_KEY` em branco por enquanto** — você vai preenchê-las após o passo 3.

### 2. Subir apenas o LiteLLM (e seu Postgres)

```sh
docker compose up -d litellm-db litellm
docker compose logs -f litellm   # acompanhe até ver "Application startup complete"
```

### 3. Criar as virtual keys

1. Abra `http://localhost:4000/ui` (ou, se já configurou DNS/firewall, `http://SEU_IP/litellm/ui`).
2. Login: usuário `admin`, senha = `LITELLM_MASTER_KEY` do `.env`.
3. Menu **Virtual Keys → Create Key**.
   - Crie **três keys**, uma para cada usuário (`user_01`, `user_02`, `user_03`).
   - Em **Models** selecione `gemini-flash-lite` (ou os que você expôs no `litellm_config.yaml`).
   - Opcional: defina `Max Budget`, `RPM`, `TPM` por key.
4. Copie cada key (começa com `sk-...`) e cole no `.env`:

```env
LITELLM_USER_01_API_KEY=sk-xxxxxxxxxxxxxxxx
LITELLM_USER_02_API_KEY=sk-yyyyyyyyyyyyyyyy
LITELLM_USER_03_API_KEY=sk-zzzzzzzzzzzzzzzz
```

### 4. Subir o resto da stack

```sh
docker compose up -d
docker compose ps           # todos devem estar Up / healthy
```

Primeiro boot demora alguns minutos — a `hermes-webui` executa `pip install` do pacote `hermes` que o agente publicou em `/opt/hermes`. Acompanhe com:

```sh
docker compose logs -f hermes-webui-user_01
```

### 5. Acessar

| URL | Login | Para quê |
|---|---|---|
| `http://SEU_IP/` | — | Redireciona para `/chat01/`. |
| `http://SEU_IP/chat01/` | `NGINX_USER_01` / `NGINX_PASS_01` | Chat do usuário 1. |
| `http://SEU_IP/chat02/` | `NGINX_USER_02` / `NGINX_PASS_02` | Chat do usuário 2. |
| `http://SEU_IP/chat03/` | `NGINX_USER_03` / `NGINX_PASS_03` | Chat do usuário 3. |
| `http://SEU_IP/dash01/` | `NGINX_USER_01` / `NGINX_PASS_01` | Dashboard admin do usuário 1. |
| `http://SEU_IP/dash02/` | `NGINX_USER_02` / `NGINX_PASS_02` | Dashboard admin do usuário 2. |
| `http://SEU_IP/dash03/` | `NGINX_USER_03` / `NGINX_PASS_03` | Dashboard admin do usuário 3. |
| `http://SEU_IP/litellm/ui` | `admin` / `LITELLM_MASTER_KEY` | Admin do LiteLLM. |

---

## Operação

### Atualizar uma versão de imagem

1. Edite a tag em [docker-compose.yml](docker-compose.yml) (cabeçalho documenta cada uma).
2. `docker compose pull`
3. `docker compose up -d`

### Upgrade do `hermes-agent` (rebuild dos volumes de código)

A WebUI cacheia o pacote `hermes` que o agente publica. Após bump da imagem do agente, recrie os volumes:

```sh
docker compose down
docker volume rm hermes-stack-nesquena_hermes-agent-src-user_01
docker volume rm hermes-stack-nesquena_hermes-agent-src-user_02
docker volume rm hermes-stack-nesquena_hermes-agent-src-user_03
docker compose pull
docker compose up -d
```

> Os volumes `hermes-home-user_0X` **não** devem ser apagados — guardam o histórico de conversas e configurações de cada usuário.

### Trocar de provider LLM

Edite [litellm/litellm_config.yaml](litellm/litellm_config.yaml). Exemplo p/ adicionar Anthropic:

```yaml
model_list:
  - model_name: sonnet
    litellm_params:
      model: anthropic/claude-sonnet-4-6
      api_key: os.environ/ANTHROPIC_API_KEY
```

Adicione `ANTHROPIC_API_KEY=...` no `.env` e exponha pro container LiteLLM (incluir em `environment:` da service `litellm`). Reinicie com `docker compose up -d litellm`. Lista completa: [docs.litellm.ai/docs/providers](https://docs.litellm.ai/docs/providers).

### Trocar o modelo padrão dos agentes

Edite `HERMES_MODEL` no `.env` — precisa bater com algum `model_name` do `litellm_config.yaml`. Reinicie:

```sh
docker compose up -d hermes-agent-user_01 hermes-agent-user_02 hermes-agent-user_03
```

### Adicionar/remover usuários

Stack está fixa em 3 slots porque cada usuário exige:

- 3 services no Compose (`hermes-agent-user_0X` + `hermes-webui-user_0X` + `hermes-dashboard-user_0X`),
- 2 volumes (`hermes-home-user_0X`, `hermes-agent-src-user_0X`),
- 2 upstreams + 2 locations no [nginx/nginx.conf](nginx/nginx.conf) (`webui_user0X` + `dash_user0X`, `/chat0X/` + `/dash0X/`),
- 1 chamada extra `generate_htpasswd "N"` em [nginx/docker-entrypoint.sh](nginx/docker-entrypoint.sh),
- 1 par `NGINX_USER_0N` / `NGINX_PASS_0N` no `.env`,
- 1 virtual key na UI do LiteLLM colada em `LITELLM_USER_0N_API_KEY`.

Para acrescentar `user_04` siga o padrão dos 3 existentes. Para remover, faça o inverso — incluindo `docker volume rm` para liberar disco.

### Resetar senha de um usuário

Edite `NGINX_PASS_0X` no `.env` e:

```sh
docker compose up -d --force-recreate nginx
```

O entrypoint regera o `.htpasswd` bcrypt no boot.

### Logs

```sh
docker compose logs -f                    # todos os serviços
docker compose logs -f hermes-webui-user_01
docker compose logs -f litellm | grep -i error
docker compose logs nginx | tail -100
```

### Backup

- `litellm-postgres-data` → virtual keys, audit logs, configuração.
- `hermes-home-user_0X` → conversas e estado de cada usuário.

```sh
docker run --rm -v hermes-stack-nesquena_hermes-home-user_01:/data \
  -v "$PWD/backup":/backup alpine \
  tar czf /backup/hermes-home-user_01-$(date +%F).tgz -C /data .
```

---

## Segurança

- **`/litellm/` não tem Basic Auth.** Em produção exposta na internet, restrinja por firewall/IP ou adicione um quarto `.htpasswd` na location.
- **Sem TLS no Nginx.** Coloque um Caddy/Traefik/CDN à frente, ou adicione `listen 443 ssl` + certificados (ex.: certbot) ao [nginx/nginx.conf](nginx/nginx.conf).
- **Senhas em texto claro no `.env`.** O Compose precisa delas em claro para passar ao entrypoint do Nginx (que as converte em bcrypt). Restrinja permissões: `chmod 600 .env`.
- **Virtual keys** — fácil revogar uma key comprometida pela UI do LiteLLM sem mexer no Compose.

---

## Troubleshooting

| Sintoma | Provável causa | Como verificar |
|---|---|---|
| `nginx-init ERRO: NGINX_PASS_01 não definido` | `.env` incompleto. | `docker compose config \| grep NGINX_PASS_01` |
| WebUI sobe mas erro `401` no LiteLLM | Virtual key inválida/expirada. | Recrie em `/litellm/ui` e atualize `LITELLM_USER_0X_API_KEY`. |
| Assets quebrados em `/chat01/` (CSS/JS 404) | `sub_filter` não pegou um caminho específico. | Inspecione no DevTools quais URLs estão `/algo` em vez de `/chat01/algo` e adicione padrões no [nginx/nginx.conf](nginx/nginx.conf). |
| WebUI demora muito no primeiro boot | `pip install` do `hermes` rodando. | `docker compose logs -f hermes-webui-user_01` — espere "Application startup complete". |
| Permissão negada nos volumes | `HERMES_UID`/`HERMES_GID` no `.env` diferem do dono dos volumes. | `id -u && id -g`; apague volumes e suba de novo se necessário. |
| `litellm` reinicia em loop | Postgres ainda não pronto. | `docker compose logs litellm-db` e aguarde `healthy`. |

---

## Referências

- LiteLLM: <https://github.com/BerriAI/litellm> · [docs.litellm.ai](https://docs.litellm.ai)
- hermes-agent: <https://github.com/NousResearch/hermes-agent>
- hermes-webui: <https://github.com/nesquena/hermes-webui>
- Stack original de referência: <https://github.com/WoneyBranga/hermes-agent-stack>

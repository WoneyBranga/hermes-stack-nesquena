#!/bin/sh
# =============================================================
# docker-entrypoint.sh — Nginx
# Gera arquivos .htpasswd (bcrypt) a partir de env vars antes
# de iniciar o nginx. Executado como root dentro do container.
# =============================================================
set -e

fail() {
  echo "[nginx-init] ERRO: $*" >&2
  exit 1
}

info() {
  echo "[nginx-init] $*"
}

# Gera um .htpasswd individual (cria ou substitui o arquivo)
generate_htpasswd() {
  local slot="$1"      # ex: "01"
  local user_var="NGINX_USER_0${slot}"
  local pass_var="NGINX_PASS_0${slot}"

  # Lê as variáveis dinamicamente via eval (POSIX sh)
  eval "local user=\${${user_var}:-}"
  eval "local pass=\${${pass_var}:-}"

  [ -n "$user" ] || fail "${user_var} não definido ou vazio."
  [ -n "$pass" ] || fail "${pass_var} não definido ou vazio."

  local htfile="/etc/nginx/.htpasswd-user_0${slot}"
  info "Gerando ${htfile} para o usuário '${user}' (bcrypt)..."
  htpasswd -cbB "${htfile}" "${user}" "${pass}"
  # Workers do nginx rodam como user 'nginx' (uid 101); root cria o
  # arquivo, então precisamos transferir a posse para que o worker
  # consiga ler. Modo 600 mantido — apenas o dono lê.
  chown nginx:nginx "${htfile}"
  chmod 600 "${htfile}"
}

generate_htpasswd "1"
generate_htpasswd "2"
generate_htpasswd "3"

info "Arquivos .htpasswd gerados. Iniciando nginx..."
exec "$@"

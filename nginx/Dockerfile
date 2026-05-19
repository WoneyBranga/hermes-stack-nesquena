# =============================================================
# Nginx customizado — gera .htpasswd via bcrypt no startup
# Base: nginx:1.27-alpine (mainline, alpine slim)
# =============================================================
FROM nginx:1.27-alpine

# apache2-utils fornece o comando htpasswd com suporte a bcrypt (-B)
RUN apk add --no-cache apache2-utils

# Configuração do nginx
COPY nginx.conf /etc/nginx/nginx.conf

# Script de inicialização: gera os .htpasswd antes de subir o nginx
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

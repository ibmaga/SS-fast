#!/usr/bin/env bash
# =============================================================================
#  ssfast — self-steal nginx для remnanode
#
#    ssfast <domain> [доп.домены в тот же сертификат...] [--renew]
#    ssfast list
#
#  Всё лежит плоско в /opt/nginx:
#    <domain>-fullchain.pem, <domain>-privkey.key, conf.d/<domain>.conf
#  Креды DNS: /etc/ssfast.env (600)
# =============================================================================
set -euo pipefail
trap 'echo -e "\033[0;31m[ERROR]\033[0m строка ${LINENO}: ${BASH_COMMAND}" >&2' ERR

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

DIR=/opt/nginx
CONF_D="$DIR/conf.d"
ENV_FILE=/etc/ssfast.env
ACME_HOME=/root/.acme.sh
ACME="$ACME_HOME/acme.sh"
REMNANODE=/opt/remnanode
SOCK=/dev/shm/nginx.sock
CT=remnanode-nginx
RENEW_DAYS=30

[[ $EUID -ne 0 ]] && error "Запусти от root"
[[ -f "$ENV_FILE" ]] && { set -a; . "$ENV_FILE"; set +a; }

reload() {
    docker ps --format '{{.Names}}' | grep -qx "$CT" || { cd "$DIR" && docker compose up -d --no-deps "$CT"; sleep 2; return 0; }
    docker exec "$CT" nginx -t >/dev/null 2>&1 || { docker exec "$CT" nginx -t; error "конфиг не применён"; }
    docker exec "$CT" nginx -s reload
    info "nginx перезагружен"
}

days_left() {
    local f="$1" exp
    [[ -f "$f" ]] || return 1
    exp=$(openssl x509 -enddate -noout -in "$f" 2>/dev/null | cut -d= -f2) || return 1
    [[ -n "$exp" ]] || return 1
    echo $(( ( $(date -d "$exp" +%s) - $(date +%s) ) / 86400 ))
}

detect_dns() {
    local ns=""
    ns=$(dig +short NS "$1" 2>/dev/null | tr 'A-Z' 'a-z') || true
    [[ -z "$ns" ]] && { ns=$(dig +short NS "${1#*.}" 2>/dev/null | tr 'A-Z' 'a-z') || true; }
    case "$ns" in
        *cloudflare*)     echo cf ;;
        *reg.ru*|*regru*) echo regru ;;
        *)                echo "${DEFAULT_DNS:-regru}" ;;
    esac
}

write_site_conf() {
    local d="$1" names="$2"
    cat > "$CONF_D/${d}.conf" <<CONF
server {
    server_name ${names};
    listen unix:$SOCK ssl proxy_protocol;
    http2 on;

    ssl_certificate         /etc/nginx/ssl/${d}-fullchain.pem;
    ssl_certificate_key     /etc/nginx/ssl/${d}-privkey.key;
    ssl_trusted_certificate /etc/nginx/ssl/${d}-fullchain.pem;

    root  /var/www/html;
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;

    location / { try_files \$uri \$uri/ =404; }
}
CONF
}

# --- разовое разворачивание, если ещё нет ------------------------------------
bootstrap() {
    local fresh=0
    [[ -f "$DIR/docker-compose.yml" && -d "$CONF_D" ]] || fresh=1

    if [[ $fresh -eq 1 ]]; then
        info "Первый запуск — разворачиваю окружение"
        [[ -f "$REMNANODE/docker-compose.yml" ]] || error "не найден $REMNANODE/docker-compose.yml"
        grep -q '/dev/shm' "$REMNANODE/docker-compose.yml" \
            || warn "в remnanode не проброшен /dev/shm — добавь volume '- /dev/shm:/dev/shm:rw' и пересоздай контейнер"

        local pkgs=()
        for p in curl socat wget cron openssl ca-certificates dnsutils; do
            dpkg -s "$p" &>/dev/null || pkgs+=("$p")
        done
        [[ ${#pkgs[@]} -gt 0 ]] && { apt-get update -qq; apt-get install -y -qq "${pkgs[@]}"; }

        grep -q "tcp_congestion_control = bbr" /etc/sysctl.conf 2>/dev/null || {
            printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' >> /etc/sysctl.conf
            sysctl -p >/dev/null; }
    fi

    # миграция со старой раскладки: креды не должны лежать в смонтированном каталоге
    if [[ -f "$DIR/.env" ]]; then
        cat "$DIR/.env" >> "$ENV_FILE" 2>/dev/null || true
        rm -f "$DIR/.env"; chmod 600 "$ENV_FILE"
        warn "перенёс $DIR/.env → $ENV_FILE (каталог монтируется в контейнер)"
    fi
    [[ -d "$DIR/certs" ]] && { rm -rf "$DIR/certs"; warn "удалил устаревший $DIR/certs"; }

    mkdir -p "$CONF_D" "$DIR/html"

    # --- миграция со старой раскладки (nginx.conf как default.conf) ----------
    if [[ -f "$DIR/nginx.conf" ]]; then
        local old_d
        old_d=$(awk '/^[[:space:]]*server_name[[:space:]]+[^_;]/{sub(/;/,"");print $2;exit}' "$DIR/nginx.conf" || true)
        if [[ -n "$old_d" && ! -f "$CONF_D/${old_d}.conf" ]]; then
            info "миграция: переношу $old_d из nginx.conf в conf.d/"
            # сертификаты под новые имена; старые пути оставляем симлинками — их читает hysteria
            if [[ -f "$DIR/fullchain.pem" && ! -e "$DIR/${old_d}-fullchain.pem" ]]; then
                mv "$DIR/fullchain.pem" "$DIR/${old_d}-fullchain.pem"
                ln -sf "${old_d}-fullchain.pem" "$DIR/fullchain.pem"
            fi
            if [[ -f "$DIR/privkey.key" && ! -e "$DIR/${old_d}-privkey.key" ]]; then
                mv "$DIR/privkey.key" "$DIR/${old_d}-privkey.key"
                ln -sf "${old_d}-privkey.key" "$DIR/privkey.key"
            fi
            write_site_conf "$old_d" "$old_d"
            mv "$DIR/nginx.conf" "$DIR/nginx.conf.migrated"
            info "миграция: conf.d/${old_d}.conf создан, старые пути сертификатов — симлинки"
        fi
    fi
    rm -f "$DIR/domains.conf"
    [[ -f "$DIR/html/index.html" ]] || cat > "$DIR/html/index.html" <<'HTML'
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Service</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{min-height:100vh;display:flex;align-items:center;
justify-content:center;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;
background:linear-gradient(145deg,#0f0f14,#1a1a24);color:#e4e4e7}
h1{font-size:1.6rem;font-weight:600;color:#fafafa}</style></head>
<body><h1>Service is running</h1></body></html>
HTML

    cat > "$CONF_D/00-common.conf" <<'CONF'
server_names_hash_bucket_size 64;

map $http_upgrade $connection_upgrade { default upgrade; "" close; }

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
CONF

    cat > "$DIR/.compose.new" <<COMPOSE
services:
  $CT:
    image: nginx:1.28
    container_name: $CT
    hostname: $CT
    restart: always
    ulimits:
      nofile: { soft: 1048576, hard: 1048576 }
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./:/etc/nginx/ssl:ro
      - ./html:/var/www/html:ro
      - /dev/shm:/dev/shm:rw
    command: sh -c 'rm -f $SOCK && exec nginx -g "daemon off;"'
    network_mode: host
    logging:
      driver: json-file
      options: { max-size: 30m, max-file: "5" }
COMPOSE

    local recreate=0
    if ! cmp -s "$DIR/.compose.new" "$DIR/docker-compose.yml" 2>/dev/null; then
        mv "$DIR/.compose.new" "$DIR/docker-compose.yml"
        recreate=1
        [[ $fresh -eq 0 ]] && warn "docker-compose.yml изменился (volumes) — пересоздаю контейнер"
    else
        rm -f "$DIR/.compose.new"
    fi

    [[ -f "$ACME" ]] || curl -fsSL https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@$(hostname -f 2>/dev/null || hostname)}"
    [[ -f "$ACME" ]] || error "acme.sh не установился"
    "$ACME" --set-default-ca --server letsencrypt >/dev/null

    touch "$ENV_FILE"; chmod 600 "$ENV_FILE"
    for v in REGRU_API_Username REGRU_API_Password CF_Token CF_Account_ID ACME_EMAIL DEFAULT_DNS; do
        if [[ -n "${!v:-}" ]] && ! grep -q "^${v}=" "$ENV_FILE"; then echo "${v}='${!v}'" >> "$ENV_FILE"; fi
    done

    ufw allow 22/tcp  comment 'SSH'         >/dev/null 2>&1 || true
    ufw allow 443/tcp comment 'HTTPS/VLESS' >/dev/null 2>&1 || true
    ufw allow 443/udp comment 'Hysteria2'   >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true

    local self; self=$(readlink -f "$0" 2>/dev/null || echo "$0")
    if [[ -f "$self" && "$self" != /dev/* && "$self" != /proc/* && "$self" != /usr/local/bin/ssfast ]]; then
        install -m 755 "$self" /usr/local/bin/ssfast && info "ssfast → /usr/local/bin/ssfast"
    fi

    cd "$DIR"
    if [[ $recreate -eq 1 ]]; then
        docker compose pull -q "$CT" || true
        docker compose up -d --no-deps --force-recreate "$CT"
        sleep 2
    elif ! docker ps --format '{{.Names}}' | grep -qx "$CT"; then
        docker compose up -d --no-deps "$CT"
        sleep 2
    fi
    [[ $fresh -eq 1 ]] && info "окружение готово"
}

# --- list --------------------------------------------------------------------
if [[ "${1:-}" == "list" ]]; then
    printf "%-28s %-9s %s\n" "DOMAIN" "EXPIRES" "SERVER_NAMES"
    for c in "$CONF_D"/*.conf; do
        [[ "$(basename "$c")" == "00-common.conf" ]] && continue
        [[ -f "$c" ]] || continue
        d=$(basename "$c" .conf)
        printf "%-28s %-9s %s\n" "$d" "$(days_left "$DIR/${d}-fullchain.pem" || echo -)дн" \
            "$(awk '/server_name/{sub(/;/,"");$1="";print;exit}' "$c")"
    done
    exit 0
fi

# --- add / update ------------------------------------------------------------
FORCE=0; DOMAINS=()
for a in "$@"; do
    case "$a" in
        --renew|--force) FORCE=1 ;;
        -*) error "неизвестный флаг: $a" ;;
        *)  DOMAINS+=("$a") ;;
    esac
done
[[ ${#DOMAINS[@]} -eq 0 ]] && { sed -n '4,6p' "$0" | sed 's/^# \{0,2\}//'; exit 1; }

bootstrap

D="${DOMAINS[0]}"
CERT="$DIR/${D}-fullchain.pem"
KEY="$DIR/${D}-privkey.key"

IPS=$(dig +short A "$D" 2>/dev/null | grep -E '^[0-9.]+$' | tr '\n' ' ') || true
[[ -z "$IPS" ]] && { IPS=$(getent ahostsv4 "$D" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ') || true; }
[[ -z "$IPS" ]] && error "$D не резолвится — добавь A-запись"
MY_IP=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
[[ -n "$MY_IP" && " $IPS " != *" $MY_IP "* ]] && warn "$D → $IPS, IP ноды $MY_IP среди них нет"

if DAYS=$(days_left "$CERT") && [[ $DAYS -gt $RENEW_DAYS && $FORCE -eq 0 ]]; then
    info "$D: сертификат валиден ещё ${DAYS} дн. — обновляю только конфиг"
else
    DNS=$(detect_dns "$D")
    case "$DNS" in
        regru) [[ -n "${REGRU_API_Username:-}" && -n "${REGRU_API_Password:-}" ]] \
                   || error "нет REGRU_API_Username/REGRU_API_Password (env или $ENV_FILE)" ;;
        cf)    [[ -n "${CF_Token:-}" ]] || error "нет CF_Token (env или $ENV_FILE)" ;;
    esac
    ARGS=(); for d in "${DOMAINS[@]}"; do ARGS+=(-d "$d"); done
    info "$D: выпускаю сертификат через ${DNS} (ec-256)"
    "$ACME" --issue --dns "dns_${DNS/cf/cf}" "${ARGS[@]}" --keylength ec-256 $([[ $FORCE -eq 1 ]] && echo --force) \
        || error "выпуск не удался — проверь креды ${DNS} и DNS-зону"
fi

"$ACME" --install-cert -d "$D" --ecc \
    --key-file "$KEY" --fullchain-file "$CERT" \
    --reloadcmd "docker exec $CT nginx -s reload 2>/dev/null || true; docker restart remnanode >/dev/null 2>&1 || true"

write_site_conf "$D" "${DOMAINS[*]}"

reload

echo ""
echo -e "${YELLOW}xray (Reality):${NC}  ${CYAN}\"dest\": \"$SOCK\", \"xver\": 1${NC}"
echo -e "                ${CYAN}\"serverNames\": [$(printf '"%s", ' "${DOMAINS[@]}" | sed 's/, $//')]${NC}"

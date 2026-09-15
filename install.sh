#!/usr/bin/env bash
# =============================================================================
#  ssfast — self-steal nginx для remnanode, мульти-домен
#
#  ssfast.sh init
#  ssfast.sh add <domain> [доп.домены...] [--name LABEL] [--dns regru|cf] [--html DIR]
#  ssfast.sh remove <name>
#  ssfast.sh list
#  ssfast.sh sync
#  ssfast.sh renew [name]
#
#  Каждый набор сертификатов живёт под своим именем:
#      /opt/nginx/certs/<name>/{fullchain.pem,privkey.key}
#      /opt/nginx/conf.d/<name>.conf
#      /opt/nginx/html/<name>/index.html
#  Реестр: /opt/nginx/domains.conf   (name|dns|domain1,domain2,...)
#  Креды:  /opt/nginx/.env           (chmod 600)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}━━━━━━━━━  $*  ━━━━━━━━━${NC}"; }

NGINX_DIR="/opt/nginx"
CONF_D="${NGINX_DIR}/conf.d"
CERTS="${NGINX_DIR}/certs"
HTML="${NGINX_DIR}/html"
DOMAINS_FILE="${NGINX_DIR}/domains.conf"
ENV_FILE="${NGINX_DIR}/.env"
COMPOSE="${NGINX_DIR}/docker-compose.yml"
REMNANODE_DIR="/opt/remnanode"
ACME_HOME="/root/.acme.sh"
ACME="${ACME_HOME}/acme.sh"
SOCK="/dev/shm/nginx.sock"
CONTAINER="remnanode-nginx"
RAW_URL="${RAW_URL:-https://raw.githubusercontent.com/ibmaga/SS-fast/main/ssfast.sh}"
RENEW_DAYS="${RENEW_DAYS:-30}"

[[ $EUID -ne 0 ]] && error "Запусти от root"
[[ -f "$ENV_FILE" ]] && { set -a; . "$ENV_FILE"; set +a; }

# =============================================================================
#  helpers
# =============================================================================
nginx_running() { docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; }

reload_nginx() {
    nginx_running || { warn "Контейнер ${CONTAINER} не запущен — пропускаю reload"; return 0; }
    docker exec "$CONTAINER" nginx -t || error "nginx -t не прошёл, конфиг не применён"
    docker exec "$CONTAINER" nginx -s reload
    info "nginx перезагружен"
}

cert_days_left() {
    local f="$1" exp
    [[ -f "$f" ]] || return 1
    exp=$(openssl x509 -enddate -noout -in "$f" 2>/dev/null | cut -d= -f2) || return 1
    [[ -n "$exp" ]] || return 1
    echo $(( ( $(date -d "$exp" +%s) - $(date +%s) ) / 86400 ))
}

registry_get()  { grep -E "^$1\|" "$DOMAINS_FILE" 2>/dev/null || true; }
registry_put()  {
    touch "$DOMAINS_FILE"
    grep -vE "^$1\|" "$DOMAINS_FILE" > "${DOMAINS_FILE}.tmp" 2>/dev/null || true
    echo "$1|$2|$3" >> "${DOMAINS_FILE}.tmp"
    sort -o "$DOMAINS_FILE" "${DOMAINS_FILE}.tmp"; rm -f "${DOMAINS_FILE}.tmp"
}
registry_del()  {
    [[ -f "$DOMAINS_FILE" ]] || return 0
    grep -vE "^$1\|" "$DOMAINS_FILE" > "${DOMAINS_FILE}.tmp" || true
    mv "${DOMAINS_FILE}.tmp" "$DOMAINS_FILE"
}

dns_env_check() {
    case "$1" in
        regru)
            [[ -n "${REGRU_API_Username:-}" && -n "${REGRU_API_Password:-}" ]] \
                || error "Для dns=regru нужны REGRU_API_Username / REGRU_API_Password (env или ${ENV_FILE})"
            ;;
        cf)
            [[ -n "${CF_Token:-}" ]] \
                || error "Для dns=cf нужен CF_Token (env или ${ENV_FILE}); при нескольких аккаунтах — ещё CF_Account_ID"
            ;;
        *) error "Неизвестный dns-провайдер: $1 (поддерживаются: regru, cf)" ;;
    esac
}
dns_plugin() { case "$1" in regru) echo dns_regru ;; cf) echo dns_cf ;; esac; }

# провайдер определяется по NS-записям зоны — руками указывать не нужно
detect_dns() {
    local d="$1" ns
    ns=$(dig +short NS "$d" 2>/dev/null | tr 'A-Z' 'a-z')
    [[ -z "$ns" ]] && ns=$(dig +short NS "${d#*.}" 2>/dev/null | tr 'A-Z' 'a-z')
    case "$ns" in
        *cloudflare*)     echo cf ;;
        *reg.ru*|*regru*) echo regru ;;
        *)                echo "${DEFAULT_DNS:-regru}" ;;
    esac
}

cmd_self_install() {
    local src; src=$(readlink -f "$0" 2>/dev/null || echo "$0")
    if [[ -f "$src" && "$src" != /dev/* && "$src" != /proc/* ]]; then
        [[ "$src" == "/usr/local/bin/ssfast" ]] || install -m 755 "$src" /usr/local/bin/ssfast
    else
        # запущены через curl | bash — тянем себя с origin
        curl -fsSL "$RAW_URL" -o /usr/local/bin/ssfast && chmod 755 /usr/local/bin/ssfast \
            || warn "Не удалось положить ssfast в /usr/local/bin (${RAW_URL})"
    fi
    cat > /etc/bash_completion.d/ssfast <<'EOF'
_ssfast() {
    local cur prev names
    cur="${COMP_WORDS[COMP_CWORD]}"; prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        --dns) COMPREPLY=($(compgen -W "regru cf" -- "$cur")); return ;;
        remove|renew) names=$(cut -d'|' -f1 /opt/nginx/domains.conf 2>/dev/null)
                      COMPREPLY=($(compgen -W "$names" -- "$cur")); return ;;
    esac
    [[ $COMP_CWORD -eq 1 ]] && COMPREPLY=($(compgen -W "init add remove list sync renew" -- "$cur"))
}
complete -F _ssfast ssfast
EOF
    info "ssfast → /usr/local/bin/ssfast (автодополнение после релогина)"
}

# =============================================================================
#  init
# =============================================================================
cmd_init() {
    section "Проверка remnanode"
    [[ -f "${REMNANODE_DIR}/docker-compose.yml" ]] \
        || error "Не найден ${REMNANODE_DIR}/docker-compose.yml"

    if grep -q '/dev/shm' "${REMNANODE_DIR}/docker-compose.yml"; then
        info "/dev/shm уже пробросен в remnanode"
    else
        warn "/dev/shm не проброшен в remnanode — добавь вручную в его docker-compose.yml:"
        echo -e "    ${CYAN}volumes:\n      - /dev/shm:/dev/shm:rw${NC}"
        echo -e "    ${GRAY}затем: docker compose -f ${REMNANODE_DIR}/docker-compose.yml up -d --force-recreate${NC}"
    fi

    section "Зависимости"
    local pkgs=()
    for p in curl socat wget cron openssl ca-certificates dnsutils; do
        dpkg -s "$p" &>/dev/null || pkgs+=("$p")
    done
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        apt-get update -qq && apt-get install -y -qq "${pkgs[@]}"
        info "Установлено: ${pkgs[*]}"
    fi

    if ! grep -q "tcp_congestion_control = bbr" /etc/sysctl.conf 2>/dev/null; then
        printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' >> /etc/sysctl.conf
        sysctl -p >/dev/null && info "BBR включён"
    fi

    section "Структура"
    mkdir -p "$CONF_D" "$CERTS" "$HTML"
    touch "$DOMAINS_FILE"
    [[ -f "$ENV_FILE" ]] || { : > "$ENV_FILE"; }
    chmod 600 "$ENV_FILE"

    # креды, переданные в одну строку, сохраняем — при следующих вызовах не нужны
    for v in REGRU_API_Username REGRU_API_Password CF_Token CF_Account_ID ACME_EMAIL DEFAULT_DNS; do
        [[ -n "${!v:-}" ]] && ! grep -q "^${v}=" "$ENV_FILE" && echo "${v}='${!v}'" >> "$ENV_FILE"
    done

    cat > "${CONF_D}/00-common.conf" <<'EOF'
server_names_hash_bucket_size 64;

map $http_upgrade $connection_upgrade {
    default upgrade;
    ""      close;
}

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
EOF

    cat > "$COMPOSE" <<EOF
services:
  ${CONTAINER}:
    image: nginx:1.28
    container_name: ${CONTAINER}
    hostname: ${CONTAINER}
    restart: always
    ulimits:
      nofile: { soft: 1048576, hard: 1048576 }
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./certs:/etc/nginx/ssl:ro
      - ./html:/var/www/html:ro
      - /dev/shm:/dev/shm:rw
    command: sh -c 'rm -f ${SOCK} && exec nginx -g "daemon off;"'
    network_mode: host
    logging:
      driver: json-file
      options: { max-size: 30m, max-file: "5" }
EOF

    section "acme.sh"
    if [[ ! -f "$ACME" ]]; then
        curl -fsSL https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@${HOSTNAME:-localhost}}"
    fi
    [[ -f "$ACME" ]] || error "acme.sh не установился"
    "$ACME" --set-default-ca --server letsencrypt >/dev/null
    info "acme.sh готов"

    section "UFW"
    ufw allow 22/tcp  comment 'SSH'         >/dev/null 2>&1 || true
    ufw allow 443/tcp comment 'HTTPS/VLESS' >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true

    section "Запуск nginx"
    cd "$NGINX_DIR"
    docker compose pull -q "$CONTAINER" || true
    docker compose up -d --no-deps "$CONTAINER"
    sleep 2
    [[ -S "$SOCK" ]] && info "Socket готов: $SOCK" || warn "Socket ещё не появился"

    cmd_self_install

    echo ""
    info "Готово. Дальше достаточно: ${CYAN}ssfast add layerzro.ru${NC}"
}

# =============================================================================
#  html
# =============================================================================
gen_html() {
    local name="$1" dir="${HTML}/${name}"
    mkdir -p "$dir"
    [[ -f "${dir}/index.html" ]] && return 0
    cat > "${dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="ru"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${name}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{min-height:100vh;display:flex;align-items:center;justify-content:center;
font-family:system-ui,-apple-system,'Segoe UI',sans-serif;
background:linear-gradient(145deg,#0f0f14 0%,#1a1a24 100%);color:#e4e4e7}
main{text-align:center}h1{font-size:1.75rem;font-weight:600;color:#fafafa}
p{margin-top:.5rem;font-size:.9rem;color:#52525b}
</style></head>
<body><main><h1>${name}</h1><p>Service is running</p></main></body></html>
EOF
    info "index.html → ${dir}/index.html"
}

# =============================================================================
#  add
# =============================================================================
cmd_add() {
    [[ -d "$CONF_D" && -f "$COMPOSE" ]] || { warn "Окружение не развёрнуто — запускаю init"; cmd_init; }

    local name="" dns="" html_src="" domains=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --dns)  dns="$2";  shift 2 ;;
            --html) html_src="$2"; shift 2 ;;
            -*)     error "Неизвестный флаг: $1" ;;
            *)      domains+=("$1"); shift ;;
        esac
    done
    [[ ${#domains[@]} -eq 0 ]] && error "Usage: ssfast.sh add <domain> [доп.домены...] [--name LABEL] [--dns regru|cf]"
    [[ -z "$name" ]] && name="${domains[0]}"
    if [[ -z "$dns" ]]; then
        dns=$(detect_dns "${domains[0]}")
        info "DNS-провайдер определён по NS: ${dns} (переопределить: --dns regru|cf)"
    fi
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || error "Недопустимое имя набора: $name"

    local primary="${domains[0]}"
    local cert_dir="${CERTS}/${name}"
    local conf="${CONF_D}/${name}.conf"
    mkdir -p "$cert_dir"

    section "DNS-проверка"
    local server_ip; server_ip=$(curl -fsS --max-time 5 https://api.ipify.org || true)
    for d in "${domains[@]}"; do
        local ips; ips=$(getent hosts "$d" | awk '{print $1}' | tr '\n' ' ')
        [[ -z "$ips" ]] && error "Домен $d не резолвится — добавь A-запись"
        if [[ -n "$server_ip" && " $ips " == *" $server_ip "* ]]; then
            info "$d → $ips (совпадает с сервером)"
        else
            warn "$d → $ips (IP сервера $server_ip не найден; для dns-01 это не критично)"
        fi
    done

    section "Сертификат: ${name}"
    local days
    if days=$(cert_days_left "${cert_dir}/fullchain.pem") && [[ $days -gt $RENEW_DAYS ]]; then
        info "Уже установлен, валиден ещё ${days} дн. — выпуск пропущен"
    elif days=$(cert_days_left "${ACME_HOME}/${primary}_ecc/fullchain.cer") && [[ $days -gt $RENEW_DAYS ]]; then
        info "Найден в хранилище acme.sh (${days} дн.) — ставлю без обращения к CA"
        install_cert "$name" "$primary"
    else
        dns_env_check "$dns"
        local args=()
        for d in "${domains[@]}"; do args+=(-d "$d"); done
        info "Выпускаю (${dns}, ec-256): ${domains[*]}"
        "$ACME" --issue --dns "$(dns_plugin "$dns")" "${args[@]}" --keylength ec-256 \
            || error "Выпуск не удался — проверь креды ${dns} и DNS-зону"
        install_cert "$name" "$primary"
    fi

    section "Контент"
    if [[ -n "$html_src" ]]; then
        mkdir -p "${HTML}/${name}"
        cp -r "${html_src%/}/." "${HTML}/${name}/"
        info "Скопировано из ${html_src}"
    else
        gen_html "$name"
    fi

    section "nginx"
    local server_names="${domains[*]}"
    cat > "$conf" <<EOF
server {
    server_name ${server_names};
    listen unix:${SOCK} ssl proxy_protocol;
    http2 on;

    ssl_certificate         /etc/nginx/ssl/${name}/fullchain.pem;
    ssl_certificate_key     /etc/nginx/ssl/${name}/privkey.key;
    ssl_trusted_certificate /etc/nginx/ssl/${name}/fullchain.pem;

    root  /var/www/html/${name};
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;

    location / { try_files \$uri \$uri/ =404; }
}
EOF
    info "conf → ${conf}"

    registry_put "$name" "$dns" "$(IFS=,; echo "${domains[*]}")"
    reload_nginx

    echo ""
    echo -e "${YELLOW}В инбаунде xray (Reality):${NC}"
    echo -e "  ${CYAN}\"dest\": \"${SOCK}\", \"xver\": 1${NC}"
    echo -e "  ${CYAN}\"serverNames\": [$(printf '"%s", ' "${domains[@]}" | sed 's/, $//')]${NC}"
}

install_cert() {
    local name="$1" primary="$2"
    "$ACME" --install-cert -d "$primary" --ecc \
        --key-file       "${CERTS}/${name}/privkey.key" \
        --fullchain-file "${CERTS}/${name}/fullchain.pem" \
        --reloadcmd      "docker exec ${CONTAINER} nginx -s reload 2>/dev/null || true"
    info "Установлен → ${CERTS}/${name}/"
}

# =============================================================================
#  remove / list / sync / renew
# =============================================================================
cmd_remove() {
    local name="${1:?Usage: ssfast.sh remove <name>}"
    local line; line=$(registry_get "$name")
    [[ -z "$line" ]] && warn "В реестре нет набора ${name} — чищу файлы, если остались"

    rm -f "${CONF_D}/${name}.conf"
    registry_del "$name"
    reload_nginx
    info "Конфиг ${name} удалён из nginx"
    echo -e "${GRAY}Сертификат и html оставлены: ${CERTS}/${name}, ${HTML}/${name}${NC}"
    echo -e "${GRAY}Удалить полностью: rm -rf ${CERTS}/${name} ${HTML}/${name}${NC}"
    [[ -n "$line" ]] && echo -e "${GRAY}Снять с автопродления: ${ACME} --remove -d $(echo "$line" | cut -d'|' -f3 | cut -d, -f1) --ecc${NC}"
}

cmd_list() {
    [[ -s "$DOMAINS_FILE" ]] || { info "Реестр пуст"; return 0; }
    printf "%-22s %-7s %-10s %s\n" "NAME" "DNS" "EXPIRES" "DOMAINS"
    while IFS='|' read -r name dns doms; do
        [[ -z "$name" ]] && continue
        local d; d=$(cert_days_left "${CERTS}/${name}/fullchain.pem" || echo "-")
        printf "%-22s %-7s %-10s %s\n" "$name" "$dns" "${d} дн." "$doms"
    done < "$DOMAINS_FILE"
}

cmd_sync() {
    [[ -s "$DOMAINS_FILE" ]] || { warn "Реестр пуст"; return 0; }
    while IFS='|' read -r name dns doms; do
        [[ -z "$name" ]] && continue
        info "Синхронизирую ${name}"
        # shellcheck disable=SC2086
        cmd_add ${doms//,/ } --name "$name" --dns "$dns"
    done < "$DOMAINS_FILE"
}

cmd_renew() {
    local target="${1:-}"
    while IFS='|' read -r name dns doms; do
        [[ -z "$name" ]] && continue
        [[ -n "$target" && "$target" != "$name" ]] && continue
        dns_env_check "$dns"
        local primary="${doms%%,*}"
        info "Продлеваю ${name} (${primary})"
        "$ACME" --renew -d "$primary" --ecc --force || warn "Не удалось продлить ${name}"
    done < "$DOMAINS_FILE"
    reload_nginx
}

# =============================================================================
case "${1:-}" in
    init)   shift; cmd_init "$@" ;;
    add)    shift; cmd_add "$@" ;;
    remove) shift; cmd_remove "$@" ;;
    list)   shift; cmd_list "$@" ;;
    sync)   shift; cmd_sync "$@" ;;
    renew)  shift; cmd_renew "$@" ;;
    self-install) shift; cmd_self_install ;;
    *.*)    cmd_add "$@" ;;          # ssfast layerzro.ru == ssfast add layerzro.ru
    *)      [[ -f "$0" ]] && sed -n '3,15p' "$0" | sed 's/^# \{0,2\}//' \
                          || echo "ssfast <domain> | init | add | remove | list | sync | renew" ;;
esac

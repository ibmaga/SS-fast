#!/usr/bin/env bash
# =============================================================================
#  SS-fast — self-steal nginx для уже установленного remnanode
#  Usage: bash install.sh <domain> <email> <regru_login> <regru_password>
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}━━━━━━━━━  $*  ━━━━━━━━━${NC}"; }

# ── args ──────────────────────────────────────────────────────────────────────
DOMAIN="${1:-}"
REGRU_USER="${3:-}"
REGRU_PASS="${4:-}"
EMAIL="${2:-}"

[[ -z "$DOMAIN"     ]] && error "Usage: bash install.sh <domain> <email> <regru_login> <regru_password>"
[[ -z "$EMAIL"      ]] && error "Usage: bash install.sh <domain> <email> <regru_login> <regru_password>"
[[ -z "$REGRU_USER" ]] && error "Usage: bash install.sh <domain> <email> <regru_login> <regru_password>"
[[ -z "$REGRU_PASS" ]] && error "Usage: bash install.sh <domain> <email> <regru_login> <regru_password>"
[[ $EUID -ne 0  ]] && error "Запусти от root"

# ── константы ─────────────────────────────────────────────────────────────────
REMNANODE_DIR="/opt/remnanode"
NGINX_DIR="/opt/nginx"
WEBROOT="${NGINX_DIR}/html"
ACME_HOME="/root/.acme.sh"
NGINX_SOCK="/dev/shm/nginx.sock"

# =============================================================================
section "1. Проверка окружения"
# =============================================================================
[[ ! -f "${REMNANODE_DIR}/docker-compose.yml" ]] && \
    error "Не найден ${REMNANODE_DIR}/docker-compose.yml — убедись что remnanode установлен"
info "remnanode найден в ${REMNANODE_DIR}"

# Проверяем что /dev/shm пробросен в remnanode контейнер
COMPOSE_FILE="${REMNANODE_DIR}/docker-compose.yml"
if grep -q '/dev/shm' "${COMPOSE_FILE}"; then
    info "/dev/shm уже пробросен в remnanode — OK"
else
    warn "/dev/shm не найден в ${COMPOSE_FILE}"
    info "Добавляю /dev/shm volume в remnanode..."

    # Добавляем строку после первого вхождения "volumes:" внутри сервиса remnanode
    # Используем python3 для надёжного парсинга YAML-отступов
    python3 << PYEOF
import re, sys

with open("${COMPOSE_FILE}", "r") as f:
    content = f.read()

# Ищем секцию volumes: внутри сервисов и добавляем /dev/shm если её нет
# Стратегия: найти строку с "volumes:" и добавить строку после неё
if '/dev/shm' in content:
    print("already present")
    sys.exit(0)

# Найти первую секцию volumes: (под сервисами)
lines = content.splitlines(keepends=True)
result = []
inserted = False
i = 0
while i < len(lines):
    result.append(lines[i])
    # Ищем строку вида "    volumes:" (с отступом — значит внутри сервиса)
    if not inserted and re.match(r'^(\s+)volumes:\s*$', lines[i]):
        indent = re.match(r'^(\s+)', lines[i]).group(1)
        # Добавляем строку с тем же отступом + 2 пробела
        result.append(indent + "  - /dev/shm:/dev/shm:rw\n")
        inserted = True
    i += 1

if not inserted:
    # volumes: секции нет вообще — добавляем в конец блока remnanode
    result2 = []
    i = 0
    while i < len(lines):
        result2.append(lines[i])
        if not inserted and re.match(r'^\s+remnanode\s*:', lines[i]):
            service_indent = re.match(r'^(\s+)', lines[i]).group(1)
            j = i + 1
            while j < len(lines) and (lines[j].strip() == '' or re.match(r'^' + service_indent + r'\s+', lines[j])):
                result2.append(lines[j])
                j += 1
            result2.append(service_indent + "  volumes:\n")
            result2.append(service_indent + "    - /dev/shm:/dev/shm:rw\n")
            inserted = True
            i = j
            continue
        i += 1
    result = result2

with open("${COMPOSE_FILE}", "w") as f:
    f.writelines(result)
print("patched")
PYEOF

    info "/dev/shm добавлен в ${COMPOSE_FILE}"

    # Перезапускаем remnanode чтобы применить изменения
    info "Перезапускаю remnanode для применения volume..."
    docker compose -f "${COMPOSE_FILE}" up -d --force-recreate remnanode
    info "remnanode перезапущен"
fi

# =============================================================================
section "2. Зависимости"
# =============================================================================
apt-get update -qq
apt-get install -y -qq curl socat wget python3

# BBR
if ! grep -q "tcp_congestion_control = bbr" /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc = fq"           >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null
    info "BBR включён"
fi
info "Зависимости готовы"

# =============================================================================
section "3. Проверка DNS"
# =============================================================================
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
         || curl -s --max-time 5 https://ifconfig.me \
         || true)
mapfile -t DNS_IPS < <(getent hosts "${DOMAIN}" | awk '{print $1}' || true)

if [[ ${#DNS_IPS[@]} -eq 0 ]]; then
    error "Домен ${DOMAIN} не резолвится. Добавь A-запись и повтори."
fi

info "DNS записи для ${DOMAIN}: ${DNS_IPS[*]}"

FOUND=0
for ip in "${DNS_IPS[@]}"; do
    [[ "$ip" == "$SERVER_IP" ]] && FOUND=1 && break
done

if [[ $FOUND -eq 0 ]]; then
    error "IP сервера (${SERVER_IP}) не найден среди A-записей домена (${DNS_IPS[*]}). Добавь запись и повтори."
else
    info "DNS OK: ${DOMAIN} содержит ${SERVER_IP}"
fi

# =============================================================================
section "4. Создание структуры /opt/nginx"
# =============================================================================
mkdir -p "${WEBROOT}"
info "Структура: ${NGINX_DIR}/"
info "           ${WEBROOT}/"

# =============================================================================
section "5. index.html (2048)"
# =============================================================================
cat > "${WEBROOT}/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>2048 — layerzro.ru</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            min-height: 100vh; display: flex; flex-direction: column;
            align-items: center; justify-content: center;
            font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
            background: linear-gradient(145deg, #0f0f14 0%, #1a1a24 100%);
            color: #e4e4e7; padding: 1rem;
        }
        .header { display: flex; align-items: center; justify-content: space-between; width: 100%; max-width: 340px; margin-bottom: 1rem; }
        h1 { font-size: 2rem; font-weight: 700; color: #fafafa; }
        .score-box { background: rgba(255,255,255,0.08); padding: 0.4rem 0.8rem; border-radius: 8px; font-size: 0.85rem; color: #a1a1aa; }
        .score-box span { font-weight: 600; color: #fff; }
        .grid-wrap { background: #2d2d36; border-radius: 12px; padding: 12px; position: relative; }
        .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; width: 280px; height: 280px; position: relative; }
        .cell { background: #3d3d48; border-radius: 6px; }
        .tile { position: absolute; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 28px; border-radius: 6px; transition: transform 0.12s ease, top 0.12s ease, left 0.12s ease, width 0.12s ease, height 0.12s ease; }
        .tile-2{background:#3d3d48;color:#e4e4e7}.tile-4{background:#4c4c5a;color:#e4e4e7}.tile-8{background:#71717a;color:#fff}.tile-16{background:#a1a1aa;color:#0f0f14}.tile-32{background:#d4d4d8;color:#0f0f14}.tile-64{background:#fafafa;color:#0f0f14}.tile-128{background:#fde047;color:#0f0f14;font-size:24px}.tile-256{background:#facc15;color:#0f0f14;font-size:24px}.tile-512{background:#eab308;color:#0f0f14;font-size:24px}.tile-1024{background:#ca8a04;color:#fff;font-size:20px}.tile-2048{background:#a16207;color:#fff;font-size:20px}.tile-super{background:#713f12;color:#fde047;font-size:18px}
        .hint { margin-top: 1rem; font-size: 0.8rem; color: #52525b; }
        .overlay { position: absolute; inset: 0; background: rgba(15,15,20,0.85); border-radius: 12px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1rem; }
        .overlay.hidden { display: none; }
        .overlay h2 { font-size: 1.5rem; }
        .overlay button { padding: 0.6rem 1.2rem; font-size: 1rem; border: none; border-radius: 8px; background: #3d3d48; color: #fff; cursor: pointer; }
        .overlay button:hover { background: #52525b; }
    </style>
</head>
<body>
    <div class="header"><h1>2048</h1><div class="score-box">Счёт: <span id="score">0</span></div></div>
    <div class="grid-wrap">
        <div class="grid" id="grid"></div>
        <div class="overlay hidden" id="overlay"><h2 id="overlayTitle">Игра окончена</h2><button id="restartBtn">Новая игра</button></div>
    </div>
    <p class="hint">Стрелки или свайп</p>
    <script>
(function(){
    const SIZE=4,CELL=66,GAP=8;let grid=[],score=0,touch=null;
    const $=id=>document.getElementById(id);
    const gridEl=$('grid'),scoreEl=$('score'),overlay=$('overlay'),title=$('overlayTitle');
    function empty(){return Array(SIZE).fill(null).map(()=>Array(SIZE).fill(0));}
    function cells(){gridEl.innerHTML='';for(let i=0;i<SIZE*SIZE;i++){const d=document.createElement('div');d.className='cell';gridEl.appendChild(d);}}
    function pos(r,c){return{top:GAP+r*(CELL+GAP),left:GAP+c*(CELL+GAP),width:CELL,height:CELL};}
    function render(){
        gridEl.querySelectorAll('.tile').forEach(t=>t.remove());
        for(let r=0;r<SIZE;r++)for(let c=0;c<SIZE;c++){
            const v=grid[r][c];if(!v)continue;
            const t=document.createElement('div');t.className='tile tile-'+(v<=2048?v:'super');t.textContent=v;
            const p=pos(r,c);Object.assign(t.style,{top:p.top+'px',left:p.left+'px',width:p.width+'px',height:p.height+'px'});
            gridEl.appendChild(t);
        }
        scoreEl.textContent=score;
    }
    function rndEmpty(){const e=[];for(let r=0;r<SIZE;r++)for(let c=0;c<SIZE;c++)if(!grid[r][c])e.push([r,c]);return e.length?e[Math.floor(Math.random()*e.length)]:null;}
    function spawn(){const p=rndEmpty();if(!p)return;grid[p[0]][p[1]]=Math.random()<.9?2:4;}
    function move(dir){
        let moved=false;const R=[0,1,2,3],C=[0,1,2,3];
        if(dir==='down')R.reverse();if(dir==='right')C.reverse();
        const vert=dir==='up'||dir==='down';
        for(const a of(vert?C:R)){
            const line=(vert?R:C).map(b=>vert?grid[b][a]:grid[a][b]).filter(v=>v);
            const m=[];let i=0;
            while(i<line.length){if(i+1<line.length&&line[i]===line[i+1]){m.push(line[i]*2);score+=line[i]*2;i+=2;moved=true;}else{m.push(line[i]);i++;}}
            const f=[...m,...Array(SIZE-m.length).fill(0)];
            if(dir==='down'||dir==='right')f.reverse();
            (vert?R:C).forEach((b,i)=>{const[r,c]=vert?[b,a]:[a,b];if(grid[r][c]!==f[i])moved=true;grid[r][c]=f[i];});
        }
        if(moved)spawn();return moved;
    }
    function canMove(){for(let r=0;r<SIZE;r++)for(let c=0;c<SIZE;c++){if(!grid[r][c])return true;const v=grid[r][c];if(c<SIZE-1&&grid[r][c+1]===v)return true;if(r<SIZE-1&&grid[r+1][c]===v)return true;}return false;}
    function step(d){if(overlay.classList.contains('hidden')&&move(d)){render();if(!canMove()){title.textContent='Игра окончена';overlay.classList.remove('hidden');}}}
    function init(){grid=empty();score=0;cells();spawn();spawn();render();overlay.classList.add('hidden');}
    document.addEventListener('keydown',e=>{const m={ArrowUp:'up',ArrowDown:'down',ArrowLeft:'left',ArrowRight:'right'};if(m[e.key]){e.preventDefault();step(m[e.key]);}});
    gridEl.addEventListener('touchstart',e=>{touch={x:e.touches[0].clientX,y:e.touches[0].clientY};},{passive:true});
    gridEl.addEventListener('touchend',e=>{if(!touch)return;const dx=e.changedTouches[0].clientX-touch.x,dy=e.changedTouches[0].clientY-touch.y;if(Math.abs(dx)>Math.abs(dy))step(dx>0?'right':'left');else if(Math.abs(dy)>=30)step(dy>0?'down':'up');touch=null;},{passive:true});
    $('restartBtn').addEventListener('click',init);init();
})();
    </script>
</body>
</html>
HTMLEOF
info "index.html → ${WEBROOT}/index.html"

# =============================================================================
section "6. acme.sh — установка"
# =============================================================================
if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then
    info "Устанавливаю acme.sh..."
    curl -fsSL https://get.acme.sh | sh -s email="${EMAIL}"
    info "acme.sh установлен"
else
    info "acme.sh уже установлен"
fi
ACME="${ACME_HOME}/acme.sh"
[[ ! -f "${ACME}" ]] && error "acme.sh не найден: ${ACME}"
export PATH="${ACME_HOME}:${PATH}"

# =============================================================================
section "7. Выпуск сертификата (dns-01, reg.ru)"
# =============================================================================

# Проверяем нужен ли перевыпуск
SKIP_CERT=0
if [[ -f "${NGINX_DIR}/fullchain.pem" ]]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "${NGINX_DIR}/fullchain.pem" 2>/dev/null | cut -d= -f2 || true)
    if [[ -n "$EXPIRY" ]]; then
        EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
        if [[ $DAYS_LEFT -gt 30 ]]; then
            info "Сертификат действителен ещё ${DAYS_LEFT} дней — пропускаю выпуск"
            SKIP_CERT=1
        else
            warn "Сертификат истекает через ${DAYS_LEFT} дней — перевыпускаю"
        fi
    fi
fi

if [[ $SKIP_CERT -eq 0 ]]; then
    info "Выпускаю сертификат для ${DOMAIN} (EC-256, Let's Encrypt, dns-01)..."

    "${ACME}" --set-default-ca --server letsencrypt

    # Сохраняем credentials в account.conf ДО запуска --issue
    ACME_CONF="${ACME_HOME}/account.conf"
    sed -i '/REGRU_API_Username/d' "${ACME_CONF}" 2>/dev/null || true
    sed -i '/REGRU_API_Password/d' "${ACME_CONF}" 2>/dev/null || true
    echo "REGRU_API_Username='${REGRU_USER}'" >> "${ACME_CONF}"
    echo "REGRU_API_Password='${REGRU_PASS}'" >> "${ACME_CONF}"

    REGRU_API_Username="${REGRU_USER}" REGRU_API_Password="${REGRU_PASS}" \
    "${ACME}" --issue \
        --dns dns_regru \
        -d "${DOMAIN}" \
        --keylength ec-256 \
        --key-file       "${NGINX_DIR}/privkey.key" \
        --fullchain-file "${NGINX_DIR}/fullchain.pem" \
        --force \
        || error "Не удалось выпустить сертификат. Проверь логин/пароль reg.ru и DNS."

    info "Сертификат → ${NGINX_DIR}/fullchain.pem, privkey.key"

    # Настраиваем автоперевыпуск
    "${ACME}" --install-cert -d "${DOMAIN}" \
        --ecc \
        --key-file       "${NGINX_DIR}/privkey.key" \
        --fullchain-file "${NGINX_DIR}/fullchain.pem" \
        --reloadcmd      "docker compose -f ${NGINX_DIR}/docker-compose.yml restart 2>/dev/null || true"
fi

# =============================================================================
section "9. nginx.conf"
# =============================================================================
cat > "${NGINX_DIR}/nginx.conf" << NGEOF
server_names_hash_bucket_size 64;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

server {
    server_name ${DOMAIN};
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.key;
    ssl_trusted_certificate /etc/nginx/ssl/fullchain.pem;

    root /var/www/html;
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
NGEOF
info "nginx.conf → ${NGINX_DIR}/nginx.conf"

# =============================================================================
section "10. docker-compose.yml"
# =============================================================================
cat > "${NGINX_DIR}/docker-compose.yml" << DCEOF
services:
  remnawave-nginx-ss:
    image: nginx:1.28
    container_name: remnawave-nginx-ss
    hostname: remnawave-nginx-ss
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./html:/var/www/html:ro
      - ./fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
      - ./privkey.key:/etc/nginx/ssl/privkey.key:ro
      - /dev/shm:/dev/shm:rw
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: 30m
        max-file: "5"
DCEOF
info "docker-compose.yml → ${NGINX_DIR}/docker-compose.yml"

# =============================================================================
section "11. UFW"
# =============================================================================
ufw allow 22/tcp  comment 'SSH'         > /dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS/VLESS' > /dev/null 2>&1 || true
ufw --force enable > /dev/null 2>&1 || true
ufw reload         > /dev/null 2>&1 || true
info "UFW: открыты 22, 443"

# =============================================================================
section "12. Запуск"
# =============================================================================
# Останавливаем старый контейнер если остался от предыдущего запуска скрипта
docker stop remnawave-nginx-ss 2>/dev/null || true
docker rm   remnawave-nginx-ss 2>/dev/null || true

cd "${NGINX_DIR}"
docker compose pull -q remnawave-nginx-ss
docker compose up -d --no-deps remnawave-nginx-ss
info "remnawave-nginx-ss запущен"

sleep 2
if [[ -S "${NGINX_SOCK}" ]]; then
    info "Unix socket готов: ${NGINX_SOCK}"
else
    warn "Socket ещё не появился — подожди несколько секунд"
fi

# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Self-steal установлен успешно!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Структура ${CYAN}/opt/nginx/${NC}"
echo -e "  ${GRAY}├── html/index.html${NC}"
echo -e "  ${GRAY}├── docker-compose.yml${NC}"
echo -e "  ${GRAY}├── nginx.conf${NC}"
echo -e "  ${GRAY}├── fullchain.pem${NC}"
echo -e "  ${GRAY}└── privkey.key${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  В конфиге remnanode (xray) укажи:${NC}"
echo -e ""
echo -e "  ${CYAN}\"dest\": \"/dev/shm/nginx.sock\"${NC}"
echo -e "  ${CYAN}\"xver\": 1${NC}"
echo -e "  ${CYAN}\"serverNames\": [\"${DOMAIN}\"]${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GRAY}Логи:    docker compose -f ${NGINX_DIR}/docker-compose.yml logs -f${NC}"
echo -e "${GRAY}Рестарт: docker compose -f ${NGINX_DIR}/docker-compose.yml restart${NC}"
echo ""

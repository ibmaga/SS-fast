# SS-fast — self-steal для уже установленного remnanode

Добавляет nginx с unix socket и selfsteal-страницей к уже работающему remnanode.  
Не трогает существующий `docker-compose.yml` remnanode — создаёт отдельный `/opt/nginx/docker-compose.yml`.

## Архитектура

```
клиент
  └─► 443/tcp (xray VLESS+Reality)
        └─► /dev/shm/nginx.sock (ssl proxy_protocol)
              └─► nginx → /opt/nginx/html (selfsteal 2048)
```

## Требования

- remnanode уже установлен в `/opt/remnanode`
- Ubuntu 22.04 / 24.04 или Debian 11 / 12
- Root доступ
- Домен с A-записью → этот сервер
- Порт 80 свободен (временно, только для ACME challenge)

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) <domain> <email>
```

**Пример:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) node1.example.com admin@example.com
```

## Что делает скрипт

| Шаг | Действие |
|-----|----------|
| 1 | Проверяет что remnanode установлен, при необходимости добавляет `/dev/shm` volume |
| 2 | Устанавливает зависимости, включает BBR |
| 3 | Проверяет DNS |
| 4 | Создаёт структуру `/opt/nginx/` |
| 5 | Создаёт `html/index.html` (игра 2048) |
| 6 | Устанавливает acme.sh |
| 7 | Запускает временный http-сервер для ACME challenge |
| 8 | Выпускает EC-256 сертификат (Let's Encrypt) |
| 9 | Создаёт `nginx.conf` (unix socket + proxy_protocol) |
| 10 | Создаёт `docker-compose.yml` |
| 11 | Настраивает UFW (22, 443) |
| 12 | Запускает `remnawave-nginx` контейнер |

## Структура после установки

```
/opt/
├── nginx/
│   ├── html/
│   │   └── index.html
│   ├── docker-compose.yml
│   ├── nginx.conf
│   ├── fullchain.pem
│   └── privkey.key
└── remnanode/
    └── docker-compose.yml   ← не трогается (только добавляется /dev/shm если нужно)
```

## После установки — настрой xray

В конфиге remnanode через remnawave-панель в inbound укажи:

```json
"realitySettings": {
    "dest": "/dev/shm/nginx.sock",
    "xver": 1,
    "serverNames": ["твой-домен.com"]
}
```

## Управление

```bash
# Логи
docker compose -f /opt/nginx/docker-compose.yml logs -f

# Рестарт
docker compose -f /opt/nginx/docker-compose.yml restart

# Обновление образа
docker compose -f /opt/nginx/docker-compose.yml pull
docker compose -f /opt/nginx/docker-compose.yml up -d
```

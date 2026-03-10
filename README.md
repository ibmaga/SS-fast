# SS-fast — self-steal для remnanode

Устанавливает nginx с unix socket и selfsteal-страницей (игра 2048) к уже работающему remnanode.  
Не трогает существующую инфраструктуру — создаёт отдельный контейнер `remnanode-nginx`.

## Архитектура

```
клиент
  └─► 443/tcp (xray VLESS+Reality)
        └─► /dev/shm/nginx.sock (ssl proxy_protocol)
              └─► nginx → /opt/nginx/html (selfsteal: игра 2048)
```

## Требования

- remnanode уже установлен в `/opt/remnanode`
- Ubuntu 22.04 / 24.04 или Debian 11 / 12
- Root доступ
- Домен с A-записью на этот сервер
- Аккаунт reg.ru с API-доступом (IP сервера в белом списке)

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) \
  <domain> <email> <regru_login> <regru_password>
```

**Пример:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) \
  node1.example.com admin@example.com admin@example.com MyApiPassword
```

## Что делает скрипт

| Шаг | Действие |
|-----|----------|
| 1 | Проверяет remnanode, добавляет `/dev/shm` volume если нужно |
| 2 | Устанавливает зависимости, включает BBR |
| 3 | Проверяет DNS (поддерживает несколько A-записей) |
| 4 | Создаёт структуру `/opt/nginx/` |
| 5 | Деплоит selfsteal-страницу (игра 2048) |
| 6 | Устанавливает acme.sh |
| 7 | Выпускает EC-256 сертификат через dns-01 (reg.ru API) — пропускает если действителен > 30 дней |
| 8 | Создаёт `nginx.conf` (unix socket + proxy_protocol + ssl_reject_handshake) |
| 9 | Создаёт `docker-compose.yml` для контейнера `remnanode-nginx` |
| 10 | Настраивает UFW (22, 443) |
| 11 | Запускает контейнер `remnanode-nginx` |

## Структура после установки

```
/opt/nginx/
├── html/
│   └── index.html        ← selfsteal страница (игра 2048)
├── docker-compose.yml
├── nginx.conf
├── fullchain.pem
└── privkey.key
```

## Настройка xray после установки

В remnawave-панели в настройках inbound укажи:

```json
"realitySettings": {
    "dest": "/dev/shm/nginx.sock",
    "xver": 1,
    "serverNames": ["твой-домен.ru"]
}
```

## Настройка API reg.ru

1. Войди в личный кабинет reg.ru
2. Перейди в **Настройки → Безопасность → API-доступ**
3. Установи отдельный API-пароль (не пароль от аккаунта)
4. Добавь IP каждого сервера в белый список

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

## Авто-перевыпуск сертификата

acme.sh устанавливает cron job который запускается раз в день.  
Сертификат перевыпускается автоматически когда до истечения остаётся менее 30 дней.  
После перевыпуска nginx перезапускается автоматически.

Проверить cron:
```bash
crontab -l | grep acme
```

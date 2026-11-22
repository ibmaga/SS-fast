# SS-fast — self-steal для remnanode

Устанавливает nginx с unix socket и выбранным встроенным сайтом к уже работающему remnanode.
Не трогает существующую инфраструктуру — создаёт отдельный контейнер `remnanode-nginx`.

## Архитектура

```
клиент
  └─► 443/tcp (xray VLESS+Reality)
        └─► /dev/shm/nginx.sock (ssl proxy_protocol)
              └─► nginx → /opt/nginx/webroots/<domain>/current (встроенный сайт)
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
| 5 | Устанавливает выбранный встроенный сайт |
| 6 | Устанавливает acme.sh |
| 7 | Выпускает EC-256 сертификат через dns-01 (reg.ru API) — пропускает если действителен > 30 дней |
| 8 | Создаёт `nginx.conf` (unix socket + proxy_protocol + ssl_reject_handshake) |
| 9 | Создаёт `docker-compose.yml` для контейнера `remnanode-nginx` |
| 10 | Настраивает UFW (22, 443) |
| 11 | Запускает контейнер `remnanode-nginx` |

## Выбор встроенного сайта

Флаг можно ставить до или после домена. Без флага используется Northvale Cloud.

| Флаг | Встроенный сайт | Значение `SS_SITE` |
|---|---|---|
| `-z`, `--zro` | Northvale Cloud | `zro` |
| `-m`, `--mona` | Tarnex | `mona` |
| `--stillform` | Stillform Studio, студия архитектурного света | `stillform` |
| `--apex-relay` | Apex Relay, клуб симрейсинга | `apex` |
| `--signal-archive` | Signal Archive, аудиолаборатория с кейсами, сметой и расчётом хранилища | `archive` |
| `--keyform` | Keyform Workshop, мастерская с каталогом деталей, сборками и конфигуратором | `keyform` |

```bash
# Установка с Stillform Studio
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) \
  --stillform <domain> <email> <regru_login> <regru_password>

# Установка Apex Relay на втором домене той же ноды
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) \
  --apex-relay racing.example.com admin@example.com your-login your-api-password

# Смена сайта только на указанном домене
bash <(curl -fsSL https://raw.githubusercontent.com/ibmaga/SS-fast/main/install.sh) \
  update racing.example.com --apex-relay
```

При установке флаг выбирает сайт для указанного домена. Повторная установка с
флагом или команда `update <domain> <флаг>` заменяет сайт только у этого домена.
Флаг можно передать до или после домена.

Домены старой установки продолжают обслуживать прежний сайт из `/opt/nginx/html`.
На старой установке с отдельными конфигами `update <domain> <флаг>` переводит
только выбранный домен на свой каталог. Команда `update <флаг>` без домена
сохраняет прежний режим для нод, на которых все сайты ещё общие. Как только
хотя бы один домен получает отдельный сайт, для обновления указывайте домен.

Исходники встроенных сайтов лежат в `sites/mona/`,
`sites/stillform/`, `sites/apex/`, `sites/archive/` и `sites/keyform/`. После правки пересоберите соответствующий
блок и проверьте синтаксис установщика.

```bash
python3 tools/embed-site.py stillform
python3 tools/embed-site.py apex
python3 tools/embed-site.py archive
python3 tools/embed-site.py keyform
bash -n install.sh
```

## Структура после установки

```
/opt/nginx/
├── html/                          ← общий сайт старых установок
├── webroots/
│   └── <domain>/
│       └── current/               ← активная версия сайта домена
├── sites/
│   └── <domain>.conf
├── docker-compose.yml
├── nginx.conf
├── <domain>-fullchain.pem
└── <domain>-privkey.key
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

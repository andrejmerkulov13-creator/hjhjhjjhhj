# TUFF CASINO — Telegram Mini App architecture

Проект содержит frontend, Node.js/Express backend, PostgreSQL, миграции, серверный кошелёк, Telegram Mini App auth, серверные игровые операции и заменяемый криптоплатёжный adapter.

> По умолчанию `TEST_MODE=true`. Реальные депозиты и production-бонусы заблокированы. Перед работой с реальными средствами необходимо проверить требования Telegram, лицензию, географические ограничения, KYC/AML, responsible gaming, правила платёжного провайдера и законодательство всех целевых юрисдикций.

## Структура

- `frontend/index.html` — Mini App, `API_BASE: '/api'`, без секретов и без настоящего баланса в localStorage.
- `backend/src` — API, Telegram validation, sessions, games, payments.
- `database/migrations` — PostgreSQL schema.
- `docker-compose.yml` — backend + PostgreSQL.
- `nginx.conf.example` — HTTPS reverse proxy.

## Быстрый запуск

```bash
cp .env.example .env
```

Сгенерируйте сильные значения:

```bash
openssl rand -hex 32   # SESSION_SECRET
openssl rand -hex 32   # PAYMENT_WEBHOOK_SECRET для mock test webhook
```

Вставьте их в `.env`. Токен бота вставьте самостоятельно:

```env
TELEGRAM_BOT_TOKEN=токен_из_BotFather
```

Не публикуйте `.env` и не помещайте токен во frontend.

Для локальной разработки вне Telegram можно временно включить только вместе с test mode:

```env
TEST_MODE=true
DEV_BYPASS_TELEGRAM=true
```

Запуск:

```bash
docker compose up -d --build
docker compose logs -f backend
curl http://127.0.0.1:3000/health
```

Миграции применяются контейнером автоматически. Вручную:

```bash
docker compose run --rm backend node src/migrate.js
```

## API

- `POST /api/miniapp/session`
- `POST /api/auth/telegram`
- `GET /api/me`
- `POST /api/games/launch`
- `POST /api/games/bet`
- `POST /api/payments/invoices`
- `POST /api/payments/webhook`
- `POST /api/bonuses/daily`
- `POST /api/missions/current/claim`
- `GET /health`

Финансовые POST-запросы требуют заголовок `Idempotency-Key`.

## Telegram Mini App

1. Создайте бота в `@BotFather`.
2. Вставьте токен только в `.env` на VPS.
3. Настройте Menu Button / Mini App URL на `https://ваш-домен/`.
4. Backend валидирует `initData` официальным HMAC-алгоритмом и проверяет `auth_date`.
5. В production установите `DEV_BYPASS_TELEGRAM=false`.

## Денежная модель

USDT хранится в минимальных единицах с scale 6. Например, `1 USDT = 1000000`. PostgreSQL использует `numeric(36,0)`, Node.js — `BigInt`. Ставки передаются строкой и разбираются без `Number`/floating point.

Баланс изменяется только внутри SQL-транзакций с `SELECT ... FOR UPDATE`. Каждое изменение записывается в `transactions`: `deposit`, `bet`, `payout`, `bonus`, `refund`, `withdrawal`, `adjustment`.

## Игры

`POST /api/games/bet` принимает:

```json
{"gameId":"ruby-sevens","amount":"1.25","currency":"USDT"}
```

Сервер проверяет пользователя, игру, лимиты, баланс и идемпотентность, блокирует кошелёк, списывает ставку, использует `crypto.randomInt`, рассчитывает payout, сохраняет bet и ledger. Встроенная игровая математика является только test-mode примером, а не сертифицированным RNG. Для production нужен сертифицированный game/RNG provider, аудит математики и ограничения по юрисдикции.

## Платёжный adapter

В проекте есть только `MockPaymentAdapter` для test mode. Конкретный API провайдера намеренно не придуман. Возможные категории провайдеров: лицензированный crypto payment processor с hosted invoice, поддержкой нужной вам юрисдикции, USDT TRC20/ERC20, подписанными webhook, testnet/sandbox и политикой, допускающей ваш вид деятельности.

После выбора провайдера:

1. Создайте adapter в `backend/src/services/payments/`.
2. Реализуйте `createInvoice()` по официальной документации.
3. Реализуйте проверку подлинной подписи webhook по документации провайдера.
4. Нормализуйте событие в `{externalId,status,amount,asset,network,eventId}`.
5. Добавьте adapter в `payments/index.js`.
6. Укажите `PAYMENT_PROVIDER`, `PAYMENT_API_KEY`, `PAYMENT_WEBHOOK_SECRET`.
7. Никогда не начисляйте баланс по frontend redirect/callback.

Баланс начисляется только после проверенного webhook, совпадения order ID, валюты, сети, суммы, статуса и проверки повторной обработки.

### Test webhook

В mock mode тело подписывается HMAC-SHA256 от точной JSON-строки ключом `PAYMENT_WEBHOOK_SECRET`, подпись передаётся в `X-Payment-Signature`. Используйте только в закрытой тестовой среде.

## Вывод

Таблица `withdrawals` и статусы созданы, но API автоматического вывода отсутствует намеренно. Production withdrawal требует KYC/AML, risk engine, ручного review, address screening, 2FA/step-up auth, лимитов, холодного/горячего кошелька и отдельного подписывающего сервиса. Не храните приватный ключ кошелька в frontend или основном web-контейнере.

## VPS, домен и HTTPS

1. Купите VPS и домен.
2. Установите Docker Engine и Compose plugin.
3. Направьте A/AAAA запись домена на VPS.
4. Скопируйте проект на сервер.
5. Создайте `.env` и заполните секреты.
6. Запустите `docker compose up -d --build`.
7. Установите Nginx и Certbot.
8. Адаптируйте `nginx.conf.example` под домен.
9. Выпустите TLS-сертификат Let's Encrypt.
10. Установите `APP_ORIGIN=https://ваш-домен` и `NODE_ENV=production`.
11. Настройте Mini App URL в BotFather.
12. Подключите sandbox выбранного платёжного провайдера и webhook URL `https://ваш-домен/api/payments/webhook`.
13. Проверьте повторные webhook, несовпадение суммы/сети, истёкшие invoices и параллельные ставки.
14. Только после аудита и юридического допуска отключайте test mode.

## Production checklist

- `NODE_ENV=production`
- `TEST_MODE=false`
- `DEV_BYPASS_TELEGRAM=false`
- сильные `SESSION_SECRET` и provider webhook secret
- настоящий provider adapter и sandbox tests
- managed PostgreSQL backups/PITR
- мониторинг, alerting и offsite audit logs
- KYC/AML, sanctions/address screening
- возрастные и географические ограничения
- responsible gaming и самоисключение
- сертифицированный RNG/game provider
- penetration test и dependency scanning
- DDoS/WAF и секрет-хранилище

## Что изменено во frontend

- сохранена мобильная тёмная красно-золотая компоновка TUFF;
- три карточки в ряд, миссии, топ, горячие игры и нижняя панель;
- `CONFIG.API_BASE='/api'`, `CURRENCY='USDT'`;
- убран localStorage как источник баланса;
- результат игры и новый баланс приходят только от backend;
- оставлены только USDT TRC20/ERC20;
- frontend не содержит токенов и provider keys.

## Примечание о Docker build context

Docker собирается из корня проекта, чтобы образ мог получить `backend`, `frontend` и `database`:

```yaml
build:
  context: .
  dockerfile: backend/Dockerfile
```

Встроенная игровая математика теперь принудительно работает только при `TEST_MODE=true`. При `TEST_MODE=false` endpoint ставок возвращает `GAME_PROVIDER_REQUIRED`, пока не подключён сертифицированный game/RNG provider.

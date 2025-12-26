# Gonka Admin — Design Document

**Дата:** 2025-12-26
**Статус:** Draft
**Автор:** Claude + DevOps Team

---

## 1. Обзор проекта

Централизованный веб-сервис для администрирования нод Gonka AI. Позволяет DevOps команде:
- Устанавливать ноды с нуля
- Мониторить состояние всех нод в реальном времени
- Управлять эпохами и claim rewards
- Управлять кошельками и пулами
- Выполнять ручные операции через тулкит
- Получать уведомления в Telegram

---

## 2. Архитектура и технологический стек

### 2.1 Общая архитектура

Централизованный веб-сервис, развернутый локально на macOS с возможностью переноса на внешний сервер.

**Компоненты системы:**
- **Backend**: FastAPI (Python) — REST API + WebSocket для real-time обновлений
- **Frontend**: React + Vite + TanStack Query + Ant Design — современный responsive UI
- **База данных**: PostgreSQL — структурированное хранение данных нод, эпох, операций
- **Графики**: Recharts — визуализация метрик по эпохам
- **Deployment**: Docker Compose — одинаковое окружение на macOS и Linux

### 2.2 Подключение к нодам

- **SSH + ControlMaster** для быстрых повторных подключений (обязательно, см. CLAUDE.md)
- **Docker API** через SSH для управления контейнерами
- **HTTP API нод** (порт 8000) для получения статусов и метрик
- **Tracker API** для данных по эпохам

### 2.3 Аутентификация

HTTP Basic Auth для простоты (внутренний сервис в закрытой сети).

### 2.4 Real-time коммуникация

WebSocket для:
- Streaming логов установки/операций
- Live обновления статусов нод
- Push уведомлений в интерфейс

### 2.5 Фоновые задачи

- **FastAPI Background Tasks** для длительных операций (установка нод, claims)
- **APScheduler** для периодических задач:
  - Health checks каждые 30-60 сек
  - Импорт эпох каждые 1-6 часов
- **Retry механизм** для критических операций (обязательно)

---

## 3. Модель данных (PostgreSQL)

### 3.1 Таблица `nodes` — информация о нодах

```sql
CREATE TABLE nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) UNIQUE NOT NULL,
    pool_id UUID REFERENCES pools(id),
    wallet_id UUID REFERENCES wallets(id),
    ssh_host VARCHAR(255) NOT NULL,
    ssh_port INTEGER DEFAULT 22,
    ssh_user VARCHAR(100) NOT NULL,
    api_port INTEGER DEFAULT 8000,
    p2p_port INTEGER DEFAULT 5000,
    install_dir VARCHAR(500) DEFAULT '/opt/gonka',
    hf_cache_dir VARCHAR(500) DEFAULT '/opt/hf-cache',
    status VARCHAR(50) DEFAULT 'stopped',  -- installing, running, paused, stopped, error, syncing
    start_date DATE,
    end_date DATE,
    server_cost_usd_monthly DECIMAL(10,2),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### 3.2 Таблица `pools` — пулы

```sql
CREATE TABLE pools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.3 Таблица `wallets` — кошельки

```sql
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address VARCHAR(255) UNIQUE NOT NULL,
    label VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.4 Таблица `node_wallet_history` — история привязок кошельков

```sql
CREATE TABLE node_wallet_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
    wallet_id UUID REFERENCES wallets(id),
    changed_by VARCHAR(255),
    changed_at TIMESTAMP DEFAULT NOW(),
    reason TEXT
);
```

### 3.5 Таблица `epochs` — данные по эпохам

```sql
CREATE TABLE epochs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    epoch_number INTEGER UNIQUE NOT NULL,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    avg_gonka_per_node DECIMAL(15,6),
    avg_usd_per_gonka_cost DECIMAL(15,6),
    gonka_usd_rate DECIMAL(15,6),
    status VARCHAR(50) DEFAULT 'active',  -- active, completed, claimed
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### 3.6 Таблица `node_epochs` — награды нод за эпохи

```sql
CREATE TABLE node_epochs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
    epoch_id UUID REFERENCES epochs(id) ON DELETE CASCADE,
    gonka_earned DECIMAL(15,6),
    blocks_mined INTEGER,
    claim_status VARCHAR(50) DEFAULT 'pending',  -- pending, claimed, failed
    claimed_at TIMESTAMP,
    wallet_id UUID REFERENCES wallets(id),
    tracker_url VARCHAR(500),
    dashboard_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(node_id, epoch_id)
);
```

### 3.7 Таблица `operations_log` — журнал операций

```sql
CREATE TABLE operations_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE SET NULL,
    operation_type VARCHAR(100) NOT NULL,  -- install, force_claim, reset_db, update_api, pause, resume
    initiated_by VARCHAR(255),
    status VARCHAR(50) DEFAULT 'pending',  -- pending, running, success, failed
    started_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP,
    duration_seconds INTEGER,
    command TEXT,
    stdout_log TEXT,
    stderr_log TEXT,
    config_before JSONB,
    config_after JSONB,
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.8 Таблица `node_health_checks` — история проверок здоровья

```sql
CREATE TABLE node_health_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE CASCADE,
    checked_at TIMESTAMP DEFAULT NOW(),
    is_healthy BOOLEAN,
    docker_status VARCHAR(50),  -- running, stopped, not_found
    sync_status VARCHAR(50),    -- syncing, synced, stuck, unknown
    db_size_bytes BIGINT,
    db_growth_rate DECIMAL(15,6),
    api_response_time_ms INTEGER,
    last_block_height BIGINT,
    issues JSONB DEFAULT '[]',
    metrics JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.9 Таблица `notifications` — уведомления

```sql
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID REFERENCES nodes(id) ON DELETE SET NULL,
    type VARCHAR(50) NOT NULL,      -- error, warning, info, success
    category VARCHAR(100) NOT NULL, -- sync_stuck, epoch_completed, claim_available, node_down, operation_completed
    title VARCHAR(255) NOT NULL,
    message TEXT,
    sent_to_telegram BOOLEAN DEFAULT FALSE,
    telegram_sent_at TIMESTAMP,
    read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.10 Таблица `system_config` — глобальные настройки

```sql
CREATE TABLE system_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(255) UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    updated_by VARCHAR(255),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Примеры настроек:
-- health_check_interval_seconds: 60
-- epoch_import_interval_hours: 6
-- telegram_bot_token: "..."
-- telegram_chat_id: "..."
-- gonka_price_api_url: "https://..."
```

---

## 4. Функциональные модули

### 4.1 Установка ноды с нуля

**Входные данные (JSON):**
```json
{
  "node_name": "london-2-tower",
  "ssh_host": "192.168.1.100",
  "ssh_user": "root",
  "ssh_port": 22,
  "key_password": "secure_password",
  "api_port": 8000,
  "p2p_port": 5000,
  "hf_cache_dir": "/opt/hf-cache",
  "install_dir": "/opt/gonka",
  "pool_id": "uuid-pool",
  "wallet_id": "uuid-wallet",
  "server_cost_usd_monthly": 1500.00
}
```

**Процесс установки:**
1. Проверка SSH подключения
2. Выполнение шагов из `node_setup.txt`:
   - System update
   - NVIDIA check
   - Docker install
   - NVIDIA Docker Toolkit
   - Directory setup
   - Clone Gonka repo
   - Config generation
   - Docker pull
3. Каждый шаг имеет статус и логируется в `operations_log`
4. Real-time streaming логов через WebSocket
5. Изменение статуса ноды: `installing` → `running` (или `error`)
6. Retry механизм для критических шагов

**API endpoint:** `POST /api/v1/nodes/install`

### 4.2 Мониторинг состояния нод

**Health Check Scheduler (каждые 30-60 секунд):**

Для каждой ноды проверяется:
1. **Docker статус** — `docker ps` через SSH, проверка контейнера `node`
2. **Синхронизация блокчейна** — два последовательных замера `du -s .inference/data/application.db/`
   - Если размер растет → `syncing`
   - Если размер не меняется > 5 минут → `stuck`
   - Если БД отсутствует → `error`
3. **API доступность** — HTTP запрос к `http://node:8000/health`
4. **Последний блок** — получение текущей высоты блока из API ноды

**Обнаружение проблем:**
- Синхронизация застряла → уведомление category='sync_stuck'
- Docker контейнер остановлен → category='node_down'
- Уведомления отправляются в Telegram

### 4.3 Управление эпохами

**Периодический импорт (каждые 1-6 часов):**

1. **Опрос Tracker API** для каждой ноды:
   - Получение списка завершенных эпох
   - Парсинг данных: epoch_number, gonka_earned, blocks_mined
   - Сохранение/обновление в `node_epochs`

2. **Получение курса GONKA/USD:**
   - API CoinGecko или Jupiter DEX
   - Сохранение в таблицу `epochs` (gonka_usd_rate)

3. **Расчет себестоимости:**
   ```
   Для каждой эпохи:
   - Длительность эпохи (дни) = end_date - start_date
   - Затраты всех нод за период = SUM(server_cost_usd_monthly / 30 * длительность_дней)
   - Общий GONKA за эпоху = SUM(node_epochs.gonka_earned)
   - avg_usd_per_gonka_cost = затраты / общий_GONKA
   ```

4. **Расчет среднего GONKA на ноду:**
   ```
   avg_gonka_per_node = SUM(node_epochs.gonka_earned) / COUNT(активных_нод)
   ```

**Полуавтоматический Claim:**

1. Обнаружение завершенных эпох → уведомление "Эпоха {number} завершена"
2. DevOps вручную запускает claim через UI
3. Force claim для конкретной эпохи через форму

### 4.4 Табличный view эпох (как в Excel)

**Структура интерфейса:**

**Верхняя часть (сводные строки):**
- Строка 1: Номера эпох (97, 98, 99... 118) — sticky header
- Строка 2: avg_usd_per_gonka_cost для каждой эпохи
- Строка 3: avg_gonka_per_node для каждой эпохи

**Основная таблица:**
- Sticky левые колонки: Пулл, Нода, Старт, Финиш, Блоки, Трекер, Кошелек, Всего GONKA
- Динамические колонки: Эпохи с gonka_earned для каждой ноды
- Цветовая индикация claim_status (зеленый/желтый/красный)

**Функциональность:**
- Горизонтальная прокрутка
- Сортировка и фильтрация
- Export в Excel

### 4.5 Управление кошельками и пулами

**Справочники:**
- CRUD для кошельков и пулов
- Привязка ноды к кошельку/пулу через dropdown
- История изменений привязок в `node_wallet_history`
- Bulk операции (массовая смена кошелька)

### 4.6 Тулкит для ручных операций

**Операции:**

| Операция | Описание | Команда |
|----------|----------|---------|
| Force Claim | Принудительное начисление | `curl -X POST http://{node}:9200/admin/v1/claim-reward/recover -d '{"force_claim": true, "epoch_id": N}'` |
| Сброс БД | Удаление данных блокчейна | `docker compose down node` + `unsafe-reset-all` + `docker compose up node -d` |
| Обновление API | Обновление до последней версии | `git pull` + `docker compose pull` + `docker compose up -d` |
| Пауза | Остановка майнинга | `docker compose stop node` |
| Возобновление | Запуск майнинга | `docker compose up node -d` |
| Логи | Получение логов | `docker compose logs --tail=N node` |
| Проверка синхронизации | Детальная проверка | Два замера `du -s .inference/data/application.db/` |

**UX:** Real-time streaming логов, retry, история в `operations_log`

### 4.7 Уведомления Telegram

**Типы уведомлений:**

| Категория | Приоритет | Шаблон сообщения |
|-----------|-----------|------------------|
| sync_stuck | Critical | "⚠️ Нода {name} — синхронизация остановилась!" |
| node_down | Critical | "🔴 Нода {name} недоступна!" |
| epoch_completed | Info | "📊 Эпоха {number} завершена. Доступен claim для {N} нод." |
| claim_available | Info | "💰 Claim доступен: {node_name}, эпоха {number}" |
| claim_success | Success | "✅ Claim выполнен: {node_name}, эпоха {number}" |
| claim_failed | Error | "❌ Claim провален: {node_name}" |
| operation_completed | Success | "✅ Операция '{type}' завершена" |
| operation_failed | Error | "❌ Операция '{type}' провалена" |

**Дедупликация:** Не отправлять повторно одинаковые уведомления в течение 15 минут.

---

## 5. Структура API (Backend)

### 5.1 REST API Endpoints

**Ноды:**
```
GET    /api/v1/nodes                    — список всех нод
POST   /api/v1/nodes                    — создать ноду
GET    /api/v1/nodes/{id}               — детали ноды
PUT    /api/v1/nodes/{id}               — обновить конфигурацию
DELETE /api/v1/nodes/{id}               — удалить ноду
POST   /api/v1/nodes/install            — установить ноду с нуля
POST   /api/v1/nodes/{id}/change-wallet — сменить кошелек
POST   /api/v1/nodes/bulk/change-wallet — массовая смена кошелька
GET    /api/v1/nodes/{id}/health        — последний health check
GET    /api/v1/nodes/{id}/health/history— история health checks
GET    /api/v1/nodes/{id}/operations    — история операций ноды
GET    /api/v1/nodes/{id}/epochs        — эпохи ноды
```

**Эпохи:**
```
GET    /api/v1/epochs                   — список эпох с агрегатами
GET    /api/v1/epochs/{number}          — детали эпохи
GET    /api/v1/epochs/{number}/nodes    — ноды в эпохе с наградами
POST   /api/v1/epochs/import            — ручной запуск импорта
```

**Claims:**
```
GET    /api/v1/claims/pending           — pending claims
POST   /api/v1/claims/execute           — выполнить claim (bulk)
POST   /api/v1/claims/force             — force claim
```

**Справочники:**
```
GET/POST/PUT/DELETE /api/v1/wallets
GET/POST/PUT/DELETE /api/v1/pools
```

**Тулкит:**
```
POST   /api/v1/toolkit/force-claim
POST   /api/v1/toolkit/reset-db
POST   /api/v1/toolkit/update-api
POST   /api/v1/toolkit/pause
POST   /api/v1/toolkit/resume
POST   /api/v1/toolkit/logs
POST   /api/v1/toolkit/check-sync
```

**Уведомления и настройки:**
```
GET    /api/v1/notifications
POST   /api/v1/notifications/{id}/read
POST   /api/v1/notifications/test-telegram
GET    /api/v1/settings
PUT    /api/v1/settings
```

**Dashboard:**
```
GET    /api/v1/dashboard/summary
GET    /api/v1/dashboard/epochs-table
```

### 5.2 WebSocket Endpoints

```
WS /ws/logs/{operation_id}    — streaming логов операции
WS /ws/health                 — real-time статусы нод
WS /ws/notifications          — push уведомлений
```

---

## 6. Структура Frontend

### 6.1 Страницы и роутинг

```
/                    — Dashboard
/nodes               — Список нод
/nodes/:id           — Детальная страница ноды
/nodes/install       — Установка новой ноды
/epochs              — Табличный view эпох
/epochs/:number      — Детали эпохи
/claims              — Pending claims
/wallets             — Справочник кошельков
/pools               — Справочник пулов
/toolkit             — Страница с операциями
/notifications       — История уведомлений
/settings            — Настройки системы
```

### 6.2 Компоненты (Ant Design)

**Layout:**
- Sider: Menu, Logo, Notification Badge
- Header: Breadcrumbs, Health Summary, Notification Bell
- Content: основной контент

**Dashboard:** Statistics Cards, Nodes Health Table, Recent Operations, Pending Claims Alert

**Epochs Table:** Toolbar с фильтрами, Summary Rows (sticky), Table с horizontal scroll

**Node Detail:** PageHeader, Tabs (Обзор, История эпох, Операции, Мониторинг, Конфигурация)

**Toolkit:** Cards Grid с формами для каждой операции

---

## 7. Структура файлов проекта

```
gonka-admin/
├── docker-compose.yml
├── .env.example
├── README.md
│
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── alembic.ini
│   ├── alembic/versions/
│   ├── app/
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── database.py
│   │   ├── models/          # SQLAlchemy models
│   │   ├── schemas/         # Pydantic schemas
│   │   ├── api/             # API routes
│   │   ├── services/        # Business logic
│   │   │   ├── ssh_manager.py
│   │   │   ├── node_installer.py
│   │   │   ├── health_checker.py
│   │   │   ├── epoch_importer.py
│   │   │   ├── claim_service.py
│   │   │   ├── telegram_notifier.py
│   │   │   ├── price_fetcher.py
│   │   │   └── toolkit_executor.py
│   │   ├── tasks/           # Background tasks
│   │   │   ├── scheduler.py
│   │   │   ├── health_check_task.py
│   │   │   ├── epoch_import_task.py
│   │   │   └── notification_task.py
│   │   └── websocket/       # WebSocket handlers
│   └── tests/
│
├── frontend/
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── package.json
│   ├── vite.config.ts
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx
│   │   ├── api/             # TanStack Query
│   │   ├── components/      # Reusable components
│   │   ├── pages/           # Page components
│   │   ├── hooks/           # Custom hooks
│   │   ├── store/           # State
│   │   └── utils/           # Helpers
│   └── public/
│
└── ssh-keys/                # Volume for SSH keys
```

---

## 8. Развертывание

### 8.1 Docker Compose

```yaml
version: '3.8'

services:
  backend:
    build: ./backend
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://user:pass@host:5432/gonka_admin
      - SSH_KEYS_PATH=/ssh-keys
    volumes:
      - ./ssh-keys:/ssh-keys:ro
    depends_on:
      - db

  frontend:
    build: ./frontend
    ports:
      - "3000:80"
    depends_on:
      - backend

  db:
    image: postgres:15
    environment:
      - POSTGRES_USER=gonka
      - POSTGRES_PASSWORD=secret
      - POSTGRES_DB=gonka_admin
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

### 8.2 Переменные окружения (.env)

```env
# Database
DATABASE_URL=postgresql://gonka:secret@localhost:5432/gonka_admin

# SSH
SSH_KEYS_PATH=/path/to/ssh-keys
SSH_CONTROL_MASTER_PATH=/tmp/ssh_gonka_cm

# Telegram
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id

# Scheduler
HEALTH_CHECK_INTERVAL_SECONDS=60
EPOCH_IMPORT_INTERVAL_HOURS=6

# Price API
GONKA_PRICE_API_URL=https://api.coingecko.com/api/v3/...

# Auth
BASIC_AUTH_USERNAME=admin
BASIC_AUTH_PASSWORD=secure_password
```

---

## 9. Ограничения и масштабирование

- **Количество нод:** до 50 (текущая архитектура без оптимизаций)
- **Установка нод:** 1-10 в сутки
- **Health checks:** каждые 30-60 секунд
- **Импорт эпох:** каждые 1-6 часов

При увеличении нагрузки потребуется:
- Connection pooling для PostgreSQL
- Параллельные SSH операции
- Redis для кэширования статусов
- Celery для очереди задач

---

## 10. Безопасность

- HTTP Basic Auth для доступа к админке
- SSH ключи хранятся в отдельном volume
- SSH ControlMaster для минимизации подключений (защита от fail2ban)
- HTTPS при развертывании на внешнем сервере (nginx + Let's Encrypt)
- Валидация всех входных данных (Pydantic schemas)

---

## 11. Следующие шаги

1. Создание структуры проекта (backend + frontend)
2. Настройка Docker Compose
3. Реализация моделей и миграций БД
4. SSH Manager с ControlMaster
5. Health Check модуль
6. Базовый UI (Dashboard, список нод)
7. Табличный view эпох
8. Тулкит операций
9. Telegram уведомления
10. Установка нод с нуля

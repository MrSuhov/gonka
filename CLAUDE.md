# CLAUDE.md

Этот файл содержит руководство для Claude Code (claude.ai/code) при работе с кодом в этом репозитории.

---

## ⚠️ КРИТИЧЕСКИ ВАЖНО: SSH ControlMaster - ОБЯЗАТЕЛЬНО!

**НИКОГДА не делайте прямые SSH-подключения к серверу!**

- Сервер использует fail2ban с жёсткими лимитами
- Множественные подключения приводят к блокировке IP
- **ВСЕ** SSH-команды должны использовать ControlMaster
- ControlMaster создаётся ОДИН РАЗ в начале и переиспользуется для всех команд

### Правильный паттерн SSH:

**ВАЖНО: Используй ЕДИНУЮ сессию ControlMaster на всю сессию работы!**

```bash
# Фиксированный путь к ControlMaster (НЕ используй $$ - это создаёт новый путь каждый раз!)
SSH_CM="/tmp/ssh_gonka_cm"

# Проверить, существует ли уже ControlMaster
ssh -o ControlPath="$SSH_CM" -O check ubuntu@185.216.21.228 2>/dev/null && echo "CM exists" || {
    # Создать ControlMaster только если его нет
    source /Users/ss/GenAI/gonka/nodes/keen-maxwell.conf
    ssh -o ControlMaster=yes -o ControlPath="$SSH_CM" -o ControlPersist=3600 -fN "${SSH_USER}@${SERVER_IP}"
}

# ВСЕ команды через этот единый ControlMaster
ssh -o ControlPath="$SSH_CM" -o ControlMaster=no ubuntu@185.216.21.228 "команда1"
ssh -o ControlPath="$SSH_CM" -o ControlMaster=no ubuntu@185.216.21.228 "команда2"

# НЕ закрывай ControlMaster между командами! Он должен жить всю сессию.
```

### ❌ ТИПИЧНАЯ ОШИБКА - создание нового ControlMaster каждый раз:

```bash
# ❌ НЕПРАВИЛЬНО - $$ даёт новый PID каждый раз = новое подключение!
SSH_CONTROL_PATH="/tmp/ssh_cm_$$"
ssh -o ControlMaster=yes -o ControlPath="$SSH_CONTROL_PATH" ... # Новое подключение!
# ... команды ...
ssh -O exit ...  # Закрыли

# Следующий вызов:
SSH_CONTROL_PATH="/tmp/ssh_cm_$$"  # Другой PID = другой путь!
ssh -o ControlMaster=yes ...  # ЕЩЁ ОДНО новое подключение! fail2ban блокирует!
```

### ЗАПРЕЩЕНО:

```bash
# ❌ НЕПРАВИЛЬНО - каждая команда создаёт новое подключение!
ssh user@server "команда1"
ssh user@server "команда2"  # fail2ban заблокирует!
ssh user@server "команда3"  # Connection refused
```

---

## Обзор проекта

Этот репозиторий посвящён **Gonka** — проекту децентрализованных AI-вычислений в сети Gonka AI. Проект включает:

- Запуск GPU-нод для AI-вычислений в децентрализованной сети Gonka
- Гибридное использование GPU: личные AI-задачи + майнинг Gonka в свободное время
- Интеграция с блокчейном (токен GNK на Solana)

## Ключевые концепции

- **Gonka AI**: Децентрализованная сеть для AI-вычислений с использованием Proof-of-Work 2.0 (99% мощности GPU направляется на полезные AI-задачи)
- **Токен GNK**: Нативный токен на Solana, торгуется на DEX Jupiter/Raydium
- **Целевое оборудование**: NVIDIA H100 96GB/80GB, A100 80GB
- **Гибридный режим**: systemd-сервис запускает ML-ноду Gonka с низким приоритетом (Nice=10, IOSchedulingClass=idle), позволяя личным AI-задачам вытеснять майнинг

## Требования к окружению

- Ubuntu 22.04/24.04 LTS
- Docker и Docker Compose
- CUDA 12.6-12.9

## Структура node-config.json

**ВАЖНО:** Формат node-config.json должен соответствовать официальной документации Gonka.

### Правильный формат (для 1 GPU - A100/H100):
```json
[
  {
    "id": "node1",
    "host": "inference",
    "inference_port": 5000,
    "poc_port": 8080,
    "max_concurrent": 500,
    "models": {
      "Qwen/Qwen3-32B-FP8": {
        "args": []
      }
    }
  }
]
```

### Правильный формат (для 8 GPU):
```json
[
  {
    "id": "node1",
    "host": "inference",
    "inference_port": 5000,
    "poc_port": 8080,
    "max_concurrent": 500,
    "models": {
      "Qwen/Qwen3-235B-A22B-Instruct-2507-FP8": {
        "args": [
          "--tensor-parallel-size",
          "4"
        ]
      }
    }
  }
]
```

### ❌ НЕПРАВИЛЬНЫЙ формат (старый, НЕ ИСПОЛЬЗОВАТЬ):
```json
[{
  "model_id": "Qwen/Qwen3-32B-FP8",
  "tensor_parallel_size": 1,
  "gpu_memory_utilization": 0.95,
  "max_model_len": 32768,
  "max_num_seqs": 256
}]
```

### Обязательные поля:
- `id` - уникальный идентификатор ноды (например "node1")
- `host` - hostname контейнера ("inference")
- `inference_port` - порт для inference (5000)
- `poc_port` - порт для PoC (8080)
- `max_concurrent` - максимум одновременных запросов (500)
- `models` - объект с моделями и их аргументами

Источник: https://gonka.ai/host/quickstart/

## Справочная документация

- Руководство по проекту: `docs/Полное_руководство_по_децентрализованным_AI_вычислениям_Gonka,_Cocoon.docx`
- Полная инструкция по развёртыванию: `docs/Full node hyperstack.md`
- Discord Gonka: https://discord.gg/gonka
- Twitter/X Gonka: https://x.com/gonka_ai

## КРИТИЧЕСКИ ВАЖНО: Правила работы со скриптом развёртывания

**НИКОГДА не выполняйте шаги развёртывания на сервере напрямую через SSH!**

### ✅ Правильный подход:

1. **Все изменения — только через перезапуск скрипта `mitch_help.sh`**
   - Скрипт идемпотентен — пропускает уже выполненные шаги
   - Скрипт следует точной последовательности из `docs/Full node hyperstack.md`
   - Скрипт автоматически обрабатывает ошибки и повторяет попытки

2. **Если что-то не работает:**
   - Исправьте код в `mitch_help.sh`
   - Перезапустите скрипт: `./mitch_help.sh nodes/<node-name>.conf`
   - Скрипт продолжит с того места, где остановился

3. **Прямое SSH-подключение разрешено ТОЛЬКО для:**
   - Установки дополнительных системных зависимостей (apt install)
   - Диагностики проблем (просмотр логов, проверка состояния)
   - Отладки (когда нужно понять, почему скрипт не работает)

### ❌ Неправильный подход:

- ❌ Создание warm wallet вручную через `docker compose run -it`
- ❌ Регистрация участника вручную через `inferenced register-new-participant`
- ❌ Настройка `persistent_peers` или `pruning` через `vi`
- ❌ Запуск контейнеров вручную через `docker compose up`
- ❌ Любые другие шаги из инструкции вручную

**Почему это важно:**
- Ручное выполнение нарушает идемпотентность скрипта
- Скрипт может не обнаружить уже выполненные шаги
- Теряется история действий в логах
- Невозможно воспроизвести развёртывание на других нодах

**Пример правильного workflow:**
```bash
# 1. Создать конфиг ноды
cp nodes/node1.conf.example nodes/my-node.conf
nano nodes/my-node.conf

# 2. Запустить скрипт
./mitch_help.sh nodes/my-node.conf

# 3. Если ошибка — исправить mitch_help.sh и перезапустить
# 4. После завершения — выполнить grant локально
cd /Users/ss/Crypto/gonka
./inferenced tx inference grant-ml-ops-permissions ...
```

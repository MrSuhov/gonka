#!/bin/bash

################################################################################
# Скрипт для проверки состояния Gonka ноды
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Функция для чтения конфига ноды
################################################################################
load_node_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Ошибка: Конфиг не найден: $config_file${NC}"
        exit 1
    fi

    # Загружаем конфиг
    source "$config_file"

    echo -e "${GREEN}Загружен конфиг: $config_file${NC}"
    echo "  KEY_NAME: $KEY_NAME"
    echo "  SERVER_IP: $SERVER_IP"
    echo "  SEED_API_URL: $SEED_API_URL"
    echo ""
}

################################################################################
# Функция для получения холодного кошелька
################################################################################
get_cold_wallet() {
    local local_key_file="/Users/ss/Crypto/gonka/local_key.txt"

    if [ ! -f "$local_key_file" ]; then
        echo -e "${RED}Ошибка: $local_key_file не найден${NC}"
        exit 1
    fi

    COLD_ADDRESS=$(grep "Address:" "$local_key_file" | cut -d':' -f2 | xargs)

    if [ -z "$COLD_ADDRESS" ]; then
        echo -e "${RED}Ошибка: Не удалось извлечь адрес из $local_key_file${NC}"
        exit 1
    fi
}

################################################################################
# Проверка 1: Participant зарегистрирован
################################################################################
check_participant_registered() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}1. Проверка регистрации участника${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local url="${SEED_API_URL}/v1/participants/${COLD_ADDRESS}"
    echo "URL: $url"
    echo ""

    local response=$(curl -s "$url" 2>/dev/null || echo "")

    if echo "$response" | grep -q "pubkey"; then
        echo -e "${GREEN}✅ УСПЕХ: Участник зарегистрирован${NC}"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        return 0
    else
        echo -e "${RED}❌ ОШИБКА: Участник не найден${NC}"
        echo "Ответ: $response"
        return 1
    fi
}

################################################################################
# Проверка 2: Участник в текущей эпохе
################################################################################
check_participant_in_epoch() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}2. Проверка участия в текущей эпохе${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local url="${SEED_API_URL}/v1/epochs/current/participants"
    echo "URL: $url"
    echo ""

    local response=$(curl -s "$url" 2>/dev/null || echo "")

    if echo "$response" | grep -q "$COLD_ADDRESS"; then
        echo -e "${GREEN}✅ УСПЕХ: Нода участвует в текущей эпохе${NC}"
        echo "$response" | jq ".[] | select(.address == \"$COLD_ADDRESS\")" 2>/dev/null || echo "Найдено в списке участников"
        return 0
    else
        echo -e "${YELLOW}⚠️  ВНИМАНИЕ: Нода не найдена в текущей эпохе${NC}"
        echo "Это нормально, если эпоха ещё не началась или нода недавно зарегистрирована."
        return 1
    fi
}

################################################################################
# Проверка 3: RPC endpoint работает
################################################################################
check_rpc_status() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}3. Проверка RPC endpoint${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local url="http://${SERVER_IP}:26657/status"
    echo "URL: $url"
    echo ""

    local response=$(curl -s "$url" 2>/dev/null || echo "")

    if echo "$response" | grep -q "catching_up"; then
        echo -e "${GREEN}✅ УСПЕХ: RPC endpoint работает${NC}"
        echo ""

        # Извлекаем ключевую информацию
        echo "Информация о ноде:"
        echo "$response" | jq -r '.result.node_info | "  Moniker: \(.moniker)\n  Network: \(.network)\n  Version: \(.version)"' 2>/dev/null || echo "$response" | head -20
        echo ""
        echo "$response" | jq -r '.result.sync_info | "Синхронизация:\n  Latest block: \(.latest_block_height)\n  Latest block time: \(.latest_block_time)\n  Catching up: \(.catching_up)"' 2>/dev/null
        return 0
    else
        echo -e "${RED}❌ ОШИБКА: RPC endpoint не отвечает${NC}"
        echo "Ответ: $response"
        return 1
    fi
}

################################################################################
# Проверка 4: Dashboard доступен
################################################################################
check_dashboard() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}4. Проверка Dashboard${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local url="http://${SERVER_IP}:8000/"
    echo "URL: $url"
    echo ""

    local response=$(curl -s -I "$url" 2>/dev/null | head -1 || echo "")

    if echo "$response" | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✅ УСПЕХ: Dashboard доступен${NC}"
        echo "$response"
        echo ""
        echo -e "${GREEN}Откройте в браузере: $url${NC}"
        return 0
    else
        echo -e "${RED}❌ ОШИБКА: Dashboard недоступен${NC}"
        echo "Ответ: $response"
        return 1
    fi
}

################################################################################
# Проверка 5: Grant транзакция
################################################################################
check_grant_transaction() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}5. Проверка Grant транзакции${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local url="${SEED_API_URL}/dashboard/gonka/account/${COLD_ADDRESS}"
    echo "Dashboard URL: $url"
    echo ""
    echo -e "${GREEN}Откройте эту ссылку в браузере для проверки Grant транзакций${NC}"
    echo ""

    # Попытка получить информацию об аккаунте
    local account_url="${SEED_API_URL}/v1/participants/${COLD_ADDRESS}"
    local response=$(curl -s "$account_url" 2>/dev/null || echo "")

    if echo "$response" | grep -q "pubkey"; then
        echo "Статус участника:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        return 0
    fi
}

################################################################################
# SSH проверки (опционально)
################################################################################
check_docker_containers() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}6. Проверка Docker контейнеров (SSH)${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if [ -z "$SSH_USER" ]; then
        echo -e "${YELLOW}⚠️  SSH_USER не задан, пропускаем SSH проверки${NC}"
        return 0
    fi

    echo "Подключение к серверу..."

    # Создаём ControlMaster
    local ssh_control_path="/tmp/ssh-control-check-${SSH_USER}@${SERVER_IP}:22"

    if ! ssh -f -N -M -o ControlPath="$ssh_control_path" -o ControlPersist=60 -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" 2>/dev/null; then
        echo -e "${RED}❌ Не удалось подключиться к серверу${NC}"
        return 1
    fi

    # Проверка контейнеров
    echo "Запущенные контейнеры:"
    ssh -o ControlPath="$ssh_control_path" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null || echo "Ошибка получения списка контейнеров"

    # Закрываем ControlMaster
    ssh -O exit -o ControlPath="$ssh_control_path" "${SSH_USER}@${SERVER_IP}" 2>/dev/null || true
}

################################################################################
# Главная функция
################################################################################
main() {
    if [ $# -ne 1 ]; then
        echo "Использование: $0 <node-config-file>"
        echo ""
        echo "Пример:"
        echo "  $0 nodes/keen-maxwell.conf"
        echo ""
        exit 1
    fi

    local config_file="$1"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GONKA NODE HEALTH CHECK${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # Загружаем конфиг
    load_node_config "$config_file"

    # Получаем холодный кошелёк
    get_cold_wallet
    echo -e "${GREEN}Cold wallet address: $COLD_ADDRESS${NC}"
    echo ""

    # Выполняем проверки
    local total_checks=0
    local passed_checks=0

    # Проверка 1
    total_checks=$((total_checks + 1))
    if check_participant_registered; then
        passed_checks=$((passed_checks + 1))
    fi

    # Проверка 2
    total_checks=$((total_checks + 1))
    if check_participant_in_epoch; then
        passed_checks=$((passed_checks + 1))
    fi

    # Проверка 3
    total_checks=$((total_checks + 1))
    if check_rpc_status; then
        passed_checks=$((passed_checks + 1))
    fi

    # Проверка 4
    total_checks=$((total_checks + 1))
    if check_dashboard; then
        passed_checks=$((passed_checks + 1))
    fi

    # Проверка 5
    check_grant_transaction

    # Проверка 6 (опционально)
    check_docker_containers

    # Итоговый отчёт
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}ИТОГОВЫЙ ОТЧЁТ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Пройдено проверок: $passed_checks из $total_checks"
    echo ""

    if [ $passed_checks -eq $total_checks ]; then
        echo -e "${GREEN}✅ Все обязательные проверки пройдены!${NC}"
        echo ""
        echo "Следующие шаги:"
        echo "1. Дождитесь начала следующей эпохи"
        echo "2. Проверьте участие в эпохе на tracker.gonka.ai"
        echo "3. Мониторьте логи: docker logs node --tail 100 -f"
    elif [ $passed_checks -ge 3 ]; then
        echo -e "${YELLOW}⚠️  Большинство проверок пройдено${NC}"
        echo ""
        echo "Нода в процессе синхронизации или ожидает начала эпохи."
    else
        echo -e "${RED}❌ Некоторые проверки не прошли${NC}"
        echo ""
        echo "Проверьте логи развёртывания и исправьте ошибки."
    fi

    echo ""
}

# Запускаем
main "$@"

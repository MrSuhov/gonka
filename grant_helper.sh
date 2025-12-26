#!/bin/bash

################################################################################
# Скрипт для выполнения grant-ml-ops-permissions
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRYPTO_DIR="/Users/ss/Crypto/gonka"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo "  SEED_API_URL: $SEED_API_URL"
}

################################################################################
# Функция для извлечения информации из local_key.txt
################################################################################
get_cold_key_info() {
    local local_key_file="$CRYPTO_DIR/local_key.txt"

    if [ ! -f "$local_key_file" ]; then
        echo -e "${RED}Ошибка: Файл $local_key_file не найден${NC}"
        exit 1
    fi

    COLD_KEY_NAME=$(grep "cold-key-name:" "$local_key_file" | cut -d':' -f2 | xargs)

    if [ -z "$COLD_KEY_NAME" ]; then
        echo -e "${RED}Ошибка: Не удалось извлечь cold-key-name из $local_key_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Cold key name: $COLD_KEY_NAME${NC}"
}

################################################################################
# Функция для извлечения warm wallet address
################################################################################
get_warm_wallet_address() {
    local warm_key_file="$SCRIPT_DIR/nodes/$KEY_NAME/warm_key.txt"

    if [ ! -f "$warm_key_file" ]; then
        echo -e "${RED}Ошибка: Файл $warm_key_file не найден${NC}"
        exit 1
    fi

    WARM_WALLET_ADDRESS=$(grep "address:" "$warm_key_file" | grep -o "gonka[0-9a-z]*" | head -1)

    if [ -z "$WARM_WALLET_ADDRESS" ]; then
        echo -e "${RED}Ошибка: Не удалось извлечь адрес из $warm_key_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Warm wallet address: $WARM_WALLET_ADDRESS${NC}"
}

################################################################################
# Функция для выполнения grant
################################################################################
do_grant() {
    local output_file="$SCRIPT_DIR/nodes/$KEY_NAME/grant.txt"

    # Формируем CHAIN_RPC_URL из SEED_API_URL
    CHAIN_RPC_URL="${SEED_API_URL}/chain-rpc/"

    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}ВЫПОЛНЕНИЕ GRANT${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Cold key name:       $COLD_KEY_NAME"
    echo "Warm wallet address: $WARM_WALLET_ADDRESS"
    echo "Chain RPC URL:       $CHAIN_RPC_URL"
    echo ""
    echo -e "${YELLOW}Вас попросят ввести passphrase для холодного кошелька${NC}"
    echo -e "${YELLOW}(тот, который вы ввели при создании $COLD_KEY_NAME)${NC}"
    echo ""

    # Переходим в директорию с inferenced
    cd "$CRYPTO_DIR"

    # Выполняем grant
    echo -e "${GREEN}Запускаю команду grant...${NC}"
    echo ""

    ./inferenced tx inference grant-ml-ops-permissions \
        "$COLD_KEY_NAME" \
        "$WARM_WALLET_ADDRESS" \
        --from "$COLD_KEY_NAME" \
        --keyring-backend file \
        --gas 2000000 \
        --node "$CHAIN_RPC_URL" 2>&1 | tee "$output_file"

    GRANT_EXIT_CODE=${PIPESTATUS[0]}

    echo ""
    echo -e "${GREEN}Вывод сохранён в: $output_file${NC}"
    echo ""

    # Проверяем результат
    if grep -q "Transaction confirmed successfully" "$output_file"; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}✅ GRANT ВЫПОЛНЕН УСПЕШНО!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        grep "Block height:" "$output_file" || true
        return 0
    elif grep -q "account .* not found" "$output_file"; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}❌ ОШИБКА: Кошелёк не найден в блокчейне${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}Это означает, что на холодном кошельке нет токенов GNK.${NC}"
        echo ""
        echo "Холодный кошелёк должен иметь баланс токенов для оплаты gas."
        echo ""
        echo -e "${YELLOW}Варианты решения:${NC}"
        echo "1. Импортировать seed в Keplr и пополнить кошелёк"
        echo "2. Использовать другой кошелёк с токенами"
        echo ""
        return 1
    else
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}⚠️  ПРОВЕРЬТЕ РЕЗУЛЬТАТ${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
        echo "Вывод команды сохранён в: $output_file"
        echo "Проверьте файл для диагностики."
        return $GRANT_EXIT_CODE
    fi
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
    echo -e "${GREEN}GRANT HELPER${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # Загружаем конфиг
    load_node_config "$config_file"
    echo ""

    # Получаем информацию о cold key
    get_cold_key_info
    echo ""

    # Получаем адрес warm wallet
    get_warm_wallet_address
    echo ""

    # Выполняем grant
    do_grant
}

# Запускаем
main "$@"

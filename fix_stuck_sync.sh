#!/bin/bash
set -e

SSH_USER="ubuntu"
SERVER_IP="185.216.21.228"
SSH_CONTROL_PATH="/tmp/ssh-fixsync-${SSH_USER}@${SERVER_IP}:22"

echo "========================================="
echo "FIX STUCK BLOCKCHAIN SYNC"
echo "========================================="
echo ""

# Создаём ControlMaster
if ! ssh -f -N -M -o ControlPath="$SSH_CONTROL_PATH" -o ControlPersist=300 -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" 2>&1; then
    echo "Ошибка подключения SSH"
    exit 1
fi

echo "1. Запрещаем коннекты к чужим пирам..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /home/ubuntu/prometheus && sudo sh iptables_disable_peers.sh" || echo "Скрипт iptables может отсутствовать, продолжаем..."

echo ""
echo "2. Останавливаем все контейнеры..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo docker compose -f docker-compose.yml -f docker-compose.mlnode.yml down"

echo ""
echo "3. Проверяем размер существующих данных..."
DATA_SIZE=$(ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo du -sm /mnt/ssd/gonka/deploy/join/.inference/data/ 2>/dev/null | awk '{print \$1}'" || echo "0")

if [ "$DATA_SIZE" -gt 1000 ]; then
    echo "Найдены существующие данные (${DATA_SIZE}MB) - СОХРАНЯЕМ их!"
    echo "Удаляем только .node_initialized и .cosmovisor для перезапуска state-sync..."
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo rm -rf .inference/.node_initialized" || true
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo rm -rf .inference/cosmovisor" || true
else
    echo "Данных нет или мало (${DATA_SIZE}MB) - обнуляем блокчейн..."
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo rm -rf .inference/data/"
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo rm -rf .inference/.node_initialized" || true
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo rm -rf .inference/cosmovisor" || true
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo mkdir -p .inference/data/"
fi

echo ""
echo "4. Запускаем контейнеры чтобы создать config.toml..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && source config.env && sudo -E docker compose -f docker-compose.yml -f docker-compose.mlnode.yml up -d"

echo ""
echo "5. Ждём 15 секунд для создания конфигурации..."
sleep 15

echo ""
echo "6. Останавливаем контейнеры для редактирования config.toml..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo docker compose down"

echo ""
echo "7. Получаем свежий trust_height и trust_hash..."
LATEST_HEIGHT=$(curl -s http://node2.gonka.ai:26657/status | jq -r '.result.sync_info.latest_block_height')
TRUST_HEIGHT=$((LATEST_HEIGHT - 1000))
TRUST_HASH=$(curl -s "http://node2.gonka.ai:26657/block?height=$TRUST_HEIGHT" | jq -r '.result.block_id.hash')

echo "  Latest height: $LATEST_HEIGHT"
echo "  Trust height: $TRUST_HEIGHT"
echo "  Trust hash: $TRUST_HASH"

echo ""
echo "8. Исправляем rpc_servers (убираем /chain-rpc, используем прямой порт 26657)..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo sed -i 's|rpc_servers = .*|rpc_servers = \"http://node2.gonka.ai:26657,http://node1.gonka.ai:26657\"|' /mnt/ssd/gonka/deploy/join/.inference/config/config.toml"

echo ""
echo "9. Обновляем trust_height и trust_hash..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo sed -i 's/^trust_height = .*/trust_height = $TRUST_HEIGHT/' /mnt/ssd/gonka/deploy/join/.inference/config/config.toml"
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo sed -i 's/^trust_hash = .*/trust_hash = \"$TRUST_HASH\"/' /mnt/ssd/gonka/deploy/join/.inference/config/config.toml"

echo ""
echo "10. Запускаем контейнеры с исправленной конфигурацией..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && source config.env && sudo -E docker compose -f docker-compose.yml -f docker-compose.mlnode.yml up -d"

echo ""
echo "11. Ждём 30 секунд для запуска..."
sleep 30

echo ""
echo "12. Проверяем правильность конфигурации state-sync..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo grep -E 'enable|rpc_servers|trust_height|trust_hash' /mnt/ssd/gonka/deploy/join/.inference/config/config.toml | grep -v '^#' | head -10"

echo ""
echo "13. Проверяем размер data (должен расти)..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "cd /mnt/ssd/gonka/deploy/join && sudo du -sh .inference/data/"

echo ""
echo "14. Проверяем логи ноды..."
ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "docker logs node --tail 30 2>&1"

echo ""
echo "========================================="
echo "15. МОНИТОРИНГ STATE-SYNC"
echo "========================================="
echo "Проверяем каждые 30 секунд (макс 50 попыток = 25 минут)..."
echo ""

MAX_ATTEMPTS=50
ATTEMPT=0
SYNC_COMPLETED=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    echo "--- Попытка $ATTEMPT/$MAX_ATTEMPTS ---"

    # Проверяем высоту блока
    HEIGHT=$(ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "curl -s http://localhost:26657/status 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo '0'")

    if [ "$HEIGHT" != "0" ] && [ "$HEIGHT" != "null" ] && [ -n "$HEIGHT" ]; then
        if [ "$HEIGHT" -gt 100 ]; then
            echo ""
            echo "✅✅✅ STATE-SYNC ЗАВЕРШЁН! ✅✅✅"
            echo "Высота блока: $HEIGHT"
            SYNC_COMPLETED=true
            break
        fi
    fi

    # Показываем прогресс чанков
    CHUNK=$(ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "docker logs node --tail 10 2>&1 | grep -o 'chunk=[0-9]*' | tail -1 | cut -d'=' -f2")

    if [ -n "$CHUNK" ]; then
        PERCENT=$((CHUNK * 100 / 368))
        echo "📦 Чанк: $CHUNK/368 ($PERCENT%)"
    else
        echo "⏳ State-sync в процессе..."
    fi

    # Показываем размер данных
    DATA_SIZE=$(ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo du -sh /mnt/ssd/gonka/deploy/join/.inference/data/ 2>/dev/null | awk '{print \$1}'")
    echo "💾 Размер данных: $DATA_SIZE"
    echo ""

    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep 30
    fi
done

if [ "$SYNC_COMPLETED" = true ]; then
    echo ""
    echo "Удаляем правило iptables DROP..."

    RULE_NUM=$(ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo iptables -t mangle -L OUTPUT -n --line-numbers | grep '^[0-9].*DROP' | awk '{print \$1}' | head -1")

    if [ -n "$RULE_NUM" ]; then
        ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "${SSH_USER}@${SERVER_IP}" "sudo iptables -t mangle -D OUTPUT $RULE_NUM"
        echo "✅ Правило iptables #$RULE_NUM удалено"
    else
        echo "ℹ️  Правило iptables уже отсутствует"
    fi
else
    echo "⚠️  State-sync всё ещё в процессе после 25 минут."
    echo "Это нормально для медленных соединений. Синхронизация продолжается в фоне."
    echo ""
    echo "ВАЖНО: Правило iptables DROP всё ещё активно!"
    echo "После завершения state-sync удалите его вручную:"
    echo "  ssh ubuntu@${SERVER_IP}"
    echo "  sudo iptables -t mangle -L OUTPUT -n --line-numbers"
    echo "  sudo iptables -t mangle -D OUTPUT <номер_правила>"
fi

# Закрываем ControlMaster
ssh -O exit -o ControlPath="$SSH_CONTROL_PATH" "${SSH_USER}@${SERVER_IP}" 2>/dev/null || true

echo ""
echo "========================================="
echo "ГОТОВО!"
echo "========================================="

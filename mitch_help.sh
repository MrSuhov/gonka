#!/bin/bash

################################################################################
# Gonka Node Deployment Script
#
# Автоматизированное развёртывание ноды Gonka AI на удалённом сервере
# Выполняется локально, все команды исполняются на сервере через SSH
#
# Использование: ./mitch_help.sh <config-file>
# Пример: ./mitch_help.sh nodes/node1.conf
################################################################################

set -euo pipefail  # Строгий режим: выход при ошибках

# Глобальные переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOGFILE=""
NODE_OUTPUT_DIR=""
SSH_CMD=""
SSH_CONTROL_PATH="/tmp/gonka-ssh-control-$$"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Функции логирования
################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"

    # Запись в файл
    echo "$log_entry" >> "$LOGFILE"

    # Вывод в консоль с цветами
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        OK|SUCCESS)
            echo -e "${GREEN}[OK]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        CHECK)
            echo -e "${BLUE}[CHECK]${NC} $message"
            ;;
        SKIP)
            echo -e "${YELLOW}[SKIP]${NC} $message"
            ;;
        EXEC)
            echo -e "${GREEN}[EXEC]${NC} $message"
            ;;
        *)
            echo "[$level] $message"
            ;;
    esac
}

log_section() {
    local title="$1"
    local separator="========================================"
    echo ""
    log "INFO" "$separator"
    log "INFO" "$title"
    log "INFO" "$separator"
    echo ""
}

die() {
    log "ERROR" "$*"
    log "ERROR" "Deployment failed. Check log: $LOGFILE"
    cleanup_ssh
    exit 1
}

cleanup_ssh() {
    # Закрываем SSH ControlMaster соединение
    if [[ -n "$SSH_CONTROL_PATH" ]] && [[ -S "$SSH_CONTROL_PATH" ]]; then
        ssh -O exit -o ControlPath="$SSH_CONTROL_PATH" "$SSH_CMD" 2>/dev/null || true
        rm -f "$SSH_CONTROL_PATH" 2>/dev/null || true
    fi
}

################################################################################
# SSH функции
################################################################################

ssh_exec() {
    local cmd="$*"
    log "EXEC" "Remote: $cmd"
    if ! ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=auto -o ControlPersist=600 -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_CMD" "$cmd" 2>&1 | tee -a "$LOGFILE"; then
        die "Failed to execute remote command: $cmd"
    fi
}

ssh_exec_quiet() {
    local cmd="$*"
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=auto -o ControlPersist=600 -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_CMD" "$cmd" 2>&1 | tee -a "$LOGFILE"
}

ssh_check() {
    local cmd="$*"
    ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=auto -o ControlPersist=600 -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_CMD" "$cmd" >/dev/null 2>&1
}

scp_upload() {
    local local_file="$1"
    local remote_path="$2"
    log "EXEC" "Upload: $local_file -> $remote_path"
    if ! scp -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=auto -o ControlPersist=600 -o StrictHostKeyChecking=no "$local_file" "$SSH_CMD:$remote_path" >> "$LOGFILE" 2>&1; then
        die "Failed to upload file: $local_file"
    fi
}

################################################################################
# Фаза 0: Валидация и подтверждение параметров
################################################################################

validate_config() {
    log_section "PHASE 0: VALIDATION"

    # Проверка обязательных параметров
    local required_params=(
        "SERVER_IP"
        "SSH_USER"
        "KEY_NAME"
        "KEYRING_PASSWORD"
        "ACCOUNT_PUBKEY"
        "MODEL_NAME"
        "SEED_API_URL"
        "NODE_CONFIG_PROFILE"
    )

    log "CHECK" "Validating required parameters..."

    for param in "${required_params[@]}"; do
        if [[ -z "${!param:-}" ]]; then
            die "Required parameter missing: $param"
        fi
    done

    # Валидация форматов
    if ! [[ "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        die "Invalid SERVER_IP format: $SERVER_IP"
    fi

    if [[ ${#KEYRING_PASSWORD} -lt 8 ]]; then
        die "KEYRING_PASSWORD too short (minimum 8 characters)"
    fi

    if ! [[ "$MODEL_NAME" =~ ^Qwen/ ]]; then
        die "MODEL_NAME must start with 'Qwen/': $MODEL_NAME"
    fi

    if ! [[ "$SEED_API_URL" =~ ^http ]]; then
        die "SEED_API_URL must be a valid URL: $SEED_API_URL"
    fi

    log "OK" "All required parameters validated"

    # Проверка локальных зависимостей
    log "CHECK" "Checking local dependencies..."

    for cmd in ssh scp; do
        if ! command -v "$cmd" &> /dev/null; then
            die "Required command not found: $cmd"
        fi
    done

    log "OK" "Local dependencies checked"

    # Создание директорий
    mkdir -p "$SCRIPT_DIR/nodes"
    mkdir -p "$SCRIPT_DIR/logs"

    # Создаём ControlMaster соединение сразу (это одновременно проверяет SSH connectivity)
    log "CHECK" "Establishing SSH ControlMaster connection to $SSH_USER@$SERVER_IP..."

    SSH_CMD="$SSH_USER@$SERVER_IP"

    # Создаём master connection в фоне
    if ! ssh -f -N -M -o ControlPath="$SSH_CONTROL_PATH" -o ControlPersist=600 -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_CMD" 2>> "$LOGFILE"; then
        die "Cannot establish SSH ControlMaster to $SSH_CMD"
    fi

    # Проверяем, что ControlMaster работает
    if ! ssh -o ControlPath="$SSH_CONTROL_PATH" -o ControlMaster=no "$SSH_CMD" "echo 'SSH OK'" >> "$LOGFILE" 2>&1; then
        die "ControlMaster created but connection test failed"
    fi

    log "OK" "SSH ControlMaster established and verified"
}

display_config() {
    local masked_password=$(echo "$KEYRING_PASSWORD" | sed 's/./*/g')

    echo ""
    echo "========================================"
    echo "     GONKA NODE DEPLOYMENT SCRIPT"
    echo "========================================"
    echo ""
    echo "Configuration loaded from: $CONFIG_FILE"
    echo ""
    echo "SERVER PARAMETERS:"
    echo "  SSH Connection:     $SSH_USER@$SERVER_IP"
    echo "  SSH Status:         ✓ Connected"
    echo ""
    echo "NODE PARAMETERS:"
    echo "  Key Name:           $KEY_NAME"
    echo "  Account PubKey:     $ACCOUNT_PUBKEY"
    echo "  Keyring Password:   $masked_password (${#KEYRING_PASSWORD} chars)"
    echo ""
    echo "NETWORK PARAMETERS:"
    echo "  Seed API URL:       $SEED_API_URL"
    echo "  Persistent Peers:   ${PERSISTENT_PEERS:0:50}... (${PERSISTENT_PEERS_COUNT:-3} peers)"
    echo ""
    echo "MODEL PARAMETERS:"
    echo "  Model Name:         $MODEL_NAME"
    echo "  HF Home:            $HF_HOME"
    echo ""
    echo "STORAGE PARAMETERS:"
    echo "  Volume Device:      $VOLUME_DEVICE"
    echo "  Mount Point:        $VOLUME_MOUNT"
    echo "  Gonka Path:         $GONKA_PATH"
    echo ""
    echo "NODE CONFIG:"
    echo "  Profile:            $NODE_CONFIG_PROFILE"
    echo ""
    echo "LOGGING:"
    echo "  Log File:           $LOGFILE"
    echo "  Output Directory:   $NODE_OUTPUT_DIR"
    echo ""
    echo "========================================"
    echo ""
}

confirm_deployment() {
    echo "Please verify all parameters above."
    echo ""

    # Проверяем AUTO_CONFIRM для неинтерактивного режима
    if [[ "${AUTO_CONFIRM:-no}" == "yes" ]]; then
        echo "AUTO_CONFIRM=yes, skipping confirmation prompt"
        log "INFO" "Auto-confirmed deployment. Starting..."
        return 0
    fi

    read -p "Do you want to proceed with deployment? (yes/no): " CONFIRMATION
    echo ""

    if [[ "$CONFIRMATION" != "yes" ]]; then
        log "INFO" "Deployment cancelled by user"
        exit 0
    fi

    log "INFO" "User confirmed deployment. Starting..."
}

################################################################################
# Фаза 1: Подготовка сервера
################################################################################

phase1_server_preparation() {
    log_section "PHASE 1: SERVER PREPARATION"

    # 1.1 Добавление SSH ключей админов
    log "CHECK" "Adding admin SSH keys..."

    local admin_keys=(
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTjwUc2ClEscDY6eKn+OWhUOr+myraIf+9eLGGV5eDR newmitch@gmail.com"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBjug98HZ7B/OXDUCFZugrKohonx2SEfC7LtlOhI2Z6LzIb8cLcB91CslBlaKbBV6cLV7K7CzdMA174dP53c9yZGcWHp/3Ky11PG4ofOug3matP4fgcorjsL0JBlHoTiTrfO73j/DcPdTHwa4VdGXpgyphfYhz4cuDNjNv2x/yL9WYT7FCHrhdkLmERzAcqqtd78/XkGQjnu4me62bFRaX8wsYYWlQVB3oYYSfxSdXrcDXFVh47CtvVSP+DEuJkYfOHEow5aAp0/N6gRGCDMuvhcuCfj/BMHdGX0nJp2ITseFWRORnXr1v1fbhXUUmseDcYFCYneQrFOz60tfvOlfd nick@PAPA-PC"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFxtkahP9A6ocXDJwFUM8eXOBaWJtSNUrLxjxCya/I+G ocromvell@gmail.com"
    )

    for key in "${admin_keys[@]}"; do
        local key_comment=$(echo "$key" | awk '{print $NF}')
        if ssh_check "grep -q '$key_comment' ~/.ssh/authorized_keys"; then
            log "SKIP" "SSH key already exists: $key_comment"
        else
            log "EXEC" "Adding SSH key: $key_comment"
            ssh_exec "echo '$key' >> ~/.ssh/authorized_keys"
            log "OK" "Added SSH key: $key_comment"
        fi
    done

    # 1.2 Монтирование Volume
    log "CHECK" "Checking volume device $VOLUME_DEVICE..."

    if ! ssh_check "lsblk | grep -q $(basename $VOLUME_DEVICE)"; then
        die "Volume device $VOLUME_DEVICE not found on server"
    fi

    log "OK" "Volume device $VOLUME_DEVICE exists"

    # Форматирование (если нужно)
    if ssh_check "sudo blkid $VOLUME_DEVICE | grep -q ext4"; then
        log "SKIP" "Volume already formatted as ext4"
    else
        log "EXEC" "Formatting volume as ext4..."
        ssh_exec "sudo mkfs.ext4 $VOLUME_DEVICE"
        log "OK" "Volume formatted"
    fi

    # Монтирование
    if ssh_check "mount | grep -q $VOLUME_MOUNT"; then
        log "SKIP" "Volume already mounted at $VOLUME_MOUNT"
    else
        log "EXEC" "Mounting volume..."
        ssh_exec "sudo mkdir -p $VOLUME_MOUNT && sudo mount $VOLUME_DEVICE $VOLUME_MOUNT"
        log "OK" "Volume mounted at $VOLUME_MOUNT"
    fi

    # Права доступа
    log "EXEC" "Setting permissions on $VOLUME_MOUNT..."
    ssh_exec "sudo chown -R $SSH_USER:$SSH_USER $VOLUME_MOUNT"

    # Получение UUID и добавление в fstab
    if ssh_check "grep -q $VOLUME_MOUNT /etc/fstab"; then
        log "SKIP" "Volume already in /etc/fstab"
    else
        log "EXEC" "Getting volume UUID..."
        local volume_uuid=$(ssh_exec_quiet "sudo blkid -s UUID -o value $VOLUME_DEVICE" | tail -1)

        if [[ -z "$volume_uuid" ]]; then
            die "Failed to get volume UUID"
        fi

        log "INFO" "Volume UUID: $volume_uuid"
        echo "$volume_uuid" > "$NODE_OUTPUT_DIR/volume.txt"

        log "EXEC" "Adding volume to /etc/fstab..."
        ssh_exec "echo 'UUID=$volume_uuid $VOLUME_MOUNT ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab"
        log "OK" "Volume added to /etc/fstab"
    fi

    # 1.3 Установка Prometheus
    log "CHECK" "Checking Prometheus installation..."

    if ssh_check "test -d ~/prometheus"; then
        log "SKIP" "Prometheus directory already exists"

        if ssh_check "docker ps | grep -q prometheus"; then
            log "SKIP" "Prometheus already running"
        else
            log "EXEC" "Starting Prometheus..."
            ssh_exec "cd ~/prometheus && sudo docker compose up -d"
            log "OK" "Prometheus started"
        fi
    else
        log "EXEC" "Cloning Prometheus repository..."
        ssh_exec "cd ~ && git clone https://github.com/akamitch/prometheus.git"

        log "EXEC" "Starting Prometheus..."
        ssh_exec "cd ~/prometheus && sudo docker compose up -d"
        log "OK" "Prometheus installed and started"
    fi

    # 1.5 Установка expect для автоматизации ввода паролей
    log "CHECK" "Checking if expect is installed..."

    if ssh_check "which expect"; then
        log "SKIP" "expect already installed"
    else
        log "EXEC" "Installing expect..."
        ssh_exec "sudo apt-get update -qq && sudo apt-get install -y expect"
        log "OK" "expect installed"
    fi

    log "SUCCESS" "Phase 1 completed: Server preparation done"
}

################################################################################
# Фаза 2: Установка Gonka и моделей
################################################################################

phase2_gonka_models() {
    log_section "PHASE 2: GONKA AND MODELS INSTALLATION"

    # 2.1 Клонирование Gonka репозитория
    log "CHECK" "Checking Gonka repository..."

    if ssh_check "test -d $GONKA_PATH"; then
        log "SKIP" "Gonka repository already exists at $GONKA_PATH"

        # Проверка правильного remote
        local remote_url=$(ssh_exec_quiet "cd $GONKA_PATH && git remote get-url origin" | tail -1)
        if [[ "$remote_url" != *"gonka-ai/gonka"* ]]; then
            log "WARN" "Wrong git remote: $remote_url"
            die "Please remove $GONKA_PATH manually and restart"
        fi
    else
        log "EXEC" "Cloning Gonka repository..."
        ssh_exec "cd $VOLUME_MOUNT && git clone https://github.com/gonka-ai/gonka.git -b main"
        log "OK" "Gonka repository cloned"
    fi

    # 2.2 Создание директории для моделей
    log "CHECK" "Checking models directory..."

    if ssh_check "test -d $HF_HOME"; then
        log "SKIP" "Models directory already exists: $HF_HOME"
    else
        log "EXEC" "Creating models directory..."
        ssh_exec "sudo mkdir -p $HF_HOME && sudo chown $SSH_USER:$SSH_USER $HF_HOME"
        log "OK" "Models directory created: $HF_HOME"
    fi

    # 2.3 Установка pipx и huggingface_hub
    log "CHECK" "Checking huggingface_hub installation..."

    if ssh_check "test -f ~/.local/bin/hf"; then
        log "SKIP" "huggingface_hub already installed"
    else
        log "EXEC" "Installing pipx and huggingface_hub..."
        ssh_exec "sudo apt update && sudo apt install -y pipx"
        ssh_exec "pipx ensurepath"
        ssh_exec "pipx install huggingface_hub"
        log "OK" "huggingface_hub installed"
    fi

    # 2.4 Скачивание модели
    log "CHECK" "Checking if model is downloaded..."

    local model_path=$(echo "$MODEL_NAME" | sed 's|/|--|g')
    if ssh_check "test -d $HF_HOME/hub/models--${model_path}/snapshots"; then
        log "SKIP" "Model already downloaded: $MODEL_NAME"
    else
        log "EXEC" "Downloading model $MODEL_NAME (this may take several minutes)..."
        log "INFO" "Progress will be shown in real-time..."

        # Скачиваем с выводом прогресса (игнорируем код возврата из-за warnings)
        ssh_exec "export HF_HOME=$HF_HOME && ~/.local/bin/hf download $MODEL_NAME" || true

        # Проверка успешности
        if ssh_check "test -d $HF_HOME/hub/models--${model_path}/snapshots"; then
            log "OK" "Model downloaded successfully"
        else
            die "Model download failed"
        fi
    fi

    log "SUCCESS" "Phase 2 completed: Gonka and models installed"
}

################################################################################
# Фаза 3: Конфигурация
################################################################################

phase3_configuration() {
    log_section "PHASE 3: CONFIGURATION"

    local deploy_dir="$GONKA_PATH/deploy/join"

    # 3.1 Создание config.env
    log "EXEC" "Creating config.env..."

    local config_env_content="export DAPI_API__PUBLIC_URL=http://${SERVER_IP}:8000
export DAPI_CHAIN_NODE__SEED_API_URL=${SEED_API_URL}
export DAPI_CHAIN_NODE__P2P_EXTERNAL_ADDRESS=${SERVER_IP}:5000
export DAPI_CHAIN_NODE__RPC_EXTERNAL_ADDRESS=${SERVER_IP}:26657
export DAPI_CHAIN_NODE__URL=http://node2.gonka.ai:26657
export DAPI_CHAIN_NODE__P2P_URL=${SEED_API_URL}/chain-p2p
export DAPI_API__POC_CALLBACK_URL=http://${SERVER_IP}:8000
export SEED_NODE_RPC_URL=${SEED_API_URL}/chain-rpc
export SEED_NODE_P2P_URL=${SEED_API_URL}/chain-p2p
export P2P_EXTERNAL_ADDRESS=${SERVER_IP}:5000
export PUBLIC_URL=http://${SERVER_IP}:8000
export SEED_API_URL=${SEED_API_URL}
export RPC_SERVER_URL_1=${SEED_API_URL}/chain-rpc
export RPC_SERVER_URL_2=http://node1.gonka.ai:8000/chain-rpc
export STATESYNC_ENABLE=false
export KEY_NAME=${KEY_NAME}
export KEYRING_PASSWORD=${KEYRING_PASSWORD}
export ACCOUNT_PUBKEY=${ACCOUNT_PUBKEY}
export HF_HOME=${HF_HOME}"

    # Сохраняем локально
    echo "$config_env_content" > "$NODE_OUTPUT_DIR/config.env"
    log "OK" "config.env created locally"

    # Загружаем на сервер
    log "EXEC" "Uploading config.env to server..."
    scp_upload "$NODE_OUTPUT_DIR/config.env" "$deploy_dir/config.env"
    log "OK" "config.env uploaded"

    # 3.2 Создание node-config.json
    log "EXEC" "Creating node-config.json for profile: $NODE_CONFIG_PROFILE..."

    # Получаем шаблон из доки Gonka (упрощённо, для x1 профиля)
    local node_config_json=""

    case "$NODE_CONFIG_PROFILE" in
        x1)
            # Формат согласно официальной документации Gonka
            # https://gonka.ai/host/quickstart/
            node_config_json='[
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
]'
            ;;
        x8)
            # Формат согласно официальной документации Gonka
            # https://gonka.ai/host/quickstart/
            node_config_json='[
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
]'
            ;;
        *)
            die "Unknown NODE_CONFIG_PROFILE: $NODE_CONFIG_PROFILE (supported: x1, x8)"
            ;;
    esac

    echo "$node_config_json" > "$NODE_OUTPUT_DIR/node-config.json"
    log "OK" "node-config.json created locally"

    log "EXEC" "Uploading node-config.json to server..."
    scp_upload "$NODE_OUTPUT_DIR/node-config.json" "$deploy_dir/node-config.json"
    log "OK" "node-config.json uploaded"

    # 3.3 Создание .env из config.env
    log "EXEC" "Creating .env from config.env..."
    ssh_exec "cd $deploy_dir && sed 's/^export //' config.env > .env"
    log "OK" ".env created"

    # 3.4 Source config.env для переменных окружения
    log "INFO" "Environment variables will be sourced with sudo -E"

    log "SUCCESS" "Phase 3 completed: Configuration done"
}

################################################################################
# Фаза 4: Запуск базовых сервисов
################################################################################

phase4_basic_services() {
    log_section "PHASE 4: BASIC SERVICES LAUNCH"

    local deploy_dir="$GONKA_PATH/deploy/join"

    # 4.1 Запуск tmkms и node
    log "EXEC" "Starting tmkms and node containers..."

    # Останавливаем старые контейнеры если они есть
    ssh_exec "cd $deploy_dir && sudo docker compose down" || true

    # Запускаем с обновлённым config
    ssh_exec "cd $deploy_dir && source config.env && sudo -E docker compose up tmkms node -d --no-deps"

    log "INFO" "Waiting 15 seconds for containers to start..."
    sleep 15

    # 4.2 Проверка статуса контейнеров
    log "CHECK" "Checking container status..."

    local node_status=$(ssh_exec_quiet "cd $deploy_dir && sudo docker compose ps node --format '{{.Status}}' 2>/dev/null | head -1")

    if echo "$node_status" | grep -qi "restarting"; then
        log "WARN" "Node container is restarting, checking logs..."
        local node_logs=$(ssh_exec_quiet "cd $deploy_dir && sudo docker logs node --tail=100 2>&1")
        log "ERROR" "Node container logs:"
        echo "$node_logs" >> "$LOGFILE"

        # Ищем реальную ошибку в логах
        local error_msg=$(echo "$node_logs" | grep -i "error\|invalid\|failed\|must be" | head -5)
        if [ -n "$error_msg" ]; then
            echo "$error_msg"
        fi

        if echo "$node_logs" | grep -q "Environment variable.*required"; then
            log "ERROR" "Missing environment variables detected"
            log "INFO" "Attempting to fix by recreating containers..."
            ssh_exec "cd $deploy_dir && sudo docker compose down"
            ssh_exec "cd $deploy_dir && source config.env && sudo -E docker compose up tmkms node -d --no-deps"
            sleep 15
        elif echo "$node_logs" | grep -q "invalid path.*data.*must be an existing directory"; then
            log "ERROR" "Data directory missing - creating it..."
            ssh_exec "sudo mkdir -p $deploy_dir/.inference/data"
            ssh_exec "cd $deploy_dir && sudo docker restart node"
            sleep 15
        elif echo "$node_logs" | grep -q "failed to load.*version does not exist"; then
            log "ERROR" "Corrupted data directory detected - cleaning for state-sync..."
            ssh_exec "cd $deploy_dir && sudo docker compose down"
            ssh_exec "sudo rm -rf $deploy_dir/.inference/data/*"
            ssh_exec "sudo mkdir -p $deploy_dir/.inference/data"
            ssh_exec "cd $deploy_dir && source config.env && sudo -E docker compose up tmkms node -d --no-deps"
            sleep 15
        else
            die "Node container failing to start. Check logs above."
        fi
    else
        log "OK" "Containers started successfully"
    fi

    # 4.3 Создание warm wallet
    log "CHECK" "Checking if warm wallet exists..."

    # Проверяем наличие ключа в файловой системе (быстрее чем docker run)
    if ssh_check "test -f $deploy_dir/.inference/keyring-file/${KEY_NAME}.address"; then
        log "SKIP" "Warm wallet already exists: $KEY_NAME"

        # Получаем адрес из файла
        WARM_ADDRESS=$(ssh_exec_quiet "cat $deploy_dir/.inference/keyring-file/${KEY_NAME}.address 2>/dev/null | tr -d '\"' | tr -d '\r\n'")

        if [[ -z "$WARM_ADDRESS" ]]; then
            log "WARN" "Address file exists but empty, trying docker method..."
            # Fallback: пытаемся получить через docker (передаём пароль через yes)
            WARM_ADDRESS=$(ssh_exec_quiet "cd $deploy_dir && yes '$KEYRING_PASSWORD' | sudo -E docker compose run --rm --no-deps -T api inferenced keys show $KEY_NAME --keyring-backend file -a 2>/dev/null | grep gonka" | tail -1 | tr -d '\r\n')
        fi

        if [[ -z "$WARM_ADDRESS" ]]; then
            die "Failed to get existing warm wallet address"
        fi

        log "INFO" "Warm wallet address: $WARM_ADDRESS"
    else
        log "EXEC" "Creating warm wallet using expect..."

        # Создаём expect-скрипт на сервере для автоматизации интерактивного ввода пароля
        # Используем quoted heredoc для предотвращения bash-интерполяции, затем делаем sed для подстановки deploy_dir
        ssh_exec_quiet "cat > /tmp/create_wallet_${KEY_NAME}.exp << 'EOFEXP'
#!/usr/bin/expect -f
set timeout 120

# Читаем переменные через bash (экранируем $ чтобы bash, а не TCL, раскрывал переменные)
set password [exec bash -c \"cd DEPLOY_DIR_PLACEHOLDER && source config.env && echo -n \\\$KEYRING_PASSWORD\"]
set keyname [exec bash -c \"cd DEPLOY_DIR_PLACEHOLDER && source config.env && echo -n \\\$KEY_NAME\"]

cd DEPLOY_DIR_PLACEHOLDER
spawn sudo -E docker compose run --rm --no-deps -it api inferenced keys add \$keyname --keyring-backend file

expect {
    \"*override*\" {
        send \"y\\r\"
        exp_continue
    }
    \"*assphrase*\" {
        send \"\$password\\r\"
        exp_continue
    }
    eof
}
EOFEXP
sed -i 's|DEPLOY_DIR_PLACEHOLDER|${deploy_dir}|g' /tmp/create_wallet_${KEY_NAME}.exp
chmod +x /tmp/create_wallet_${KEY_NAME}.exp"

        local warm_key_output
        set +e
        warm_key_output=$(ssh_exec_quiet "/tmp/create_wallet_${KEY_NAME}.exp 2>&1")
        local exit_code=$?
        set -e

        # Удаляем скрипт
        ssh_exec_quiet "rm -f /tmp/create_wallet_${KEY_NAME}.exp" 2>/dev/null || true

        # Сохраняем вывод
        echo -e "$warm_key_output" > "$NODE_OUTPUT_DIR/warm_key.txt"

        # Извлекаем адрес из вывода (формат: "- address: gonka1...")
        WARM_ADDRESS=$(echo "$warm_key_output" | grep "address:" | awk '{print $3}' | tr -d '\r\n')

        if [[ -z "$WARM_ADDRESS" ]]; then
            log "WARN" "Failed to extract address from creation output"
            log "WARN" "Checking if wallet was actually created..."

            # Проверяем через файловую систему
            if ssh_check "test -f $deploy_dir/.inference/keyring-file/${KEY_NAME}.address"; then
                log "OK" "Wallet file exists, reading address..."
                WARM_ADDRESS=$(ssh_exec_quiet "cat $deploy_dir/.inference/keyring-file/${KEY_NAME}.address 2>/dev/null | tr -d '\"' | tr -d '\r\n'")
            fi

            if [[ -z "$WARM_ADDRESS" ]]; then
                die "Cannot continue without warm wallet address. Check $NODE_OUTPUT_DIR/warm_key.txt for details"
            fi
        fi

        log "OK" "Warm wallet created"
        log "OK" "Warm wallet address: $WARM_ADDRESS"

        # 4.3.1 Регистрация участника СРАЗУ после создания warm wallet
        # Согласно инструкции: "Изнутри этого же контейнера, зарегистрировать в блокчейне нашу ноду"
        log "EXEC" "Registering participant in blockchain (from same container)..."

        # Создаём временный скрипт регистрации на сервере через echo
        # Используем set -a для автоэкспорта всех переменных перед source
        log "EXEC" "Creating registration script on server..."
        ssh_exec_quiet "echo '#!/bin/bash' > /tmp/register_participant.sh"
        ssh_exec_quiet "echo 'set -e' >> /tmp/register_participant.sh"
        ssh_exec_quiet "echo 'cd $deploy_dir' >> /tmp/register_participant.sh"
        ssh_exec_quiet "echo 'set -a' >> /tmp/register_participant.sh"
        ssh_exec_quiet "echo 'source config.env' >> /tmp/register_participant.sh"
        ssh_exec_quiet "echo 'set +a' >> /tmp/register_participant.sh"
        ssh_exec_quiet "echo 'sudo -E docker compose run --rm --no-deps -T api inferenced register-new-participant \"\$DAPI_API__PUBLIC_URL\" \"\$ACCOUNT_PUBKEY\" --node-address \"\$DAPI_CHAIN_NODE__SEED_API_URL\"' >> /tmp/register_participant.sh"
        ssh_exec_quiet "chmod +x /tmp/register_participant.sh"

        set +e
        local registration_output=$(ssh_exec_quiet "/tmp/register_participant.sh")
        local reg_exit_code=$?
        set -e

        # Удаляем временный скрипт
        ssh_exec_quiet "rm -f /tmp/register_participant.sh" || true

        # Сохраняем вывод
        echo -e "$registration_output" > "$NODE_OUTPUT_DIR/registration.txt"

        # Проверка успеха
        if echo "$registration_output" | grep -q "Participant registration successful"; then
            log "OK" "Participant registered successfully"
        else
            log "WARN" "Registration output saved to: $NODE_OUTPUT_DIR/registration.txt"
            log "WARN" "Will verify via API..."
        fi
    fi

    # Сохраняем адрес для дальнейшего использования
    echo "$WARM_ADDRESS" > "$NODE_OUTPUT_DIR/warm_address.txt"

    # 4.4 Проверка регистрации через API
    log "CHECK" "Verifying participant registration via API..."

    # Даём время на распространение в сети
    sleep 5

    local participant_check=$(curl -s "${SEED_API_URL}/v1/participants/${WARM_ADDRESS}" 2>/dev/null || echo "")

    if [[ "$participant_check" == *"pubkey"* ]]; then
        log "OK" "Participant verified in blockchain"
    else
        log "WARN" "Participant not yet visible in API (may need time to propagate)"
        log "WARN" "Check manually: ${SEED_API_URL}/v1/participants/${WARM_ADDRESS}"
    fi

    log "SUCCESS" "Phase 4 completed: Basic services launched"
}

################################################################################
# Фаза 5: Настройка блокчейна
################################################################################

phase5_blockchain_config() {
    log_section "PHASE 5: BLOCKCHAIN CONFIGURATION"

    local deploy_dir="$GONKA_PATH/deploy/join"
    local config_toml="$deploy_dir/.inference/config/config.toml"
    local app_toml="$deploy_dir/.inference/config/app.toml"

    # 5.1 Настройка persistent_peers
    log "EXEC" "Configuring persistent_peers..."

    ssh_exec "sudo sed -i 's/^persistent_peers = .*/persistent_peers = \"$PERSISTENT_PEERS\"/' $config_toml"
    log "OK" "persistent_peers configured"

    # 5.2 Настройка pruning
    log "EXEC" "Configuring pruning settings..."

    # Удаляем старые строки
    ssh_exec "sudo sed -i '/^pruning[[:space:]]*=/d' $app_toml"
    ssh_exec "sudo sed -i '/^pruning-keep-recent[[:space:]]*=/d' $app_toml"
    ssh_exec "sudo sed -i '/^pruning-interval[[:space:]]*=/d' $app_toml"

    # Добавляем новые настройки
    ssh_exec "echo '' | sudo tee -a $app_toml"
    ssh_exec "echo '# Custom pruning configuration' | sudo tee -a $app_toml"
    ssh_exec "echo 'pruning = \"custom\"' | sudo tee -a $app_toml"
    ssh_exec "echo 'pruning-keep-recent = \"1000\"' | sudo tee -a $app_toml"
    ssh_exec "echo 'pruning-interval = \"100\"' | sudo tee -a $app_toml"

    log "OK" "Pruning configured"

    # 5.3 Подготовка директории data для state-sync
    log "EXEC" "Preparing data directory for state-sync..."

    # State-sync требует пустую директорию data или отсутствие LastBlockHeight > 0
    # Удаляем старые данные если они есть
    ssh_exec "sudo rm -rf $deploy_dir/.inference/data/*" || true
    ssh_exec "sudo mkdir -p $deploy_dir/.inference/data"

    log "OK" "Data directory cleaned and ready for state-sync"

    # 5.4 Настройка state-sync для быстрой синхронизации
    log "EXEC" "Configuring state-sync for fast blockchain sync..."

    # Получаем свежий snapshot height и hash
    log "INFO" "Fetching latest snapshot information..."
    local latest_height=$(curl -s http://node2.gonka.ai:26657/status | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)

    if [ -z "$latest_height" ] || [ "$latest_height" == "null" ]; then
        log "WARN" "Could not fetch latest height, using fallback values"
        local trust_height=1851443
        local trust_hash="C7B2ED7863CFC5F363D24B244CDD18A6A7754BEAD3C2F88AE503FF6A0D3F3C27"
    else
        local trust_height=$((latest_height - 1000))
        local trust_hash=$(curl -s "http://node2.gonka.ai:26657/block?height=$trust_height" | jq -r '.result.block_id.hash' 2>/dev/null)

        if [ -z "$trust_hash" ] || [ "$trust_hash" == "null" ]; then
            log "WARN" "Could not fetch trust_hash, using fallback"
            trust_height=1851443
            trust_hash="C7B2ED7863CFC5F363D24B244CDD18A6A7754BEAD3C2F88AE503FF6A0D3F3C27"
        fi
    fi

    log "INFO" "Trust height: $trust_height, Trust hash: $trust_hash"

    # Включаем state-sync с правильными RPC серверами (напрямую на порт 26657)
    ssh_exec "sudo sed -i '/^\[statesync\]/,/^enable = / s/^enable = .*/enable = true/' $config_toml"
    ssh_exec "sudo sed -i 's|^rpc_servers = .*|rpc_servers = \"http://node2.gonka.ai:26657,http://node1.gonka.ai:26657\"|' $config_toml"
    ssh_exec "sudo sed -i 's/^trust_height = .*/trust_height = $trust_height/' $config_toml"
    ssh_exec "sudo sed -i 's/^trust_hash = .*/trust_hash = \"$trust_hash\"/' $config_toml"

    log "OK" "State-sync configured"

    # 5.5 Перезапуск node контейнера для применения настроек
    log "EXEC" "Restarting node container to apply all configurations..."
    ssh_exec "cd $deploy_dir && sudo docker stop node && sudo docker start node"

    # 5.6 Мониторинг progress state-sync с обнаружением зависания
    log "INFO" "Monitoring state-sync progress (checking every 30 seconds)..."

    local max_attempts=50  # 50 попыток * 30 сек = 25 минут максимум
    local attempt=0
    local sync_completed=false
    local last_chunk=0
    local stuck_count=0
    local iptables_rule_removed=false

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))

        # Проверяем высоту блока
        local current_height=$(curl -s "http://${SERVER_IP}:26657/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo "0")

        if [ "$current_height" != "0" ] && [ "$current_height" != "null" ] && [ -n "$current_height" ] && [ "$current_height" -gt 100 ]; then
            log "OK" "State-sync completed! Current block height: $current_height"
            sync_completed=true

            # Удаляем правило iptables DROP если оно есть
            if [ "$iptables_rule_removed" = false ]; then
                log "INFO" "Removing iptables DROP rule to allow all peer connections..."
                local drop_rule_num=$(ssh_exec_quiet "sudo iptables -t mangle -L OUTPUT -n --line-numbers | grep '^[0-9].*DROP' | awk '{print \$1}' | head -1")
                if [ -n "$drop_rule_num" ]; then
                    ssh_exec "sudo iptables -t mangle -D OUTPUT $drop_rule_num"
                    log "OK" "iptables DROP rule #$drop_rule_num removed"
                    iptables_rule_removed=true
                else
                    log "INFO" "No DROP rule found in iptables"
                fi
            fi

            break
        fi

        # Проверяем прогресс через логи (сколько чанков загружено)
        local chunk_info=$(ssh_exec_quiet "docker logs node --tail 20 2>&1 | grep -o 'chunk=[0-9]*' | tail -1 | cut -d'=' -f2")

        if [ -n "$chunk_info" ]; then
            log "INFO" "State-sync progress: chunk ~$chunk_info/368 (attempt $attempt/$max_attempts)"

            # Проверяем, застрял ли state-sync на одном чанке
            if [ "$chunk_info" = "$last_chunk" ]; then
                stuck_count=$((stuck_count + 1))
                if [ $stuck_count -ge 3 ]; then
                    log "WARN" "State-sync stuck at chunk $chunk_info for 3 attempts (90 seconds)"
                    log "WARN" "Applying fix for stuck sync..."

                    # Запускаем процедуру исправления зависания
                    log "EXEC" "Running fix_stuck_sync procedure..."

                    # Блокируем чужие peers
                    ssh_exec "cd /home/ubuntu/prometheus && sudo sh iptables_disable_peers.sh" || log "WARN" "iptables script not found, continuing..."

                    # Останавливаем контейнеры
                    ssh_exec "cd $deploy_dir && sudo docker compose down"

                    # Проверяем размер существующих данных
                    log "INFO" "Checking existing data size..."
                    local data_size_mb=$(ssh_exec_quiet "sudo du -sm $deploy_dir/.inference/data/ 2>/dev/null | awk '{print \$1}'" || echo "0")

                    if [ "$data_size_mb" -gt 1000 ]; then
                        log "INFO" "Found existing data (${data_size_mb}MB) - PRESERVING it!"
                        log "INFO" "Removing only .node_initialized and .cosmovisor to restart state-sync..."
                        ssh_exec "sudo rm -rf $deploy_dir/.inference/.node_initialized" || true
                        ssh_exec "sudo rm -rf $deploy_dir/.inference/cosmovisor" || true
                    else
                        log "INFO" "No data or small data (${data_size_mb}MB) - resetting blockchain..."
                        ssh_exec "sudo rm -rf $deploy_dir/.inference/data/"
                        ssh_exec "sudo rm -rf $deploy_dir/.inference/.node_initialized" || true
                        ssh_exec "sudo rm -rf $deploy_dir/.inference/cosmovisor" || true
                        ssh_exec "sudo mkdir -p $deploy_dir/.inference/data/"
                    fi

                    # Запускаем контейнеры чтобы создать config.toml
                    log "INFO" "Starting containers to create config.toml..."
                    ssh_exec "cd $deploy_dir && source config.env && sudo -E docker compose up -d"

                    log "INFO" "Waiting 15 seconds for config creation..."
                    sleep 15

                    # Останавливаем для редактирования конфига
                    log "INFO" "Stopping containers to edit config.toml..."
                    ssh_exec "cd $deploy_dir && sudo docker compose down"

                    # Получаем свежий trust_height и trust_hash
                    log "INFO" "Fetching fresh trust_height and trust_hash..."
                    local latest_height=$(curl -s http://node2.gonka.ai:26657/status | jq -r '.result.sync_info.latest_block_height')
                    local trust_height=$((latest_height - 1000))
                    local trust_hash=$(curl -s "http://node2.gonka.ai:26657/block?height=$trust_height" | jq -r '.result.block_id.hash')

                    log "INFO" "Latest height: $latest_height, Trust height: $trust_height"

                    # Исправляем rpc_servers (убираем /chain-rpc, используем прямой порт 26657)
                    log "INFO" "Fixing rpc_servers to use direct port 26657..."
                    ssh_exec "sudo sed -i 's|rpc_servers = .*|rpc_servers = \"http://node2.gonka.ai:26657,http://node1.gonka.ai:26657\"|' $deploy_dir/.inference/config/config.toml"

                    # Обновляем trust_height и trust_hash
                    ssh_exec "sudo sed -i 's/^trust_height = .*/trust_height = $trust_height/' $deploy_dir/.inference/config/config.toml"
                    ssh_exec "sudo sed -i 's/^trust_hash = .*/trust_hash = \"$trust_hash\"/' $deploy_dir/.inference/config/config.toml"

                    # Перезапускаем с исправленной конфигурацией
                    log "INFO" "Starting containers with fixed config..."
                    ssh_exec "cd $deploy_dir && source config.env && sudo -E docker compose up -d"

                    log "OK" "Fix applied, waiting 30 seconds..."
                    sleep 30

                    # Сбрасываем счётчики
                    stuck_count=0
                    last_chunk=0
                    continue
                fi
            else
                stuck_count=0
            fi
            last_chunk=$chunk_info
        else
            log "INFO" "State-sync in progress... (attempt $attempt/$max_attempts)"
        fi

        if [ $attempt -lt $max_attempts ]; then
            sleep 30
        fi
    done

    if [ "$sync_completed" = false ]; then
        log "WARN" "State-sync still in progress after ${max_attempts} attempts (20 minutes)"
        log "INFO" "This may be normal for slow connections. State-sync will continue in background."
        log "INFO" "You can monitor with: ssh ubuntu@${SERVER_IP} 'docker logs node --tail 50'"
    fi

    log "SUCCESS" "Phase 5 completed: Blockchain configuration done"
}

################################################################################
# Фаза 6: Финальный запуск
################################################################################

phase6_final_launch() {
    log_section "PHASE 6: FINAL LAUNCH"

    local deploy_dir="$GONKA_PATH/deploy/join"

    # 6.1 Создание .env (повторно для уверенности)
    log "EXEC" "Ensuring .env is up to date..."
    ssh_exec "cd $deploy_dir && sed 's/^export //' config.env > .env"

    # 6.2 Запуск всех сервисов включая mlnode
    log "EXEC" "Starting all services (including MLNode)..."
    log "INFO" "This will download Docker images if needed (may take time)..."

    ssh_exec "cd $deploy_dir && source config.env && sudo -E docker compose -f docker-compose.yml -f docker-compose.mlnode.yml up -d"

    log "INFO" "Waiting 20 seconds for all services to start..."
    sleep 20

    log "OK" "All services started"

    # 6.3 Проверка запущенных контейнеров
    log "CHECK" "Verifying running containers..."

    local containers=$(ssh_exec_quiet "cd $deploy_dir && sudo docker compose ps --format '{{.Service}}' 2>/dev/null" | tr '\n' ' ')

    log "INFO" "Running containers: $containers"

    if [[ "$containers" != *"node"* ]] || [[ "$containers" != *"api"* ]] || [[ "$containers" != *"mlnode"* ]]; then
        log "WARN" "Some expected containers may not be running"
    else
        log "OK" "All expected containers are running"
    fi

    # 6.4 Ожидание загрузки модели
    log "INFO" "Waiting for model to load (this may take 1-3 minutes)..."
    log "INFO" "Model: $MODEL_NAME"

    local max_wait=180  # 3 minutes max
    local wait_interval=15
    local elapsed=0
    local model_loaded=false

    while [[ $elapsed -lt $max_wait ]]; do
        # Проверяем GPU memory usage
        local gpu_used=$(ssh_exec_quiet "nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null" | head -1 | tr -d '\r\n ')

        if [[ -n "$gpu_used" ]] && [[ "$gpu_used" -gt 30000 ]]; then
            log "OK" "Model loaded! GPU memory: $((gpu_used / 1024))GB"
            model_loaded=true
            break
        fi

        # Проверяем current_status через API
        local status=$(ssh_exec_quiet "curl -s http://localhost:9200/admin/v1/nodes 2>/dev/null | grep -o '\"current_status\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4")

        if [[ "$status" == "INFERENCE" ]]; then
            log "OK" "Node status: INFERENCE"
            model_loaded=true
            break
        fi

        log "INFO" "Still loading... (${elapsed}s elapsed, GPU: ${gpu_used:-0}MB, status: ${status:-unknown})"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    if [[ "$model_loaded" == false ]]; then
        log "WARN" "Model loading timeout after ${max_wait}s. Will continue, but model may still be loading."
        log "INFO" "Check status with: ssh ubuntu@${SERVER_IP} 'curl -s http://localhost:9200/admin/v1/nodes | jq'"
    fi

    log "SUCCESS" "Phase 6 completed: Final launch done"
}

################################################################################
# Фаза 7: Проверки и отчёт
################################################################################

phase7_verification() {
    log_section "PHASE 7: VERIFICATION AND REPORT"

    local deploy_dir="$GONKA_PATH/deploy/join"
    local verification_log="$NODE_OUTPUT_DIR/verification.txt"

    echo "GONKA NODE VERIFICATION REPORT" > "$verification_log"
    echo "Generated at: $(date)" >> "$verification_log"
    echo "======================================" >> "$verification_log"
    echo "" >> "$verification_log"

    # Загружаем WARM_ADDRESS
    if [[ -f "$NODE_OUTPUT_DIR/warm_address.txt" ]]; then
        WARM_ADDRESS=$(cat "$NODE_OUTPUT_DIR/warm_address.txt")
    fi

    # 7.1 Проверки API endpoints
    log "CHECK" "Verifying API endpoints..."

    # Participant registration
    local participant_response=$(curl -s "${SEED_API_URL}/v1/participants/${WARM_ADDRESS}" 2>/dev/null || echo "ERROR")
    if [[ "$participant_response" == *"pubkey"* ]]; then
        log "OK" "Participant registered in blockchain"
        echo "✓ Participant registered: ${SEED_API_URL}/v1/participants/${WARM_ADDRESS}" >> "$verification_log"
    else
        log "WARN" "Participant not found in API"
        echo "✗ Participant not found" >> "$verification_log"
    fi

    # Node RPC
    local node_rpc_response=$(curl -s "http://${SERVER_IP}:26657/status" 2>/dev/null || echo "ERROR")
    if [[ "$node_rpc_response" == *"result"* ]]; then
        log "OK" "Node RPC responding"
        echo "✓ Node RPC: http://${SERVER_IP}:26657/status" >> "$verification_log"
    else
        log "WARN" "Node RPC not responding"
        echo "✗ Node RPC not responding" >> "$verification_log"
    fi

    # API Dashboard
    local api_response=$(curl -s "http://${SERVER_IP}:8000/" 2>/dev/null || echo "ERROR")
    if [[ ! -z "$api_response" ]]; then
        log "OK" "API Dashboard responding"
        echo "✓ Dashboard: http://${SERVER_IP}:8000/" >> "$verification_log"
    else
        log "WARN" "API Dashboard not responding"
        echo "✗ Dashboard not responding" >> "$verification_log"
    fi

    # 7.2 Проверки CUDA
    log "CHECK" "Verifying CUDA availability..."

    # Находим имя mlnode контейнера
    local mlnode_container=$(ssh_exec_quiet "cd $deploy_dir && sudo docker compose ps --format '{{.Name}}' 2>/dev/null | grep mlnode" | head -1 | tr -d '\r\n')

    if [[ -z "$mlnode_container" ]]; then
        log "WARN" "MLNode container not found"
        echo "✗ MLNode container not found" >> "$verification_log"
    else
        log "INFO" "MLNode container: $mlnode_container"

        # nvidia-smi
        local nvidia_smi_output=$(ssh_exec_quiet "sudo docker exec $mlnode_container nvidia-smi 2>&1" || echo "ERROR")
        if [[ "$nvidia_smi_output" != *"Failed to initialize"* ]] && [[ "$nvidia_smi_output" != *"ERROR"* ]]; then
            log "OK" "CUDA GPU detected via nvidia-smi"
            echo "✓ CUDA GPU detected" >> "$verification_log"
        else
            log "WARN" "CUDA GPU not detected (may need container recreation)"
            echo "✗ CUDA GPU not detected" >> "$verification_log"
        fi

        # PyTorch CUDA check (с версией CUDA)
        local torch_check=$(ssh_exec_quiet "sudo docker exec $mlnode_container /app/packages/api/.venv/bin/python3 -c \"import torch; print(f'CUDA:{torch.cuda.is_available()},GPUs:{torch.cuda.device_count()},Version:{torch.version.cuda}')\" 2>&1" | tail -1)
        if [[ "$torch_check" == *"CUDA:True"* ]]; then
            log "OK" "PyTorch CUDA available: $torch_check"
            echo "✓ PyTorch: $torch_check" >> "$verification_log"
        else
            log "WARN" "PyTorch CUDA not available: $torch_check"
            echo "✗ PyTorch CUDA issue: $torch_check" >> "$verification_log"
        fi

        # MLNode health endpoint
        local health_response=$(ssh_exec_quiet "curl -s http://localhost:8080/health 2>/dev/null" | tr -d '\r\n')
        if [[ "$health_response" == *"ok"* ]] || [[ "$health_response" == *"healthy"* ]] || [[ -n "$health_response" ]]; then
            log "OK" "MLNode health endpoint responding"
            echo "✓ MLNode health: OK" >> "$verification_log"
        else
            log "WARN" "MLNode health endpoint not responding"
            echo "✗ MLNode health: not responding" >> "$verification_log"
        fi

        # GPU devices endpoint
        local gpu_devices=$(ssh_exec_quiet "curl -s http://localhost:8080/api/v1/gpu/devices 2>/dev/null" | tr -d '\r\n')
        if [[ "$gpu_devices" == *"name"* ]] || [[ "$gpu_devices" == *"device"* ]]; then
            log "OK" "GPU devices endpoint responding"
            echo "✓ GPU devices: available" >> "$verification_log"
        elif [[ -n "$gpu_devices" ]]; then
            log "INFO" "GPU devices response: $gpu_devices"
            echo "  GPU devices: $gpu_devices" >> "$verification_log"
        else
            log "WARN" "GPU devices endpoint not responding"
            echo "⚠ GPU devices: not responding" >> "$verification_log"
        fi
    fi

    # 7.3 Проверка API node configuration
    log "CHECK" "Verifying API node configuration..."
    echo "" >> "$verification_log"
    echo "API NODE CONFIGURATION:" >> "$verification_log"

    # Проверка nodes array через admin API
    local nodes_response=$(ssh_exec_quiet "curl -s http://localhost:9200/admin/v1/nodes 2>/dev/null" | tr -d '\r\n')

    if [[ "$nodes_response" == "[]" ]] || [[ -z "$nodes_response" ]]; then
        log "ERROR" "API nodes array is EMPTY! node-config.json may have wrong format"
        echo "✗ nodes: EMPTY (check node-config.json format!)" >> "$verification_log"
        log "INFO" "Expected format: {id, host, inference_port, poc_port, max_concurrent, models}"
        log "INFO" "See CLAUDE.md for correct node-config.json structure"
    else
        # Извлекаем информацию о нодах
        local node_count=$(echo "$nodes_response" | grep -o '"id"' | wc -l | tr -d ' ')
        log "OK" "API has $node_count node(s) configured"
        echo "✓ nodes: $node_count node(s) configured" >> "$verification_log"

        # Проверка current_status
        local current_status=$(echo "$nodes_response" | grep -o '"current_status":"[^"]*"' | head -1 | cut -d'"' -f4)
        local intended_status=$(echo "$nodes_response" | grep -o '"intended_status":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [[ "$current_status" == "INFERENCE" ]]; then
            log "OK" "Node current_status: INFERENCE"
            echo "✓ current_status: INFERENCE" >> "$verification_log"
        elif [[ "$current_status" == "LOADING" ]]; then
            log "INFO" "Node current_status: LOADING (model is being loaded)"
            echo "⏳ current_status: LOADING (model loading...)" >> "$verification_log"
        else
            log "WARN" "Node current_status: $current_status (expected: INFERENCE)"
            echo "⚠ current_status: $current_status (expected: INFERENCE)" >> "$verification_log"
        fi

        log "INFO" "Node intended_status: $intended_status"
        echo "  intended_status: $intended_status" >> "$verification_log"
    fi

    # Проверка merged_node_config
    local config_dump=$(ssh_exec_quiet "cat $deploy_dir/.dapi/config-dump.json 2>/dev/null" | tr -d '\r\n')
    if [[ "$config_dump" == *'"merged_node_config":true'* ]] || [[ "$config_dump" == *'"merged_node_config": true'* ]]; then
        log "OK" "merged_node_config: true"
        echo "✓ merged_node_config: true" >> "$verification_log"
    else
        log "WARN" "merged_node_config: false (config not merged yet)"
        echo "⚠ merged_node_config: false" >> "$verification_log"
    fi

    # Проверка GPU usage
    log "CHECK" "Verifying GPU memory usage..."
    local gpu_info=$(ssh_exec_quiet "nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null" | head -1 | tr -d '\r\n')

    if [[ -n "$gpu_info" ]]; then
        local gpu_used=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
        local gpu_total=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')

        if [[ -n "$gpu_used" ]] && [[ -n "$gpu_total" ]]; then
            local gpu_used_gb=$((gpu_used / 1024))
            local gpu_total_gb=$((gpu_total / 1024))

            if [[ "$gpu_used" -gt 30000 ]]; then  # More than 30GB used = model loaded
                log "OK" "GPU memory: ${gpu_used_gb}GB / ${gpu_total_gb}GB (model loaded)"
                echo "✓ GPU memory: ${gpu_used_gb}GB / ${gpu_total_gb}GB (model loaded)" >> "$verification_log"
            elif [[ "$gpu_used" -gt 1000 ]]; then  # 1-30GB = loading
                log "INFO" "GPU memory: ${gpu_used_gb}GB / ${gpu_total_gb}GB (model loading...)"
                echo "⏳ GPU memory: ${gpu_used_gb}GB / ${gpu_total_gb}GB (loading)" >> "$verification_log"
            else
                log "WARN" "GPU memory: ${gpu_used_gb}GB / ${gpu_total_gb}GB (model NOT loaded)"
                echo "⚠ GPU memory: ${gpu_used_gb}GB / ${gpu_total_gb}GB (model not loaded)" >> "$verification_log"
            fi
        fi
    else
        log "WARN" "Could not get GPU info"
        echo "⚠ GPU info: not available" >> "$verification_log"
    fi

    # 7.5 Проверка логов на ошибки
    log "CHECK" "Checking logs for errors..."
    echo "" >> "$verification_log"
    echo "CONTAINER LOGS:" >> "$verification_log"

    local error_count=0

    for container in node api; do
        local errors=$(ssh_exec_quiet "cd $deploy_dir && sudo docker logs $container --since 10m 2>&1 | grep -i 'error\|fatal' | wc -l" | tail -1 | tr -d '\r\n ')

        if [[ "$errors" -gt 0 ]]; then
            log "WARN" "Found $errors error lines in $container logs"
            echo "⚠ $container: $errors error lines" >> "$verification_log"
            error_count=$((error_count + errors))
        else
            echo "✓ $container: no errors" >> "$verification_log"
        fi
    done

    if [[ $error_count -eq 0 ]]; then
        log "OK" "No errors in container logs"
    fi

    # 7.6 Проверка состояния сервиса (/api/v1/state)
    log "CHECK" "Verifying service state..."
    echo "" >> "$verification_log"
    echo "SERVICE STATE:" >> "$verification_log"

    local state_response=$(ssh_exec_quiet "curl -s http://localhost:8080/api/v1/state 2>/dev/null" | tr -d '\r\n')

    if [[ -n "$state_response" ]]; then
        local service_state=$(echo "$state_response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
        if [[ "$service_state" == "INFERENCE" ]]; then
            log "OK" "Service state: INFERENCE"
            echo "✓ service_state: INFERENCE" >> "$verification_log"
        elif [[ "$service_state" == "LOADING" ]]; then
            log "INFO" "Service state: LOADING (model is being loaded)"
            echo "⏳ service_state: LOADING" >> "$verification_log"
        else
            log "WARN" "Service state: $service_state"
            echo "⚠ service_state: $service_state" >> "$verification_log"
        fi
    else
        log "WARN" "Service state endpoint not responding"
        echo "⚠ service_state: not responding" >> "$verification_log"
    fi

    # 7.7 Проверка загрузки модели vLLM (/v1/models на порту 5050)
    log "CHECK" "Verifying vLLM model loading..."
    echo "" >> "$verification_log"
    echo "VLLM MODEL:" >> "$verification_log"

    local models_response=$(ssh_exec_quiet "curl -s http://localhost:5050/v1/models 2>/dev/null" | tr -d '\r\n')

    if [[ -n "$models_response" ]] && [[ "$models_response" != *"error"* ]] && [[ "$models_response" != *"Connection refused"* ]]; then
        local model_id=$(echo "$models_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        local max_len=$(echo "$models_response" | grep -o '"max_model_len":[0-9]*' | cut -d':' -f2)

        if [[ -n "$model_id" ]]; then
            log "OK" "vLLM model loaded: $model_id (max_len: $max_len)"
            echo "✓ vLLM model: $model_id" >> "$verification_log"
            echo "  max_model_len: $max_len" >> "$verification_log"
        else
            log "WARN" "vLLM model endpoint responded but no model found"
            echo "⚠ vLLM model: no model loaded" >> "$verification_log"
        fi
    else
        log "WARN" "vLLM model endpoint not responding (model may still be loading)"
        echo "⚠ vLLM model: not responding (loading...)" >> "$verification_log"
    fi

    # 7.8 Общий отчёт настройки (/admin/v1/setup/report)
    log "CHECK" "Fetching setup report..."
    echo "" >> "$verification_log"
    echo "SETUP REPORT:" >> "$verification_log"

    local setup_report=$(ssh_exec_quiet "curl -s http://localhost:9200/admin/v1/setup/report 2>/dev/null" | tr -d '\r\n')

    if [[ -n "$setup_report" ]] && [[ "$setup_report" != *"error"* ]]; then
        local overall_status=$(echo "$setup_report" | grep -o '"overall_status":"[^"]*"' | cut -d'"' -f4)
        local passed_checks=$(echo "$setup_report" | grep -o '"passed_checks":[0-9]*' | cut -d':' -f2)
        local failed_checks=$(echo "$setup_report" | grep -o '"failed_checks":[0-9]*' | cut -d':' -f2)
        local total_checks=$(echo "$setup_report" | grep -o '"total_checks":[0-9]*' | cut -d':' -f2)

        if [[ "$overall_status" == "PASS" ]]; then
            log "OK" "Setup report: PASS ($passed_checks/$total_checks checks passed)"
            echo "✓ setup_report: PASS ($passed_checks/$total_checks)" >> "$verification_log"
        else
            log "WARN" "Setup report: $overall_status ($passed_checks/$total_checks passed, $failed_checks failed)"
            echo "⚠ setup_report: $overall_status ($passed_checks/$total_checks passed)" >> "$verification_log"

            # Извлекаем issues
            local issues=$(echo "$setup_report" | grep -o '"issues":\[[^]]*\]' | sed 's/"issues":\[//' | sed 's/\]//' | tr ',' '\n' | sed 's/"//g')
            if [[ -n "$issues" ]]; then
                echo "  Issues:" >> "$verification_log"
                echo "$issues" | while read -r issue; do
                    if [[ -n "$issue" ]]; then
                        echo "    - $issue" >> "$verification_log"
                    fi
                done
            fi
        fi

        # Проверка ключевых статусов из отчёта
        if [[ "$setup_report" == *'"id":"permissions_granted"'*'"status":"PASS"'* ]]; then
            log "OK" "Permissions: granted"
            echo "✓ permissions: granted" >> "$verification_log"
        fi

        if [[ "$setup_report" == *'"id":"block_sync"'*'"status":"PASS"'* ]]; then
            log "OK" "Block sync: synced"
            echo "✓ block_sync: synced" >> "$verification_log"
        fi

        if [[ "$setup_report" == *'"id":"mlnode_node1"'*'"status":"PASS"'* ]]; then
            log "OK" "MLNode: healthy"
            echo "✓ mlnode: healthy" >> "$verification_log"
        fi
    else
        log "WARN" "Setup report endpoint not responding"
        echo "⚠ setup_report: not responding" >> "$verification_log"
    fi

    echo "" >> "$verification_log"
    echo "Verification completed at: $(date)" >> "$verification_log"

    log "OK" "Verification report saved to: $verification_log"

    log "SUCCESS" "Phase 7 completed: Verification done"
}

################################################################################
# Фаза 8: Grant ML Permissions
################################################################################

phase8_grant_permissions() {
    log_section "PHASE 8: GRANT ML PERMISSIONS"

    # Проверяем, синхронизирована ли нода
    local current_height=$(curl -s "http://${SERVER_IP}:26657/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo "0")

    if [ "$current_height" = "0" ] || [ "$current_height" = "null" ] || [ -z "$current_height" ]; then
        log "WARN" "Node is not synced yet (block height: $current_height)"
        log "WARN" "Skipping grant - you can run it manually later with:"
        echo ""
        echo "  cd /Users/ss/Crypto/gonka"
        echo "  ./inferenced tx inference grant-ml-ops-permissions \\"
        echo "    <COLD_KEY_NAME> \\"
        echo "    $(cat "$NODE_OUTPUT_DIR/warm_address.txt") \\"
        echo "    --from <COLD_KEY_NAME> \\"
        echo "    --keyring-backend file \\"
        echo "    --gas 2000000 \\"
        echo "    --node http://node2.gonka.ai:26657"
        echo ""
        log "INFO" "Phase 8 skipped: Node not synced"
        return 0
    fi

    log "OK" "Node is synced at block height: $current_height"

    # Читаем необходимую информацию
    local warm_address=$(cat "$NODE_OUTPUT_DIR/warm_address.txt" 2>/dev/null)
    local cold_key_file="/Users/ss/Crypto/gonka/local_key.txt"

    if [ ! -f "$cold_key_file" ]; then
        log "ERROR" "Cold key file not found: $cold_key_file"
        log "WARN" "Skipping grant - run manually later"
        return 0
    fi

    local cold_key_name=$(grep "cold-key-name:" "$cold_key_file" | cut -d':' -f2 | xargs)

    if [ -z "$cold_key_name" ] || [ -z "$warm_address" ]; then
        log "ERROR" "Could not extract cold key name or warm address"
        log "INFO" "Cold key name: $cold_key_name"
        log "INFO" "Warm address: $warm_address"
        log "WARN" "Skipping grant - run manually later"
        return 0
    fi

    log "INFO" "Cold key name: $cold_key_name"
    log "INFO" "Warm address: $warm_address"

    # Спрашиваем пользователя
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "GRANT ML PERMISSIONS"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Ready to grant ML operations permissions:"
    echo "  From (cold wallet): $cold_key_name"
    echo "  To (warm wallet):   $warm_address"
    echo ""
    echo "You will be prompted for your cold wallet passphrase."
    echo ""
    read -p "Execute grant now? (y/n): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Grant skipped by user"
        log "INFO" "You can run it manually later with:"
        echo ""
        echo "  cd /Users/ss/Crypto/gonka"
        echo "  ./inferenced tx inference grant-ml-ops-permissions \\"
        echo "    $cold_key_name \\"
        echo "    $warm_address \\"
        echo "    --from $cold_key_name \\"
        echo "    --keyring-backend file \\"
        echo "    --gas 2000000 \\"
        echo "    --node http://node2.gonka.ai:26657"
        echo ""
        return 0
    fi

    # Выполняем grant
    log "EXEC" "Executing grant ML permissions..."

    local grant_output_file="$NODE_OUTPUT_DIR/grant.txt"
    local crypto_dir="/Users/ss/Crypto/gonka"
    local chain_rpc_url="http://node2.gonka.ai:26657"

    cd "$crypto_dir"

    set +e
    ./inferenced tx inference grant-ml-ops-permissions \
        "$cold_key_name" \
        "$warm_address" \
        --from "$cold_key_name" \
        --keyring-backend file \
        --gas 2000000 \
        --node "$chain_rpc_url" 2>&1 | tee "$grant_output_file"

    local grant_exit_code=${PIPESTATUS[0]}
    set -e

    cd - > /dev/null

    # Проверяем результат
    if grep -q "Transaction confirmed successfully" "$grant_output_file"; then
        log "OK" "Grant executed successfully!"
        echo ""
        grep "Block height:" "$grant_output_file" || true
        log "SUCCESS" "Phase 8 completed: Grant ML permissions done"
    elif grep -q "account .* not found" "$grant_output_file"; then
        log "ERROR" "Cold wallet not found in blockchain"
        log "WARN" "This usually means the cold wallet has no tokens for gas"
        log "INFO" "Grant output saved to: $grant_output_file"
        log "WARN" "Phase 8 failed: Account not found"
    else
        log "WARN" "Grant result unclear - check output"
        log "INFO" "Grant output saved to: $grant_output_file"
        cat "$grant_output_file"
        log "WARN" "Phase 8 completed with warnings"
    fi
}

################################################################################
# Финальный отчёт
################################################################################

final_report() {
    log_section "DEPLOYMENT COMPLETED SUCCESSFULLY"

    # Загружаем адреса
    local warm_address=""
    if [[ -f "$NODE_OUTPUT_DIR/warm_address.txt" ]]; then
        warm_address=$(cat "$NODE_OUTPUT_DIR/warm_address.txt")
    fi

    echo ""
    echo "========================================"
    echo "     DEPLOYMENT COMPLETED"
    echo "========================================"
    echo ""
    echo "NODE: $KEY_NAME"
    echo "SERVER: $SSH_USER@$SERVER_IP"
    echo ""
    echo "WALLETS:"
    echo "  Cold PubKey:    $ACCOUNT_PUBKEY"
    echo "  Warm Address:   $warm_address"
    echo ""
    echo "USEFUL LINKS:"
    echo "  Dashboard:      http://${SERVER_IP}:8000/"
    echo "  Chain RPC:      http://${SERVER_IP}:26657/status"
    echo "  Participant:    ${SEED_API_URL}/v1/participants/${warm_address}"
    echo ""
    echo "TRACKERS:"
    echo "  - http://34.60.64.109/"
    echo "  - https://tracker.gonka.hyperfusion.io/"
    echo "  - https://gonkahub.com/network"
    echo ""
    echo "SAVED FILES:"
    echo "  Config:         $NODE_OUTPUT_DIR/config.env"
    echo "  Warm Key:       $NODE_OUTPUT_DIR/warm_key.txt"
    echo "  Warm Address:   $NODE_OUTPUT_DIR/warm_address.txt"
    echo "  Registration:   $NODE_OUTPUT_DIR/registration.txt"
    echo "  Volume Info:    $NODE_OUTPUT_DIR/volume.txt"
    echo "  Verification:   $NODE_OUTPUT_DIR/verification.txt"
    echo "  Full Log:       $LOGFILE"
    echo ""
    echo "========================================"
    echo ""
    echo "IMPORTANT NEXT STEPS:"
    echo "  1. Wait for next epoch to start (check trackers)"
    echo "  2. Monitor node health in trackers"
    echo "  3. Update your spreadsheet with node information"
    echo "  4. Grant ML permissions from local machine (if not done yet)"
    echo ""
    echo "========================================"
    echo ""

    log "SUCCESS" "All phases completed successfully!"
}

################################################################################
# Main
################################################################################

main() {
    # Проверка аргументов
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <config-file>"
        echo "Example: $0 nodes/node1.conf"
        exit 1
    fi

    CONFIG_FILE="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Загрузка конфигурации
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # Установка дефолтных значений
    VOLUME_DEVICE="${VOLUME_DEVICE:-/dev/vdc}"
    VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/ssd}"
    HF_HOME="${HF_HOME:-/mnt/ssd/hf}"
    GONKA_PATH="${GONKA_PATH:-/mnt/ssd/gonka}"
    PERSISTENT_PEERS="${PERSISTENT_PEERS:-981908092bc597e60cc81eda4329783aea7af9d7@85.234.66.95:5000,0aaa255c5b119e95cd66e1bd6032b213ce1c7943@85.234.66.223:5000,8e99e6adee695719c1c0ed5a37165e14f4c0751f@85.234.66.191:5000}"

    # Создание директорий для ноды
    NODE_OUTPUT_DIR="$SCRIPT_DIR/nodes/$KEY_NAME"
    mkdir -p "$NODE_OUTPUT_DIR"

    # Создание лог-файла
    LOGFILE="$SCRIPT_DIR/logs/${KEY_NAME}_${TIMESTAMP}.log"
    touch "$LOGFILE"

    # Создание симлинка на последний лог
    ln -sf "$(basename "$LOGFILE")" "$SCRIPT_DIR/logs/${KEY_NAME}_latest.log"

    # Начало логирования
    log "INFO" "========================================="
    log "INFO" "Gonka Node Deployment Script"
    log "INFO" "========================================="
    log "INFO" "Started at: $(date)"
    log "INFO" "Config file: $CONFIG_FILE"
    log "INFO" "Log file: $LOGFILE"
    log "INFO" "========================================="

    # Фаза 0: Валидация
    validate_config
    display_config
    confirm_deployment

    # Основные фазы развёртывания
    phase1_server_preparation
    phase2_gonka_models
    phase3_configuration
    phase4_basic_services
    phase5_blockchain_config
    phase6_final_launch
    phase7_verification
    phase8_grant_permissions

    # Финальный отчёт
    final_report

    log "INFO" "========================================="
    log "INFO" "Deployment finished at: $(date)"
    log "INFO" "========================================="

    cleanup_ssh
    exit 0
}

# Установка trap для cleanup при выходе
trap cleanup_ssh EXIT INT TERM

# Запуск
main "$@"

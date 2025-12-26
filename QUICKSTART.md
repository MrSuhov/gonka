# Быстрый старт - Gonka Node Deployment

## 1. Подготовка (выполняется ОДИН РАЗ)

### Создайте холодный кошелёк локально:

```bash
cd /path/to/inferenced
./inferenced keys add my-node-name --keyring-backend file
```

**ВАЖНО:** Сохраните вывод (seed и public key) в безопасное место!

## 2. Настройка для новой ноды

### Скопируйте пример конфига:

```bash
cd /Users/ss/GenAI/gonka
cp nodes/node1.conf.example nodes/my-node.conf
```

### Отредактируйте конфиг:

```bash
nano nodes/my-node.conf
```

Заполните обязательные параметры:
- `SERVER_IP` - IP вашего сервера
- `KEY_NAME` - имя ноды
- `KEYRING_PASSWORD` - новый рандомный пароль (≥8 символов)
- `ACCOUNT_PUBKEY` - public key из холодного кошелька
- `MODEL_NAME` - `Qwen/Qwen3-32B-FP8` (для 1 GPU) или `Qwen/Qwen3-235B-A22B-Instruct-2507-FP8` (для 8 GPU)
- `NODE_CONFIG_PROFILE` - `x1` или `x8`

## 3. Запуск деплоя

```bash
./mitch_help.sh nodes/my-node.conf
```

Проверьте параметры и введите `yes` для подтверждения.

## 4. После успешного деплоя

### Выдайте права (ОБЯЗАТЕЛЬНО!):

Возьмите `warm_address` из файла `nodes/<KEY_NAME>/warm_address.txt` и выполните:

```bash
./inferenced tx inference grant-ml-ops-permissions \
    my-node-name \
    gonka1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
    --from my-node-name \
    --keyring-backend file \
    --gas 2000000 \
    --node http://node2.gonka.ai:8000/chain-rpc/
```

Где:
- `my-node-name` - имя вашего холодного ключа
- `gonka1xxx...` - адрес из `warm_address.txt`

## 5. Проверка

Откройте в браузере:
- Dashboard: `http://<SERVER_IP>:8000/`
- Chain RPC: `http://<SERVER_IP>:26657/status`

Проверьте трекеры (после начала эпохи):
- http://34.60.64.109/
- https://tracker.gonka.hyperfusion.io/
- https://gonkahub.com/network

## Проблемы?

Смотрите лог: `logs/<KEY_NAME>_latest.log`

Подробности в [README.md](README.md)

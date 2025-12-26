# Оригинальная дока

* [https://gonka.ai/host/quickstart/\#how-to-clean-up-your-node-full-reset](https://gonka.ai/host/quickstart/#how-to-clean-up-your-node-full-reset)  
* В ней предполагается, что сетап идет из под root, или из под юзера который может docker compose запускать. Но на hyperstack docker через sudo только запускается.  
  Все идет через переменные окружения, а они у юзера.  
  Поэтому надо делать “sudo \-E” чтоб использовались переменные окружения пользователя.

# Трекеры

* [http://34.60.64.109/](http://34.60.64.109/)   
* [https://tracker.gonka.hyperfusion.io/](https://tracker.gonka.hyperfusion.io/)   
* [https://tracker.gonka.top/](https://tracker.gonka.top/)   
* [https://gonkahub.com/network](https://gonkahub.com/network) 

# (Локально) разово

* Скачать консольную утилиту кошелек [github](https://github.com/gonka-ai/gonka/releases)  
* Положить ее в удобное место и использовать потом, у меня /home/mitch/Crypto/[gonka.ai](http://gonka.ai)  
* \# ./inferenced keys add local-key \--keyring-backend file  
  * local-key \- это имя кошелька локальное, может быть любое  
  * Записать (в первый раз) passphrase, это локальный пароль для работы с кошельком.  
* Сделать папку для всех будущих нод у меня  
  * /home/mitch/Crypto/gonka.ai/servers/

# Добавить виртуалку (Хостинг панель)

* Ubuntu 24.04 cuda 12.8. with docker  
  * поставить галочки  
    * SSH Access  
    * Public IP Address

# Добавить Volume (Хостинг панель)

* В админке создать Volume, с тем же именем и дц что и хост машина на 2000G  
  * в той же локации, не загрузочный  
* зайти в виртуалку Volumes, подключить его  
* 

# Firewall (Хостинг панель)

* зайти в виртуалку, Firewall  
* подключить уже настроенный пресет full\_node или full\_node\_us, доступен будет только из локации виртуалки  
  * там открыты порты 5000, 26657, 8000

# (Локально) Создать холодный кошелек ноды

* \# cd /home/mitch/Crypto/[gonka.ai](http://gonka.ai)  
* \# cp \-R servers/blank servers/node\_name/  
  * в этой папке делать все файлы по настраиваемой ноде  
  * **шаблоны, папку blank можно взять из репозитория** [https://github.com/akamitch/prometheus/tree/main/blank](https://github.com/akamitch/prometheus/tree/main/blank)   
* \# ./inferenced keys add name-of-key \--keyring-backend file  
  * name-of-key это имя ключа которое локально в твоем кошельке используется  
  * name-of-key заменяем на имя ноды, такое же как рабочая папка  
  * [https://claude.ai/share/54753e1a-f321-4dfa-92b2-f85aba95fa18](https://claude.ai/share/54753e1a-f321-4dfa-92b2-f85aba95fa18) для лучшего понимания. когда нод будет несколько, для каждой нужен отдельный кошелек. и в след раз gonka-account-key меняй на что то другое, это имя ключа которое локально в твоем кошельке используется  
  * поведение команды при создании первого кошелька-ключа, и остальных разное:  
    * первый раз надо задать passphrase  
    * а в остальные разы ее вводить  
* Записать команду и ее вывод команды в local\_key.txt в папке ноды. там seed и паблик кей который потом понадобится  
* Записываем в [таблицу](https://docs.google.com/spreadsheets/d/1n-pJ2Hlz1p1fxrvmAhYJggURtKcoLtgBH_rrWGDh-1g/edit?gid=315833646#gid=315833646) address который соответствуют ноде

# Сервер консоль

* ssh ubuntu@185.216.20.162  
  * заработает через неск минут после запуска виртуалки  
* Систему не обновлять, от этого виртуалка ломается\!\!\!  
* screen  
* или если уже настраивали, с ssh отвалился то  
* screen \-x

## 

## Прописать ключи остальных админов

* vi .ssh/authorized\_keys  
* ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTjwUc2ClEscDY6eKn+OWhUOr+myraIf+9eLGGV5eDR [newmitch@gmail.com](mailto:newmitch@gmail.com)  
* ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBjug98HZ7B/OXDUCFZugrKohonx2SEfC7LtlOhI2Z6LzIb8cLcB91CslBlaKbBV6cLV7K7CzdMA174dP53c9yZGcWHp/3Ky11PG4ofOug3matP4fgcorjsL0JBlHoTiTrfO73j/DcPdTHwa4VdGXpgyphfYhz4cuDNjNv2x/yL9WYT7FCHrhdkLmERzAcqqtd78/XkGQjnu4me62bFRaX8wsYYWlQVB3oYYSfxSdXrcDXFVh47CtvVSP+DEuJkYfOHEow5aAp0/N6gRGCDMuvhcuCfj/BMHdGX0nJp2ITseFWRORnXr1v1fbhXUUmseDcYFCYneQrFOz60tfvOlfd nick@PAPA-PC  
* ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFxtkahP9A6ocXDJwFUM8eXOBaWJtSNUrLxjxCya/I+G [ocromvell@gmail.com](mailto:ocromvell@gmail.com)  
  * 

## Примонтировать Volume

* lsblk  
  * посмотреть винты, всегда нужный /dev/vdc будет  
* sudo mkfs.ext4 /dev/vdc  
  * отформатировать  
* sudo mkdir \-p /mnt/ssd && sudo mount /dev/vdc /mnt/ssd && sudo chown \-R ubuntu:ubuntu /mnt/ssd  
* sudo blkid \-s UUID \-o value /dev/vdc  
  * скопировать UUID, который напротив /dev/vdc например  
  * /dev/vdc: UUID=c0ef20c6-57c0-4bc7-9ac6-dd6362ed8e6c BLOCK\_SIZE="4096" TYPE="ext4"  
* sudo vi /etc/fstab  
* UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /mnt/ssd ext4 defaults,nofail 0 2  
  * добавить в своим UUID нижней строкой  
  * править в файле volume.txt

## Поставить Prometheus

* cd  
* git clone [https://github.com/akamitch/prometheus.git](https://github.com/akamitch/prometheus.git) && cd prometheus && sudo docker compose up \-d

## Скачать файлы gonka и моделей

* cd /mnt/ssd && git clone https://github.com/gonka-ai/gonka.git \-b main  
* cd /mnt/ssd/gonka/deploy/join  
* sudo mkdir /mnt/ssd/hf && sudo chown ubuntu:ubuntu /mnt/ssd/hf  
  * тут будут модели хранится, это внешнее хранилище примонтировано  
* export HF\_HOME=/mnt/ssd/hf && sudo apt update && sudo apt install \-y pipx && pipx ensurepath && pipx install huggingface\_hub  
* \~/.local/bin/hf download Qwen/Qwen3-235B-A22B-Instruct-2507-FP8  
  * большая (если сетапите х8 видях)  
  * скачает модель и положит в /mnt/ssd/hf тк этот путь у нас в переменной окружения HF\_HOME  
* \~/.local/bin/hf download Qwen/Qwen3-32B-FP8  
  * маленькая (если сетапите 1 видяху)  
* чтоб не ждать, можно открыть еще 1 теминал и продолжить сетап, тк это неск минут, в USA вообще 15 может быть

# Local сделать конфиг

* Отредактировать файл config.env:  
  * IP масс заменой поменять  
  * KEY\_NAME=quick-newton  
    * имя ноды, делам как хостер сгенерил  
  * KEYRING\_PASSWORD=kjhjfjfjfbe5rig7hkjnf  
    * рандомный новый пароль  
  * ACCOUNT\_PUBKEY=A6Mh+ZZil8mCUSIJG9iWLj/IH5PfCJaMoAX3U70c2GE/  
    * паблик кей холодного кошелька ноды, без кавычек, который в local\_key.txt  
  * export HF\_HOME=/mnt/ssd/hf  
    * путь где модели хранятся. уже прописан, но бывал у нас разный

# Server

* cd /mnt/ssd/gonka/deploy/join  
* vi config.env  
  * залить gonka/deploy/join/config.env  
* vi node-config.json  
  * взять из [доки](https://gonka.ai/host/quickstart/#__tabbed_1_1) подходящий по железкам node-config.json, залить на сервер  
* sed 's/^export //' config.env \> .env  
* source config.env  
  * создать переменные окружения из файла  
* sudo \-E docker compose up tmkms node \-d \--no-deps  
  * запуск чтоб от рута были переменные окружекния  
* sudo docker compose logs tmkms node \-f  
  * проверит логи, должно куча логов сыавться, ctrl-c выйти  
* sudo \-E docker compose logs tmkms node | grep \-i error  
  * так тольок ошибки, на этой стадии они будут тк не все запущено  
* sudo \-E docker compose run \--rm \--no-deps \-it api /bin/sh  
  * генерация теплого ключа  
  * скачает вначале образы, и останется в шелле, но внутри контейнера  
  * выполнить команду, и записать ее вывод в файл warm\_key.txt, в папке ноды на локальном компе.  
  * printf '%s\\n%s\\n' "$KEYRING\_PASSWORD" "$KEYRING\_PASSWORD" | inferenced keys add "$KEY\_NAME" \--keyring-backend file  
    * Там будет seed, на случай если ноду надо будет восстанавливать  
    * address: gonka1l3dekw8zxjqjw2g5nlgj5f0adkel2ja8rk3gqk  
      * вот он понадобится потом на локальной машине чтоб выдать доступ этому ключу работать от имени холодного ключа.  
* Изнутри этого же контейнера, зарегистрировать в блокчейне нашу ноду  
  * inferenced register-new-participant \\  
  *     $DAPI\_API\_\_PUBLIC\_URL \\  
  *     $ACCOUNT\_PUBKEY \\  
  *     \--node-address $DAPI\_CHAIN\_NODE\_\_SEED\_API\_URL  
* В выводе должно быть кроме прочих данных “Participant registration successful”  
* Пример вывода в случае успеха, сохранить его в текстовик в папку ноды registration.txt он не понадобится скорее всего никогда, но пусть будет для дебага   
  * No consensus key provided, attempting to auto-fetch from chain node...  
  * Successfully auto-fetched and validated consensus key from chain node  
  * Registering new participant:  
  *   Node URL: http://185.216.20.162:8000  
  *   Account Address: gonka1waly2r34992fg8h7ejkd9ukv77ctdh5tqf329f  
  *   Account Public Key: AgpVXxAuKV+dszt5nWaqy4UaotgBoTBtEcn5ItJBsGZi  
  *   Validator Consensus Key: kFbcB6h1xXpZ1Lc1YofYaXZDF8qfblv9IbTYkpdDasg= (auto-fetched)  
  *   Seed Node Address: http://node2.gonka.ai:8000  
  * Sending registration request to http://node2.gonka.ai:8000/v1/participants  
  * Response status code: 200  
  * Participant registration successful.  
  * Waiting for participant to be available (timeout: 30 seconds)...  
  * ..  
  * Found participant with pubkey: AgpVXxAuKV+dszt5nWaqy4UaotgBoTBtEcn5ItJBsGZi (balance: 0\)  
  * Participant is now available at [http://node2.gonka.ai:8000/v1/participants/gonka1waly2r34992fg8h7ejkd9ukv77ctdh5tqf329f](http://node2.gonka.ai:8000/v1/participants/gonka1waly2r34992fg8h7ejkd9ukv77ctdh5tqf329f)  
* exit  
  * Выйти из контейнера в хост машину

# Local выдать права grant.txt

* cd /home/mitch/Crypto/[gonka.ai/](http://gonka.ai/)  
* Дать разрешение серверному ML-ключу работать от имени холодного ключа в сети.  
* В команде ниже надо заменить данные из примера на свои  
  * inventive-bohr  
    * это имя ключа, которое было локально создано в начале и сохранено в local\_key.txt, оно там 2 раза  
  * gonka1l3dekw8zxjqjw2g5nlgj5f0adkel2ja8rk3gqk  
    * ML кошелек, который был создан на серваке, внутри контейнера при запуске команды print... который записывали в warm\_key.txt  
  * [http://node2.gonka.ai:8000](http://node2.gonka.ai:8000)  
    * через кого регаемся, тот же адрес что у нас в config.env в SEED\_API\_URL  
  * сохрани в файл grant.txt и там отредактируй перед запуском, и туда же вывод команды (для дебага)  
* Пример:  
* ./inferenced tx inference grant-ml-ops-permissions \\  
*     inventive-bohr \\  
*     gonka1l3dekw8zxjqjw2g5nlgj5f0adkel2ja8rk3gqk \\  
*     \--from inventive-bohr \\  
*     \--keyring-backend file \\  
*     \--gas 2000000 \\  
*     \--node [http://node2.gonka.ai:8000/chain-rpc/](http://node2.gonka.ai:8000/chain-rpc/)  
*   
* При запуске спросит пароль, который был задан при первом запуске локально inferenced  
* Пример вывода в случае успеха:  
  * Enter keyring passphrase (attempt 1/3):  
  * Detected chain-id: gonka-mainnet  
  * Transaction sent with hash: 1E0F79AB83C92A08AB8969702700A8147F6BB5719D283ADA71DB145760551AB9  
  * Waiting for transaction to be included in a block...  
  * .  
  * Transaction confirmed successfully\!  
  * Block height: 1178738  
* Главное чтоб был “Transaction confirmed successfully\!”

# persistent\_peers

* cd /mnt/ssd/gonka/deploy/join/  
* sudo vi ./.inference/config/config.toml  
  * Найдите строку persistent\_peers \= "" и замените на:  
  * persistent\_peers \= "981908092bc597e60cc81eda4329783aea7af9d7@85.234.66.95:5000,0aaa255c5b119e95cd66e1bd6032b213ce1c7943@85.234.66.223:5000,8e99e6adee695719c1c0ed5a37165e14f4c0751f@85.234.66.191:5000"

# Ограничить рост чейна

* sudo vi /mnt/ssd/gonka/deploy/join/.inference/config/app.toml  
* cd /mnt/ssd/gonka/deploy/join/  
* \# или другой путь, если не я сетапил, в gonka/deploy/join/  
* sudo vi .inference/config/app.toml  
* \# отредактировать конфиг, можно и другим редактором   
* \# **найди и удали** строки с переменными  
  * pruning  
  * pruning-keep-recent  
  * pruning-interval  
* \# **вставь их с такими значениями:**  
  * pruning \= "custom"  
  * pruning-keep-recent \= "1000"  
  * pruning-interval    \= "100"  
* \# если вставляешь эти три строки, то найди ниже немного эти переменные   
* sudo docker stop node  
* sudo docker start node

# Proxy если не качает docker

* sudo mkdir \-p /etc/systemd/system/docker.service.d/  
* sudo vi /etc/systemd/system/docker.service.d/http-proxy.conf  
  * \[Service\]  
  * Environment="HTTP\_PROXY=http://user:kjher8734fddd@173.214.244.109:8888"  
  * Environment="HTTPS\_PROXY=http://user:kjher8734fddd@173.214.244.109:8888"  
  * Environment="NO\_PROXY=localhost,127.0.0.1”  
* sudo systemctl daemon-reload  
* sudo systemctl restart docker

# Server запуск

* sed 's/^export //' config.env \> .env  
* sudo \-E docker compose \-f docker-compose.yml \-f docker-compose.mlnode.yml up \-d  
  * докер должен чето скачать и запустить все 

# Проверки

* [http://node2.gonka.ai:8000/v1/participants/](http://node2.gonka.ai:8000/v1/participants/)\<your-gonka-cold-address\>  
* http://node2.gonka.ai:8000/v1/participants/gonka1ajvs7j8wlgjy8d3kjad520am6jm3a4alj7k4jq  
  * должен отвечать {"pubkey":"AmplcHwWteU7Gxt0q+PjSA9CiehuFNtXOeliBC/KQiU/"}  
  * так он после регистрации уже отвечает, тут должен быть публичный ключб из local\_key.txt  
* [http://node2.gonka.ai:8000/v1/epochs/current/participants](http://node2.gonka.ai:8000/v1/epochs/current/participants)   
  * после начала эпохи ноду должно быть видно поиском по холодному кошельку  
* [http://185.216.20.162:26657/status](http://185.216.20.162:26657/status)  
  * должен показывать json  
* [http://185.216.20.162:8000/](http://185.216.20.162:8000/)   
  * dashboard  
* [http://node2.gonka.ai:8000/dashboard/gonka/account/gonka1waly2r34992fg8h7ejkd9ukv77ctdh5tqf329f](http://node2.gonka.ai:8000/dashboard/gonka/account/gonka1waly2r34992fg8h7ejkd9ukv77ctdh5tqf329f)    
  * транзакция с Grant×24  
* все это удобнее из [таблички](https://docs.google.com/spreadsheets/d/1n-pJ2Hlz1p1fxrvmAhYJggURtKcoLtgBH_rrWGDh-1g/edit?gid=1472632274#gid=1472632274) кликать

# 

# Проверка cuda

* cd /mnt/ssd/gonka/deploy/join && sudo docker exec join-mlnode-308-1 nvidia-smi  
  * Failed to initialize NVML: Unknown Error  
* sudo docker exec join-mlnode-308-1 /app/packages/api/.venv/bin/python3 \-c "import torch; print(f'CUDA Available: {torch.cuda.is\_available()}'); print(f'GPU Count: {torch.cuda.device\_count()}'); print(f'CUDA Version: {torch.version.cuda}')"  
  * Надо получается смотреть не только на True но и на цифру реально живых процев  
* curl [http://localhost:8080/health](http://localhost:8080/health)  
* curl [http://localhost:8080/api/v1/gpu/devices](http://localhost:8080/api/v1/gpu/devices)  
  * тож самое примерно что скрипт выше  
* sudo \-E docker compose \-f docker-compose.mlnode.yml up \-d \--force-recreate  
  * **вот так фиксится, если не работает**  
* Еще можно просто сделать ребут виртуалки. Один раз это починило cuda, а докер команда не помогала  
* nvidia-smi \-r  
  * выполняет reset (перезагрузку) GPU, пока не пригодилась на всяк случай записал тут

\================= сетап закончен, далее разные полезности=====

# Логи

* At the server with MLNode:  
* \# sudo docker logs join-mlnode-308-1 \--since 4h | grep \-i error  
  * искать ошибки  
* sudo docker logs api \--since 15m &\> api\_gonka1agp2tqpnpl4fu8y7wwls800taqeznpds4e0r07.log  
*   
* api server  
* \# sudo docker compose logs api \--since 24h 2\>/dev/null | grep \-i error  
*   
* сетевая нода  
* \# sudo docker logs node \--since 24h  
*   
* Это если не заработало и надо показать супорту  
* ошибки искать  
  * CUDA is not available \- no GPU support detected  
  * Error querying GPU device 0: Unknown Error  
* \#очистить логи  
* sudo sh \-c 'truncate \-s 0 /var/lib/docker/containers/\*/\*-json.log'

# Статусы локальные

* curl \-s [http://localhost:9200/admin/v1/nodes](http://localhost:9200/admin/v1/nodes)  
* curl http://0.0.0.0:26657/status | jq   
  * локальный статус блокчейна  
* curl \-s http://localhost:8080/api/v1/state | jq   
  * статус  
* curl [http://localhost:5050/v1/models](http://localhost:5050/v1/models)  
  *  \- загрузка модели  
* curl \-s http://localhost:9200/admin/v1/setup/report |jq | less  
  * \- общий отчет (тут все PASS кроме участия в эпохи, и Validator is NOT in consensus validator set \- я понимаю это норм)  
  * если чейн не засинкан, то пустой ответ выдает  
* curl \-s http://localhost:8080/health | jq

# Если блокчейн завис на синхронихации

### Запретить конекты к чужим пирам

* cd /home/ubuntu/prometheus  
* sudo ip a | less  
  * поискать сетевуху по IP сервера  
* поменять сетевуху в файле iptables\_disable\_peers.sh  
* sudo sh iptables\_disable\_peers.sh

### Обнулить блокчейн

* cd /mnt/ssd/gonka/deploy/join/  
* \# надо находится в папке gonka/deploy/join/  
* sudo docker compose \-f docker-compose.yml \-f docker-compose.mlnode.yml down  
* sudo rm \-rf .inference/data/  
* sudo rm \-rf .inference/.node\_initialized  
* sudo rm \-rf .inference/cosmovisor  
* sudo mkdir .inference/data/  
* source config.env  
* sudo \-E docker compose \-f docker-compose.yml \-f docker-compose.mlnode.yml up \-d  
* sudo du \-sh .inference/data/  
  * \# посмотреть размер, должен расти

### Разрешить коннектится ко всем

* sudo iptables \-t mangle \-L OUTPUT \-n \--line-numbers  
* \# чтобы найти правило, когда его пора удалить, поменять цифру в команде ниже  
* \# sudo iptables \-t mangle \-D OUTPUT 16


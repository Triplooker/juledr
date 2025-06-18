#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода цветного текста
print_color() {
    echo -e "${1}${2}${NC}"
}

# Функция для вывода заголовков
print_header() {
    echo
    print_color $BLUE "========================================"
    print_color $BLUE "$1"
    print_color $BLUE "========================================"
    echo
}

# Функция для проверки успешности команды
check_status() {
    if [ $? -eq 0 ]; then
        print_color $GREEN "✓ $1 выполнено успешно"
    else
        print_color $RED "✗ Ошибка при выполнении: $1"
        exit 1
    fi
}

# Функция для запроса ввода
ask_input() {
    local prompt=$1
    local var_name=$2
    local is_private=${3:-false}
    
    while true; do
        if [ "$is_private" = true ]; then
            echo -n "$prompt: "
            read -s input
            echo
        else
            read -p "$prompt: " input
        fi
        
        if [[ -n "$input" ]]; then
            eval "$var_name='$input'"
            break
        else
            print_color $RED "Поле не может быть пустым. Попробуйте снова."
        fi
    done
}

# Функция для подтверждения
confirm() {
    local prompt=$1
    while true; do
        read -p "$prompt (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Пожалуйста, ответьте y или n.";;
        esac
    done
}

# Функция для исправления источников пакетов
fix_sources() {
    print_color $YELLOW "Исправление источников пакетов..."
    
    # Создаем резервную копию
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    
    # Заменяем на стандартные Ubuntu репозитории
    cat > /tmp/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted
deb http://archive.ubuntu.com/ubuntu/ jammy universe
deb http://archive.ubuntu.com/ubuntu/ jammy-updates universe
deb http://archive.ubuntu.com/ubuntu/ jammy multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted
deb http://security.ubuntu.com/ubuntu/ jammy-security universe
deb http://security.ubuntu.com/ubuntu/ jammy-security multiverse
EOF
    
    sudo cp /tmp/sources.list /etc/apt/sources.list
    rm /tmp/sources.list
    
    print_color $GREEN "✓ Источники пакетов исправлены"
}

print_header "СКРИПТ ВОССТАНОВЛЕНИЯ НОДЫ DROSERA NETWORK"

print_color $YELLOW "Этот скрипт поможет восстановить вашу ноду Drosera Network"
print_color $YELLOW "с использованием существующих данных трапа и оператора."
echo

# Сбор необходимой информации
print_header "СБОР ИНФОРМАЦИИ"

ask_input "Введите адрес вашего трапа (0x...)" TRAP_ADDRESS
ask_input "Введите ваш приватный ключ кошелька" PRIVATE_KEY true
ask_input "Введите публичный адрес вашего кошелька (адрес оператора)" OPERATOR_ADDRESS
ask_input "Введите ваш Holesky RPC URL" RPC_URL
ask_input "Введите IP адрес вашего VPS" VPS_IP
ask_input "Введите ваш email для Git" GIT_EMAIL
ask_input "Введите ваше имя пользователя для Git" GIT_USERNAME

echo
print_color $BLUE "Хотите ли вы настроить роль Cadet (для Discord)?"
if confirm ""; then
    SETUP_CADET=true
    ask_input "Введите ваш Discord username" DISCORD_USERNAME
else
    SETUP_CADET=false
fi

echo
print_color $YELLOW "Проверьте введенные данные:"
echo "Адрес трапа: $TRAP_ADDRESS"
echo "Адрес оператора: $OPERATOR_ADDRESS"
echo "RPC URL: $RPC_URL"
echo "IP VPS: $VPS_IP"
echo "Git Email: $GIT_EMAIL"
echo "Git Username: $GIT_USERNAME"
if [ "$SETUP_CADET" = true ]; then
    echo "Discord Username: $DISCORD_USERNAME"
fi

if ! confirm "Все данные корректны?"; then
    print_color $RED "Перезапустите скрипт и введите данные заново."
    exit 1
fi

print_header "НАЧИНАЕМ УСТАНОВКУ"

# Остановка старых сервисов если они запущены
print_color $YELLOW "Остановка старых сервисов..."
sudo systemctl stop drosera 2>/dev/null
sudo systemctl disable drosera 2>/dev/null
docker compose down -v 2>/dev/null
docker stop drosera-node 2>/dev/null
docker rm drosera-node 2>/dev/null

# Очистка поврежденных конфигураций Docker
print_color $YELLOW "Очистка старых конфигураций Docker..."
sudo rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null
sudo rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null

# Исправление источников пакетов
fix_sources

# Обновление системы с повторными попытками
print_header "ОБНОВЛЕНИЕ СИСТЕМЫ"

print_color $YELLOW "Очистка кэша пакетов..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Попытка обновления с обработкой ошибок
for attempt in 1 2 3; do
    print_color $YELLOW "Попытка обновления системы ($attempt/3)..."
    if sudo apt-get update; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось обновить список пакетов после 3 попыток"
            print_color $YELLOW "Попытка использовать альтернативные зеркала..."
            
            # Используем альтернативные зеркала
            cat > /tmp/sources_alt.list << EOF
deb http://us.archive.ubuntu.com/ubuntu/ jammy main restricted
deb http://us.archive.ubuntu.com/ubuntu/ jammy-updates main restricted
deb http://us.archive.ubuntu.com/ubuntu/ jammy universe
deb http://us.archive.ubuntu.com/ubuntu/ jammy-updates universe
deb http://us.archive.ubuntu.com/ubuntu/ jammy multiverse
deb http://us.archive.ubuntu.com/ubuntu/ jammy-updates multiverse
deb http://us.archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted
deb http://security.ubuntu.com/ubuntu/ jammy-security universe
deb http://security.ubuntu.com/ubuntu/ jammy-security multiverse
EOF
            sudo cp /tmp/sources_alt.list /etc/apt/sources.list
            rm /tmp/sources_alt.list
            
            sudo apt-get clean
            sudo rm -rf /var/lib/apt/lists/*
            sudo apt-get update
            check_status "Обновление списка пакетов"
            break
        fi
        sleep 5
    fi
done

# Обновление пакетов
print_color $YELLOW "Обновление установленных пакетов..."
sudo apt-get upgrade -y
check_status "Обновление системы"

print_color $YELLOW "Установка базовых пакетов..."
sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip
check_status "Установка базовых пакетов"

# Установка Docker
print_header "УСТАНОВКА DOCKER"

# Полная очистка Docker
print_color $YELLOW "Удаление старых версий Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do 
    sudo apt-get remove $pkg -y 2>/dev/null
    sudo apt-get purge $pkg -y 2>/dev/null
done

# Очистка apt кэша
sudo apt-get autoremove -y 2>/dev/null
sudo apt-get autoclean 2>/dev/null

# Повторная очистка конфигураций Docker
sudo rm -rf /etc/apt/sources.list.d/docker.list* 2>/dev/null
sudo rm -rf /etc/apt/keyrings/docker.gpg* 2>/dev/null
sudo rm -rf /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null

sudo apt-get install -y ca-certificates curl gnupg lsb-release
check_status "Установка базовых пакетов для Docker"

sudo install -m 0755 -d /etc/apt/keyrings

# Скачивание GPG ключа Docker с повторными попытками
print_color $YELLOW "Добавление GPG ключа Docker..."
for attempt in 1 2 3; do
    if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось скачать GPG ключ Docker"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка скачивания GPG ключа..."
        sleep 5
    fi
done
check_status "Добавление GPG ключа Docker"

# Добавление репозитория Docker
print_color $YELLOW "Добавление репозитория Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
check_status "Добавление репозитория Docker"

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
check_status "Установка Docker"

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER

# Тест Docker
sudo docker run hello-world >/dev/null 2>&1
check_status "Тестирование Docker"

# Установка CLI инструментов
print_header "УСТАНОВКА CLI ИНСТРУМЕНТОВ"

# Drosera CLI - исправленная версия
print_color $YELLOW "Установка Drosera CLI..."

# Сначала попробуем стандартный установщик
for attempt in 1 2 3; do
    if curl -L https://app.drosera.io/install | bash; then
        print_color $GREEN "✓ Установка через стандартный инсталлер успешна"
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $YELLOW "Стандартный инсталлер не сработал, пробуем альтернативные методы..."
        else
            print_color $YELLOW "Повторная попытка установки через стандартный инсталлер..."
            sleep 5
        fi
    fi
done

# Обновляем PATH и переменные окружения
source /root/.bashrc 2>/dev/null || true

# Проверяем где установился droseraup
if [ -f "/root/.droseraup/bin/droseraup" ]; then
    print_color $YELLOW "Найден droseraup, запускаем установку..."
    /root/.droseraup/bin/droseraup
elif command -v droseraup >/dev/null 2>&1; then
    print_color $YELLOW "droseraup найден в PATH, запускаем установку..."
    droseraup
else
    print_color $YELLOW "droseraup не найден, устанавливаем напрямую..."
    
    # Создаем директорию
    mkdir -p /root/.drosera/bin
    
    # Попробуем разные источники для загрузки
    DOWNLOAD_SUCCESS=false
    
    # Список возможных URL для скачивания
    DOWNLOAD_URLS=(
        "https://github.com/drosera-network/drosera-cli/releases/latest/download/drosera-x86_64-unknown-linux-gnu"
        "https://github.com/drosera-network/drosera/releases/latest/download/drosera-x86_64-unknown-linux-gnu"
        "https://github.com/drosera-network/drosera-cli/releases/download/v0.1.0/drosera-x86_64-unknown-linux-gnu"
    )
    
    for url in "${DOWNLOAD_URLS[@]}"; do
        print_color $YELLOW "Попытка скачивания с: $url"
        if wget -q -O /root/.drosera/bin/drosera "$url" 2>/dev/null; then
            if [ -s "/root/.drosera/bin/drosera" ]; then
                chmod +x /root/.drosera/bin/drosera
                DOWNLOAD_SUCCESS=true
                print_color $GREEN "✓ Успешно скачано с $url"
                break
            else
                print_color $YELLOW "Файл пустой, пробуем следующий URL..."
                rm -f /root/.drosera/bin/drosera
            fi
        else
            print_color $YELLOW "Не удалось скачать с $url"
        fi
    done
    
    # Если не удалось скачать, пробуем curl
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        for url in "${DOWNLOAD_URLS[@]}"; do
            print_color $YELLOW "Попытка скачивания через curl с: $url"
            if curl -L -o /root/.drosera/bin/drosera "$url" 2>/dev/null; then
                if [ -s "/root/.drosera/bin/drosera" ]; then
                    chmod +x /root/.drosera/bin/drosera
                    DOWNLOAD_SUCCESS=true
                    print_color $GREEN "✓ Успешно скачано через curl с $url"
                    break
                else
                    print_color $YELLOW "Файл пустой, пробуем следующий URL..."
                    rm -f /root/.drosera/bin/drosera
                fi
            else
                print_color $YELLOW "Не удалось скачать через curl с $url"
            fi
        done
    fi
    
    # Если все еще не удалось, пробуем установить через cargo (если доступен)
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        print_color $YELLOW "Пробуем установить через альтернативные методы..."
        
        # Проверяем наличие cargo
        if command -v cargo >/dev/null 2>&1; then
            print_color $YELLOW "Найден cargo, устанавливаем через него..."
            cargo install --git https://github.com/drosera-network/drosera-cli drosera --bin drosera --root /root/.drosera 2>/dev/null
            if [ -f "/root/.drosera/bin/drosera" ]; then
                DOWNLOAD_SUCCESS=true
                print_color $GREEN "✓ Успешно установлено через cargo"
            fi
        fi
    fi
    
    # Последняя попытка - попробуем собрать из исходников
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        print_color $YELLOW "Последняя попытка - установка Rust и сборка из исходников..."
        
        # Устанавливаем Rust если его нет
        if ! command -v rustc >/dev/null 2>&1; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source /root/.cargo/env
        fi
        
        # Пробуем клонировать и собрать
        cd /tmp
        if git clone https://github.com/drosera-network/drosera-cli.git 2>/dev/null; then
            cd drosera-cli
            if cargo build --release 2>/dev/null; then
                cp target/release/drosera /root/.drosera/bin/
                chmod +x /root/.drosera/bin/drosera
                DOWNLOAD_SUCCESS=true
                print_color $GREEN "✓ Успешно собрано из исходников"
            fi
            cd ..
            rm -rf drosera-cli
        fi
        cd ~
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        print_color $RED "✗ Критическая ошибка: не удалось установить Drosera CLI никаким способом"
        print_color $YELLOW "Возможные причины:"
        print_color $YELLOW "1. Проблемы с интернет-соединением"
        print_color $YELLOW "2. Изменились URL для скачивания"
        print_color $YELLOW "3. Временные проблемы с GitHub"
        print_color $YELLOW ""
        print_color $YELLOW "Рекомендации:"
        print_color $YELLOW "1. Проверьте интернет-соединение: ping google.com"
        print_color $YELLOW "2. Попробуйте запустить скрипт позже"
        print_color $YELLOW "3. Установите вручную с GitHub: https://github.com/drosera-network/drosera-cli/releases"
        exit 1
    fi
fi

# Обновляем PATH
export PATH="/root/.drosera/bin:$PATH"
echo 'export PATH="/root/.drosera/bin:$PATH"' >> /root/.bashrc
source /root/.bashrc 2>/dev/null || true

# Проверяем установку
if [ -f "/root/.drosera/bin/drosera" ]; then
    print_color $GREEN "✓ Drosera CLI успешно установлен"
    # Проверяем что файл исполняемый и не поврежден
    if /root/.drosera/bin/drosera --version >/dev/null 2>&1; then
        print_color $GREEN "✓ Drosera CLI работает корректно"
    else
        print_color $YELLOW "⚠ Drosera CLI установлен, но могут быть проблемы с запуском"
    fi
elif command -v drosera >/dev/null 2>&1; then
    print_color $GREEN "✓ Drosera CLI найден в системе"
    if drosera --version >/dev/null 2>&1; then
        print_color $GREEN "✓ Drosera CLI работает корректно"
    else
        print_color $YELLOW "⚠ Drosera CLI найден, но могут быть проблемы с запуском"
    fi
else
    print_color $RED "✗ Критическая ошибка: Drosera CLI не найден после установки"
    exit 1
fi

check_status "Установка Drosera CLI"

# Foundry CLI
print_color $YELLOW "Установка Foundry CLI..."
for attempt in 1 2 3; do
    if curl -L https://foundry.paradigm.xyz | bash; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось установить Foundry CLI"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка установки Foundry CLI..."
        sleep 5
    fi
done

source /root/.bashrc 2>/dev/null || true
/root/.foundry/bin/foundryup
check_status "Установка Foundry CLI"

# Bun
print_color $YELLOW "Установка Bun..."
for attempt in 1 2 3; do
    if curl -fsSL https://bun.sh/install | bash; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось установить Bun"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка установки Bun..."
        sleep 5
    fi
done

source /root/.bashrc 2>/dev/null || true
check_status "Установка Bun"

# Настройка трапа
print_header "НАСТРОЙКА ТРАПА"

cd ~
rm -rf my-drosera-trap 2>/dev/null
mkdir my-drosera-trap
cd my-drosera-trap

git config --global user.email "$GIT_EMAIL"
git config --global user.name "$GIT_USERNAME"
check_status "Настройка Git"

# Инициализация трапа
print_color $YELLOW "Инициализация трапа из шаблона..."
for attempt in 1 2 3; do
    if /root/.foundry/bin/forge init --template https://github.com/drosera-network/trap-foundry-template.git >/dev/null 2>&1; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось инициализировать трап"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка инициализации трапа..."
        sleep 5
    fi
done
check_status "Инициализация трапа из шаблона"

# Установка зависимостей
source /root/.bashrc 2>/dev/null || true
print_color $YELLOW "Установка зависимостей трапа..."
/root/.bun/bin/bun install >/dev/null 2>&1
/root/.foundry/bin/forge build >/dev/null 2>&1
check_status "Компиляция трапа" # This initial build compiles template contracts

# Конфигурация и применение трапа в зависимости от SETUP_CADET
if [ "$SETUP_CADET" = true ]; then
    print_header "НАСТРОЙКА CADET РОЛИ (ТРАП)" # Modified header to be more specific
    cd ~/my-drosera-trap # Ensure correct directory

    # Создание Trap.sol для Cadet роли
    cat > src/Trap.sol << EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface IMockResponse {
   function isActive() external view returns (bool);
}

contract Trap is ITrap {
   address public constant RESPONSE_CONTRACT = 0x4608Afa7f277C8E0BE232232265850d1cDeB600E;
   string constant discordName = "$DISCORD_USERNAME";

   function collect() external view returns (bytes memory) {
       bool active = IMockResponse(RESPONSE_CONTRACT).isActive();
       return abi.encode(active, discordName);
   }

   function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
       (bool active, string memory name) = abi.decode(data[0], (bool, string));

       if (!active || bytes(name).length == 0) {
           return (false, bytes(""));
       }
       return (true, abi.encode(name));
   }
}
EOF
    check_status "Создание src/Trap.sol для Cadet роли"

    print_color $YELLOW "Конфигурирование drosera.toml для Cadet роли..."
    # Modify drosera.toml (from template) for Cadet
    sed -i 's|^path = .*|path = "out/Trap.sol/Trap.json"|' drosera.toml
    sed -i 's|^response_contract = .*|response_contract = "0x4608Afa7f277C8E0BE232232265850d1cDeB600E"|' drosera.toml
    sed -i 's|^response_function = .*|response_function = "respondWithDiscordName(string)"|' drosera.toml
    sed -i 's|^whitelist = .*|whitelist = ["'$OPERATOR_ADDRESS'"]|' drosera.toml

    # Ensure global trap address is configured for `drosera apply`
    if ! grep -q "^address = \"$TRAP_ADDRESS\"" drosera.toml; then
        echo "" >> drosera.toml # ensure newline
        echo "address = \"$TRAP_ADDRESS\"" >> drosera.toml
    fi
    check_status "Конфигурация drosera.toml для Cadet роли"

    # Компиляция нового Trap.sol и применение
    source /root/.bashrc 2>/dev/null || true
    print_color $YELLOW "Компиляция Cadet Trap.sol..."
    /root/.foundry/bin/forge build >/dev/null 2>&1
    check_status "Компиляция Cadet Trap.sol"

    apply_success=false
    print_color $YELLOW "Применение конфигурации Cadet роли..."
    for attempt in 1 2 3; do
        if echo "ofc" | DROSERA_PRIVATE_KEY=$PRIVATE_KEY /root/.drosera/bin/drosera apply --eth-rpc-url $RPC_URL; then
            apply_success=true
            break
        else
            if [ $attempt -eq 3 ]; then
                print_color $RED "✗ Не удалось применить конфигурацию Cadet роли после 3 попыток."
                # apply_success remains false
                break
            fi
            print_color $YELLOW "Повторная попытка применения конфигурации Cadet роли ($attempt/3)..."
            sleep 10
        fi
    done

    if [ "$apply_success" = true ]; then
        true # Sets $? to 0 for check_status
        check_status "Применение конфигурации Cadet роли"
    else
        false # Sets $? to 1 for check_status
        check_status "Применение конфигурации Cadet роли (НЕ УДАЛОСЬ)"
        # The script will exit here if check_status is called with $? != 0 due to its internal `exit 1`.
    fi
else
    print_header "НАСТРОЙКА DEFAULT (HELLOWORLD) ТРАПА"
    cd ~/my-drosera-trap # Ensure correct directory

    # src/HelloWorldTrap.sol is used by default from template.
    print_color $YELLOW "Конфигурирование drosera.toml для Default трапа..."
    # Path, response_contract, response_function are already set for HelloWorld in template's drosera.toml.
    # We only need to set the whitelist and ensure TRAP_ADDRESS is configured.
    sed -i 's|^whitelist = .*|whitelist = ["'$OPERATOR_ADDRESS'"]|' drosera.toml

    if ! grep -q "^address = \"$TRAP_ADDRESS\"" drosera.toml; then
        echo "" >> drosera.toml
        echo "address = \"$TRAP_ADDRESS\"" >> drosera.toml
    fi
    check_status "Конфигурация drosera.toml для Default трапа"

    # Compile (HelloWorldTrap should be built by the previous build, but an explicit build here is safer)
    source /root/.bashrc 2>/dev/null || true
    print_color $YELLOW "Компиляция Default (HelloWorld) Trap.sol..."
    /root/.foundry/bin/forge build >/dev/null 2>&1
    check_status "Компиляция Default Trap.sol"

    apply_success=false
    print_color $YELLOW "Применение конфигурации Default трапа..."
    for attempt in 1 2 3; do
        if echo "ofc" | DROSERA_PRIVATE_KEY=$PRIVATE_KEY /root/.drosera/bin/drosera apply --eth-rpc-url $RPC_URL; then
            apply_success=true
            break
        else
            if [ $attempt -eq 3 ]; then
                print_color $RED "✗ Не удалось применить конфигурацию Default трапа после 3 попыток."
                # apply_success remains false
                break
            fi
            print_color $YELLOW "Повторная попытка применения конфигурации Default трапа ($attempt/3)..."
            sleep 10
        fi
    done

    if [ "$apply_success" = true ]; then
        true # Sets $? to 0 for check_status
        check_status "Применение конфигурации Default трапа"
    else
        false # Sets $? to 1 for check_status
        check_status "Применение конфигурации Default трапа (НЕ УДАЛОСЬ)"
        # The script will exit here if check_status is called with $? != 0 due to its internal `exit 1`.
    fi
fi

# Установка оператора
print_header "УСТАНОВКА ОПЕРАТОРА"

cd ~
print_color $YELLOW "Скачивание оператора..."
for attempt in 1 2 3; do
    if wget -q https://github.com/drosera-network/releases/releases/download/v1.17.2/drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось скачать оператор"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка скачивания оператора..."
        sleep 5
    fi
done

tar -xzf drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz >/dev/null 2>&1
sudo cp drosera-operator /usr/bin/
rm drosera-operator-v1.17.2-x86_64-unknown-linux-gnu.tar.gz
check_status "Установка оператора"

# Загрузка Docker образа
print_color $YELLOW "Загрузка Docker образа оператора..."
for attempt in 1 2 3; do
    if docker pull ghcr.io/drosera-network/drosera-operator:latest >/dev/null 2>&1; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось загрузить Docker образ"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка загрузки Docker образа..."
        sleep 10
    fi
done
check_status "Загрузка Docker образа оператора"

# Настройка файрвола
print_header "НАСТРОЙКА ФАЙРВОЛА"

sudo ufw --force enable >/dev/null 2>&1
sudo ufw allow ssh >/dev/null 2>&1
sudo ufw allow 22 >/dev/null 2>&1
sudo ufw allow 31313/tcp >/dev/null 2>&1
sudo ufw allow 31314/tcp >/dev/null 2>&1
check_status "Настройка файрвола"

# Настройка Docker окружения
print_header "НАСТРОЙКА DOCKER ОКРУЖЕНИЯ"

cd ~
rm -rf Drosera-Network 2>/dev/null
print_color $YELLOW "Клонирование репозитория конфигурации..."
for attempt in 1 2 3; do
    if git clone https://github.com/0xmoei/Drosera-Network >/dev/null 2>&1; then
        break
    else
        if [ $attempt -eq 3 ]; then
            print_color $RED "Не удалось клонировать репозиторий"
            exit 1
        fi
        print_color $YELLOW "Повторная попытка клонирования..."
        sleep 5
    fi
done
cd Drosera-Network
check_status "Клонирование репозитория конфигурации"

# Создание .env файла
cat > .env << EOF
ETH_PRIVATE_KEY=$PRIVATE_KEY
VPS_IP=$VPS_IP
EOF

# Создание docker-compose.yaml
cat > docker-compose.yaml << EOF
version: '3'
services:
  drosera-node:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url $RPC_URL --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key \${ETH_PRIVATE_KEY} --listen-address 0.0.0.0 --network-external-p2p-address \${VPS_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
EOF

check_status "Создание конфигурационных файлов Docker"

# Запуск ноды
print_header "ЗАПУСК НОДЫ"

cd ~/Drosera-Network
docker compose up -d >/dev/null 2>&1
check_status "Запуск ноды через Docker"

# Проверка статуса
sleep 10
if docker ps | grep -q drosera-node; then
    print_color $GREEN "✓ Нода успешно запущена!"
else
    print_color $RED "✗ Ошибка запуска ноды"
    print_color $YELLOW "Проверка логов..."
    docker logs drosera-node 2>/dev/null || print_color $RED "Не удалось получить логи"
    exit 1
fi

print_header "УСТАНОВКА ЗАВЕРШЕНА!"

print_color $GREEN "🎉 Нода Drosera Network успешно восстановлена!"
echo
print_color $YELLOW "Что дальше:"
print_color $BLUE "1. Перейдите на https://app.drosera.io/"
print_color $BLUE "2. Подключите ваш кошелек"
print_color $BLUE "3. Найдите ваш трап в разделе 'Traps Owned'"
print_color $BLUE "4. Нажмите 'Opt-in' для подключения оператора к трапу"
echo
print_color $YELLOW "Полезные команды:"
print_color $BLUE "Просмотр логов: cd ~/Drosera-Network && docker logs -f drosera-node"
print_color $BLUE "Перезапуск ноды: cd ~/Drosera-Network && docker compose restart"
print_color $BLUE "Остановка ноды: cd ~/Drosera-Network && docker compose down -v"
echo

if [ "$SETUP_CADET" = true ]; then
    print_color $YELLOW "Для проверки статуса Cadet роли через несколько минут выполните:"
    print_color $BLUE "cast call 0x4608Afa7f277C8E0BE232232265850d1cDeB600E \"isResponder(address)(bool)\" $OPERATOR_ADDRESS --rpc-url $RPC_URL"
fi

print_color $GREEN "Готово! Ваша нода восстановлена и работает."

# Анализ безопасности и рекомендации по улучшению install.sh

## 🔴 КРИТИЧЕСКИЕ ПРОБЛЕМЫ БЕЗОПАСНОСТИ

### 1. Неограниченный sudo доступ без пароля (Строка 126)
```bash
echo "$FRAPPE_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$FRAPPE_USER"
```

**Проблема:** Пользователь получает полный root доступ без пароля - это серьезная уязвимость!

**Решение:** Ограничить sudo только необходимыми командами:
```bash
echo "$FRAPPE_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/nginx, /usr/bin/supervisorctl" > "/etc/sudoers.d/$FRAPPE_USER"
```

### 2. Хранение паролей в /tmp (Строки 191, 207, 312, 374)
```bash
echo "$root_password" > /tmp/mysql_root_password
chmod 600 /tmp/mysql_root_password
```

**Проблема:** Директория /tmp может очищаться системой и доступна всем процессам.

**Решение:** Использовать переменные окружения или защищенный файл:
```bash
MYSQL_ROOT_PASSWORD="$root_password"
# или
SECURE_DIR="/root/.erpnext-install"
mkdir -p "$SECURE_DIR" && chmod 700 "$SECURE_DIR"
echo "$root_password" > "$SECURE_DIR/mysql_root_password"
```

### 3. Передача пароля через командную строку (Строка 361)
```bash
bench new-site $domain --mariadb-root-password '$mysql_root_password' --admin-password admin
```

**Проблема:** Пароли видны в процессах (ps aux) и истории команд.

**Решение:** Использовать файл конфигурации или stdin:
```bash
echo "$mysql_root_password" | bench new-site $domain --mariadb-root-password --admin-password admin
```

### 4. Жестко закодированный пароль администратора (Строка 361)
```bash
--admin-password admin
```

**Проблема:** Все установки используют один и тот же слабый пароль!

**Решение:** Генерировать случайный пароль:
```bash
ADMIN_PASSWORD=$(pwgen -s 16 1)
--admin-password "$ADMIN_PASSWORD"
# Сохранить в безопасное место
```

## ⚠️ ВАЖНЫЕ ПРОБЛЕМЫ

### 5. Недостаточная валидация ввода
Функции `ask_input` и `ask_yes_no` не валидируют ввод пользователя.

**Решение:** Добавить валидацию:
```bash
ask_input_validated() {
    local question="$1"
    local default="$2"
    local pattern="$3"
    local input
    while true; do
        read -p "$question [default: $default]: " input
        input="${input:-$default}"
        if [[ $input =~ $pattern ]]; then
            echo "$input"
            return
        else
            echo "Invalid input. Please try again."
        fi
    done
}

# Использование для домена:
domain=$(ask_input_validated "Enter domain for ERPNext site" "$DEFAULT_DOMAIN" '^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$|^[a-zA-Z0-9][a-zA-Z0-9-]*\.local$')
```

### 6. Использование `|| true` скрывает ошибки
Множество команд используют `|| true`, что может скрывать реальные проблемы.

**Решение:** Использовать явную обработку:
```bash
if ! systemctl start redis-server; then
    warning "Failed to start Redis, but continuing..."
    # Или error_exit если критично
fi
```

### 7. SQL инъекции в MariaDB командах (Строки 174-179)
Хотя пароль контролируется скриптом, лучше использовать более безопасные методы.

**Решение:** Использовать файл конфигурации:
```bash
cat > /root/.my.cnf << EOF
[client]
user=root
password=$root_password
EOF
chmod 600 /root/.my.cnf
mysql -e "DELETE FROM mysql.user WHERE User='';"
```

### 8. Отсутствие проверки минимальных системных требований
Скрипт не проверяет RAM, disk space, CPU.

**Решение:** Добавить проверку:
```bash
check_system_requirements() {
    log "${BLUE}=== Checking System Requirements ===${NC}"
    
    # Проверка RAM (минимум 2GB)
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 2 ]; then
        warning "System has ${total_ram}GB RAM. Recommended: 4GB+"
        if ! ask_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
    
    # Проверка свободного места (минимум 10GB)
    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$free_space" -lt 10 ]; then
        error_exit "Insufficient disk space. Need 10GB+, have ${free_space}GB"
    fi
    
    # Проверка версии Debian
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "debian" ]] || [[ "${VERSION_ID}" != "13" ]]; then
            warning "This script is designed for Debian 13. Detected: $PRETTY_NAME"
        fi
    fi
    
    success "System requirements check passed"
}
```

## 💡 РЕКОМЕНДАЦИИ ПО УЛУЧШЕНИЮ КОДА

### 9. Улучшить обработку ошибок с rollback
Добавить механизм отката изменений при ошибке.

**Решение:**
```bash
# Массив выполненных шагов для rollback
COMPLETED_STEPS=()

track_step() {
    COMPLETED_STEPS+=("$1")
}

rollback() {
    log "${RED}Rolling back changes...${NC}"
    for step in "${COMPLETED_STEPS[@]}"; do
        case $step in
            "mariadb")
                systemctl stop mariadb
                apt-get remove -y mariadb-server mariadb-client
                ;;
            "frappe_user")
                userdel -r "$FRAPPE_USER" 2>/dev/null || true
                ;;
            # ... другие шаги
        esac
    done
}

# В функциях:
setup_mariadb() {
    # ... установка ...
    track_step "mariadb"
    success "MariaDB configured"
}

# При ошибке:
error_exit() {
    log "${RED}ERROR: $1${NC}"
    if ask_yes_no "Attempt rollback?" "y"; then
        rollback
    fi
    exit 1
}
```

### 10. Вынести конфигурацию в отдельный файл
Создать config.sh для настроек.

**Решение:**
```bash
# config.sh
CONFIG_FRAPPE_VERSION="version-15"
CONFIG_ERPNEXT_VERSION="version-15"
CONFIG_NODE_VERSION="22"
CONFIG_MIN_RAM_GB=2
CONFIG_MIN_DISK_GB=10
CONFIG_DEFAULT_DOMAIN="erp.local"
CONFIG_DEFAULT_USER="frappe"

# В install.sh:
if [ -f "./config.sh" ]; then
    source ./config.sh
fi
```

### 11. Добавить режим "тихой" установки
Для автоматизации CI/CD.

**Решение:**
```bash
# Добавить в начало скрипта:
SILENT_MODE=false
if [ "$1" == "--silent" ] || [ "$1" == "-s" ]; then
    SILENT_MODE=true
    # Загрузить параметры из файла или переменных окружения
fi

ask_yes_no() {
    if [ "$SILENT_MODE" = true ]; then
        return 0  # или прочитать из конфига
    fi
    # ... обычная логика ...
}
```

### 12. Улучшить heredoc для безопасности
Использовать quoted heredoc для предотвращения интерполяции.

**Решение:**
```bash
# Вместо:
su - "$frappe_user" << EOFUSER
    export PATH=\$PATH:\$HOME/.local/bin
EOFUSER

# Использовать:
su - "$frappe_user" << 'EOFUSER'
    export PATH=$PATH:$HOME/.local/bin
EOFUSER
# или передавать переменные явно
```

### 13. Добавить тесты работоспособности
После каждого шага проверять, что сервисы работают.

**Решение:**
```bash
test_mariadb() {
    local root_password="$1"
    if mysql -u root -p"$root_password" -e "SELECT 1;" &>/dev/null; then
        success "MariaDB is working"
        return 0
    else
        error_exit "MariaDB test failed"
    fi
}

test_redis() {
    if redis-cli ping | grep -q "PONG"; then
        success "Redis is working"
        return 0
    else
        error_exit "Redis test failed"
    fi
}
```

### 14. Улучшить логирование
Добавить timestamps и уровни логирования.

**Решение:**
```bash
log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "${RED}$1${NC}" "ERROR"
    log "${YELLOW}Installation failed. Check log at $LOG_FILE${NC}" "ERROR"
    exit 1
}

success() {
    log "${GREEN}✓ $1${NC}" "SUCCESS"
}
```

### 15. Добавить прогресс-бар для длительных операций
Показывать прогресс установки.

**Решение:**
```bash
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %d%%" "$percent"
}

# Использование:
total_steps=10
current_step=0

# В каждой функции:
current_step=$((current_step + 1))
show_progress $current_step $total_steps
```

## 📋 CHECKLIST ПЕРЕД ПРОДАКШЕНОМ

- [ ] Исправить sudo права (ограничить команды)
- [ ] Убрать хранение паролей в /tmp
- [ ] Генерировать случайные пароли для admin
- [ ] Добавить валидацию ввода
- [ ] Добавить проверку системных требований
- [ ] Реализовать механизм rollback
- [ ] Добавить тесты работоспособности
- [ ] Улучшить логирование с timestamps
- [ ] Вынести конфигурацию в отдельный файл
- [ ] Добавить документацию по использованию
- [ ] Протестировать на чистой системе Debian 13
- [ ] Добавить backup существующих конфигов перед изменением

## 🎯 ПРИОРИТЕТЫ ИСПРАВЛЕНИЙ

1. **Немедленно:** #1, #2, #3, #4 (критические проблемы безопасности)
2. **Важно:** #5, #6, #7, #8 (качество и надежность)
3. **Желательно:** #9-#15 (улучшения UX и поддерживаемости)

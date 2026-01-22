# ERPNext Installation Scripts for Debian 13

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Debian 13](https://img.shields.io/badge/Debian-13-red)](https://www.debian.org/)
[![ERPNext 15](https://img.shields.io/badge/ERPNext-15-blue)](https://erpnext.com/)

Complete installation scripts for ERPNext on Debian 13 with enhanced security, multiple installation modes, and comprehensive error handling.

## 🚀 Quick Start

### Simple Installation (Recommended)
```bash
# Download and make the quick installation script executable
wget https://raw.githubusercontent.com/your-repo/erpnext-debian13-install/main/quick-install.sh
chmod +x quick-install.sh
sudo ./quick-install.sh
```

### Advanced Installation (Interactive)
```bash
# Download and make the full installation script executable
wget https://raw.githubusercontent.com/your-repo/erpnext-debian13-install/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## 📋 System Requirements

- **OS**: Debian 13 (Bookworm)
- **RAM**: Minimum 4GB (8GB recommended)
- **Disk Space**: Minimum 20GB free space
- **Architecture**: amd64
- **Network**: Internet connection required

## 🔧 Installation Modes

### 1. Quick Installation (`quick-install.sh`)
Automated installation with default settings. Perfect for development or testing environments.

```bash
sudo ./quick-install.sh
```

**Features:**
- Uses default domain `site1.local`
- Generates random secure passwords
- Installs all required components automatically
- Includes production setup with Nginx and Supervisor
- Configures UFW firewall

### 2. Interactive Installation (`install.sh`)
Full-featured installation with user interaction and customization options.

```bash
sudo ./install.sh
```

**Features:**
- Choose Node.js version (22 or 24)
- Custom domain name with validation
- Select additional Frappe apps
- Step-by-step or full installation modes
- Advanced configuration options

### 3. Automated Installation
For CI/CD pipelines or headless servers:

```bash
# Set environment variables
export ERPNEXT_DOMAIN="your-domain.com"
export ERPNEXT_ADMIN_PASSWORD="your-secure-password"
export MARIADB_ROOT_PASSWORD="your-db-password"
export FRAPPE_USER="frappe"

# Run automated installation
sudo ./install.sh --silent
```

## 📁 File Structure

```
.
├── install.sh              # Main interactive installer
├── quick-install.sh        # Simple automated installer
├── config.sh               # Configuration file (optional)
└── README.md              # This documentation
```

## 🔐 Security Features

### Password Management
- **Random Password Generation**: Admin and database passwords are generated securely
- **Secure Storage**: Passwords stored in protected files with restrictive permissions
- **No Plain Text**: Passwords never exposed in logs or command history

### Access Control
- **Limited Sudo**: User has access only to necessary system commands
- **Firewall**: UFW configured with minimal required ports
- **Service Isolation**: Services run under dedicated user account

### Data Protection
- **Encrypted Connections**: MariaDB configured for secure connections
- **Secure Defaults**: No anonymous users or test databases
- **Backup Ready**: Scripts prepare for automated backups

## 🛠️ Usage Examples

### Basic Usage
```bash
# Quick installation with defaults
sudo ./quick-install.sh

# Interactive installation
sudo ./install.sh

# Quick mode with custom settings
sudo ./install.sh --quick

# Automated installation
sudo ./install.sh --silent
```

### Custom Configuration
Create `config.sh` to customize installation:

```bash
# config.sh
CONFIG_DEFAULT_DOMAIN="erp.company.com"
CONFIG_DEFAULT_USER="erpnext"
CONFIG_NODE_VERSION="22"
CONFIG_MIN_RAM_GB=8
CONFIG_MIN_DISK_GB=50
CONFIG_PRODUCTION_MODE=true
CONFIG_FIREWALL_ENABLED=true
```

### Testing Installation
```bash
# Test system requirements only
sudo ./quick-install.sh --test

# View help
sudo ./install.sh --help
```

## 🔍 Post-Installation

### Access ERPNext
After successful installation, access your ERPNext instance:

```
URL: http://your-domain.com
Username: administrator
Password: [Check installation log or /root/admin_credentials.txt]
```

### Important First Steps
1. **Change Admin Password**: Login and change the default administrator password
2. **Setup SSL**: Configure HTTPS certificates
3. **Configure Backups**: Setup automated backup schedules
4. **Review Security**: Check firewall rules and user permissions

### Useful Commands
```bash
# Start ERPNext bench
su - frappe -c 'cd frappe-bench && bench start'

# Stop ERPNext bench
su - frappe -c 'cd frappe-bench && bench stop'

# View bench status
su - frappe -c 'cd frappe-bench && bench status'

# View logs
tail -f /tmp/erpnext-install.log
```

## 🐛 Troubleshooting

### Common Issues

#### Installation Fails
```bash
# Check system requirements
sudo ./quick-install.sh --test

# View detailed logs
tail -f /tmp/erpnext-install.log
tail -f /tmp/erpnext-quick-install.log
```

#### Debian 13 Repository Issues
The scripts automatically fix Debian 13 repository configuration by:
- Installing `ca-certificates` and `debian-archive-keyring`
- Enabling `contrib` and `non-free` components
- Updating package lists with `--allow-releaseinfo-change`

Note: The `software-properties-common` package is Ubuntu-specific and not available in Debian. The scripts handle repository management directly without this package.

If you encounter repository issues manually:
```bash
# Install certificates first
sudo apt install -y ca-certificates debian-archive-keyring

# Enable contrib and non-free repositories
sudo sed -i 's/Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources

# Update package lists
sudo apt update --allow-releaseinfo-change
```

#### Yarn Registry Issues
The scripts automatically configure Yarn to use the npm registry instead of the default Yarn registry to avoid network connectivity issues:

```bash
yarn config set registry https://registry.npmjs.org/
yarn cache clean
```

If you encounter yarn install errors manually:
```bash
# Clear yarn cache and set npm registry
yarn cache clean
yarn config set registry https://registry.npmjs.org/

# Retry installation
yarn install
```

#### wkhtmltopdf Not Available
The `wkhtmltopdf` package may not be available in Debian 13 repositories. The scripts will attempt to install it, but if it's not found, the installation will continue with a warning. PDF generation features in ERPNext may not work without this package.

To install wkhtmltopdf manually if needed:
```bash
# Try from backports
sudo apt install -y -t trixie-backports wkhtmltopdf

# Or download from wkhtmltopdf.org and install manually
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-3.bookworm_amd64.deb
```

#### Database Connection Issues
```bash
# Test MariaDB connection
mysql -u root -p -e "SELECT 1;"

# Check MariaDB status
systemctl status mariadb
```

#### Permission Issues
```bash
# Check sudo configuration
sudo -l -U frappe

# Verify file permissions
ls -la /root/mysql_credentials.txt
ls -la /root/admin_credentials.txt
```

#### Service Startup Issues
```bash
# Check Redis status
systemctl status redis-server

# Check Nginx configuration
nginx -t

# Check Supervisor processes
supervisorctl status
```

### Recovery Options
The installation scripts include rollback functionality:

```bash
# Manual cleanup (if needed)
sudo userdel -r frappe
sudo rm -rf /home/frappe/
sudo mysql -u root -p -e "DROP DATABASE erpnext_site1_local;"
```

## 📊 Monitoring & Maintenance

### Health Checks
```bash
# Test all services
curl -f http://localhost:8000  # ERPNext
redis-cli ping                  # Redis
mysql -u root -p -e "SELECT 1;" # MariaDB
```

### Backup Procedures
```bash
# Create backup
su - frappe -c 'cd frappe-bench && bench backup --site site1.local'

# Restore from backup
su - frappe -c 'cd frappe-bench && bench restore /path/to/backup.sql --site site1.local'
```

### Log Files
- Installation logs: `/tmp/erpnext-install.log`
- Quick install logs: `/tmp/erpnext-quick-install.log`
- ERPNext logs: `/home/frappe/frappe-bench/logs/`
- Nginx logs: `/var/log/nginx/`
- MariaDB logs: `/var/log/mysql/`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [ERPNext](https://erpnext.com/) - The ERP system
- [Frappe Framework](https://frappeframework.com/) - The underlying framework
- [Debian](https://www.debian.org/) - The operating system
- [MariaDB](https://mariadb.org/) - The database
- [Redis](https://redis.io/) - The cache system

## 📞 Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section above
- Review the installation logs for error details

---

# ERPNext Скрипты установки для Debian 13

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Debian 13](https://img.shields.io/badge/Debian-13-red)](https://www.debian.org/)
[![ERPNext 15](https://img.shields.io/badge/ERPNext-15-blue)](https://erpnext.com/)

Полнофункциональные скрипты установки ERPNext на Debian 13 с улучшенной безопасностью, множественными режимами установки и комплексной обработкой ошибок.

## 🚀 Быстрый старт

### Простая установка (Рекомендуется)
```bash
# Скачайте и запустите скрипт быстрой установки
wget https://raw.githubusercontent.com/your-repo/erpnext-debian13-install/main/quick-install.sh
chmod +x quick-install.sh
sudo ./quick-install.sh
```

### Продвинутая установка (Интерактивная)
```bash
# Скачайте и запустите полный скрипт установки
wget https://raw.githubusercontent.com/your-repo/erpnext-debian13-install/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## 📋 Системные требования

- **ОС**: Debian 13 (Bookworm)
- **ОЗУ**: Минимум 4ГБ (рекомендуется 8ГБ)
- **Место на диске**: Минимум 20ГБ свободного места
- **Архитектура**: amd64
- **Сеть**: Требуется подключение к интернету

## 🔧 Режимы установки

### 1. Быстрая установка (`quick-install.sh`)
Автоматизированная установка с настройками по умолчанию. Идеально для сред разработки или тестирования.

```bash
sudo ./quick-install.sh
```

**Особенности:**
- Использует домен по умолчанию `site1.local`
- Генерирует случайные безопасные пароли
- Устанавливает все необходимые компоненты автоматически
- Включает настройку production с Nginx и Supervisor
- Настраивает UFW firewall

### 2. Интерактивная установка (`install.sh`)
Полнофункциональная установка с взаимодействием пользователя и опциями настройки.

```bash
sudo ./install.sh
```

**Особенности:**
- Выбор версии Node.js (22 или 24)
- Пользовательское доменное имя с валидацией
- Выбор дополнительных приложений Frappe
- Пошаговый или полный режимы установки
- Расширенные опции конфигурации

### 3. Автоматизированная установка
Для CI/CD пайплайнов или безголовых серверов:

```bash
# Установите переменные окружения
export ERPNEXT_DOMAIN="your-domain.com"
export ERPNEXT_ADMIN_PASSWORD="your-secure-password"
export MARIADB_ROOT_PASSWORD="your-db-password"
export FRAPPE_USER="frappe"

# Запустите автоматизированную установку
sudo ./install.sh --silent
```

## 📁 Структура файлов

```
.
├── install.sh              # Основной интерактивный установщик
├── quick-install.sh        # Простой автоматизированный установщик
├── config.sh               # Файл конфигурации (опционально)
└── README.md              # Эта документация
```

## 🔐 Функции безопасности

### Управление паролями
- **Генерация случайных паролей**: Пароли администратора и базы данных генерируются безопасно
- **Безопасное хранение**: Пароли хранятся в защищенных файлах с ограниченными правами
- **Без открытого текста**: Пароли никогда не раскрываются в логах или истории команд

### Контроль доступа
- **Ограниченный sudo**: Пользователь имеет доступ только к необходимым системным командам
- **Firewall**: UFW настроен с минимально необходимыми портами
- **Изоляция сервисов**: Сервисы работают под выделенной учетной записью пользователя

### Защита данных
- **Зашифрованные соединения**: MariaDB настроена для безопасных соединений
- **Безопасные настройки по умолчанию**: Нет анонимных пользователей или тестовых баз данных
- **Готовность к резервному копированию**: Скрипты подготавливают автоматизированные резервные копии

## 🛠️ Примеры использования

### Базовое использование
```bash
# Быстрая установка с настройками по умолчанию
sudo ./quick-install.sh

# Интерактивная установка
sudo ./install.sh

# Быстрый режим с пользовательскими настройками
sudo ./install.sh --quick

# Автоматизированная установка
sudo ./install.sh --silent
```

### Пользовательская конфигурация
Создайте `config.sh` для настройки установки:

```bash
# config.sh
CONFIG_DEFAULT_DOMAIN="erp.company.com"
CONFIG_DEFAULT_USER="erpnext"
CONFIG_NODE_VERSION="22"
CONFIG_MIN_RAM_GB=8
CONFIG_MIN_DISK_GB=50
CONFIG_PRODUCTION_MODE=true
CONFIG_FIREWALL_ENABLED=true
```

### Тестирование установки
```bash
# Тестирование только системных требований
sudo ./quick-install.sh --test

# Просмотр справки
sudo ./install.sh --help
```

## 🔍 После установки

### Доступ к ERPNext
После успешной установки, получите доступ к вашему экземпляру ERPNext:

```
URL: http://your-domain.com
Логин: administrator
Пароль: [Проверьте лог установки или /root/admin_credentials.txt]
```

### Важные первые шаги
1. **Измените пароль администратора**: Войдите и измените пароль администратора по умолчанию
2. **Настройте SSL**: Настройте HTTPS сертификаты
3. **Настройте резервное копирование**: Настройте расписание автоматического резервного копирования
4. **Проверьте безопасность**: Проверьте правила firewall и права пользователей

### Полезные команды
```bash
# Запуск ERPNext bench
su - frappe -c 'cd frappe-bench && bench start'

# Остановка ERPNext bench
su - frappe -c 'cd frappe-bench && bench stop'

# Просмотр статуса bench
su - frappe -c 'cd frappe-bench && bench status'

# Просмотр логов
tail -f /tmp/erpnext-install.log
```

## 🐛 Устранение неполадок

### Распространенные проблемы

#### Установка завершается неудачей
```bash
# Проверьте системные требования
sudo ./quick-install.sh --test

# Просмотрите подробные логи
tail -f /tmp/erpnext-install.log
tail -f /tmp/erpnext-quick-install.log
```

#### Проблемы с подключением к базе данных
```bash
# Тестирование подключения MariaDB
mysql -u root -p -e "SELECT 1;"

# Проверка статуса MariaDB
systemctl status mariadb
```

#### Проблемы с правами доступа
```bash
# Проверка конфигурации sudo
sudo -l -U frappe

# Проверка прав доступа к файлам
ls -la /root/mysql_credentials.txt
ls -la /root/admin_credentials.txt
```

#### Проблемы с запуском сервисов
```bash
# Проверка статуса Redis
systemctl status redis-server

# Проверка конфигурации Nginx
nginx -t

# Проверка процессов Supervisor
supervisorctl status
```

### Опции восстановления
Скрипты установки включают функциональность отката:

```bash
# Ручная очистка (при необходимости)
sudo userdel -r frappe
sudo rm -rf /home/frappe/
sudo mysql -u root -p -e "DROP DATABASE erpnext_site1_local;"
```

## 📊 Мониторинг и обслуживание

### Проверки работоспособности
```bash
# Тестирование всех сервисов
curl -f http://localhost:8000  # ERPNext
redis-cli ping                  # Redis
mysql -u root -p -e "SELECT 1;" # MariaDB
```

### Процедуры резервного копирования
```bash
# Создание резервной копии
su - frappe -c 'cd frappe-bench && bench backup --site site1.local'

# Восстановление из резервной копии
su - frappe -c 'cd frappe-bench && bench restore /path/to/backup.sql --site site1.local'
```

### Файлы логов
- Логи установки: `/tmp/erpnext-install.log`
- Логи быстрой установки: `/tmp/erpnext-quick-install.log`
- Логи ERPNext: `/home/frappe/frappe-bench/logs/`
- Логи Nginx: `/var/log/nginx/`
- Логи MariaDB: `/var/log/mysql/`

## 🤝 Вклад в проект

1. Форкните репозиторий
2. Создайте ветку для функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте изменения (`git commit -m 'Add amazing feature'`)
4. Отправьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📝 Лицензия

Этот проект лицензирован под MIT License - смотрите файл [LICENSE](LICENSE) для деталей.

## 🙏 Благодарности

- [ERPNext](https://erpnext.com/) - Система ERP
- [Frappe Framework](https://frappeframework.com/) - Базовый фреймворк
- [Debian](https://www.debian.org/) - Операционная система
- [MariaDB](https://mariadb.org/) - База данных
- [Redis](https://redis.io/) - Система кэширования

## 📞 Поддержка

Для вопросов и проблем:
- Создайте issue на GitHub
- Проверьте раздел устранения неполадок выше
- Просмотрите логи установки для деталей ошибок

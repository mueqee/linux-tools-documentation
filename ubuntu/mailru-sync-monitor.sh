#!/bin/bash

# Скрипт мониторинга синхронизации Mail.ru Cloud
# Автор: liiilia
# Дата: 2025-07-28

set -e

# Конфигурация
SOURCE_DIR="/home/liiilia/Yandex.Disk/lily-is-here"
TARGET_DIR="/lily-is-here"
THREADS=8
DIRECTION="push"
LOG_FILE="/tmp/mailru_sync_monitor.log"
PID_FILE="/tmp/mailru_sync.pid"
STATUS_FILE="/tmp/mailru_sync_status.txt"

# Конфигурация виртуального окружения (раскомментируйте при необходимости)
VENV_PATH="/home/liiilia/.venv"
# PYTHON_PATH="$VENV_PATH/bin/python"
# MAILRU_CMD="$VENV_PATH/bin/mailrucloud"

# Автоматическое определение mailrucloud
MAILRU_CMD="mailrucloud"

# Функция для активации виртуального окружения
activate_venv() {
    if [ -n "$VENV_PATH" ] && [ -f "$VENV_PATH/bin/activate" ]; then
        log_message "Активация виртуального окружения: $VENV_PATH"
        source "$VENV_PATH/bin/activate"
        return 0
    fi
    return 1
}

# Функция для определения команды mailrucloud
detect_mailrucloud() {
    # Проверяем, указан ли путь к виртуальному окружению
    if [ -n "$VENV_PATH" ] && [ -f "$VENV_PATH/bin/mailrucloud" ]; then
        MAILRU_CMD="$VENV_PATH/bin/mailrucloud"
        log_message "Используется mailrucloud из виртуального окружения: $MAILRU_CMD"
        return 0
    fi
    
    # Проверяем глобальную установку
    if command -v mailrucloud &> /dev/null; then
        MAILRU_CMD="mailrucloud"
        log_message "Используется глобально установленный mailrucloud"
        return 0
    fi
    
    # Проверяем стандартные пути виртуальных окружений
    for venv_dir in "$HOME/.venv" "$HOME/venv" "$HOME/.virtualenvs/mailru" "$(pwd)/venv"; do
        if [ -f "$venv_dir/bin/mailrucloud" ]; then
            MAILRU_CMD="$venv_dir/bin/mailrucloud"
            log_message "Найден mailrucloud в: $MAILRU_CMD"
            return 0
        fi
    done
    
    return 1
}

# Функция для отправки уведомлений
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-dialog-information}"
    
    if command -v notify-send &> /dev/null; then
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
        notify-send -i "$icon" "$title" "$message"
    fi
}

# Функция для логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция для запуска синхронизации
start_sync() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        log_message "Синхронизация уже запущена (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    log_message "Запуск синхронизации: $SOURCE_DIR → $TARGET_DIR"
    send_notification "📂 Mail.ru Cloud Sync" "Начинается синхронизация UI проекта"
    
    # Запуск синхронизации в фоновом режиме с перенаправлением вывода
    nohup "$MAILRU_CMD" sync "$SOURCE_DIR" "$TARGET_DIR" \
        --direction "$DIRECTION" \
        --threads "$THREADS" \
        --only-new > "$STATUS_FILE" 2>&1 &
    
    local sync_pid=$!
    echo "$sync_pid" > "$PID_FILE"
    log_message "Синхронизация запущена с PID: $sync_pid"
    
    # Запуск мониторинга
    monitor_sync
}

# Функция для остановки синхронизации
stop_sync() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log_message "Синхронизация остановлена (PID: $pid)"
            send_notification "⏹️ Mail.ru Cloud Sync" "Синхронизация остановлена пользователем"
        fi
        rm -f "$PID_FILE"
    fi
}

# Функция для парсинга прогресса из вывода mailrucloud
parse_progress_info() {
    local log_file="$1"
    local progress_info=""
    local uploaded_files=0
    local total_files=0
    local percentage=0
    
    if [ ! -f "$log_file" ]; then
        echo "Инициализация..."
        return 0
    fi
    
    # Ищем информацию о прогрессе в последних строках лога
    local recent_output=$(tail -n 20 "$log_file")
    
    # Поиск количества файлов для загрузки (в начале процесса)
    if [ "$total_files" -eq 0 ]; then
        total_files=$(echo "$recent_output" | grep -o "Found [0-9]\+ files" | head -1 | grep -o "[0-9]\+")
        if [ -z "$total_files" ]; then
            total_files=$(echo "$recent_output" | grep -o "Найдено [0-9]\+ файлов" | head -1 | grep -o "[0-9]\+")
        fi
        # Сохраняем total_files в временный файл для последующего использования
        if [ -n "$total_files" ] && [ "$total_files" -gt 0 ]; then
            echo "$total_files" > "/tmp/mailru_total_files.tmp"
        fi
    fi
    
    # Читаем сохраненное значение total_files
    if [ -f "/tmp/mailru_total_files.tmp" ]; then
        total_files=$(cat "/tmp/mailru_total_files.tmp")
    fi
    
    # Поиск текущего прогресса загрузки
    uploaded_files=$(echo "$recent_output" | grep -o "Uploaded [0-9]\+" | tail -1 | grep -o "[0-9]\+")
    if [ -z "$uploaded_files" ]; then
        uploaded_files=$(echo "$recent_output" | grep -o "Загружено [0-9]\+" | tail -1 | grep -o "[0-9]\+")
    fi
    
    # Поиск процентов
    percentage=$(echo "$recent_output" | grep -o "[0-9]\+%" | tail -1 | grep -o "[0-9]\+")
    
    # Альтернативный способ подсчета прогресса
    if [ -z "$uploaded_files" ]; then
        uploaded_files=$(echo "$recent_output" | grep -c "✓\|√\|uploaded\|загружен")
    fi
    
    # Расчет процентов, если не найден в выводе
    if [ -z "$percentage" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ] && [ -n "$uploaded_files" ]; then
        percentage=$((uploaded_files * 100 / total_files))
    fi
    
    # Формирование строки прогресса
    if [ -n "$uploaded_files" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ]; then
        if [ -n "$percentage" ]; then
            echo "${uploaded_files}/${total_files} ${percentage}%"
        else
            echo "${uploaded_files}/${total_files}"
        fi
    elif [ -n "$percentage" ]; then
        echo "${percentage}%"
    elif [ -n "$uploaded_files" ] && [ "$uploaded_files" -gt 0 ]; then
        echo "Загружено: ${uploaded_files} файлов"
    else
        # Проверяем, есть ли активность в логе
        local last_activity=$(echo "$recent_output" | tail -5 | grep -E "(uploading|downloading|sync|загрузка|скачивание)" | tail -1)
        if [ -n "$last_activity" ]; then
            echo "Обработка файлов..."
        else
            echo "Анализ структуры..."
        fi
    fi
}

# Функция для получения статуса синхронизации
get_sync_status() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Синхронизация не запущена"
        return 1
    fi
    
    local pid=$(cat "$PID_FILE")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Процесс синхронизации завершён"
        rm -f "$PID_FILE"
        return 1
    fi
    
    # Получение прогресса
    local progress=$(parse_progress_info "$STATUS_FILE")
    
    # Получение информации о ресурсах
    local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')
    local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | tr -d ' ')
    
    if [ -n "$cpu_usage" ] && [ -n "$mem_usage" ]; then
        echo "$progress (CPU: ${cpu_usage}%, RAM: ${mem_usage}%)"
    else
        echo "$progress"
    fi
}

# Функция для мониторинга синхронизации
monitor_sync() {
    local notification_interval=300  # 5 минут в секундах
    local last_notification=0
    local start_time=$(date +%s)
    
    while [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        local elapsed_minutes=$((elapsed_time / 60))
        
        # Получение статуса
        local status=$(get_sync_status)
        
        # Отправка уведомления каждые 5 минут
        if [ $((current_time - last_notification)) -ge $notification_interval ]; then
            local hours=$((elapsed_minutes / 60))
            local minutes=$((elapsed_minutes % 60))
            local time_str=""
            
            if [ $hours -gt 0 ]; then
                time_str="${hours}ч ${minutes}м"
            else
                time_str="${minutes}м"
            fi
            
            send_notification "🔄 Mail.ru Cloud Sync" \
                "Время работы: $time_str\n$status" \
                "dialog-information"
            
            log_message "Уведомление отправлено. Время работы: $time_str. Статус: $status"
            last_notification=$current_time
        fi
        
        sleep 30  # Проверка каждые 30 секунд
    done
    
    # Проверка результата синхронизации
    if [ -f "$STATUS_FILE" ]; then
        local final_status=$(tail -n 10 "$STATUS_FILE")
        if echo "$final_status" | grep -q "успешно\|success\|complete"; then
            send_notification "✅ Mail.ru Cloud Sync" \
                "Синхронизация завершена успешно!\nВремя выполнения: $((elapsed_minutes))м" \
                "dialog-positive"
            log_message "Синхронизация завершена успешно за $elapsed_minutes минут"
        else
            send_notification "❌ Mail.ru Cloud Sync" \
                "Синхронизация завершена с ошибкой\nПроверьте логи: $LOG_FILE" \
                "dialog-error"
            log_message "Синхронизация завершена с ошибкой"
        fi
    fi
    
    # Очистка
    rm -f "$PID_FILE"
}

# Функция показа справки
show_help() {
    echo "Использование: $0 [КОМАНДА]"
    echo ""
    echo "Команды:"
    echo "  start    - Запустить синхронизацию с мониторингом"
    echo "  stop     - Остановить текущую синхронизацию"
    echo "  status   - Показать текущий статус синхронизации"
    echo "  log      - Показать последние 20 строк лога"
    echo "  help     - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 start     # Запустить синхронизацию"
    echo "  $0 status    # Проверить статус"
    echo "  $0 stop      # Остановить синхронизацию"
    echo ""
    echo "Конфигурация виртуального окружения:"
    echo "  Если mailrucloud установлен в виртуальном окружении, отредактируйте"
    echo "  переменную VENV_PATH в начале скрипта:"
    echo "    VENV_PATH=\"/path/to/your/venv\""
    echo ""
    echo "  Скрипт автоматически ищет mailrucloud в следующих местах:"
    echo "    - Глобальная установка (pip install mailru-cloud-client)"
    echo "    - Указанное виртуальное окружение (VENV_PATH)"
    echo "    - \$HOME/.venv/bin/mailrucloud"
    echo "    - \$HOME/venv/bin/mailrucloud"
    echo "    - \$HOME/.virtualenvs/mailru/bin/mailrucloud"
    echo "    - ./venv/bin/mailrucloud"
}

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# Определение и проверка mailrucloud
if ! detect_mailrucloud; then
    echo "Ошибка: mailrucloud не найден!"
    echo ""
    echo "Возможные решения:"
    echo "1. Установите глобально: pip install mailru-cloud-client"
    echo "2. Установите в виртуальном окружении и укажите VENV_PATH в скрипте"
    echo "3. Активируйте виртуальное окружение перед запуском"
    echo ""
    echo "Для использования виртуального окружения отредактируйте переменную VENV_PATH в начале скрипта:"
    echo "  VENV_PATH=\"/path/to/your/venv\""
    send_notification "❌ Mail.ru Cloud Sync" "mailrucloud не найден! Проверьте установку." "dialog-error"
    exit 1
fi

# Активация виртуального окружения (если указано)
activate_venv

# Проверка наличия notify-send
if ! command -v notify-send &> /dev/null; then
    echo "Предупреждение: notify-send не установлен. Уведомления отключены."
fi

# Обработка команд
case "${1:-help}" in
    start)
        start_sync
        ;;
    stop)
        stop_sync
        ;;
    status)
        if status=$(get_sync_status); then
            echo "Статус синхронизации: $status"
            log_message "Запрос статуса: $status"
        else
            echo "Синхронизация не активна"
        fi
        ;;
    log)
        if [ -f "$LOG_FILE" ]; then
            echo "Последние записи лога:"
            tail -n 20 "$LOG_FILE"
        else
            echo "Лог-файл не найден"
        fi
        ;;
    help|*)
        show_help
        ;;
esac 
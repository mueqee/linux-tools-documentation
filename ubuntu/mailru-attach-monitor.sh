#!/bin/bash

# Скрипт для подключения мониторинга к существующему процессу mailrucloud
# Автор: liiilia
# Дата: 2025-07-28

set -e

# Конфигурация
VENV_PATH="/home/liiilia/.venv"
LOG_FILE="/tmp/mailru_sync_monitor.log"
PID_FILE="/tmp/mailru_sync.pid"
STATUS_FILE="/tmp/mailru_sync_status.txt"

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

# Поиск существующего процесса mailrucloud
find_existing_process() {
    local mailru_pid=$(ps aux | grep mailrucloud | grep -v grep | grep sync | awk '{print $2}' | head -1)
    if [ -n "$mailru_pid" ]; then
        echo "$mailru_pid"
        return 0
    fi
    return 1
}

# Подключение к существующему процессу
attach_to_existing() {
    local existing_pid
    if existing_pid=$(find_existing_process); then
        echo "$existing_pid" > "$PID_FILE"
        log_message "Подключение к существующему процессу синхронизации (PID: $existing_pid)"
        send_notification "🔗 Mail.ru Cloud Monitor" "Подключение к процессу синхронизации (PID: $existing_pid)"
        
        # Получение информации о процессе
        local process_info=$(ps -p "$existing_pid" -o cmd --no-headers)
        log_message "Процесс: $process_info"
        
        # Запуск мониторинга
        monitor_existing_process "$existing_pid"
        return 0
    else
        echo "Активный процесс mailrucloud sync не найден"
        send_notification "❌ Mail.ru Cloud Monitor" "Активный процесс синхронизации не найден"
        return 1
    fi
}

# Функция для парсинга прогресса из логов процесса
parse_process_progress() {
    local pid="$1"
    local progress_info=""
    local uploaded_files=0
    local total_files=0
    local percentage=0
    
    # Попытка найти лог-файлы процесса или использовать STATUS_FILE
    local log_content=""
    
    # Проверяем, есть ли STATUS_FILE
    if [ -f "$STATUS_FILE" ]; then
        log_content=$(tail -n 30 "$STATUS_FILE" 2>/dev/null)
    else
        # Попытка получить информацию из /proc/*/fd/* (stdout процесса)
        local proc_dir="/proc/$pid"
        if [ -d "$proc_dir" ]; then
            # Пытаемся прочитать из стандартного вывода процесса (если доступно)
            log_content=$(timeout 1 strace -p "$pid" -e write 2>&1 | head -20 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$log_content" ]; then
        echo "Активен"
        return 0
    fi
    
    # Поиск общего количества файлов
    total_files=$(echo "$log_content" | grep -o "Found [0-9]\+ files\|Найдено [0-9]\+ файлов" | head -1 | grep -o "[0-9]\+")
    if [ -n "$total_files" ] && [ "$total_files" -gt 0 ]; then
        echo "$total_files" > "/tmp/mailru_total_files_$pid.tmp"
    elif [ -f "/tmp/mailru_total_files_$pid.tmp" ]; then
        total_files=$(cat "/tmp/mailru_total_files_$pid.tmp")
    fi
    
    # Поиск загруженных файлов
    uploaded_files=$(echo "$log_content" | grep -o "Uploaded [0-9]\+\|Загружено [0-9]\+" | tail -1 | grep -o "[0-9]\+")
    
    # Поиск процентов
    percentage=$(echo "$log_content" | grep -o "[0-9]\+%" | tail -1 | grep -o "[0-9]\+")
    
    # Альтернативный подсчет загруженных файлов
    if [ -z "$uploaded_files" ]; then
        uploaded_files=$(echo "$log_content" | grep -c "✓\|√\|uploaded\|загружен\|→")
    fi
    
    # Вычисление процентов если есть данные
    if [ -z "$percentage" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ] && [ -n "$uploaded_files" ]; then
        percentage=$((uploaded_files * 100 / total_files))
    fi
    
    # Формирование результата
    if [ -n "$uploaded_files" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ]; then
        if [ -n "$percentage" ]; then
            echo "${uploaded_files}/${total_files} ${percentage}%"
        else
            echo "${uploaded_files}/${total_files}"
        fi
    elif [ -n "$percentage" ]; then
        echo "${percentage}%"
    elif [ -n "$uploaded_files" ] && [ "$uploaded_files" -gt 0 ]; then
        echo "Обработано: ${uploaded_files}"
    else
        echo "Активен"
    fi
}

# Мониторинг существующего процесса
monitor_existing_process() {
    local pid="$1"
    local notification_interval=300  # 5 минут
    local last_notification=0
    local start_time=$(date +%s)
    
    log_message "Начат мониторинг процесса PID: $pid"
    
    while kill -0 "$pid" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        local elapsed_minutes=$((elapsed_time / 60))
        
        # Получение информации о процессе
        local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers | tr -d ' ')
        local mem_usage=$(ps -p "$pid" -o %mem --no-headers | tr -d ' ')
        
        # Получение прогресса
        local progress=$(parse_process_progress "$pid")
        
        local status="$progress (CPU: ${cpu_usage}%, RAM: ${mem_usage}%)"
        
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
            
            send_notification "🔄 Mail.ru Cloud Monitor" \
                "Время мониторинга: $time_str\n$status" \
                "dialog-information"
            
            log_message "Уведомление: время мониторинга $time_str, статус: $status"
            last_notification=$current_time
        fi
        
        sleep 30  # Проверка каждые 30 секунд
    done
    
    # Процесс завершился
    local final_time=$((elapsed_time / 60))
    send_notification "✅ Mail.ru Cloud Monitor" \
        "Процесс синхронизации завершён\nВремя работы: ${final_time}м" \
        "dialog-positive"
    
    log_message "Процесс синхронизации завершён. Общее время мониторинга: ${final_time} минут"
    
    # Очистка временных файлов
    rm -f "$PID_FILE" "/tmp/mailru_total_files_$pid.tmp"
}

# Остановка мониторинга
stop_monitoring() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        echo "Остановка мониторинга процесса PID: $pid"
        log_message "Остановка мониторинга пользователем"
        send_notification "⏹️ Mail.ru Cloud Monitor" "Мониторинг остановлен пользователем"
        rm -f "$PID_FILE"
        exit 0
    else
        echo "Мониторинг не активен"
    fi
}

# Показать статус
show_status() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers | tr -d ' ')
            local mem_usage=$(ps -p "$pid" -o %mem --no-headers | tr -d ' ')
            local progress=$(parse_process_progress "$pid")
            
            echo "Мониторинг активен для процесса PID: $pid"
            echo "Прогресс: $progress"
            echo "Использование CPU: ${cpu_usage}%"
            echo "Использование RAM: ${mem_usage}%"
            echo "Команда: $(ps -p "$pid" -o cmd --no-headers)"
        else
            echo "Процесс завершён, очистка PID файла"
            rm -f "$PID_FILE"
        fi
    else
        echo "Мониторинг не активен"
        if existing_pid=$(find_existing_process); then
            echo "Найден активный процесс mailrucloud: PID $existing_pid"
            local progress=$(parse_process_progress "$existing_pid")
            echo "Прогресс: $progress"
            echo "Используйте '$0 attach' для подключения"
        fi
    fi
}

# Функция показа справки
show_help() {
    echo "Использование: $0 [КОМАНДА]"
    echo ""
    echo "Команды:"
    echo "  attach   - Подключиться к существующему процессу mailrucloud sync"
    echo "  stop     - Остановить мониторинг (не затрагивает сам процесс синхронизации)"
    echo "  status   - Показать статус мониторинга"
    echo "  log      - Показать последние 20 строк лога"
    echo "  help     - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 attach    # Подключиться к текущему процессу синхронизации"
    echo "  $0 status    # Проверить статус мониторинга"
    echo "  $0 stop      # Остановить только мониторинг"
}

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# Обработка команд
case "${1:-help}" in
    attach)
        attach_to_existing
        ;;
    stop)
        stop_monitoring
        ;;
    status)
        show_status
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
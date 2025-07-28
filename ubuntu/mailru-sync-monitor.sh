#!/bin/bash

# Скрипт мониторинга синхронизации Mail.ru Cloud
# Автор: liiilia
# Дата: 2025-07-28

set -e

# Конфигурация
SOURCE_DIR="/home/liiilia/Yandex.Disk/lily-is-here/UI"
TARGET_DIR="/lily-is-here/UI"
THREADS=8
DIRECTION="push"
LOG_FILE="/tmp/mailru_sync_monitor.log"
PID_FILE="/tmp/mailru_sync.pid"
STATUS_FILE="/tmp/mailru_sync_status.txt"

# Функция для отправки уведомлений
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-dialog-information}"
    
    DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
    notify-send -i "$icon" "$title" "$message"
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
    nohup mailrucloud sync "$SOURCE_DIR" "$TARGET_DIR" \
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
    
    # Анализ лог-файла для извлечения прогресса
    if [ -f "$STATUS_FILE" ]; then
        local last_line=$(tail -n 5 "$STATUS_FILE" | grep -E "(Загружено|Uploaded|Progress|%)" | tail -n 1)
        if [ -n "$last_line" ]; then
            echo "$last_line"
        else
            echo "Синхронизация выполняется... (анализ файлов)"
        fi
    else
        echo "Синхронизация выполняется... (инициализация)"
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
}

# Проверка наличия mailrucloud
if ! command -v mailrucloud &> /dev/null; then
    echo "Ошибка: mailrucloud не установлен или не найден в PATH"
    send_notification "❌ Mail.ru Cloud Sync" "mailrucloud не установлен!" "dialog-error"
    exit 1
fi

# Проверка наличия notify-send
if ! command -v notify-send &> /dev/null; then
    echo "Предупреждение: notify-send не установлен. Уведомления отключены."
fi

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

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
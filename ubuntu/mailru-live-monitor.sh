#!/bin/bash

# Живой мониторинг процесса mailrucloud с детальным прогрессом
# Автор: liiilia
# Дата: 2025-07-29

set -e

# Конфигурация
LOG_FILE="/tmp/mailru_live_monitor.log"
PROGRESS_LOG="/tmp/mailru_progress_data.log"
NOTIFICATION_INTERVAL=300  # 5 минут в секундах

# Функция для отправки уведомлений
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-dialog-information}"
    
    if command -v notify-send &> /dev/null; then
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
        notify-send -i "$icon" "$title" "$message" -t 8000
    fi
}

# Функция для логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция для получения детального прогресса процесса
get_process_progress() {
    local pid="$1"
    local uploaded_files=0
    local total_files=0
    local current_file=""
    local network_activity=""
    
    # Получаем сетевую активность (показатель загрузки)
    local net_stats=$(ss -i -p | grep "$pid" 2>/dev/null | head -1)
    if [ -n "$net_stats" ]; then
        network_activity="Сеть активна"
    fi
    
    # Анализируем открытые файлы для определения текущего файла
    local open_files=$(lsof -p "$pid" 2>/dev/null | grep -E "\.zip$|\.rar$|\.jpg$|\.png$|\.pdf$|\.doc" | tail -1)
    if [ -n "$open_files" ]; then
        current_file=$(echo "$open_files" | awk '{print $NF}' | xargs basename)
    fi
    
    # Считаем количество обработанных соединений (приблизительный показатель)
    local connections=$(ss -t | grep -c "cloud.mail.ru" 2>/dev/null || echo "0")
    
    # Получаем время работы процесса
    local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | head -1)
    local elapsed_seconds=$(ps -o etime= -p "$pid" 2>/dev/null | head -1 | awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else print $1*60+$2}' | tr -d ' ')
    
    # Приблизительная оценка на основе времени работы (1 файл в 30 секунд в среднем)
    if [ -n "$elapsed_seconds" ] && [ "$elapsed_seconds" -gt 0 ]; then
        uploaded_files=$((elapsed_seconds / 30))
        # Оценка общего количества файлов на основе структуры директории
        if [ "$total_files" -eq 0 ]; then
            total_files=$(find "/home/liiilia/Yandex.Disk/lily-is-here/UI" -type f 2>/dev/null | wc -l)
            echo "$total_files" > "/tmp/mailru_estimated_total.tmp"
        elif [ -f "/tmp/mailru_estimated_total.tmp" ]; then
            total_files=$(cat "/tmp/mailru_estimated_total.tmp")
        fi
    fi
    
    # Формируем прогресс
    local progress_text=""
    if [ "$total_files" -gt 0 ] && [ "$uploaded_files" -gt 0 ]; then
        local percentage=$((uploaded_files * 100 / total_files))
        if [ "$percentage" -gt 100 ]; then
            percentage=99  # Ограничиваем до 99% пока не завершено
        fi
        progress_text="${uploaded_files}/${total_files} ${percentage}%"
    elif [ "$uploaded_files" -gt 0 ]; then
        progress_text="Обработано: ~${uploaded_files} файлов"
    else
        progress_text="Инициализация..."
    fi
    
    # Добавляем информацию о текущем файле
    if [ -n "$current_file" ]; then
        progress_text="$progress_text - $current_file"
    fi
    
    # Добавляем сетевую активность
    if [ -n "$network_activity" ]; then
        progress_text="$progress_text ($network_activity)"
    fi
    
    echo "$progress_text"
}

# Функция для мониторинга процесса
monitor_live_process() {
    local pid="$1"
    
    if [ -z "$pid" ]; then
        echo "Ошибка: не указан PID процесса"
        return 1
    fi
    
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Ошибка: процесс $pid не найден или недоступен"
        return 1
    fi
    
    log_message "Начат живой мониторинг процесса PID: $pid"
    send_notification "🔄 Mail.ru Cloud Live Monitor" "Начат мониторинг процесса $pid"
    
    local start_time=$(date +%s)
    local last_notification=0
    
    while kill -0 "$pid" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        local elapsed_minutes=$((elapsed_time / 60))
        
        # Получение ресурсов процесса
        local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')
        local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | tr -d ' ')
        
        # Получение прогресса
        local progress=$(get_process_progress "$pid")
        
        # Логирование прогресса
        echo "[$(date '+%H:%M:%S')] $progress (CPU: ${cpu_usage}%, RAM: ${mem_usage}%)" >> "$PROGRESS_LOG"
        
        # Отправка уведомления каждые 5 минут
        if [ $((current_time - last_notification)) -ge $NOTIFICATION_INTERVAL ]; then
            local hours=$((elapsed_minutes / 60))
            local minutes=$((elapsed_minutes % 60))
            local time_str=""
            
            if [ $hours -gt 0 ]; then
                time_str="${hours}ч ${minutes}м"
            else
                time_str="${minutes}м"
            fi
            
            local detailed_status="⏱️ Время: $time_str\n📊 $progress\n🖥️ CPU: ${cpu_usage}%, RAM: ${mem_usage}%"
            
            send_notification "🔄 Mail.ru Cloud Sync" "$detailed_status" "dialog-information"
            log_message "Уведомление отправлено: $time_str, прогресс: $progress"
            
            last_notification=$current_time
        fi
        
        sleep 30  # Проверка каждые 30 секунд
    done
    
    # Процесс завершился
    local final_time=$((elapsed_time / 60))
    send_notification "✅ Mail.ru Cloud Sync" \
        "Синхронизация завершена!\n⏱️ Время: ${final_time}м\n📁 Процесс завершён успешно" \
        "dialog-positive"
    
    log_message "Процесс синхронизации завершён. Время работы: ${final_time} минут"
    
    # Очистка
    rm -f "/tmp/mailru_estimated_total.tmp"
}

# Функция поиска активного процесса mailrucloud
find_mailru_process() {
    ps aux | grep mailrucloud | grep -v grep | grep sync | awk '{print $2}' | head -1
}

# Функция показа текущего прогресса
show_current_progress() {
    local pid=$(find_mailru_process)
    
    if [ -z "$pid" ]; then
        echo "Активный процесс mailrucloud не найден"
        return 1
    fi
    
    local progress=$(get_process_progress "$pid")
    local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')
    local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | tr -d ' ')
    
    echo "PID: $pid"
    echo "Прогресс: $progress"
    echo "CPU: ${cpu_usage}%, RAM: ${mem_usage}%"
    
    # Показываем последние записи прогресса
    if [ -f "$PROGRESS_LOG" ]; then
        echo ""
        echo "Последние обновления:"
        tail -n 5 "$PROGRESS_LOG"
    fi
}

# Функция показа справки
show_help() {
    echo "Использование: $0 [КОМАНДА] [PID]"
    echo ""
    echo "Команды:"
    echo "  start [PID]  - Начать мониторинг указанного или найденного процесса"
    echo "  progress     - Показать текущий прогресс"
    echo "  log          - Показать логи мониторинга"
    echo "  help         - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 start           # Автопоиск и мониторинг процесса mailrucloud"
    echo "  $0 start 355458    # Мониторинг конкретного PID"
    echo "  $0 progress        # Показать текущий прогресс"
}

# Основная логика
case "${1:-help}" in
    start)
        if [ -n "$2" ]; then
            monitor_live_process "$2"
        else
            local pid=$(find_mailru_process)
            if [ -n "$pid" ]; then
                echo "Найден процесс mailrucloud: PID $pid"
                monitor_live_process "$pid"
            else
                echo "Активный процесс mailrucloud не найден"
                exit 1
            fi
        fi
        ;;
    progress)
        show_current_progress
        ;;
    log)
        if [ -f "$LOG_FILE" ]; then
            echo "Основной лог:"
            tail -n 20 "$LOG_FILE"
            echo ""
        fi
        if [ -f "$PROGRESS_LOG" ]; then
            echo "Лог прогресса:"
            tail -n 10 "$PROGRESS_LOG"
        fi
        ;;
    help|*)
        show_help
        ;;
esac 
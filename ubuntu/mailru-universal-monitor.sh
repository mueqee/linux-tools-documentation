#!/bin/bash

# Универсальный мониторинг процессов mailrucloud с автоматическим переключением
# Автор: liiilia
# Дата: 2025-07-29

set -e

# Конфигурация
LOG_FILE="/tmp/mailru_universal_monitor.log"
PROGRESS_LOG="/tmp/mailru_universal_progress.log"
STATE_FILE="/tmp/mailru_monitor_state.json"
NOTIFICATION_INTERVAL=300  # 5 минут в секундах
CHECK_INTERVAL=30  # 30 секунд между проверками

# Функция для отправки уведомлений
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-dialog-information}"
    
    if command -v notify-send &> /dev/null; then
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
        notify-send -i "$icon" "$title" "$message" -t 10000
    fi
}

# Функция для логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция для сохранения состояния мониторинга
save_state() {
    local pid="$1"
    local start_time="$2"
    local last_notification="$3"
    local source_dir="$4"
    local target_dir="$5"
    
    cat > "$STATE_FILE" << EOF
{
    "pid": $pid,
    "start_time": $start_time,
    "last_notification": $last_notification,
    "source_dir": "$source_dir",
    "target_dir": "$target_dir",
    "timestamp": $(date +%s)
}
EOF
}

# Функция для загрузки состояния
load_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo '{"pid": 0, "start_time": 0, "last_notification": 0}'
    fi
}

# Функция поиска всех процессов mailrucloud sync
find_all_mailru_processes() {
    ps aux | grep mailrucloud | grep sync | grep -v grep | while read line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
        echo "$pid:$cmd"
    done
}

# Функция для парсинга информации о процессе
parse_process_info() {
    local process_line="$1"
    local pid=$(echo "$process_line" | cut -d: -f1)
    local cmd=$(echo "$process_line" | cut -d: -f2-)
    
    # Извлекаем исходную и целевую директории
    local source_dir=$(echo "$cmd" | grep -o 'sync [^"]*/[^"]*' | sed 's/sync //' | awk '{print $1}')
    local target_dir=$(echo "$cmd" | grep -o 'sync [^"]*/[^"]* [^"]*' | awk '{print $3}')
    
    # Если путь в кавычках
    if [[ "$cmd" == *'"'* ]]; then
        source_dir=$(echo "$cmd" | sed -n 's/.*sync "\([^"]*\)".*/\1/p')
        target_dir=$(echo "$cmd" | sed -n 's/.*sync "[^"]*" "\([^"]*\)".*/\1/p')
    fi
    
    echo "$pid|$source_dir|$target_dir"
}

# Функция для получения детального прогресса процесса
get_process_progress() {
    local pid="$1"
    local source_dir="$2"

    local uploaded_files=0
    local total_files=0
    local percentage=""
    local current_file=""
    local network_activity=""

    # Получаем сетевую активность
    local net_stats=$(ss -t | grep -c "cloud.mail.ru" 2>/dev/null || echo "0")
    if [ "$net_stats" -gt 0 ]; then
        network_activity="Сеть активна"
    fi

    # Анализируем открытые файлы для определения текущего файла
    local open_files=$(lsof -p "$pid" 2>/dev/null | grep -E "\.(zip|rar|jpg|jpeg|png|pdf|doc|docx|mp4|avi|mov)$" | tail -1)
    if [ -n "$open_files" ]; then
        current_file=$(echo "$open_files" | awk '{print $NF}' | xargs basename)
    fi

    # === 1) Попытка получить реальный прогресс из stdout ===
    local stdout_path="$(readlink -f /proc/$pid/fd/1 2>/dev/null)"
    if [ -n "$stdout_path" ] && [ -r "$stdout_path" ]; then
        local recent_output=$(timeout 0.3 tail -n 25 "$stdout_path" 2>/dev/null)
        # Ищем X/Y
        local xy=$(echo "$recent_output" | grep -Eo "[0-9]+/[0-9]+" | tail -1)
        if [[ "$xy" == */* ]]; then
            uploaded_files=$(echo "$xy" | cut -d/ -f1)
            total_files=$(echo "$xy" | cut -d/ -f2)
        fi
        # Ищем процент
        local perc=$(echo "$recent_output" | grep -Eo "[0-9]{1,3}%" | tail -1 | tr -d '%')
        if [ -n "$perc" ]; then
            percentage=$perc
        fi
    fi

    # === 1b) Если stdout не дал результатов, пробуем strace на write ===
    if [ -z "$xy" ]; then
        local strace_tmp=$(mktemp)
        timeout 0.3 strace -p $pid -e write -s 200 2>$strace_tmp || true
        local strace_out=$(grep -oE '"[^"]+"' $strace_tmp | tr -d '"')
        rm -f $strace_tmp
        xy=$(echo "$strace_out" | grep -Eo "[0-9]+/[0-9]+" | tail -1)
        if [[ "$xy" == */* ]]; then
            uploaded_files=$(echo "$xy" | cut -d/ -f1)
            total_files=$(echo "$xy" | cut -d/ -f2)
        fi
        perc=$(echo "$strace_out" | grep -Eo "[0-9]{1,3}%" | tail -1 | tr -d '%')
        if [ -n "$perc" ]; then
            percentage=$perc
        fi
    fi

    local cache_file="/tmp/mailru_total_${pid}.tmp"
    if [ -z "$total_files" ] || [ "$total_files" -eq 0 ]; then
        # Получаем из кэша/файловой системы ТОЛЬКО если X/Y не найдено
        if [ -f "$cache_file" ]; then
            total_files=$(cat "$cache_file")
        elif [ -d "$source_dir" ]; then
            total_files=$(find "$source_dir" -type f 2>/dev/null | wc -l)
            echo "$total_files" > "$cache_file"
        fi
    fi

    # === 3) Если только процент известен, вычисляем uploaded_files ===
    if [ -n "$percentage" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ] && [ "$uploaded_files" -eq 0 ]; then
        uploaded_files=$((percentage * total_files / 100))
    fi

    # === 4) Если ничего не найдено — резервная оценка по времени ===
    if [ -z "$uploaded_files" ] || [ "$uploaded_files" -eq 0 ]; then
        local elapsed_seconds=$(ps -o etime= -p "$pid" 2>/dev/null | head -1 | awk -F: '{if(NF==3) print $1*3600+$2*60+$3; else if(NF==2) print $1*60+$2; else print $1}' | tr -d ' ')
        local base_speed=5  # файлов в минуту (резервная оценка)
        uploaded_files=$((elapsed_seconds * base_speed / 60))
    fi

    # Пересчитываем процент если нужно
    if [ -z "$percentage" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ]; then
        percentage=$((uploaded_files * 100 / total_files))
    fi

    # Формируем прогресс
    local progress_text=""
    if [ -n "$uploaded_files" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ]; then
        progress_text="${uploaded_files}/${total_files} ${percentage}%"
    elif [ -n "$percentage" ]; then
        progress_text="${percentage}%"
    else
        progress_text="~${uploaded_files} файлов"
    fi

    local folder_name=$(basename "$source_dir")
    progress_text="📁 $folder_name: $progress_text"
    if [ -n "$current_file" ]; then
        progress_text="$progress_text - $current_file"
    fi
    if [ -n "$network_activity" ]; then
        progress_text="$progress_text ($network_activity)"
    fi

    echo "$progress_text"
}

# Функция для мониторинга процесса
monitor_process() {
    local pid="$1"
    local source_dir="$2"
    local target_dir="$3"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log_message "Процесс $pid больше не активен"
        return 1
    fi
    
    local current_time=$(date +%s)
    
    # Загружаем состояние
    local state=$(load_state)
    local last_notification=$(echo "$state" | grep -o '"last_notification": [0-9]*' | awk '{print $2}' | tr -d ',')
    local monitor_start_time=$(echo "$state" | grep -o '"start_time": [0-9]*' | awk '{print $2}' | tr -d ',')
    
    # Если это новый процесс, инициализируем
    if [ "$monitor_start_time" -eq 0 ] || [ "$pid" != "$(echo "$state" | grep -o '"pid": [0-9]*' | awk '{print $2}' | tr -d ',')" ]; then
        monitor_start_time=$current_time
        last_notification=0
        log_message "Начат мониторинг нового процесса PID: $pid ($source_dir → $target_dir)"
        send_notification "🔄 Mail.ru Cloud Monitor" "Начат мониторинг синхронизации\n📁 $(basename "$source_dir")"
    fi
    
    # Получение ресурсов процесса
    local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')
    local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | tr -d ' ')
    
    # Получение прогресса
    local progress=$(get_process_progress "$pid" "$source_dir")
    
    # Логирование прогресса
    echo "[$(date '+%H:%M:%S')] PID:$pid $progress (CPU: ${cpu_usage}%, RAM: ${mem_usage}%)" >> "$PROGRESS_LOG"
    
    # Отправка уведомления каждые 5 минут
    if [ $((current_time - last_notification)) -ge $NOTIFICATION_INTERVAL ]; then
        local elapsed_time=$((current_time - monitor_start_time))
        local elapsed_minutes=$((elapsed_time / 60))
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
    
    # Сохраняем состояние
    save_state "$pid" "$monitor_start_time" "$last_notification" "$source_dir" "$target_dir"
    
    return 0
}

# Основная функция мониторинга
main_monitor_loop() {
    log_message "Запуск универсального мониторинга mailrucloud"
    send_notification "🚀 Mail.ru Cloud Monitor" "Универсальный мониторинг запущен"
    
    local current_pid=0
    
    while true; do
        # Получаем список всех активных процессов
        local processes=$(find_all_mailru_processes)
        
        if [ -z "$processes" ]; then
            if [ "$current_pid" -ne 0 ]; then
                log_message "Все процессы mailrucloud завершены"
                send_notification "✅ Mail.ru Cloud Monitor" "Все синхронизации завершены" "dialog-positive"
                current_pid=0
                rm -f "$STATE_FILE" /tmp/mailru_total_*.tmp
            fi
            sleep $CHECK_INTERVAL
            continue
        fi
        
        # Выбираем самый новый процесс (с наибольшим PID)
        local latest_process=$(echo "$processes" | sort -t: -k1 -n | tail -1)
        local process_info=$(parse_process_info "$latest_process")
        local new_pid=$(echo "$process_info" | cut -d'|' -f1)
        local source_dir=$(echo "$process_info" | cut -d'|' -f2)
        local target_dir=$(echo "$process_info" | cut -d'|' -f3)
        
        # Если процесс сменился
        if [ "$new_pid" != "$current_pid" ]; then
            if [ "$current_pid" -ne 0 ]; then
                log_message "Переключение с процесса $current_pid на $new_pid"
                send_notification "🔄 Mail.ru Cloud Monitor" "Переключение на новую синхронизацию\n📁 $(basename "$source_dir")"
            fi
            current_pid=$new_pid
            # Сбрасываем состояние для нового процесса
            save_state "$current_pid" 0 0 "$source_dir" "$target_dir"
        fi
        
        # Мониторим текущий процесс
        if ! monitor_process "$current_pid" "$source_dir" "$target_dir"; then
            # Процесс завершился
            local final_progress=$(get_process_progress "$current_pid" "$source_dir")
            send_notification "✅ Mail.ru Cloud Sync" \
                "Синхронизация завершена!\n📁 $(basename "$source_dir")\n📊 $final_progress" \
                "dialog-positive"
            log_message "Процесс $current_pid завершён: $final_progress"
            current_pid=0
            rm -f "/tmp/mailru_total_${current_pid}.tmp"
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# Функция показа текущего состояния
show_status() {
    local processes=$(find_all_mailru_processes)
    
    if [ -z "$processes" ]; then
        echo "Активные процессы mailrucloud не найдены"
        return 1
    fi
    
    echo "Активные процессы mailrucloud sync:"
    echo "================================="
    
    local count=1
    echo "$processes" | while read process_line; do
        local process_info=$(parse_process_info "$process_line")
        local pid=$(echo "$process_info" | cut -d'|' -f1)
        local source_dir=$(echo "$process_info" | cut -d'|' -f2)
        local target_dir=$(echo "$process_info" | cut -d'|' -f3)
        
        local progress=$(get_process_progress "$pid" "$source_dir")
        local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')
        local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | tr -d ' ')
        
        echo "$count. PID: $pid"
        echo "   Прогресс: $progress"
        echo "   Ресурсы: CPU ${cpu_usage}%, RAM ${mem_usage}%"
        echo "   Путь: $source_dir → $target_dir"
        echo ""
        
        count=$((count + 1))
    done
    
    # Показываем последние записи прогресса
    if [ -f "$PROGRESS_LOG" ]; then
        echo "Последние обновления:"
        tail -n 5 "$PROGRESS_LOG"
    fi
}

# Функция показа справки
show_help() {
    echo "Использование: $0 [КОМАНДА]"
    echo ""
    echo "Команды:"
    echo "  start        - Запустить универсальный мониторинг"
    echo "  status       - Показать статус всех процессов"
    echo "  logs         - Показать логи мониторинга"
    echo "  stop         - Остановить мониторинг"
    echo "  help         - Показать эту справку"
    echo ""
    echo "Особенности:"
    echo "  • Автоматическое обнаружение новых процессов"
    echo "  • Переключение между процессами"
    echo "  • Уведомления каждые 5 минут"
    echo "  • Адаптивный расчет прогресса"
    echo "  • Определение типа синхронизируемых данных"
}

# Функция остановки мониторинга
stop_monitor() {
    local monitor_pids=$(ps aux | grep mailru-universal-monitor | grep -v grep | awk '{print $2}')
    
    if [ -n "$monitor_pids" ]; then
        echo "$monitor_pids" | xargs kill 2>/dev/null
        log_message "Универсальный мониторинг остановлен"
        send_notification "⏹️ Mail.ru Cloud Monitor" "Мониторинг остановлен"
        echo "Мониторинг остановлен"
    else
        echo "Активный мониторинг не найден"
    fi
}

# Основная логика
case "${1:-help}" in
    start)
        main_monitor_loop
        ;;
    status)
        show_status
        ;;
    logs)
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
    stop)
        stop_monitor
        ;;
    help|*)
        show_help
        ;;
esac 
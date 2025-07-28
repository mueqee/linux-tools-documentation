#!/bin/bash

# Улучшенный трекер прогресса для mailrucloud sync
# Автор: liiilia
# Дата: 2025-07-29

set -e

# Конфигурация
MAILRU_LOG_DIR="$HOME/.local/share/mailrucloud"
TEMP_LOG="/tmp/mailru_current_session.log"
PROGRESS_FILE="/tmp/mailru_progress.json"

# Функция для создания JSON с прогрессом
create_progress_json() {
    local uploaded="$1"
    local total="$2"
    local percentage="$3"
    local current_file="$4"
    local speed="$5"
    
    cat > "$PROGRESS_FILE" << EOF
{
    "uploaded": ${uploaded:-0},
    "total": ${total:-0},
    "percentage": ${percentage:-0},
    "current_file": "${current_file:-}",
    "speed": "${speed:-}",
    "timestamp": $(date +%s)
}
EOF
}

# Функция для парсинга детального прогресса
parse_detailed_progress() {
    local log_file="$1"
    local uploaded_files=0
    local total_files=0
    local percentage=0
    local current_file=""
    local upload_speed=""
    
    if [ ! -f "$log_file" ]; then
        create_progress_json 0 0 0 "Лог не найден" ""
        echo "0/0 0% (лог не найден)"
        return
    fi
    
    local recent_content=$(tail -n 50 "$log_file")
    
    # Поиск общего количества файлов
    total_files=$(echo "$recent_content" | grep -o "Found [0-9]\+ files to upload\|Found [0-9]\+ files" | head -1 | grep -o "[0-9]\+" | head -1)
    if [ -z "$total_files" ]; then
        total_files=$(echo "$recent_content" | grep -o "Найдено [0-9]\+ файлов" | head -1 | grep -o "[0-9]\+")
    fi
    
    # Поиск загруженных файлов через различные паттерны
    # Паттерн 1: "Uploaded X/Y files"
    local upload_progress=$(echo "$recent_content" | grep -o "Uploaded [0-9]\+/[0-9]\+ files\|Загружено [0-9]\+/[0-9]\+ файлов" | tail -1)
    if [ -n "$upload_progress" ]; then
        uploaded_files=$(echo "$upload_progress" | grep -o "[0-9]\+" | head -1)
        total_files=$(echo "$upload_progress" | grep -o "[0-9]\+" | tail -1)
    fi
    
    # Паттерн 2: "Uploaded X files"
    if [ -z "$uploaded_files" ] || [ "$uploaded_files" -eq 0 ]; then
        uploaded_files=$(echo "$recent_content" | grep -o "Uploaded [0-9]\+ files\|Загружено [0-9]\+ файлов" | tail -1 | grep -o "[0-9]\+")
    fi
    
    # Паттерн 3: Подсчет строк с успешной загрузкой
    if [ -z "$uploaded_files" ] || [ "$uploaded_files" -eq 0 ]; then
        uploaded_files=$(echo "$recent_content" | grep -c "✓\|√\|uploaded\|→\|UPLOADED\|SUCCESS")
    fi
    
    # Поиск текущего загружаемого файла
    current_file=$(echo "$recent_content" | grep -o "Uploading.*\|Загрузка.*" | tail -1 | sed 's/Uploading //; s/Загрузка //')
    if [ -z "$current_file" ]; then
        current_file=$(echo "$recent_content" | grep "→" | tail -1 | awk -F'→' '{print $1}' | sed 's/^[[:space:]]*//')
    fi
    
    # Поиск скорости загрузки
    upload_speed=$(echo "$recent_content" | grep -o "[0-9]\+\.[0-9]\+ MB/s\|[0-9]\+ KB/s\|[0-9]\+ B/s" | tail -1)
    
    # Поиск готового процента
    percentage=$(echo "$recent_content" | grep -o "[0-9]\+%" | tail -1 | grep -o "[0-9]\+")
    
    # Вычисление процента если данные есть
    if [ -z "$percentage" ] && [ -n "$total_files" ] && [ "$total_files" -gt 0 ] && [ -n "$uploaded_files" ]; then
        percentage=$((uploaded_files * 100 / total_files))
    fi
    
    # Обеспечиваем числовые значения
    uploaded_files=${uploaded_files:-0}
    total_files=${total_files:-0}
    percentage=${percentage:-0}
    
    # Создаем JSON с прогрессом
    create_progress_json "$uploaded_files" "$total_files" "$percentage" "$current_file" "$upload_speed"
    
    # Формируем вывод
    local output=""
    if [ "$total_files" -gt 0 ]; then
        output="${uploaded_files}/${total_files} ${percentage}%"
        if [ -n "$upload_speed" ]; then
            output="$output ($upload_speed)"
        fi
        if [ -n "$current_file" ] && [ ${#current_file} -lt 50 ]; then
            output="$output - $(basename "$current_file")"
        fi
    elif [ "$uploaded_files" -gt 0 ]; then
        output="Загружено: ${uploaded_files}"
        if [ -n "$upload_speed" ]; then
            output="$output ($upload_speed)"
        fi
    elif [ -n "$current_file" ]; then
        output="Загрузка: $(basename "$current_file")"
        if [ -n "$upload_speed" ]; then
            output="$output ($upload_speed)"
        fi
    else
        output="Анализ файлов..."
    fi
    
    echo "$output"
}

# Функция для поиска активного лог-файла mailrucloud
find_active_log() {
    local mailru_pid=$(ps aux | grep mailrucloud | grep -v grep | grep sync | awk '{print $2}' | head -1)
    
    if [ -z "$mailru_pid" ]; then
        echo ""
        return 1
    fi
    
    # Проверяем открытые файлы процесса
    local log_files=$(lsof -p "$mailru_pid" 2>/dev/null | grep -E "\.log$|stdout|stderr" | awk '{print $9}' | grep -v "^$")
    
    # Ищем в стандартных местах
    if [ -z "$log_files" ]; then
        for log_path in \
            "/tmp/mailru_sync_status.txt" \
            "$HOME/.mailrucloud/sync.log" \
            "$MAILRU_LOG_DIR/sync.log" \
            "$HOME/.local/share/mailrucloud/logs/sync.log" \
            "/tmp/mailrucloud_$mailru_pid.log"; do
            if [ -f "$log_path" ]; then
                echo "$log_path"
                return 0
            fi
        done
    else
        echo "$log_files" | head -1
        return 0
    fi
    
    echo ""
    return 1
}

# Функция непрерывного мониторинга
continuous_monitor() {
    local refresh_interval=${1:-5}  # секунды между обновлениями
    
    echo "Запуск непрерывного мониторинга (обновление каждые ${refresh_interval}s, Ctrl+C для выхода)..."
    echo "==============================================================================="
    
    while true; do
        local log_file=$(find_active_log)
        local timestamp=$(date '+%H:%M:%S')
        
        if [ -n "$log_file" ]; then
            local progress=$(parse_detailed_progress "$log_file")
            printf "\r[%s] %s                                                    " "$timestamp" "$progress"
        else
            printf "\r[%s] Процесс mailrucloud не найден                                  " "$timestamp"
        fi
        
        sleep "$refresh_interval"
    done
}

# Функция однократной проверки
single_check() {
    local log_file=$(find_active_log)
    
    if [ -n "$log_file" ]; then
        parse_detailed_progress "$log_file"
        
        # Показываем дополнительную информацию если запрошено
        if [ "$1" = "--verbose" ] || [ "$1" = "-v" ]; then
            echo ""
            echo "Лог файл: $log_file"
            if [ -f "$PROGRESS_FILE" ]; then
                echo "JSON прогресс:"
                cat "$PROGRESS_FILE" | jq . 2>/dev/null || cat "$PROGRESS_FILE"
            fi
        fi
    else
        echo "Активный процесс mailrucloud sync не найден"
        return 1
    fi
}

# Функция показа справки
show_help() {
    echo "Использование: $0 [КОМАНДА] [ОПЦИИ]"
    echo ""
    echo "Команды:"
    echo "  check              - Однократная проверка прогресса"
    echo "  monitor [секунды]  - Непрерывный мониторинг (по умолчанию: каждые 5 сек)"
    echo "  json               - Вывод прогресса в JSON формате"
    echo "  help               - Показать эту справку"
    echo ""
    echo "Опции:"
    echo "  -v, --verbose      - Подробный вывод"
    echo ""
    echo "Примеры:"
    echo "  $0 check           # Проверить текущий прогресс"
    echo "  $0 check -v        # Подробная информация"
    echo "  $0 monitor         # Мониторинг каждые 5 секунд"
    echo "  $0 monitor 3       # Мониторинг каждые 3 секунды"
    echo "  $0 json            # JSON формат для интеграции"
}

# Основная логика
case "${1:-check}" in
    check)
        single_check "$2"
        ;;
    monitor)
        continuous_monitor "${2:-5}"
        ;;
    json)
        single_check > /dev/null
        if [ -f "$PROGRESS_FILE" ]; then
            cat "$PROGRESS_FILE"
        else
            echo '{"error": "No progress data available"}'
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Неизвестная команда: $1"
        echo "Используйте '$0 help' для справки"
        exit 1
        ;;
esac 
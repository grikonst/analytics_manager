#!/bin/bash
# Система управления видеопотоками и аналитикой v5.5.5
# Функция для безопасного завершения
cleanup() {
    echo "🛑 Завершение работы..."
    # Останавливаем все фоновые процессы
    for pid in "${BG_RECORD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        fi
    done
    # Останавливаем StreamRecorder если он запущен
    if [[ "$STREAM_RECORDER_RUNNING" == "true" ]]; then
        echo "🛑 Останавливаем StreamRecorder..."
        stop_stream_recorder
    fi
    exit 0
}
# Обработка сигналов прерывания
trap cleanup SIGINT SIGTERM
# Глобальные массивы для управления фоновыми процессами
declare -a BG_RECORD_PIDS=()
declare -A BG_RECORD_INFO=()  # Хранение информации о фоновых процессах
declare -g STREAM_RECORDER_RUNNING="false"
# Запрос пароля
echo -n "🔑 Введите пароль: "
read -rs password
echo
# Проверка пароля (sha256 от "password123")
if ! echo "$password" | sha256sum --check --status <(echo "a840c539c75b6c9123eb72ee2d6599ef56a8b726230ee69e52efe1d3020c6331  -") 2>/dev/null; then
    echo "❌ Неверный пароль. Доступ запрещен."
    exit 1
fi
echo "✅ Авторизация успешна!"
sleep 1
# Реорганизованная конфигурация
CONFIG_DIR="$HOME/.stream_manager"
AGENTS_DIR="$CONFIG_DIR/agents"
SCANNER_DIR="$AGENTS_DIR/scanner"
BAGS_DIR="$AGENTS_DIR/bags"
RELEASES_DIR="$AGENTS_DIR/releases"
RECORDER_DIR="$CONFIG_DIR/recorder"
CONFIG_FILE="$CONFIG_DIR/config"
TEMPLATE_FILE="$CONFIG_DIR/template_req.json"
TEMPLATE_CONFIG_FILE="$CONFIG_DIR/template.conf"
SCANNER_CONFIG_FILE="$SCANNER_DIR/scanner.conf"
BAGS_CONFIG_FILE="$BAGS_DIR/bags.conf"
ANALYSIS_CONFIG_FILE="$CONFIG_DIR/analysis.conf"
LOGS_CONFIG_FILE="$CONFIG_DIR/logs.conf"
RECORDER_CONFIG_FILE="$RECORDER_DIR/docker-compose.yml"
YUCCA_CONFIG_FILE="$RECORDER_DIR/yucca.toml"
HISTORY_FILE="$CONFIG_DIR/camera_history.txt"
CAMS_LIST_DIR="$CONFIG_DIR/cams_list"
REPORT_DIR="$CONFIG_DIR/reports"
LOGS_DIR="$CONFIG_DIR/logs_archive"
RECORDS_DIR="$CONFIG_DIR/records"
FRAMES_DIR="$CONFIG_DIR/frames"
# Переменные по умолчанию
DEFAULT_ACCOUNT_ID="00000000-0000-4000-b000-000000000146"
DEFAULT_API_URL="http://127.0.0.1:5230/2/streams"
DEFAULT_HOST_IP="127.0.0.1"
ACCOUNT_ID="$DEFAULT_ACCOUNT_ID"
API_URL="$DEFAULT_API_URL"
HOST_IP="$DEFAULT_HOST_IP"
# Диагностика - настройки по умолчанию
ANALYSIS_TIMEOUT=15
DEFAULT_CAMERAS_FILE="$CAMS_LIST_DIR/cams.list"
# Настройки логов по умолчанию
DEFAULT_LOG_HOURS="6h"
LOG_RETENTION_DAYS=7
# Framer настройки
DEFAULT_CAMS_LIST="$CAMS_LIST_DIR/cams.list"
# StreamRecorder настройки
DEFAULT_RECORDER_PORT_WEB="9910"
DEFAULT_RECORDER_PORT_TELEMETRY="9912"
DEFAULT_RECORDER_PORT_SMTP="1025"
DEFAULT_RECORDER_IMAGE="yuccastream/yucca:latest"
DEFAULT_RECORDER_DATA_DIR="$RECORDER_DIR/yucca_data"
DEFAULT_RECORDER_FFMPEG_DIR="$RECORDER_DIR/yucca_ffmpeg"
# Определяем TUI команду заранее
TUI_CMD=""
# Увеличенные размеры TUI окон
TUI_HEIGHT=35
TUI_WIDTH=85
MENU_HEIGHT=25
PROGRESS_HEIGHT=15
INPUT_HEIGHT=16
MSG_HEIGHT=30
# Глобальные переменные для управления потоками
SELECTED_STREAMS=()
declare -g STREAM_CACHE=""
declare -gi STREAM_CACHE_TIMESTAMP=0
CACHE_TIMEOUT=300
# Шаблоны аналитики
declare -g TEMPLATE_PEOPLE_ANALYTICS TEMPLATE_FACECOVER_ANALYTICS TEMPLATE_WEAPON_ANALYTICS \
           TEMPLATE_FIGHTS_ANALYTICS TEMPLATE_FIRE_ANALYTICS TEMPLATE_BAGS_ANALYTICS \
           TEMPLATE_HANDSUP_ANALYTICS TEMPLATE_LYINGDOWN_ANALYTICS
TEMPLATE_PEOPLE_ANALYTICS='{
  "analytic_name": "people_count",
  "parameters": {
    "parameters": {
      "image_retain_policy": {
        "max_size": 5640
      },
      "event_policy": {
        "trigger": "start"
      },
      "rate": {
        "unit": "frame",
        "period": 1
      },
      "probe_count": 3
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      }
    ],
    "targets": [
      "people_count",
      "overview"
    ]
  }
}'
TEMPLATE_FACECOVER_ANALYTICS='{
  "analytic_name": "facecover_analytics",
  "parameters": {
    "parameters": {
      "facecover_threshold": 0.8,
      "min_body_detection_size": 200,
      "timeout_interval": 100,
      "image_retain_policy": {
        "max_size": 5640
      },
      "event_policy": {
        "trigger": "end"
      },
      "time_filter": {
        "type": "median",
        "length": 4
      },
      "rate": {
        "unit": "second",
        "period": 0.1
      }
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      },
      {
        "type": "luna-event",
        "enable": 1
      }
    ],
    "targets": [
      "facecover",
      "overview"
    ]
  }
}'
TEMPLATE_WEAPON_ANALYTICS='{
  "analytic_name": "weapon_analytics",
  "parameters": {
    "parameters": {
      "weapon_threshold": 0.75,
      "min_body_detection_size": 200,
      "timeout_interval": 100,
      "image_retain_policy": {
        "max_size": 5640
      },
      "event_policy": {
        "trigger": "start"
      },
      "rate": {
        "period": 0.1,
        "unit": "second"
      },
      "time_filter": {
        "type": "median",
        "length": 4
      }
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      },
      {
        "type": "luna-event"
      }
    ],
    "targets": [
      "weapon",
      "overview"
    ]
  }
}'
TEMPLATE_FIGHTS_ANALYTICS='{
  "analytic_name": "fights_analytics",
  "parameters": {
    "parameters": {
      "fight_threshold": 0.97,
      "image_retain_policy": {
        "max_size": 5640
      },
      "event_policy": {
        "trigger": "start"
      },
      "rate": {
        "period": 0.066,
        "unit": "second"
      },
      "probe_count": 20
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      },
      {
        "type": "luna-event"
      }
    ],
    "targets": [
      "fight",
      "overview"
    ]
  }
}'
TEMPLATE_FIRE_ANALYTICS='{
  "analytic_name": "fire_analytics",
  "parameters": {
    "parameters": {
      "fire_threshold": 0.75,
      "image_retain_policy": {
        "max_size": 5640
      },
      "event_policy": {
        "trigger": "start"
      },
      "rate": {
        "period": 1,
        "unit": "second"
      },
      "probe_count": 5
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      },
      {
        "type": "luna-event"
      }
    ],
    "targets": [
      "fire",
      "overview"
    ]
  }
}'
TEMPLATE_BAGS_ANALYTICS='{
  "analytic_name": "bags_analytics",
  "parameters": {
    "parameters": {
      "event_policy": {
        "trigger": "start"
      },
      "image_retain_policy": {
        "mimetype": "JPEG",
        "quality": 0,
        "max_size": 5640
      },
      "rate": {
        "unit": "second",
        "period": 7
      },
      "rate_large": {
        "unit": "second",
        "period": 50
      },
      "bag_confidence_trh_small": 0.1,
      "bag_confidence_trh_large": 0.1,
      "area_trh": 450,
      "probe_count": 0,
      "min_lenght_lost": 70,
      "iou_static_trh": 0.8,
      "human_bbox_expand_coeff":0.25,
      "human_intersection_num_frames_trh": 5,
      "human_intersection_new_range_trh": 10
    },
    "targets": [
      "overview"
    ],
    "callbacks": [
      {
        "type": "luna-ws-notification"
      },
      {
        "type": "luna-event",
        "enable": 1
      }
    ]
  }
}'
TEMPLATE_HANDSUP_ANALYTICS='{
  "analytic_name": "handsup_analytics",
  "parameters": {
    "targets": [
      "overview",
      "handsup"
    ],
    "parameters": {
      "image_retain_policy": {
        "mimetype": "PNG",
        "quality": 0.5,
        "max_size": 1270
      },
      "rate": {"period": 0.25, "unit": "second"},
      "handsup_threshold": 0.7,
      "time_filter": {"type": "median", "length": 1}
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      }
    ]
  }
}'
TEMPLATE_LYINGDOWN_ANALYTICS='{
  "analytic_name": "lying_down_analytics",
  "parameters": {
    "targets": [
      "overview",
      "lying_down"
    ],
    "parameters": {
      "image_retain_policy": {
        "mimetype": "JPEG",
        "quality": 0.8,
        "max_size": 2048
      },
      "rate": {"period": 0.5, "unit": "second"},
      "lying_down_threshold": 0.65,
      "min_body_detection_size": 150,
      "timeout_interval": 120,
      "event_policy": {
        "trigger": "start",
        "min_duration": 5
      },
      "time_filter": {"type": "median", "length": 3},
      "area_of_interest": {
        "x": 0,
        "y": 0,
        "width": 100,
        "height": 100,
        "mode": "percent"
      }
    },
    "callbacks": [
      {
        "type": "luna-ws-notification"
      },
      {
        "type": "luna-event",
        "enable": 1
      }
    ]
  }
}'
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
ACCOUNT_ID="$ACCOUNT_ID"
API_URL="$API_URL"
HOST_IP="$HOST_IP"
EOF
}
save_template_config() {
    mkdir -p "$(dirname "$TEMPLATE_CONFIG_FILE")"
    cat > "$TEMPLATE_CONFIG_FILE" << EOF
WEAPON_ANALYTICS_ENABLED="$WEAPON_ANALYTICS_ENABLED"
FIGHTS_ANALYTICS_ENABLED="$FIGHTS_ANALYTICS_ENABLED"
FIRE_ANALYTICS_ENABLED="$FIRE_ANALYTICS_ENABLED"
PEOPLE_ANALYTICS_ENABLED="$PEOPLE_ANALYTICS_ENABLED"
FACECOVER_ANALYTICS_ENABLED="$FACECOVER_ANALYTICS_ENABLED"
BAGS_ANALYTICS_ENABLED="$BAGS_ANALYTICS_ENABLED"
HANDSUP_ANALYTICS_ENABLED="$HANDSUP_ANALYTICS_ENABLED"
LYINGDOWN_ANALYTICS_ENABLED="$LYINGDOWN_ANALYTICS_ENABLED"
EOF
}
save_scanner_config() {
    mkdir -p "$SCANNER_DIR"
    cat > "$SCANNER_CONFIG_FILE" << EOF
SCANNER_TAG="$SCANNER_TAG"
SCANNER_INSTANCES="$SCANNER_INSTANCES"
DOCKER_REGISTRY="$DOCKER_REGISTRY"
CONFIGURATOR_HOST="$CONFIGURATOR_HOST"
CONFIGURATOR_PORT="$CONFIGURATOR_PORT"
SCANNER_PORT_START="$SCANNER_PORT_START"
WORKER_COUNT="$WORKER_COUNT"
SCANNER_USE_GPU="$SCANNER_USE_GPU"
EOF
}
save_bags_config() {
    mkdir -p "$BAGS_DIR"
    cat > "$BAGS_CONFIG_FILE" << EOF
BAGS_TAG="$BAGS_TAG"
BAGS_INSTANCES="$BAGS_INSTANCES"
DOCKER_REGISTRY="$DOCKER_REGISTRY"
CONFIGURATOR_HOST="$CONFIGURATOR_HOST"
CONFIGURATOR_PORT="$CONFIGURATOR_PORT"
BAGS_PORT_START="$BAGS_PORT_START"
WORKER_COUNT="$WORKER_COUNT"
BAGS_USE_GPU="$BAGS_USE_GPU"
EOF
}
save_analysis_config() {
    mkdir -p "$(dirname "$ANALYSIS_CONFIG_FILE")"
    cat > "$ANALYSIS_CONFIG_FILE" << EOF
ANALYSIS_TIMEOUT="$ANALYSIS_TIMEOUT"
DEFAULT_CAMERAS_FILE="$DEFAULT_CAMERAS_FILE"
EOF
}
save_logs_config() {
    mkdir -p "$(dirname "$LOGS_CONFIG_FILE")"
    cat > "$LOGS_CONFIG_FILE" << EOF
LOGS_DIR="$LOGS_DIR"
DEFAULT_LOG_HOURS="$DEFAULT_LOG_HOURS"
LOG_RETENTION_DAYS="$LOG_RETENTION_DAYS"
EOF
}
init_recorder_config() {
    mkdir -p "$RECORDER_DIR"
    
    # Создаем docker-compose.yml для StreamRecorder если не существует
    if [[ ! -f "$RECORDER_CONFIG_FILE" ]]; then
        cat > "$RECORDER_CONFIG_FILE" << EOF
networks:
  recoder_network:
services:
  recorder:
    image: yuccastream/yucca:latest
    container_name: recorder
    restart: always
    shm_size: "512mb"
    volumes:
      - "/etc/localtime:/etc/localtime:ro"
      - "./yucca_data:/opt/yucca/data"  # Основные данные
      - "./yucca.toml:/opt/yucca/yucca.toml:ro"
      - "./yucca_ffmpeg:/opt/yucca/ffmpeg"
    networks:
      - recoder_network
    ports:
      - "${DEFAULT_RECORDER_PORT_WEB}:9910" # Web UI
      - "${DEFAULT_RECORDER_PORT_TELEMETRY}:9912" # Telemetry
      - "${DEFAULT_RECORDER_PORT_SMTP}:1025" # SMTP server
    environment:
      - TZ=\${TZ:-Europe/Moscow}  # Значение по умолчанию
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
EOF
        echo "📝 Создан конфигурационный файл docker-compose.yml для StreamRecorder"
    fi
    
    # Создаем yucca.toml если не существует
    if [[ ! -f "$YUCCA_CONFIG_FILE" ]]; then
        cat > "$YUCCA_CONFIG_FILE" << EOF
[analytics.yandex_metrika]
counter_id = 0
webvisor = false
[branding]
app_logo = "https://docs.visionlabs.ru/logo.png"  # Укажите свой путь
app_title = "Arena-V1sionLabs"
site = "http://${HOST_IP}:8080"
[cookie]
lifetime = "720h"
[security]
audit_logs = true
brute_force_login_protection = true
[telemetry]
path = "/metrics"
[server]
log_level = "info"
EOF
        echo "📝 Создан конфигурационный файл yucca.toml"
    fi
    
    # Создаем директории для данных
    mkdir -p "$DEFAULT_RECORDER_DATA_DIR"
    mkdir -p "$DEFAULT_RECORDER_FFMPEG_DIR"
    
    echo "✅ Конфигурация StreamRecorder инициализирована в $RECORDER_DIR"
}
start_stream_recorder() {
    echo "🚀 Запуск StreamRecorder..."
    
    # Проверяем, запущен ли уже recorder
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
        show_message "ℹ️  Информация" "✅ StreamRecorder уже запущен"
        STREAM_RECORDER_RUNNING="true"
        return 0
    fi
    
    # Инициализируем конфигурацию если нужно
    init_recorder_config
    
    # Переходим в директорию с конфигурацией
    pushd "$RECORDER_DIR" > /dev/null 2>&1
    
    show_message "🚀 Запуск StreamRecorder" "Запускаем StreamRecorder...\n\n⏳ Это может занять несколько секунд."
    
    if docker-compose up -d 2>&1 | tee /tmp/recorder_start.log; then
        # Даем контейнеру время на запуск
        sleep 5
        
        # Проверяем статус
        if docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -q "recorder"; then
            local container_status
            container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "recorder" | awk '{print $2}')
            
            STREAM_RECORDER_RUNNING="true"
            
            local web_url="http://${HOST_IP}:${DEFAULT_RECORDER_PORT_WEB}"
            
            local result_message="✅ STREAMRECORDER УСПЕШНО ЗАПУЩЕН!\n\n"
            result_message+="📊 Статус: $container_status\n"
            result_message+="🌐 Веб-интерфейс: $web_url\n"
            result_message+="📁 Директория конфигурации: $RECORDER_DIR\n"
            result_message+="📁 Данные: $DEFAULT_RECORDER_DATA_DIR\n\n"
            result_message+="💡 Для входа в веб-интерфейс откройте в браузере:\n$web_url\n\n"
            result_message+="🚀 StreamRecorder готов, перейдите в веб-интерфейс, добавить видеопотоки"
            
            show_message "🎉 StreamRecorder запущен" "$result_message" 25 90
            echo "✅ StreamRecorder запущен. Веб-интерфейс доступен по адресу: $web_url"
        else
            show_message "❌ Ошибка" "Контейнер StreamRecorder не запустился. Проверьте логи."
            STREAM_RECORDER_RUNNING="false"
            popd > /dev/null 2>&1
            return 1
        fi
    else
        show_message "❌ Ошибка" "Не удалось запустить StreamRecorder. Проверьте установлен ли docker-compose."
        STREAM_RECORDER_RUNNING="false"
        popd > /dev/null 2>&1
        return 1
    fi
    
    popd > /dev/null 2>&1
    return 0
}
stop_stream_recorder() {
    echo "🛑 Остановка StreamRecorder..."
    
    # Переходим в директорию с конфигурацией
    pushd "$RECORDER_DIR" > /dev/null 2>&1
    
    if docker-compose down 2>&1 | tee /tmp/recorder_stop.log; then
        STREAM_RECORDER_RUNNING="false"
        show_message "✅ StreamRecorder остановлен" "StreamRecorder успешно остановлен и удален."
        echo "✅ StreamRecorder остановлен"
    else
        show_message "❌ Ошибка" "Не удалось остановить StreamRecorder. Попробуйте остановить вручную: docker rm -f recorder"
        popd > /dev/null 2>&1
        return 1
    fi
    
    popd > /dev/null 2>&1
    return 0
}
show_stream_recorder_status() {
    local status_info=""
    
    # Проверяем, запущен ли контейнер
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
        local container_status container_ports container_image
        container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "recorder" | awk '{print $2}')
        container_ports=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep "recorder" | awk '{print $2}')
        container_image=$(docker ps --format "table {{.Names}}\t{{.Image}}" | grep "recorder" | awk '{print $2}')
        
        STREAM_RECORDER_RUNNING="true"
        
        status_info+="📊 СТАТУС STREAMRECORDER:\n\n"
        status_info+="✅ Запущен: $container_status\n"
        status_info+="🔌 Портs: $container_ports\n\n"
        
        status_info+="🌐 ВЕБ-ИНТЕРФЕЙС:\n"
        status_info+="• Веб-интерфейс: http://${HOST_IP}:${DEFAULT_RECORDER_PORT_WEB}\n"
        
        status_info+="📁 КОНФИГУРАЦИЯ:\n"
        status_info+="• Директория: $RECORDER_DIR\n"
        status_info+="• Данные: $DEFAULT_RECORDER_DATA_DIR\n"
        
        show_message "📊 Статус StreamRecorder" "$status_info" 20 85
    else
        STREAM_RECORDER_RUNNING="false"
        show_message "📊 Статус StreamRecorder" "❌ StreamRecorder не запущен.\n\nДля запуска используйте соответствующую команду в меню."
    fi
}
restart_stream_recorder() {
    echo "🔄 Перезапуск StreamRecorder..."
    
    if [[ "$STREAM_RECORDER_RUNNING" == "true" ]]; then
        stop_stream_recorder
        sleep 2
    fi
    
    start_stream_recorder
}
view_stream_recorder_logs() {
    echo "📋 Просмотр логов StreamRecorder..."
    
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
        if show_yesno "📋 Просмотр логов" "Показать последние 50 строк логов StreamRecorder?"; then
            docker logs --tail 50 recorder 2>&1 | tee /tmp/recorder_logs.log
            show_message "📋 Логи StreamRecorder" "$(cat /tmp/recorder_logs.log)" 25 90
        fi
    else
        show_message "❌ Ошибка" "StreamRecorder не запущен"
    fi
}
configure_stream_recorder() {
    while true; do
        local recorder_status="❌ Остановлен"
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
            recorder_status="✅ Запущен"
        fi
        
        local choice
        choice=$(show_menu "⚙️  КОНФИГУРАЦИЯ STREAMRECORDER" "Настройка параметров StreamRecorder\n\n📊 Статус: $recorder_status\n\n🔧 Порты • 📁 Директории • ⚙️ Конфигурация" \
            "1" "🔌 Изменить порт веб-интерфейса (сейчас: $DEFAULT_RECORDER_PORT_WEB)" \
#            "2" "📡 Изменить порт телеметрии (сейчас: $DEFAULT_RECORDER_PORT_TELEMETRY)" \
#            "3" "📨 Изменить порт SMTP (сейчас: $DEFAULT_RECORDER_PORT_SMTP)" \
            "4" "🐳 Изменить Docker образ (сейчас: $DEFAULT_RECORDER_IMAGE)" \
            "5" "📁 Изменить директорию данных (сейчас: $DEFAULT_RECORDER_DATA_DIR)" \
#            "6" "📝 Редактировать конфигурацию yucca.toml" \
            "7" "👁️ Просмотр текущей конфигурации" \
            "8" "🔄 Сбросить конфигурацию" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                local new_port
                new_port=$(show_input "🔌 ПОРТ ВЕБ-ИНТЕРФЕЙСА" "Введите новый порт для веб-интерфейса:" "$DEFAULT_RECORDER_PORT_WEB")
                if [[ -n "$new_port" ]] && [[ "$new_port" =~ ^[0-9]+$ ]]; then
                    DEFAULT_RECORDER_PORT_WEB="$new_port"
                    show_message "✅ Успех" "Порт веб-интерфейса изменен на: $DEFAULT_RECORDER_PORT_WEB"
                    init_recorder_config
                else
                    show_message "❌ Ошибка" "Введите корректный номер порта"
                fi
                ;;
            "2")
                local new_port
                new_port=$(show_input "📡 ПОРТ ТЕЛЕМЕТРИИ" "Введите новый порт для телеметрии:" "$DEFAULT_RECORDER_PORT_TELEMETRY")
                if [[ -n "$new_port" ]] && [[ "$new_port" =~ ^[0-9]+$ ]]; then
                    DEFAULT_RECORDER_PORT_TELEMETRY="$new_port"
                    show_message "✅ Успех" "Порт телеметрии изменен на: $DEFAULT_RECORDER_PORT_TELEMETRY"
                    init_recorder_config
                else
                    show_message "❌ Ошибка" "Введите корректный номер порта"
                fi
                ;;
            "3")
                local new_port
                new_port=$(show_input "📨 ПОРТ SMTP" "Введите новый порт для SMTP:" "$DEFAULT_RECORDER_PORT_SMTP")
                if [[ -n "$new_port" ]] && [[ "$new_port" =~ ^[0-9]+$ ]]; then
                    DEFAULT_RECORDER_PORT_SMTP="$new_port"
                    show_message "✅ Успех" "Порт SMTP изменен на: $DEFAULT_RECORDER_PORT_SMTP"
                    init_recorder_config
                else
                    show_message "❌ Ошибка" "Введите корректный номер порта"
                fi
                ;;
            "4")
                local new_image
                new_image=$(show_input "🐳 DOCKER ОБРАЗ" "Введите новый Docker образ:" "$DEFAULT_RECORDER_IMAGE")
                if [[ -n "$new_image" ]]; then
                    DEFAULT_RECORDER_IMAGE="$new_image"
                    show_message "✅ Успех" "Docker образ изменен на: $DEFAULT_RECORDER_IMAGE"
                    init_recorder_config
                fi
                ;;
            "5")
                local new_data_dir
                new_data_dir=$(show_input "📁 ДИРЕКТОРИЯ ДАННЫХ" "Введите новую директорию для данных:" "$DEFAULT_RECORDER_DATA_DIR")
                if [[ -n "$new_data_dir" ]]; then
                    DEFAULT_RECORDER_DATA_DIR="$new_data_dir"
                    mkdir -p "$DEFAULT_RECORDER_DATA_DIR"
                    show_message "✅ Успех" "Директория данных изменена на: $DEFAULT_RECORDER_DATA_DIR"
                    init_recorder_config
                fi
                ;;
            "6")
                if [[ -f "$YUCCA_CONFIG_FILE" ]]; then
                    local editor="${EDITOR:-nano}"
                    if command -v "$editor" &> /dev/null; then
                        $editor "$YUCCA_CONFIG_FILE"
                        show_message "✅ Успех" "Конфигурация yucca.toml отредактирована"
                    else
                        show_message "❌ Ошибка" "Текстовый редактор $editor не найден"
                    fi
                else
                    show_message "❌ Ошибка" "Файл конфигурации не найден"
                fi
                ;;
            "7")
                if [[ -f "$RECORDER_CONFIG_FILE" ]]; then
                    show_message "⚙️ Конфигурация docker-compose.yml" "$(cat "$RECORDER_CONFIG_FILE")" 25 90
                else
                    show_message "❌ Ошибка" "Файл конфигурации не найден"
                fi
                ;;
            "8")
                if show_yesno "🔄 Сброс конфигурации" "Сбросить конфигурацию StreamRecorder к значениям по умолчанию?\n\n⚠️ Все текущие настройки будут потеряны!"; then
                    rm -f "$RECORDER_CONFIG_FILE" "$YUCCA_CONFIG_FILE" 2>/dev/null
                    init_recorder_config
                    show_message "✅ Успех" "Конфигурация StreamRecorder сброшена к значениям по умолчанию"
                fi
                ;;
            "0") break ;;
        esac
    done
}
get_network_info() {
    local network_info=""
    local primary_ip
    primary_ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -1)
    
    if [[ -n "$primary_ip" ]]; then
        network_info+="📡 IP Address: $primary_ip\n"
    else
        network_info+="📡 IP Address: ❌ Недоступно\n"
    fi
    
    local hostname
    hostname=$(hostname 2>/dev/null)
    if [[ -n "$hostname" ]]; then
        network_info+="🏷️  Hostname: $hostname\n"
    else
        network_info+="🏷️  Hostname: ❌ Недоступно\n"
    fi
    
    network_info+="🔌 Сетевые интерфейсы:\n"
    
    if command -v ip >/dev/null 2>&1; then
        local interface_count=0
        while IFS= read -r line; do
            if [[ $interface_count -lt 3 ]]; then
                local interface_name
                interface_name=$(echo "$line" | awk '{print $2}' | tr -d ':')
                local ip_address
                ip_address=$(echo "$line" | awk '{print $4}' | cut -d'/' -f1)
                
                if [[ -n "$interface_name" && "$interface_name" != "lo" && -n "$ip_address" ]]; then
                    network_info+="  📶 $interface_name: $ip_address\n"
                    ((interface_count++))
                fi
            fi
        done < <(ip -o -4 addr show 2>/dev/null | head -10)
        
        if [[ $interface_count -eq 0 ]]; then
            network_info+="  ❌ Интерфейсы не найдены\n"
        fi
    else
        network_info+="  ❌ Команда 'ip' недоступна\n"
    fi
    
    echo -e "$network_info"
}
get_facestream_version() {
    local fs_paths=(
        "/var/lib/fs/fs-current"
        "/var/lib/luna-point/current"
    )
    
    for path in "${fs_paths[@]}"; do
        if [[ -L "$path" ]] || [[ -d "$path" ]]; then
            local real_path
            real_path=$(readlink -f "$path" 2>/dev/null || echo "$path")
            local version
            version=$(basename "$real_path" | grep -oE '_v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/_v//' || \
                     basename "$real_path" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            
            if [[ -n "$version" ]]; then
                echo "$version"
                return 0
            fi
        fi
    done
    
    echo "❌ Недоступно"
    return 1
}
get_agent_releases() {
    echo "📦 Получение релизов агентов аналитики..."
    
    mkdir -p "$RELEASES_DIR"
    
    local scanner_tag="$SCANNER_TAG"
    local bags_tag="$BAGS_TAG"
    local docker_registry="$DOCKER_REGISTRY"
    
    if [[ -z "$scanner_tag" ]] || [[ -z "$bags_tag" ]] || [[ -z "$docker_registry" ]]; then
        show_message "❌ Ошибка" "Не заданы теги или Docker registry в конфигурации"
        return 1
    fi
    
    local images_to_pull=(
        "$docker_registry/agent-scanner-configs:$scanner_tag"
        "$docker_registry/luna-agent-scanner:$scanner_tag"
        "$docker_registry/agent-bags-configs:$bags_tag"
        "$docker_registry/luna-agent-bags:$bags_tag"
    )
    
    local total_images=${#images_to_pull[@]}
    local pulled_count=0
    local failed_count=0
    
    show_message "ℹ️  Информация" "Начинается загрузка Docker образов...\n\n📊 Всего образов: $total_images\n\n🏷️  Теги:\n• Scanner: $scanner_tag\n• Bags: $bags_tag\n\n⏳ Это может занять несколько минут в зависимости от скорости сети."
    
    for image in "${images_to_pull[@]}"; do
        echo "⬇️  Загрузка образа: $image"
        
        if pull_docker_image "$image"; then
            ((pulled_count++))
        else
            ((failed_count++))
        fi
    done
    
    if [[ $pulled_count -eq 0 ]]; then
        show_message "❌ Ошибка" "Не удалось загрузить ни одного образа"
        return 1
    fi
    
    # Получение архивов Docker образов
    local timestamp
    timestamp=$(date +%Y%m%d)
    local releases_subdir="$RELEASES_DIR/$timestamp"
    mkdir -p "$releases_subdir"
    
    local current=0
    local total_archives=4
    
    show_message "📦 Получение архивов" "Создание архивов Docker образов...\n\n📊 Всего архивов: $total_archives\n\n📁 Директория: $releases_subdir"
    
    # 1. Scanner основной образ
    ((current++))
    local scanner_image="$docker_registry/luna-agent-scanner:$scanner_tag"
    local scanner_archive="$releases_subdir/$scanner_tag.tar"
    
    if [[ -n "$TUI_CMD" ]]; then
        show_progress_with_percent "📦 Создание архивов" "Создание архива: $scanner_tag.tar ($current/$total_archives)" "$((current * 100 / total_archives))"
    else
        echo "📦 Создание архива: $scanner_tag.tar ($current/$total_archives)"
    fi
    
    if docker save -o "$scanner_archive" "$scanner_image" 2>&1; then
        local scanner_size
        scanner_size=$(du -h "$scanner_archive" 2>/dev/null | cut -f1 || echo "0")
        echo "✅ Создан архив: $scanner_archive ($scanner_size)"
    else
        echo "❌ Ошибка создания архива: $scanner_archive"
        rm -f "$scanner_archive" 2>/dev/null
    fi
    
    # 2. Scanner configs образ
    ((current++))
    local scanner_configs_image="$docker_registry/agent-scanner-configs:$scanner_tag"
    local scanner_configs_archive="$releases_subdir/configs-$scanner_tag.tar"
    
    if [[ -n "$TUI_CMD" ]]; then
        show_progress_with_percent "📦 Создание архивов" "Создание архива: configs-$scanner_tag.tar ($current/$total_archives)" "$((current * 100 / total_archives))"
    else
        echo "📦 Создание архива: configs-$scanner_tag.tar ($current/$total_archives)"
    fi
    
    if docker save -o "$scanner_configs_archive" "$scanner_configs_image" 2>&1; then
        local scanner_configs_size
        scanner_configs_size=$(du -h "$scanner_configs_archive" 2>/dev/null | cut -f1 || echo "0")
        echo "✅ Создан архив: $scanner_configs_archive ($scanner_configs_size)"
    else
        echo "❌ Ошибка создания архива: $scanner_configs_archive"
        rm -f "$scanner_configs_archive" 2>/dev/null
    fi
    
    # 3. Bags основной образ
    ((current++))
    local bags_image="$docker_registry/luna-agent-bags:$bags_tag"
    local bags_archive="$releases_subdir/$bags_tag.tar"
    
    if [[ -n "$TUI_CMD" ]]; then
        show_progress_with_percent "📦 Создание архивов" "Создание архива: $bags_tag.tar ($current/$total_archives)" "$((current * 100 / total_archives))"
    else
        echo "📦 Создание архива: $bags_tag.tar ($current/$total_archives)"
    fi
    
    if docker save -o "$bags_archive" "$bags_image" 2>&1; then
        local bags_size
        bags_size=$(du -h "$bags_archive" 2>/dev/null | cut -f1 || echo "0")
        echo "✅ Создан архив: $bags_archive ($bags_size)"
    else
        echo "❌ Ошибка создания архива: $bags_archive"
        rm -f "$bags_archive" 2>/dev/null
    fi
    
    # 4. Bags configs образ
    ((current++))
    local bags_configs_image="$docker_registry/agent-bags-configs:$bags_tag"
    local bags_configs_archive="$releases_subdir/configs-$bags_tag.tar"
    
    if [[ -n "$TUI_CMD" ]]; then
        show_progress_with_percent "📦 Создание архивов" "Создание архива: configs-$bags_tag.tar ($current/$total_archives)" "$((current * 100 / total_archives))"
    else
        echo "📦 Создание архива: configs-$bags_tag.tar ($current/$total_archives)"
    fi
    
    if docker save -o "$bags_configs_archive" "$bags_configs_image" 2>&1; then
        local bags_configs_size
        bags_configs_size=$(du -h "$bags_configs_archive" 2>/dev/null | cut -f1 || echo "0")
        echo "✅ Создан архив: $bags_configs_archive ($bags_configs_size)"
    else
        echo "❌ Ошибка создания архива: $bags_configs_archive"
        rm -f "$bags_configs_archive" 2>/dev/null
    fi
    
    # Создание общего сжатого архива
    show_message "🗜️ Сжатие архивов" "Создание общего сжатого архива...\n\n⏳ Это может занять некоторое время в зависимости от размера образов."
    
    local final_archive="$RELEASES_DIR/agents_releases_$timestamp.tar.zst"
    
    if command -v pv >/dev/null 2>&1 && command -v zstdmt >/dev/null 2>&1; then
        # С использованием pv для отображения прогресса
        local total_size
        total_size=$(du -sb "$releases_subdir" 2>/dev/null | cut -f1)
        if [[ -z "$total_size" ]] || [[ "$total_size" -eq 0 ]]; then
            total_size=1000000
        fi
        
        if tar cf - -C "$releases_subdir" . 2>/dev/null | pv -s "$total_size" | zstdmt -3 -T0 -o "$final_archive" 2>&1; then
            local final_size
            final_size=$(du -h "$final_archive" 2>/dev/null | cut -f1 || echo "0")
            
            # Получаем список файлов в архиве
            local archive_contents
            archive_contents=$(zstdmt -dc "$final_archive" 2>/dev/null | tar -tf - 2>/dev/null | head -20 || echo "Не удалось прочитать содержимое архива")
            
            local result_message="✅ РЕЛИЗЫ АГЕНТОВ УСПЕШНО СОЗДАНЫ!\n\n"
            result_message+="📦 Основной архив: $(basename "$final_archive")\n"
            result_message+="📊 Размер: $final_size\n"
            result_message+="📁 Директория: $releases_subdir\n\n"
            result_message+="🏷️  ТЕГИ ОБРАЗОВ:\n"
            result_message+="• Scanner: $scanner_tag\n"
            result_message+="• Bags: $bags_tag\n\n"
            result_message+="📄 СОЗДАННЫЕ АРХИВЫ:\n"
            
            local created_files=()
            for file in "$releases_subdir"/*.tar; do
                if [[ -f "$file" ]]; then
                    local file_size
                    file_size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "0")
                    created_files+=("$(basename "$file") ($file_size)")
                fi
            done
            
            for file_info in "${created_files[@]}"; do
                result_message+="• $file_info\n"
            done
            
            result_message+="\n📋 СОДЕРЖИМОЕ АРХИВА (первые 20 файлов):\n$archive_contents\n\n"
            result_message+="💡 ИНСТРУКЦИЯ ПЕРЕНОСА:\n"
            result_message+="1. Скопируйте архив на целевой хост\n"
            result_message+="2. Распакуйте: zstdmt -dc agents_releases_*.tar.zst | tar -xf -\n"
            result_message+="3. Загрузите образы: docker load -i <имя_архива>.tar"
            
            show_message "🎉 Готово" "$result_message" 30 90
            
            # Записываем информацию о релизе в лог
            local release_log="$RELEASES_DIR/releases.log"
            echo "========================================" >> "$release_log"
            echo "Дата создания: $(date)" >> "$release_log"
            echo "Scanner tag: $scanner_tag" >> "$release_log"
            echo "Bags tag: $bags_tag" >> "$release_log"
            echo "Основной архив: $final_archive ($final_size)" >> "$release_log"
            echo "Созданные файлы:" >> "$release_log"
            for file_info in "${created_files[@]}"; do
                echo "  $file_info" >> "$release_log"
            done
            echo "========================================" >> "$release_log"
            
            return 0
        else
            show_message "❌ Ошибка" "Не удалось создать общий архив"
            return 1
        fi
    else
        # Без pv и zstdmt - используем стандартные инструменты
        echo "ℹ️  PV или ZSTDMT не установлены, используем стандартный tar+gzip"
        
        final_archive="$RELEASES_DIR/agents_releases_$timestamp.tar.gz"
        
        if tar czf "$final_archive" -C "$releases_subdir" . 2>&1; then
            local final_size
            final_size=$(du -h "$final_archive" 2>/dev/null | cut -f1 || echo "0")
            
            local result_message="✅ РЕЛИЗЫ АГЕНТОВ УСПЕШНО СОЗДАНЫ!\n\n"
            result_message+="📦 Основной архив: $(basename "$final_archive")\n"
            result_message+="📊 Размер: $final_size\n"
            result_message+="📁 Директория: $releases_subdir\n\n"
            result_message+="🏷️  ТЕГИ ОБРАЗОВ:\n"
            result_message+="• Scanner: $scanner_tag\n"
            result_message+="• Bags: $bags_tag\n"
            
            show_message "🎉 Готово" "$result_message"
            return 0
        else
            show_message "❌ Ошибка" "Не удалось создать общий архив"
            return 1
        fi
    fi
}
show_system_info_splash() {
    clear
    local system_info=""
    
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "N/A")
    
    local mem_info
    mem_info=$(free -h | awk 'NR==2{printf "%s/%s", $3, $2}')
    
    local disk_info
    disk_info=$(df / | awk 'NR==2{printf "%s", $5}')
    
    local uptime_info
    uptime_info=$(uptime -p | sed 's/up //')
    
    local current_time
    current_time=$(date '+%Y-%m-%d %H:%M')
    
    local active_streams
    active_streams=$(get_active_streams_count)
    
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    
    # Проверяем статус StreamRecorder
    local recorder_status=""
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
        recorder_status="✅ Запущен"
    else
        recorder_status="❌ Остановлен"
    fi
    
    system_info+="═══════════════════════════════════════════════════════════════════════════════\n"
    system_info+="                🎥 Система Управления Камерами Аналитики v5.5.5 🚀              \n"
    system_info+="═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    system_info+="📡 СЕТЕВЫЕ НАСТРОЙКИ:\n"
    system_info+="  🌐 Host IP: ${HOST_IP}\n"
    system_info+="  🔗 LunaAPI: ${API_URL}\n"
    system_info+="  👤 Account ID: ${ACCOUNT_ID}\n\n"
    
    system_info+="⚙️  СИСТЕМНЫЕ РЕСУРСЫ:\n"
    system_info+="  🖥️  CPU: ${cpu_cores} ядер\n"
    system_info+="  💾 Память: ${mem_info}\n"
    system_info+="  💿 Диск: ${disk_info} использовано\n"
    system_info+="  🎮 GPU: ${available_gpus} доступно\n\n"
    
    system_info+="📊 СТАТУС СЕРВИСОВ:\n"
    system_info+="  📹 StreamRecorder: ${recorder_status}\n\n"
    
    system_info+="🕒 СИСТЕМА:\n"
    system_info+="  ⏱️  Время работы: ${uptime_info}\n"
    system_info+="  🕐 Текущее время: ${current_time}\n"
    system_info+="\n═══════════════════════════════════════════════════════════════════════════════\n"
    
    echo -e "$system_info"
    sleep 2
}
get_available_gpu_count() {
    if command -v nvidia-smi &> /dev/null; then
        local gpu_count
        gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "0")
        if [[ "$gpu_count" =~ ^[0-9]+$ ]] && [[ "$gpu_count" -gt 0 ]]; then
            echo "$gpu_count"
            return 0
        fi
    fi
    echo "0"
    return 1
}
check_gpu_availability() {
    local gpu_index="$1"
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi -i "$gpu_index" --query-gpu=count --format=csv,noheader &>/dev/null; then
            return 0
        fi
    fi
    return 1
}
check_docker_image_exists() {
    local image="$1"
    if docker image inspect "$image" &> /dev/null; then
        return 0
    else
        return 1
    fi
}
pull_docker_image() {
    local image="$1"
    echo "⬇️  Загрузка Docker образа: $image"
    
    if [[ "$TUI_CMD" == "dialog" ]]; then
        show_message "⬇️  Загрузка образа" "Начинается загрузка Docker образа:\n$image\n\n⏳ Это может занять несколько минут..."
        
        if docker pull "$image" 2>&1 | tee /tmp/docker_pull.log; then
            if docker image inspect "$image" &> /dev/null; then
                echo "✅ Docker образ успешно загружен: $image"
                return 0
            else
                echo "❌ Не удалось загрузить Docker образ: $image"
                return 1
            fi
        else
            echo "❌ Ошибка при загрузке Docker образа: $image"
            return 1
        fi
    else
        echo "⬇️  Загрузка Docker образа: $image"
        if timeout 300 docker pull "$image"; then
            echo "✅ Docker образ успешно загружен: $image"
            return 0
        else
            echo "❌ Не удалось загрузить Docker образ: $image"
            return 1
        fi
    fi
}
check_gpu_health() {
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    
    if [[ "$available_gpus" -eq 0 ]]; then
        show_message "🎮 Проверка GPU" "❌ NVIDIA GPU не обнаружены\n\nСистема будет использовать CPU для обработки.\n\n💡 Если требуется GPU ускорение, проверьте:\n1. Установлены ли драйверы NVIDIA\n2. Запущен ли nvidia-docker\n3. Доступны ли GPU устройства"
        return 1
    fi
    
    local gpu_info="✅ Обнаружено GPU: $available_gpus\n\n"
    
    for ((i=0; i<available_gpus; i++)); do
        local gpu_name gpu_mem_total gpu_mem_used gpu_util gpu_temp
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader --id=$i 2>/dev/null | head -1 | sed 's/ *$//' || echo "N/A")
        gpu_mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader --id=$i 2>/dev/null | head -1 | sed 's/ MiB//' | tr -d ' ' || echo "N/A")
        gpu_mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader --id=$i 2>/dev/null | head -1 | sed 's/ MiB//' | tr -d ' ' || echo "N/A")
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader --id=$i 2>/dev/null | head -1 | tr -d ' ' || echo "N/A")
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader --id=$i 2>/dev/null | head -1 | tr -d ' ' || echo "N/A")
        
        gpu_info+="🎮 GPU$i: $gpu_name\n"
        gpu_info+="   💾 Память: ${gpu_mem_used}MB / ${gpu_mem_total}MB\n"
        gpu_info+="   📊 Загрузка: ${gpu_util}%, 🌡️ Температура: ${gpu_temp}°C\n"
        
        if [[ "$gpu_temp" != "N/A" ]] && [[ "$gpu_temp" -gt 85 ]]; then
            gpu_info+="   ⚠️  ВНИМАНИЕ: Высокая температура!\n"
        fi
        
        if [[ "$gpu_mem_used" != "N/A" ]] && [[ "$gpu_mem_total" != "N/A" ]]; then
            local mem_usage_percent
            mem_usage_percent=$((gpu_mem_used * 100 / gpu_mem_total))
            if [[ "$mem_usage_percent" -gt 90 ]]; then
                gpu_info+="   ⚠️  ВНИМАНИЕ: Высокая загрузка памяти ($mem_usage_percent%)\n"
            fi
        fi
        
        gpu_info+="\n"
    done
    
    show_message "🎮 Состояние GPU" "$gpu_info"
}
start_scanner_instances() {
    echo "🚀 Запуск инстансов luna-agent-scanner"
    
    echo "🔄 Выполнение миграции базы данных..."
    show_message "🔄 Миграция базы данных" "Выполняется миграция базы данных конфигурации...\n\n⏳ Это может занять несколько секунд."
    
    local migrate_cmd="docker run -v /etc/localtime:/etc/localtime:ro --entrypoint=/bin/bash --rm --network=host $DOCKER_REGISTRY/agent-scanner-configs:$SCANNER_TAG -c \"python3 -m agent_scanner_configs.migrate head --config_db_url postgres://luna:luna@${HOST_IP}:5432/luna_configurator\""
    
    if eval "$migrate_cmd" 2>&1 | tee /tmp/migration.log; then
        echo "✅ Миграция базы данных успешно выполнена"
    else
        local migration_error
        migration_error=$(cat /tmp/migration.log 2>/dev/null || echo "Неизвестная ошибка")
        echo "❌ Ошибка выполнения миграции: $migration_error"
        if ! show_yesno "❌ Ошибка миграции" "Не удалось выполнить миграцию базы данных:\n\n$migration_error\n\nПродолжить запуск Scanner?"; then
            return 1
        fi
    fi
    
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    
    local run_mode="$SCANNER_USE_GPU"
    if [[ "$run_mode" != "true" ]]; then
        run_mode="false"
    fi
    
    local total_instances=$SCANNER_INSTANCES
    local started_count=0
    local failed_count=0
    
    if [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]]; then
        show_message "ℹ️  Информация" "Конфигурация запуска Scanner:\n• 📊 Всего инстансов: $total_instances\n• 🎮 Режим: GPU (требуется)\n• ❌ Доступно GPU: 0\n• ⚠️  ВНИМАНИЕ: GPU не обнаружены, но режим GPU включен!\n\nScanner будет запущен на CPU"
        echo "ℹ️  GPU не обнаружены, но режим GPU включен. Запуск Scanner на CPU"
    elif [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        show_message "ℹ️  Информация" "Конфигурация запуска Scanner (режим GPU):\n• 📊 Всего инстансов: $total_instances\n• ✅ Доступно GPU: $available_gpus\n• 🔄 Распределение: циклическое по всем доступным GPU"
        echo "✅ Обнаружено доступных GPU для Scanner: $available_gpus"
    else
        show_message "ℹ️  Информация" "Конфигурация запуска Scanner (режим CPU):\n• 📊 Всего инстансов: $total_instances\n• 🖥️  Режим: CPU (явно выбран)\n• ⚠️  ВНИМАНИЕ: Для лучшей производительности рекомендуется использовать GPU"
        echo "ℹ️  Запуск Scanner в режиме CPU (явно выбран пользователем)"
    fi
    
    local current=0
    
    for ((i=1; i<=total_instances; i++)); do
        local instance_name="luna-agent-scanner-$i"
        local scanner_port=$((SCANNER_PORT_START + i - 1))
        
        if docker ps --format "table {{.Names}}" | grep -q "$instance_name"; then
            echo "✅ Контейнер $instance_name уже запущен, пропускаем"
            continue
        fi
        
        if netstat -tuln 2>/dev/null | grep -q ":${scanner_port} "; then
            echo "❌ Порт $scanner_port занят, пропускаем инстанс $instance_name"
            ((failed_count++))
            continue
        fi
        
        ((current++))
        
        local docker_cmd="docker run --env=CONFIGURATOR_HOST=$CONFIGURATOR_HOST \
--env=CONFIGURATOR_PORT=$CONFIGURATOR_PORT \
--env=PORT=$scanner_port \
--env=WORKER_COUNT=$WORKER_COUNT \
--env=RELOAD_CONFIG=1 \
--env=RELOAD_CONFIG_INTERVAL=10 \
-v /etc/localtime:/etc/localtime:ro \
--name=$instance_name \
--restart=always \
--detach=true \
--network=host \
$DOCKER_REGISTRY/luna-agent-scanner:$SCANNER_TAG"
        
        if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
            local gpu_device=$(( (i - 1) % available_gpus ))
            
            if check_gpu_availability "$gpu_device"; then
                docker_cmd=$(echo "$docker_cmd" | sed "s/--detach=true/--gpus device=$gpu_device --detach=true/")
                echo "🚀 Запуск: $instance_name на GPU$gpu_device ($current/$total_instances)"
            else
                echo "❌ GPU$gpu_device недоступен, запускаем $instance_name на CPU"
                echo "🚀 Запуск: $instance_name на CPU ($current/$total_instances)"
            fi
        else
            echo "🚀 Запуск: $instance_name на CPU ($current/$total_instances)"
        fi
        
        if eval "$docker_cmd" 2>/dev/null; then
            echo "✅ Успешно запущен $instance_name (порт: $scanner_port)"
            ((started_count++))
            sleep 0.5
        else
            echo "❌ Ошибка запуска $instance_name"
            ((failed_count++))
        fi
    done
    
    local result_message="✅ Запуск инстансов Scanner завершен:\n\n"
    result_message+="✅ Успешно: $started_count\n"
    result_message+="❌ Ошибок: $failed_count\n"
    result_message+="📊 Всего: $total_instances\n\n"
    result_message+="⚙️  Конфигурация:\n"
    result_message+="• 🐳 Docker образ: $DOCKER_REGISTRY/luna-agent-scanner:$SCANNER_TAG\n"
    
    if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        result_message+="• 🎮 Режим: GPU (распределение: циклическое по GPU)\n"
        result_message+="• ✅ Доступно GPU: $available_gpus\n"
        
        result_message+="• 🔄 Распределение инстансов:\n"
        for ((gpu=0; gpu<available_gpus; gpu++)); do
            local instances_on_gpu=0
            for ((i=1; i<=total_instances; i++)); do
                if [[ $(( (i - 1) % available_gpus )) -eq "$gpu" ]]; then
                    ((instances_on_gpu++))
                fi
            done
            result_message+="  🎮 GPU$gpu: $instances_on_gpu инстансов\n"
        done
    elif [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]]; then
        result_message+="• 🎮 Режим: GPU (требуется, но GPU не обнаружены)\n"
        result_message+="• 🖥️  Фактически: запущены на CPU\n"
        result_message+="• ⚠️  ВНИМАНИЕ: Для лучшей производительности рекомендуется использовать GPU\n"
    else
        result_message+="• 🖥️  Режим: CPU (явно выбран пользователем)\n"
        result_message+="• ⚠️  ВНИМАНИЕ: Для лучшей производительности рекомендуется использовать GPU\n"
    fi
    
    result_message+="• 🔌 Порт начала: $SCANNER_PORT_START\n"
    result_message+="• ⚙️  Configurator: $CONFIGURATOR_HOST:$CONFIGURATOR_PORT"
    
    show_message "📊 Результат запуска Scanner" "$result_message"
    
    if [[ "$started_count" -eq 0 ]]; then
        echo "❌ Не удалось запустить ни одного инстанса scanner"
        return 1
    fi
    
    return 0
}
show_scanner_status() {
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    local run_mode="$SCANNER_USE_GPU"
    
    local status_info=""
    local running_count=0
    
    status_info+="📊 Статус инстансов luna-agent-scanner\n\n"
    status_info+="📋 Системная информация:\n"
    
    if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        status_info+="• 🎮 Режим: GPU (распределение: циклическое по GPU)\n"
        status_info+="• ✅ Доступно GPU: $available_gpus\n"
    elif [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]]; then
        status_info+="• 🎮 Режим: GPU (требуется, но GPU не обнаружены)\n"
        status_info+="• 🖥️  Фактически: запущены на CPU\n"
    else
        status_info+="• 🖥️  Режим: CPU (явно выбран)\n"
    fi
    
    status_info+="• 🐳 Docker образ: $DOCKER_REGISTRY/luna-agent-scanner:$SCANNER_TAG\n"
    status_info+="• 📊 Конфигурация инстансов: $SCANNER_INSTANCES\n"
    status_info+="• ⚙️  Configurator: $CONFIGURATOR_HOST:$CONFIGURATOR_PORT\n"
    status_info+="• 🔌 Порт начала: $SCANNER_PORT_START\n\n"
    
    status_info+="🔄 Состояние инстансов:\n"
    
    for ((i=1; i<=SCANNER_INSTANCES; i++)); do
        local instance_name="luna-agent-scanner-$i"
        local scanner_port=$((SCANNER_PORT_START + i - 1))
        
        local device_info
        if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
            local gpu_device=$(( (i - 1) % available_gpus ))
            device_info="GPU$gpu_device"
        else
            device_info="CPU"
        fi
        
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$instance_name"; then
            local container_status
            container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$instance_name" | awk '{print $2}')
            status_info+="✅ $instance_name ($device_info, порт:$scanner_port) - $container_status\n"
            ((running_count++))
        else
            status_info+="❌ $instance_name ($device_info, порт:$scanner_port) - ОСТАНОВЛЕН\n"
        fi
    done
    
    status_info+="\n📊 Всего запущено: $running_count/$SCANNER_INSTANCES"
    
    if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        status_info+="\n\n🎮 Распределение по GPU:\n"
        for ((gpu=0; gpu<available_gpus; gpu++)); do
            local instances_on_gpu=0
            for ((i=1; i<=SCANNER_INSTANCES; i++)); do
                if [[ $(( (i - 1) % available_gpus )) -eq "$gpu" ]]; then
                    ((instances_on_gpu++))
                fi
            done
            status_info+="• 🎮 GPU$gpu: $instances_on_gpu инстансов\n"
        done
    fi
    
    if [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]] && [[ "$running_count" -gt 0 ]]; then
        status_info+="\n\n⚠️  ВНИМАНИЕ: Scanner настроен на GPU, но GPU не обнаружены. Запуск на CPU."
    fi
    
    show_message "📊 Статус агента Scanner" "$status_info" 25 90
}
# ============================================================================
# ФУНКЦИИ УПРАВЛЕНИЯ ЛОГАМИ SCANNER
# ============================================================================
collect_scanner_logs() {
    local hours="$1"
    local selected_instances="$2"
    
    echo "📦 Сбор логов Scanner за $hours"
    
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M")
    local date_dir
    date_dir=$(date +"%Y-%m-%d")
    local logs_date_dir="$LOGS_DIR/$date_dir"
    mkdir -p "$logs_date_dir"
    
    local archive_name="scanner_logs_${timestamp}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    mkdir -p "$temp_dir/scanner"
    
    local instances_to_collect=()
    if [[ "$selected_instances" == "all" ]]; then
        for ((i=1; i<=SCANNER_INSTANCES; i++)); do
            instances_to_collect+=("luna-agent-scanner-$i")
        done
    else
        IFS=',' read -ra instances_to_collect <<< "$selected_instances"
    fi
    
    local total_instances=${#instances_to_collect[@]}
    local processed=0
    
    # Создаем файл для объединенных логов
    local scanner_all_log="$temp_dir/scanner/scanner_all.log"
    echo "=== ОБЪЕДИНЕННЫЙ ЛОГ SCANNER ===" > "$scanner_all_log"
    echo "Время сбора: $(date)" >> "$scanner_all_log"
    echo "Период: $hours" >> "$scanner_all_log"
    echo "=================================" >> "$scanner_all_log"
    echo "" >> "$scanner_all_log"
    
    for instance in "${instances_to_collect[@]}"; do
        ((processed++))
        local percent=$((processed * 100 / total_instances))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "📦 Сбор логов Scanner" "Сбор логов: $instance ($processed/$total_instances)" "$percent"
        else
            echo "📦 Сбор логов: $instance ($processed/$total_instances)"
        fi
        
        local log_file="$temp_dir/scanner/${instance}.log"
        
        if docker ps -a 2>/dev/null | grep -q "$instance"; then
            if docker logs --since "$hours" --timestamps "$instance" > "$log_file" 2>&1; then
                echo "✅ Логи собраны для $instance"
                # Добавляем в объединенный лог
                echo "=== ЛОГ $instance ===" >> "$scanner_all_log"
                echo "" >> "$scanner_all_log"
                cat "$log_file" >> "$scanner_all_log"
                echo "" >> "$scanner_all_log"
                echo "=================================" >> "$scanner_all_log"
                echo "" >> "$scanner_all_log"
            else
                echo "❌ Ошибка сбора логов для $instance"
                echo "❌ Ошибка сбора логов для контейнера $instance" > "$log_file"
            fi
        else
            echo "❌ Контейнер $instance не найден"
            echo "❌ Контейнер $instance не найден или не запущен" > "$log_file"
        fi
    done
    
    if tar -czf "$LOGS_DIR/$archive_name" -C "$temp_dir" .; then
        echo "✅ Архив логов Scanner создан: $archive_name"
        rm -rf "$temp_dir"
        
        local archive_size
        archive_size=$(du -h "$LOGS_DIR/$archive_name" 2>/dev/null | cut -f1 || echo "N/A")
        local archive_info="✅ Архив логов Scanner успешно создан!\n\n"
        archive_info+="📁 Имя файла: $archive_name\n"
        archive_info+="📊 Размер: $archive_size\n"
        archive_info+="⏱️  Период: $hours\n"
        archive_info+="🔧 Инстансы: ${instances_to_collect[*]}\n"
        archive_info+="📁 Путь: $LOGS_DIR/$archive_name"
        
        show_message "✅ Сбор логов Scanner завершен" "$archive_info"
    else
        echo "❌ Ошибка создания архива логов Scanner"
        show_message "❌ Ошибка" "Не удалось создать архив логов Scanner"
        rm -rf "$temp_dir"
        return 1
    fi
}
collect_scanner_logs_screen() {
    local hours
    hours=$(show_input "📦 СБОР ЛОГОВ SCANNER" "Введите период для сбора логов (например: 6h, 1d):" "$DEFAULT_LOG_HOURS")
    [[ -z "$hours" ]] && return
    
    local instances_options=()
    
    for ((i=1; i<=SCANNER_INSTANCES; i++)); do
        instances_options+=("luna-agent-scanner-$i" "Scanner инстанс $i" "OFF")
    done
    
    local selected_instances
    selected_instances=$(show_checklist "📋 ВЫБОР ИНСТАНСОВ SCANNER" "Выберите инстансы Scanner для сбора логов:" "${instances_options[@]}")
    
    if [[ -n "$selected_instances" ]]; then
        selected_instances=$(echo "$selected_instances" | sed 's/"//g')
        
        if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ" "Собрать логи Scanner за период: $hours\n\n🔧 Инстансы:\n$selected_instances"; then
            collect_scanner_logs "$hours" "$selected_instances"
        fi
    else
        show_message "❌ ОТМЕНА" "Сбор логов Scanner отменен"
    fi
}
view_scanner_logs() {
    echo "📋 Просмотр логов Scanner..."
    
    local instances_options=()
    local running_instances=0
    
    for ((i=1; i<=SCANNER_INSTANCES; i++)); do
        local instance_name="luna-agent-scanner-$i"
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "$instance_name"; then
            instances_options+=("$instance_name" "Scanner инстанс $i (✅ запущен)")
            ((running_instances++))
        else
            instances_options+=("$instance_name" "Scanner инстанс $i (❌ остановлен)")
        fi
    done
    
    if [[ $running_instances -eq 0 ]]; then
        show_message "❌ Ошибка" "Нет запущенных инстансов Scanner"
        return
    fi
    
    local selected_instance
    selected_instance=$(show_menu "📋 ВЫБОР ИНСТАНСА SCANNER" "Выберите инстанс Scanner для просмотра логов:" "${instances_options[@]}")
    
    if [[ -n "$selected_instance" ]]; then
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "$selected_instance"; then
            local lines
            lines=$(show_input "📋 ПРОСМОТР ЛОГОВ" "Введите количество строк логов (по умолчанию 50):" "50")
            [[ -z "$lines" ]] && lines=50
            
            docker logs --tail "$lines" "$selected_instance" 2>&1 | tee /tmp/scanner_logs.log
            show_message "📋 Логи $selected_instance" "$(cat /tmp/scanner_logs.log)" 25 90
        else
            show_message "❌ Ошибка" "Инстанс $selected_instance не запущен"
        fi
    fi
}
run_migration() {
    echo "🔄 Запуск миграции базы данных конфигурации"
    
    local migrate_cmd="docker run -v /etc/localtime:/etc/localtime:ro --entrypoint=/bin/bash --rm --network=host $DOCKER_REGISTRY/agent-scanner-configs:$SCANNER_TAG -c \"python3 -m agent_scanner_configs.migrate head --config_db_url postgres://luna:luna@${HOST_IP}:5432/luna_configurator\""
    
    show_message "🔄 Миграция базы данных" "Выполняется миграция базы данных конфигурации...\n\n⏳ Это может занять несколько секунд."
    
    if eval "$migrate_cmd" 2>&1 | tee /tmp/migration.log; then
        echo "✅ Миграция базы данных успешно выполнена"
        show_message "✅ Миграция завершена" "Миграция базы данных успешно выполнена!"
        return 0
    else
        local migration_error
        migration_error=$(cat /tmp/migration.log 2>/dev/null || echo "Неизвестная ошибка")
        echo "❌ Ошибка выполнения миграции: $migration_error"
        show_message "❌ Ошибка миграции" "Не удалось выполнить миграцию базы данных:\n\n$migration_error\n\n🔍 Проверьте:\n• Доступность PostgreSQL\n• Корректность учетных данных\n• Сетевое подключение"
        return 1
    fi
}
select_analytics_before_add() {
    echo "📊 Выбор аналитик для применения к видеопотокам..."
    
    # Сохраняем текущие настройки аналитик
    local current_weapon="$WEAPON_ANALYTICS_ENABLED"
    local current_fights="$FIGHTS_ANALYTICS_ENABLED"
    local current_fire="$FIRE_ANALYTICS_ENABLED"
    local current_people="$PEOPLE_ANALYTICS_ENABLED"
    local current_facecover="$FACECOVER_ANALYTICS_ENABLED"
    local current_bags="$BAGS_ANALYTICS_ENABLED"
    local current_handsup="$HANDSUP_ANALYTICS_ENABLED"
    local current_lyingdown="$LYINGDOWN_ANALYTICS_ENABLED"
    
    # Создаем опции для выбора аналитик
    local analytics_options=()
    
    # Добавляем варианты аналитик
    if [[ "$current_weapon" == "true" ]]; then
        analytics_options+=("weapon" "🔫 Обнаружение оружия (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("weapon" "🔫 Обнаружение оружия" "OFF")
    fi
    
    if [[ "$current_fights" == "true" ]]; then
        analytics_options+=("fights" "🥊 Обнаружение драк (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("fights" "🥊 Обнаружение драк" "OFF")
    fi
    
    if [[ "$current_fire" == "true" ]]; then
        analytics_options+=("fire" "🔥 Обнаружение огня (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("fire" "🔥 Обнаружение огня" "OFF")
    fi
    
    if [[ "$current_facecover" == "true" ]]; then
        analytics_options+=("facecover" "😷 Обнаружение балаклав (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("facecover" "😷 Обнаружение балаклав" "OFF")
    fi
    
    if [[ "$current_people" == "true" ]]; then
        analytics_options+=("people" "👥 Подсчет людей (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("people" "👥 Подсчет людей" "OFF")
    fi
    
    if [[ "$current_bags" == "true" ]]; then
        analytics_options+=("bags" "🎒 Оставленные предметы (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("bags" "🎒 Оставленные предметы" "OFF")
    fi
    
    if [[ "$current_handsup" == "true" ]]; then
        analytics_options+=("handsup" "🙌 Обнаружение рук вверх (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("handsup" "🙌 Обнаружение рук вверх" "OFF")
    fi
    
    if [[ "$current_lyingdown" == "true" ]]; then
        analytics_options+=("lyingdown" "🛌 Обнаружение лежащих людей (ВКЛЮЧЕНО)" "ON")
    else
        analytics_options+=("lyingdown" "🛌 Обнаружение лежащих людей" "OFF")
    fi
    
    # Показываем меню выбора
    local selected_analytics
    selected_analytics=$(show_checklist "📊 ВЫБОР АНАЛИТИК" "Выберите аналитики для применения к новым видеопотокам:" "${analytics_options[@]}")
    
    if [[ -n "$selected_analytics" ]]; then
        # Сбрасываем все аналитики
        WEAPON_ANALYTICS_ENABLED="false"
        FIGHTS_ANALYTICS_ENABLED="false"
        FIRE_ANALYTICS_ENABLED="false"
        PEOPLE_ANALYTICS_ENABLED="false"
        FACECOVER_ANALYTICS_ENABLED="false"
        BAGS_ANALYTICS_ENABLED="false"
        HANDSUP_ANALYTICS_ENABLED="false"
        LYINGDOWN_ANALYTICS_ENABLED="false"
        
        # Устанавливаем выбранные аналитики
        IFS=' ' read -ra selected_array <<< "$selected_analytics"
        for analytic in "${selected_array[@]}"; do
            analytic=$(echo "$analytic" | sed 's/"//g')
            case "$analytic" in
                "weapon") WEAPON_ANALYTICS_ENABLED="true" ;;
                "fights") FIGHTS_ANALYTICS_ENABLED="true" ;;
                "fire") FIRE_ANALYTICS_ENABLED="true" ;;
                "people") PEOPLE_ANALYTICS_ENABLED="true" ;;
                "facecover") FACECOVER_ANALYTICS_ENABLED="true" ;;
                "bags") BAGS_ANALYTICS_ENABLED="true" ;;
                "handsup") HANDSUP_ANALYTICS_ENABLED="true" ;;
                "lyingdown") LYINGDOWN_ANALYTICS_ENABLED="true" ;;
            esac
        done
        
        # Сохраняем временную конфигурацию
        save_template_config
        
        # Создаем временный шаблон с выбранными аналитиками
        create_default_template
        
        # Показываем информацию о выбранных аналитиках
        local selected_list=""
        [[ "$WEAPON_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 🔫 Обнаружение оружия\n"
        [[ "$FIGHTS_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 🥊 Обнаружение драк\n"
        [[ "$FIRE_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 🔥 Обнаружение огня\n"
        [[ "$FACECOVER_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 😷 Обнаружение балаклав\n"
        [[ "$PEOPLE_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 👥 Подсчет людей\n"
        [[ "$BAGS_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 🎒 Оставленные предметы\n"
        [[ "$HANDSUP_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 🙌 Обнаружение рук вверх\n"
        [[ "$LYINGDOWN_ANALYTICS_ENABLED" == "true" ]] && selected_list+="• 🛌 Обнаружение лежащих людей\n"
        
        if [[ -z "$selected_list" ]]; then
            selected_list="❌ Не выбрано ни одной аналитики\n"
        fi
        
        show_message "✅ АНАЛИТИКИ ВЫБРАНЫ" "📊 Выбраны следующие аналитики:\n\n$selected_list\n⚙️  Шаблон обновлен и готов к использованию."
        
        # Возвращаем успешный результат
        return 0
    else
        # Если выбор отменен, восстанавливаем старые настройки
        WEAPON_ANALYTICS_ENABLED="$current_weapon"
        FIGHTS_ANALYTICS_ENABLED="$current_fights"
        FIRE_ANALYTICS_ENABLED="$current_fire"
        PEOPLE_ANALYTICS_ENABLED="$current_people"
        FACECOVER_ANALYTICS_ENABLED="$current_facecover"
        BAGS_ANALYTICS_ENABLED="$current_bags"
        HANDSUP_ANALYTICS_ENABLED="$current_handsup"
        LYINGDOWN_ANALYTICS_ENABLED="$current_lyingdown"
        
        show_message "❌ ОТМЕНА" "Выбор аналитик отменен. Используются текущие настройки."
        return 1
    fi
}
# ============================================================================
# ОПТИМИЗИРОВАННЫЕ ФУНКЦИИ ГЕНЕРАЦИИ ОТЧЕТОВ
# ============================================================================
generate_system_report() {
    echo "📊 Формирование системного отчета"
    
    mkdir -p "$REPORT_DIR"
    local report_file="$REPORT_DIR/sysreport_$(hostname)_$(date +%F_%H-%M).txt"
    
    {
        echo "======================================"
        echo "📋 СИСТЕМНЫЙ ОТЧЁТ ($(hostname))"
        echo "======================================"
        echo "📅 Дата: $(date)"
        echo "👤 Пользователь: $USER"
        echo "--------------------------------------"
        echo ""
        echo "=== 🖥️  ОС и ядро ==="
        if command -v lsb_release &> /dev/null; then
            lsb_release -a 2>/dev/null
        else
            cat /etc/os-release 2>/dev/null || echo "Информация об ОС недоступна"
        fi
        uname -a
        echo ""
        echo "=== ⚙️  Аппаратные данные ==="
        echo "CPU:"
        if command -v lscpu &> /dev/null; then
            lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core' 2>/dev/null || echo "Информация о CPU недоступна"
        else
            echo "lscpu не установлен"
        fi
        echo ""
        echo "Память:"
        free -h 2>/dev/null || echo "Информация о памяти недоступна"
        echo ""
        echo "Диски:"
        if command -v lsblk &> /dev/null; then
            lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null || echo "Информация о дисках недоступна"
        else
            echo "lsblk не установлен"
        fi
        echo ""
        echo "Файловые системы:"
        df -hT 2>/dev/null | grep -v tmpfs || echo "Информация о файловых системах недоступна"
        echo ""
        echo "=== 🌐 Сеть ==="
        if command -v ip &> /dev/null; then
            ip -brief address 2>/dev/null || echo "Информация о сети недоступна"
        else
            echo "ip команда недоступна"
        fi
        echo ""
        echo "=== 📊 Нагрузка и процессы ==="
        echo "⏱️  Uptime: $(uptime -p 2>/dev/null || echo "N/A")"
        echo "📈 Средняя загрузка: $(uptime 2>/dev/null | awk -F'load average:' '{print $2}' || echo "N/A")"
        echo "🔥 Топ-5 по CPU:"
        ps -eo pid,comm,%cpu --sort=-%cpu 2>/dev/null | head -6 || echo "Информация о процессах недоступна"
    } > "$report_file"
    echo "✅ Системный отчет сохранен: $report_file"
    show_message "📊 Системный отчет" "📋 Отчёт сохранён в: $report_file\n\n📊 Размер: $(du -h "$report_file" 2>/dev/null | cut -f1 || echo "N/A")"
}
check_dependencies() {
    local missing=()
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    if ! command -v dialog &> /dev/null && ! command -v whiptail &> /dev/null; then
        missing+=("dialog или whiptail")
    fi
  
    if ! command -v ffprobe &> /dev/null; then
        missing+=("ffprobe (из пакета ffmpeg)")
    fi
    
    if ! command -v bc &> /dev/null; then
        missing+=("bc")
    fi
    
    if ! command -v tar &> /dev/null; then
        missing+=("tar")
    fi
    
    if ! command -v pv &> /dev/null; then
        missing+=("pv")
    fi
    
    if ! command -v zstd &> /dev/null; then
        missing+=("zstd")
    fi
    
    # Проверяем docker-compose для StreamRecorder
    if ! command -v docker-compose &> /dev/null; then
        missing+=("docker-compose")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "╔════════════════════════════════════════════════════════════════════════════════╗"
        echo "║                              ❌ ОШИБКА!                                        ║"
        echo "╚════════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "📦 Отсутствуют зависимости: ${missing[*]}"
        echo "🔧 Установите их:"
        for dep in "${missing[@]}"; do
            if [[ "$dep" == "ffprobe (из пакета ffmpeg)" ]]; then
                echo "  📹 ffmpeg: sudo apt-get install ffmpeg"
            elif [[ "$dep" == "docker-compose" ]]; then
                echo "  🐳 docker-compose: sudo apt-get install docker-compose"
            else
                echo "  🔧 $dep: sudo apt-get install $dep"
            fi
        done
        echo ""
        exit 1
    fi
    if command -v dialog &> /dev/null; then
        TUI_CMD="dialog"
        echo "✅ Найден интерфейс: dialog"
    elif command -v whiptail &> /dev/null; then
        TUI_CMD="whiptail"
        echo "✅ Найден интерфейс: whiptail"
    fi
}
init() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$AGENTS_DIR"
    mkdir -p "$SCANNER_DIR"
    mkdir -p "$BAGS_DIR"
    mkdir -p "$RELEASES_DIR"
    mkdir -p "$RECORDER_DIR"
    mkdir -p "$REPORT_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$RECORDS_DIR"
    mkdir -p "$FRAMES_DIR"
    mkdir -p "$CAMS_LIST_DIR"
    
    load_configs
    
    # Инициализируем конфигурацию StreamRecorder
    init_recorder_config
    
    echo "✅ Система Управления Камерами Аналитики инициализирована"
}
load_configs() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" 2>/dev/null || {
            echo "⚠️  Ошибка загрузки конфигурации, используются значения по умолчанию"
            save_config
        }
    else
        save_config
    fi
    
    if [[ -f "$TEMPLATE_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$TEMPLATE_CONFIG_FILE" 2>/dev/null || create_default_template_config
    else
        create_default_template_config
    fi
    
    if [[ -f "$SCANNER_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$SCANNER_CONFIG_FILE" 2>/dev/null || create_default_scanner_config
    else
        create_default_scanner_config
    fi
    
    if [[ -f "$BAGS_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$BAGS_CONFIG_FILE" 2>/dev/null || create_default_bags_config
    else
        create_default_bags_config
    fi
    
    if [[ -f "$ANALYSIS_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$ANALYSIS_CONFIG_FILE" 2>/dev/null || create_default_analysis_config
    else
        create_default_analysis_config
    fi
    
    if [[ -f "$LOGS_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$LOGS_CONFIG_FILE" 2>/dev/null || create_default_logs_config
    else
        create_default_logs_config
    fi
    
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        create_default_template
    fi
    
    if [[ ! -f "$HISTORY_FILE" ]]; then
        touch "$HISTORY_FILE"
    fi
}
create_default_template_config() {
    cat > "$TEMPLATE_CONFIG_FILE" << 'EOF'
WEAPON_ANALYTICS_ENABLED=true
FIGHTS_ANALYTICS_ENABLED=true
FIRE_ANALYTICS_ENABLED=false
PEOPLE_ANALYTICS_ENABLED=false
FACECOVER_ANALYTICS_ENABLED=false
BAGS_ANALYTICS_ENABLED=false
HANDSUP_ANALYTICS_ENABLED=false
LYINGDOWN_ANALYTICS_ENABLED=false
EOF
    echo "✅ Создана конфигурация шаблона по умолчанию"
}
create_default_bags_config() {
    cat > "$BAGS_CONFIG_FILE" << EOF
BAGS_TAG="ff1a2aa4"
BAGS_INSTANCES=2
DOCKER_REGISTRY="test-server.vlabs:5000"
CONFIGURATOR_HOST="${HOST_IP}"
CONFIGURATOR_PORT="5070"
BAGS_PORT_START="5950"
WORKER_COUNT="1"
BAGS_USE_GPU="false"
EOF
    echo "✅ Создана конфигурация bags по умолчанию"
}
create_default_logs_config() {
    cat > "$LOGS_CONFIG_FILE" << EOF
LOGS_DIR="$CONFIG_DIR/logs_archive"
DEFAULT_LOG_HOURS="6h"
LOG_RETENTION_DAYS=7
EOF
    echo "✅ Создана конфигурация логов по умолчанию"
}
create_default_analysis_config() {
    cat > "$ANALYSIS_CONFIG_FILE" << EOF
ANALYSIS_TIMEOUT="$ANALYSIS_TIMEOUT"
DEFAULT_CAMERAS_FILE="$DEFAULT_CAMERAS_FILE"
EOF
    echo "✅ Создана конфигурация анализа по умолчанию"
}
create_default_scanner_config() {
    cat > "$SCANNER_CONFIG_FILE" << EOF
SCANNER_TAG="737f3a0b"
SCANNER_INSTANCES=8
DOCKER_REGISTRY="test-server.vlabs:5000"
CONFIGURATOR_HOST="${HOST_IP}"
CONFIGURATOR_PORT="5070"
SCANNER_PORT_START="5850"
WORKER_COUNT="1"
SCANNER_USE_GPU="true"
EOF
    echo "✅ Создана конфигурация сканера по умолчанию"
}
create_default_template() {
    local base_template='{
  "name": "$camera_name",
  "description": "auto_generated",
  "splittable":1,
  "data": {
    "type": "stream",
    "downloadable": false,
    "timestamp_source": "auto",
    "reference": "$camera_url",
    "rotation": 0,
    "pts": {
      "start_time": 0
    }
  },
  "autorestart": {
    "restart": 1,
    "attempt_count": 500,
    "delay": 30
  },
  "analytics": []
}'
    local temp_file
    temp_file=$(mktemp)
    echo "$base_template" > "$temp_file"
    
    # Удаляем переменные из шаблона для корректной работы jq
    sed -i 's/\$camera_name/TEMPLATE_NAME/g; s/\$camera_url/TEMPLATE_URL/g' "$temp_file"
    
    # Добавляем аналитики в зависимости от настроек
    if [ "$WEAPON_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson weapon_analytic "$TEMPLATE_WEAPON_ANALYTICS" '.analytics += [$weapon_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления weapon аналитики в шаблон"
        fi
    fi
    if [ "$FIGHTS_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson fights_analytic "$TEMPLATE_FIGHTS_ANALYTICS" '.analytics += [$fights_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления fights аналитики в шаблон"
        fi
    fi
    if [ "$FIRE_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson fire_analytic "$TEMPLATE_FIRE_ANALYTICS" '.analytics += [$fire_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления fire аналитики в шаблон"
        fi
    fi
    if [ "$PEOPLE_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson people_analytic "$TEMPLATE_PEOPLE_ANALYTICS" '.analytics += [$people_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления people аналитики в шаблон"
        fi
    fi
    if [ "$FACECOVER_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson facecover_analytic "$TEMPLATE_FACECOVER_ANALYTICS" '.analytics += [$facecover_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления facecover аналитики в шаблон"
        fi
    fi
    if [ "$BAGS_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson bags_analytic "$TEMPLATE_BAGS_ANALYTICS" '.analytics += [$bags_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления bags аналитики в шаблон"
        fi
    fi
    if [ "$HANDSUP_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson handsup_analytic "$TEMPLATE_HANDSUP_ANALYTICS" '.analytics += [$handsup_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления handsup аналитики в шаблон"
        fi
    fi
    if [ "$LYINGDOWN_ANALYTICS_ENABLED" = "true" ]; then
        if jq --argjson lyingdown_analytic "$TEMPLATE_LYINGDOWN_ANALYTICS" '.analytics += [$lyingdown_analytic]' "$temp_file" > "${temp_file}.tmp"; then
            mv "${temp_file}.tmp" "$temp_file"
        else
            echo "❌ Ошибка добавления lyingdown аналитики в шаблон"
        fi
    fi
    cp "$temp_file" "$TEMPLATE_FILE"
    rm -f "$temp_file" "${temp_file}.tmp" 2>/dev/null
    
    echo "✅ Создан шаблон по умолчанию"
}
show_message() {
    local title="$1"
    local message="$2"
    local height="${3:-$MSG_HEIGHT}"
    local width="${4:-$TUI_WIDTH}"
    
    if [[ -z "$TUI_CMD" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo " $title"
        echo "════════════════════════════════════════════════════════════"
        echo -e "$message"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        return
    fi
    
    if [[ "$TUI_CMD" == "dialog" ]]; then
        dialog --title "$title" --msgbox "$message" "$height" "$width" 2>/dev/null
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        whiptail --title "$title" --msgbox "$message" "$height" "$width" 2>/dev/null
    else
        echo -e "$title\n$message"
    fi
}
show_menu() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")
    
    if [[ -z "$TUI_CMD" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo " $title"
        echo "════════════════════════════════════════════════════════════"
        echo -e "$prompt"
        echo "────────────────────────────────────────────────────────────"
        
        local index=1
        for ((i=0; i<${#options[@]}; i+=2)); do
            echo " $index) ${options[i+1]}"
            ((index++))
        done
        echo " 0) 🔙 Назад"
        echo "════════════════════════════════════════════════════════════"
        echo -n " 📍 Выберите пункт: "
        read -r choice
        
        # Преобразуем числовой выбор в значение
        local selected_index=$(( (choice * 2) - 2 ))
        if [[ $selected_index -ge 0 ]] && [[ $selected_index -lt ${#options[@]} ]]; then
            echo "${options[$selected_index]}"
        else
            echo ""
        fi
        return
    fi
    
    local choice
    if [[ "$TUI_CMD" == "dialog" ]]; then
        choice=$(dialog --title "$title" --menu "$prompt" $TUI_HEIGHT $TUI_WIDTH $MENU_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3)
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        local whiptail_options=()
        for ((i=0; i<${#options[@]}; i+=2)); do
            whiptail_options+=("${options[i]}" "${options[i+1]}")
        done
        choice=$(whiptail --title "$title" --menu "$prompt" $TUI_HEIGHT $TUI_WIDTH $MENU_HEIGHT "${whiptail_options[@]}" 3>&1 1>&2 2>&3)
    fi
    echo "$choice"
}
show_input() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    
    if [[ -z "$TUI_CMD" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo " $title"
        echo "════════════════════════════════════════════════════════════"
        echo -e "$prompt"
        echo -n " [$default]: "
        read -r input
        echo "${input:-$default}"
        return
    fi
    
    local input
    if [[ "$TUI_CMD" == "dialog" ]]; then
        input=$(dialog --title "$title" --inputbox "$prompt" $INPUT_HEIGHT $TUI_WIDTH "$default" 3>&1 1>&2 2>&3)
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        input=$(whiptail --title "$title" --inputbox "$prompt" $INPUT_HEIGHT $TUI_WIDTH "$default" 3>&1 1>&2 2>&3)
    fi
    echo "$input"
}
show_yesno() {
    local title="$1"
    local message="$2"
    
    if [[ -z "$TUI_CMD" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo " $title"
        echo "════════════════════════════════════════════════════════════"
        echo -e "$message"
        echo -n " (y/N): "
        read -r response
        [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    
    if [[ "$TUI_CMD" == "dialog" ]]; then
        dialog --title "$title" --yesno "$message" $INPUT_HEIGHT $TUI_WIDTH 3>&1 1>&2 2>&3
        return $?
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        whiptail --title "$title" --yesno "$message" $INPUT_HEIGHT $TUI_WIDTH 3>&1 1>&2 2>&3
        return $?
    fi
    return 1
}
show_progress() {
    local title="$1"
    local prompt="$2"
    local percent="$3"
    
    if [[ -z "$TUI_CMD" ]]; then
        echo -e "📊 $title: $prompt - ${percent}%"
        return
    fi
    
    if [[ "$TUI_CMD" == "dialog" ]]; then
        echo "$percent" | dialog --title "$title" --gauge "$prompt" $PROGRESS_HEIGHT $TUI_WIDTH 0 2>/dev/null
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        echo "$percent" | whiptail --title "$title" --gauge "$prompt" $PROGRESS_HEIGHT $TUI_WIDTH 0 2>/dev/null
    fi
}
show_progress_with_percent() {
    local title="$1"
    local prompt="$2"
    local percent="$3"
    
    if [[ -z "$TUI_CMD" ]]; then
        echo -e "📊 $title: $prompt - ${percent}%"
        return
    fi
    
    show_progress "$title" "$prompt" "$percent"
}
show_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")
    
    if [[ -z "$TUI_CMD" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo " $title"
        echo "════════════════════════════════════════════════════════════"
        echo -e "$prompt"
        echo "────────────────────────────────────────────────────────────"
        
        local index=1
        for ((i=0; i<${#options[@]}; i+=3)); do
            echo " $index) ${options[i+1]} (${options[i]})"
            ((index++))
        done
        echo ""
        echo -n " 📍 Введите номера выбранных пунктов (через пробел): "
        read -r choices
        echo "$choices"
        return
    fi
    
    local choices
    if [[ "$TUI_CMD" == "dialog" ]]; then
        choices=$(dialog --title "$title" --checklist "$prompt" $TUI_HEIGHT $TUI_WIDTH $MENU_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3)
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        choices=$(dialog --title "$title" --checklist "$prompt" $TUI_HEIGHT $TUI_WIDTH $MENU_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3 2>/dev/null || echo "")
    fi
    echo "$choices"
}
show_radiolist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")
    
    if [[ -z "$TUI_CMD" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo " $title"
        echo "════════════════════════════════════════════════════════════"
        echo -e "$prompt"
        echo "────────────────────────────────────────────────────────────"
        
        local index=1
        for ((i=0; i<${#options[@]}; i+=3)); do
            echo " $index) ${options[i+1]}"
            ((index++))
        done
        echo ""
        echo -n " 📍 Выберите пункт: "
        read -r choice
        
        local selected_index=$(( (choice * 3) - 3 ))
        if [[ $selected_index -ge 0 ]] && [[ $selected_index -lt ${#options[@]} ]]; then
            echo "${options[$selected_index]}"
        else
            echo ""
        fi
        return
    fi
    
    local choice
    if [[ "$TUI_CMD" == "dialog" ]]; then
        choice=$(dialog --title "$title" --radiolist "$prompt" $TUI_HEIGHT $TUI_WIDTH $MENU_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3)
    elif [[ "$TUI_CMD" == "whiptail" ]]; then
        choice=$(dialog --title "$title" --radiolist "$prompt" $TUI_HEIGHT $TUI_WIDTH $MENU_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3 2>/dev/null || echo "")
    fi
    echo "$choice"
}
# ============================================================================
# ИСПРАВЛЕННЫЕ ФУНКЦИИ ДЛЯ РАБОТЫ С ПОТОКАМИ
# ============================================================================
get_streams_list() {
    local force_refresh="$1"
    local response
    local error_file
    
    # Если требуется обновить кэш или кэш устарел
    local current_time=$(date +%s)
    local cache_age=$((current_time - STREAM_CACHE_TIMESTAMP))
    
    if [[ -z "$STREAM_CACHE" ]] || [[ "$force_refresh" == "force" ]] || [[ $cache_age -gt $CACHE_TIMEOUT ]]; then
        echo "🔄 Обновление кэша потоков..."
        
        # Пробуем получить данные через API
        response=$(curl -s --connect-timeout 10 --max-time 30 \
            --header "luna-account-id: $ACCOUNT_ID" \
            "${API_URL}?page_size=1000" 2>/dev/null)
        
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -ne 0 ]] || [[ -z "$response" ]]; then
            echo "❌ Ошибка при запросе к API (curl exit code: $curl_exit_code)"
            return 1
        fi
        
        # Проверяем валидность JSON
        if ! echo "$response" | jq empty 2>/dev/null; then
            echo "❌ Ответ API не является валидным JSON"
            echo "Ответ API: $response"
            return 1
        fi
        
        # Проверяем, есть ли данные в ответе
        if ! echo "$response" | jq -e '.streams' >/dev/null 2>&1 && ! echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
            echo "❌ В ответе API отсутствуют данные о потоках"
            echo "Ответ API: $response"
            return 1
        fi
        
        STREAM_CACHE="$response"
        STREAM_CACHE_TIMESTAMP=$current_time
        echo "✅ Кэш потоков обновлен"
    else
        response="$STREAM_CACHE"
        echo "✅ Используем кэшированные данные (возраст: ${cache_age}с)"
    fi
    
    # Извлекаем потоки из ответа
    local streams=()
    local stream_ids=()
    
    # Пробуем разные форматы ответа
    if echo "$response" | jq -e '.streams' >/dev/null 2>&1; then
        stream_ids=$(echo "$response" | jq -r '.streams[]?.stream_id // empty' 2>/dev/null)
    elif echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
        stream_ids=$(echo "$response" | jq -r '.[]?.stream_id // empty' 2>/dev/null)
    else
        echo "❌ Не удалось определить структуру ответа API"
        return 1
    fi
    
    if [[ -z "$stream_ids" ]]; then
        echo "ℹ️ Потоки не найдены"
        return 0
    fi
    
    # Получаем информацию о каждом потоке
    while IFS= read -r stream_id; do
        [[ -z "$stream_id" ]] && continue
        
        # Получаем информацию о потоке
        local stream_info stream_name stream_status
        
        if echo "$response" | jq -e '.streams' >/dev/null 2>&1; then
            stream_info=$(echo "$response" | jq -r --arg id "$stream_id" \
                '.streams[] | select(.stream_id==$id) | {name: .name, status: .status}' 2>/dev/null)
        else
            stream_info=$(echo "$response" | jq -r --arg id "$stream_id" \
                '.[] | select(.stream_id==$id) | {name: .name, status: .status}' 2>/dev/null)
        fi
        
        if [[ -n "$stream_info" ]] && [[ "$stream_info" != "null" ]]; then
            stream_name=$(echo "$stream_info" | jq -r '.name // ""' 2>/dev/null)
            stream_status=$(echo "$stream_info" | jq -r '.status // "0"' 2>/dev/null)
        else
            stream_name="Поток $stream_id"
            stream_status="0"
        fi
        
        if [[ -z "$stream_name" ]]; then
            stream_name="Поток $stream_id"
        fi
        
        local status_display=$(get_stream_status_display "$stream_status")
        local display_name="${stream_name:0:30}"
        if [[ ${#stream_name} -gt 30 ]]; then
            display_name="${display_name}..."
        fi
        
        streams+=("$stream_id")
        streams+=("$display_name | $status_display")
        
    done <<< "$stream_ids"
    
    if [[ ${#streams[@]} -eq 0 ]]; then
        echo "ℹ️ Потоки не найдены"
        return 0
    fi
    
    printf '%s\n' "${streams[@]}"
    return 0
}
get_stream_status_display() {
    local status_code="$1"
    case "$status_code" in
        "1") echo "🔄 В процессе" ;;
        "5") echo "⏸️ Остановлен" ;;
        "4") echo "⏸️ Сбой" ;;
        "3") echo "🔄 Перезапуск" ;;
        "0") echo "⏳ Ожидание" ;;
        *) echo "❓ Неизвестный ($status_code)" ;;
    esac
}
select_streams_dialog() {
    local title="$1"
    local prompt="$2"
    local selection_mode="$3"  # "single" или "multi"
    
    echo "📋 Получение списка потоков..."
    
    # Получаем список потоков
    local streams_output
    streams_output=$(get_streams_list "force")
    local ret_code=$?
    
    if [[ $ret_code -ne 0 ]]; then
        show_message "❌ Ошибка" "Не удалось получить список видеопотоков\n\nПроверьте:\n• Доступность API ($API_URL)\n• Сетевые настройки\n• Account ID: $ACCOUNT_ID\n• Запущен ли сервис Luna"
        return 1
    fi
    
    if [[ -z "$streams_output" ]]; then
        show_message "ℹ️  Информация" "Видеопотоки не найдены"
        return 1
    fi
    
    # Преобразуем вывод в массив
    local streams_array=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            streams_array+=("$line")
        fi
    done <<< "$streams_output"
    
    local total_streams=$((${#streams_array[@]} / 2))
    
    if [[ $total_streams -eq 0 ]]; then
        show_message "ℹ️  Информация" "Видеопотоки не найдены"
        return 1
    fi
    
    echo "✅ Найдено потоков: $total_streams"
    
    if [[ "$selection_mode" == "multi" ]]; then
        # Режим множественного выбора
        local checklist_options=()
        for ((i=0; i<${#streams_array[@]}; i+=2)); do
            local stream_id="${streams_array[i]}"
            local display_name="${streams_array[i+1]}"
            checklist_options+=("$stream_id" "$display_name" "OFF")
        done
        
        local choices
        choices=$(show_checklist "$title" "$prompt" "${checklist_options[@]}")
        
        if [[ -n "$choices" ]]; then
            SELECTED_STREAMS=()
            # Обрабатываем выбор (удаляем кавычки если они есть)
            IFS=' ' read -r -a selected_array <<< "$choices"
            for item in "${selected_array[@]}"; do
                item=$(echo "$item" | sed 's/"//g')
                SELECTED_STREAMS+=("$item")
            done
            return 0
        else
            return 1
        fi
        
    else
        # Режим одиночного выбора
        local menu_options=()
        for ((i=0; i<${#streams_array[@]}; i+=2)); do
            menu_options+=("${streams_array[i]}" "${streams_array[i+1]}")
        done
        
        local choice
        choice=$(show_menu "$title" "$prompt" "${menu_options[@]}")
        
        if [[ -n "$choice" ]]; then
            SELECTED_STREAMS=("$choice")
            return 0
        else
            return 1
        fi
    fi
}
# ============================================================================
# ОПТИМИЗИРОВАННЫЕ ФУНКЦИИ API
# ============================================================================
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    local url="${API_URL}/${endpoint}"
    
    case "$method" in
        "GET")
            curl -s --connect-timeout 10 --max-time 30 \
                --header "luna-account-id: $ACCOUNT_ID" \
                "$url" 2>/dev/null
            ;;
        "POST")
            curl -s --connect-timeout 10 --max-time 30 \
                --header "luna-account-id: $ACCOUNT_ID" \
                --header "Content-Type: application/json" \
                --request POST \
                --data "$data" \
                "$url" 2>/dev/null
            ;;
        "PATCH")
            curl -s --connect-timeout 10 --max-time 30 \
                --header "luna-account-id: $ACCOUNT_ID" \
                --header "Content-Type: application/json" \
                --request PATCH \
                --data "$data" \
                "$url" 2>/dev/null
            ;;
        "DELETE")
            curl -s --connect-timeout 10 --max-time 30 \
                --header "luna-account-id: $ACCOUNT_ID" \
                --request DELETE \
                "$url" 2>/dev/null
            ;;
    esac
}
get_active_streams_count() {
    local response
    response=$(curl -s --max-time 10 --connect-timeout 5 "http://${HOST_IP}:5230/2/streams/count?statuses=1" 2>/dev/null || echo '{"count": 0}')
    local count
    count=$(echo "$response" | jq -r '.count // 0' 2>/dev/null || echo "0")
    echo "$count"
}
get_stream_info() {
    local stream_id="$1"
    local response
    response=$(curl -s --connect-timeout 5 --max-time 10 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "${API_URL}/${stream_id}" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
    else
        echo ""
    fi
}
add_stream() {
    local camera_name="$1"
    local camera_url="$2"
    
    echo "➕ Добавление видеопотока: $camera_name"
    
    echo "$(date '+%Y-%m-%d %H:%M') $camera_name $camera_url" >> "$HISTORY_FILE"
    
    local current_date
    current_date=$(date '+%Y-%m-%d %H:%M')
    local description="${current_date}"
    
    local temp_template
    temp_template=$(mktemp)
    
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        echo "❌ Шаблонный файл не найден: $TEMPLATE_FILE"
        return 1
    fi
    
    if ! jq --arg NAME "$camera_name" --arg REFERENCE "$camera_url" --arg DESC "$description" \
        '.name = $NAME | .data.reference = $REFERENCE | .description = $DESC' "$TEMPLATE_FILE" > "$temp_template" 2>/dev/null; then
        echo "❌ Ошибка обработки шаблона JSON"
        rm -f "$temp_template"
        return 1
    fi
    
    local json_data
    json_data=$(cat "$temp_template")
    rm -f "$temp_template"
    
    local response
    response=$(api_request "POST" "" "$json_data")
    
    if echo "$response" | jq -e '.stream_id' >/dev/null 2>&1; then
        local stream_id
        stream_id=$(echo "$response" | jq -r '.stream_id')
        echo "✅ Видеопоток добавлен: $camera_name (ID: $stream_id)"
        STREAM_CACHE=""
        STREAM_CACHE_TIMESTAMP=0
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.detail // .message // "Неизвестная ошибка"' 2>/dev/null || echo "Неизвестная ошибка")
        echo "❌ Ошибка добавления $camera_name: $error_msg"
        return 1
    fi
}
stop_stream() {
    local stream_id="$1"
    
    echo "⏸️  Остановить видеопоток: $stream_id"
    
    local response
    response=$(api_request "PATCH" "$stream_id?action=stop" "{}")
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Видеопоток остановлен: $stream_id"
        STREAM_CACHE=""
        STREAM_CACHE_TIMESTAMP=0
        return 0
    else
        echo "❌ Ошибка остановки видеопотока: $stream_id"
        return 1
    fi
}
resume_stream() {
    local stream_id="$1"
    
    echo "▶️  Возобновление видеопотока: $stream_id"
    
    local response
    response=$(api_request "PATCH" "$stream_id?action=resume" "{}")
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Видеопоток возобновлен: $stream_id"
        STREAM_CACHE=""
        STREAM_CACHE_TIMESTAMP=0
        return 0
    else
        echo "❌ Ошибка возобновления видеопотока: $stream_id"
        return 1
    fi
}
delete_stream() {
    local stream_id="$1"
    
    echo "🗑️  Удалить видеопоток: $stream_id"
    
    local response
    response=$(api_request "DELETE" "$stream_id" "")
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Видеопоток удален: $stream_id"
        STREAM_CACHE=""
        STREAM_CACHE_TIMESTAMP=0
        return 0
    else
        echo "❌ Ошибка удаления видеопотока: $stream_id"
        return 1
    fi
}
stop_selected_streams() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "❌ Ошибка" "Не выбраны видеопотоки для остановки"
        return 1
    fi
    
    local count=0
    local total=${#SELECTED_STREAMS[@]}
    local current=0
    
    for stream_id in "${SELECTED_STREAMS[@]}"; do
        ((current++))
        local percent=$((current * 100 / total))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "⏸️  Остановка видеопотоков" "Остановка: $stream_id ($current/$total)" "$percent"
        else
            echo "⏸️  Остановка: $stream_id ($current/$total)"
        fi
        
        if stop_stream "$stream_id"; then
            ((count++))
        fi
        sleep 0.2
    done
    
    show_message "📊 Результат" "⏸️  Остановлено видеопотоков: $count из $total"
    echo "✅ Остановлено видеопотоков: $count из $total"
}
resume_selected_streams() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "❌ Ошибка" "Не выбраны видеопотоки для возобновления"
        return 1
    fi
    
    local count=0
    local total=${#SELECTED_STREAMS[@]}
    local current=0
    
    for stream_id in "${SELECTED_STREAMS[@]}"; do
        ((current++))
        local percent=$((current * 100 / total))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "▶️  Возобновление видеопотоков" "Возобновление: $stream_id ($current/$total)" "$percent"
        else
            echo "▶️  Возобновление: $stream_id ($current/$total)"
        fi
        
        if resume_stream "$stream_id"; then
            ((count++))
        fi
        sleep 0.2
    done
    
    show_message "📊 Результат" "▶️  Возобновлено видеопотоков: $count из $total"
    echo "✅ Возобновлено видеопотоков: $count из $total"
}
delete_selected_streams() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "❌ Ошибка" "Не выбраны видеопотоки для удаления"
        return 1
    fi
    
    if ! show_yesno "⚠️  Подтверждение удаления" "Вы уверены, что хотите удалить выбранные видеопотоки?\n\n📊 Количество: ${#SELECTED_STREAMS[@]}\n\n⚠️  Это действие нельзя отменить!"; then
        show_message "❌ Отмена" "Удаление отменено"
        return 0
    fi
    
    local count=0
    local total=${#SELECTED_STREAMS[@]}
    local current=0
    
    for stream_id in "${SELECTED_STREAMS[@]}"; do
        ((current++))
        local percent=$((current * 100 / total))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "🗑️  Удаление видеопотоков" "Удаление: $stream_id ($current/$total)" "$percent"
        else
            echo "🗑️  Удаление: $stream_id ($current/$total)"
        fi
        
        if delete_stream "$stream_id"; then
            ((count++))
        fi
        sleep 0.2
    done
    
    show_message "📊 Результат" "🗑️  Удалено видеопотоков: $count из $total"
    echo "✅ Удалено видеопотоков: $count из $total"
}
stop_all_streams() {
    echo "📋 Получение списка видеопотоков для остановки..."
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "${API_URL}?page_size=1000" 2>/dev/null)
    
    local uuids
    uuids=$(echo "$response" | jq -r '.streams[]? | .stream_id' 2>/dev/null)
    
    if [[ -z "$uuids" ]]; then
        uuids=$(echo "$response" | jq -r '.[]? | .stream_id' 2>/dev/null)
    fi
    
    if [[ -z "$uuids" ]]; then
        show_message "ℹ️  Информация" "Не найдено видеопотоков для остановки"
        return 0
    fi
    
    local count=0
    local total
    total=$(echo "$uuids" | wc -l)
    local current=0
    
    while IFS= read -r uuid; do
        [[ -z "$uuid" ]] && continue
        ((current++))
        local percent=$((current * 100 / total))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "⏸️  Остановка видеопотоков" "Остановка: $uuid ($current/$total)" "$percent"
        else
            echo "⏸️  Остановка: $uuid ($current/$total)"
        fi
        
        if stop_stream "$uuid"; then
            ((count++))
            echo "✅ Остановлен видеопоток: $uuid"
        fi
        sleep 0.2
    done <<< "$uuids"
    
    show_message "📊 Результат" "⏸️  Остановлено видеопотоков: $count"
    echo "✅ Остановлено видеопотоков: $count"
}
resume_all_streams() {
    echo "📋 Получение списка видеопотоков для возобновления..."
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "${API_URL}?page_size=1000" 2>/dev/null)
    
    local uuids
    uuids=$(echo "$response" | jq -r '.streams[]? | .stream_id' 2>/dev/null)
    
    if [[ -z "$uuids" ]]; then
        uuids=$(echo "$response" | jq -r '.[]? | .stream_id' 2>/dev/null)
    fi
    
    if [[ -z "$uuids" ]]; then
        show_message "ℹ️  Информация" "Не найдено видеопотоков для возобновления"
        return 0
    fi
    
    local count=0
    local total
    total=$(echo "$uuids" | wc -l)
    local current=0
    
    while IFS= read -r uuid; do
        [[ -z "$uuid" ]] && continue
        ((current++))
        local percent=$((current * 100 / total))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "▶️  Возобновление видеопотоков" "Возобновление: $uuid ($current/$total)" "$percent"
        else
            echo "▶️  Возобновление: $uuid ($current/$total)"
        fi
        
        if resume_stream "$uuid"; then
            ((count++))
            echo "✅ Возобновлен видеопоток: $uuid"
        fi
        sleep 0.2
    done <<< "$uuids"
    
    show_message "📊 Результат" "▶️  Возобновлено видеопотоков: $count"
    echo "✅ Возобновлено видеопотоков: $count"
}
add_streams_from_file() {
    local file_path="$1"
    local success_count=0
    local fail_count=0
    local total_count=0
    
    if [[ "$file_path" != */* ]] && [[ "$file_path" != *.* ]]; then
        local config_file_path="$CAMS_LIST_DIR/$file_path"
        if [[ -f "$config_file_path" ]]; then
            file_path="$config_file_path"
            echo "📁 Найден файл в директории cams_list: $file_path"
        else
            config_file_path="$CONFIG_DIR/$file_path"
            if [[ -f "$config_file_path" ]]; then
                file_path="$config_file_path"
                echo "📁 Найден файл в директории конфигурации: $file_path"
            fi
        fi
    fi
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            ((total_count++))
        fi
    done < "$file_path"
    
    if [[ $total_count -eq 0 ]]; then
        show_message "❌ Ошибка" "В файле не найдено валидных записей видеопотоков"
        return 1
    fi
    
    local current=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        ((current++))
        local camera_name
        camera_name=$(echo "$line" | awk '{print $1}')
        local camera_url
        camera_url=$(echo "$line" | awk '{$1=""; print substr($0,2)}' | sed 's/^[[:space:]]*//')
        
        local percent=$((current * 100 / total_count))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "➕ Добавление видеопотоков" "Обработка: $camera_name ($current/$total_count)" "$percent"
        else
            echo "➕ Обработка: $camera_name ($current/$total_count)"
        fi
        
        if add_stream "$camera_name" "$camera_url"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
        sleep 0.3
        
    done < "$file_path"
    
    show_message "📊 Результат" "✅ Добавление завершено:\n✅ Успешно: $success_count\n❌ Ошибок: $fail_count\n📊 Всего: $total_count"
}
delete_all_streams() {
    if ! show_yesno "⚠️  Подтверждение удаления" "ВЫ УВЕРЕНЫ, ЧТО ХОТИТЕ УДАЛИТЬ ВСЕ ВИДЕОПОТОКИ?\n\n⚠️  Это действие нельзя отменить!"; then
        show_message "❌ Отмена" "Удаление отменено"
        return 0
    fi
    
    echo "📋 Получение списка видеопотоков для удаления..."
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "${API_URL}?page_size=1000" 2>/dev/null)
    
    local uuids
    uuids=$(echo "$response" | jq -r '.streams[]? | .stream_id' 2>/dev/null)
    
    if [[ -z "$uuids" ]]; then
        uuids=$(echo "$response" | jq -r '.[]? | .stream_id' 2>/dev/null)
    fi
    
    if [[ -z "$uuids" ]]; then
        show_message "ℹ️  Информация" "Не найдено видеопотоков для удаления"
        return 0
    fi
    
    local count=0
    local total
    total=$(echo "$uuids" | wc -l)
    local current=0
    
    while IFS= read -r uuid; do
        [[ -z "$uuid" ]] && continue
        ((current++))
        local percent=$((current * 100 / total))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "🗑️  Удаление видеопотоков" "Удаление: $uuid ($current/$total)" "$percent"
        else
            echo "🗑️  Удаление: $uuid ($current/$total)"
        fi
        
        if delete_stream "$uuid"; then
            ((count++))
            echo "✅ Удален видеопоток: $uuid"
        fi
        sleep 0.2
    done <<< "$uuids"
    
    show_message "📊 Результат" "🗑️  Удалено видеопотоков: $count"
    echo "✅ Удалено видеопотоков: $count"
}
list_streams() {
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "${API_URL}?page_size=1000" 2>/dev/null)
    
    local count
    count=$(echo "$response" | jq -r '.streams? | length' 2>/dev/null || echo "0")
    
    if [[ "$count" -eq 0 ]] || [[ "$count" == "null" ]]; then
        count=$(echo "$response" | jq -r 'length' 2>/dev/null || echo "0")
    fi
    
    if [[ "$count" -eq 0 ]] || [[ "$count" == "null" ]]; then
        show_message "ℹ️  Информация" "Активные видеопотоки не найдены"
        return 0
    fi
    
    local stream_list=""
    stream_list=$(echo "$response" | jq -r '.streams[] | "\(.stream_id) \(.name) \(.data.reference)"' 2>/dev/null | \
    while IFS= read -r line; do
        echo "$line"
    done)
    
    if [[ -z "$stream_list" ]]; then
        stream_list=$(echo "$response" | jq -r '.[] | "\(.stream_id) \(.name) \(.data.reference)"' 2>/dev/null | \
    while IFS= read -r line; do
        echo "$line"
    done)
    fi
    
    if [[ -z "$stream_list" ]]; then
        show_message "ℹ️  Информация" "Активные видеопотоки не найдены"
        return 0
    fi
    
    show_message "🎥 Активные видеопотоки ($count)" "$stream_list" 20 80
}
show_stream_status() {
    local active_count
    active_count=$(get_active_streams_count)
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "${API_URL}?page_size=1000" 2>/dev/null)
    
    local total
    total=$(echo "$response" | jq -r '.streams? | length' 2>/dev/null || echo "0")
    
    if [[ "$total" -eq 0 ]] || [[ "$total" == "null" ]]; then
        total=$(echo "$response" | jq -r 'length' 2>/dev/null || echo "0")
    fi
    
    if [[ "$total" -eq 0 ]] || [[ "$total" == "null" ]]; then
        show_message "📊 Статус видеопотоков" "Видеопотоки не найдены"
        return 0
    fi
    
    local in_progress=0
    local stopped=0
    local restarting=0
    local waiting=0
    local status_list=""
    
    local temp_file
    temp_file=$(mktemp)
    
    echo "$response" | jq -r '.streams[]? | [.stream_id, .name, .status] | @tsv' 2>/dev/null > "$temp_file"
    
    local lines_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    
    if [[ "$lines_count" -eq 0 ]]; then
        echo "$response" | jq -r '.[]? | [.stream_id, .name, .status] | @tsv' 2>/dev/null > "$temp_file"
        lines_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    fi
    
    if [[ "$lines_count" -eq 0 ]]; then
        echo "$response" | grep -o '"stream_id":"[^"]*"' | cut -d'"' -f4 > "$temp_file"
        lines_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
        
        if [[ "$lines_count" -gt 0 ]]; then
            local temp_file2
            temp_file2=$(mktemp)
            while IFS= read -r stream_id; do
                if [[ -n "$stream_id" ]]; then
                    echo "$stream_id Поток_${stream_id:0:8} 0" >> "$temp_file2"
                fi
            done < "$temp_file"
            mv "$temp_file2" "$temp_file"
        fi
    fi
    
    local table_content=""
    table_content+="$(printf "%-36s %-25s %-12s\n" "ID" "Имя" "Статус")\n"
    table_content+="$(printf "%-36s %-25s %-12s\n" "------------------------------------" "-------------------------" "------------")\n"
    
    while IFS=$'\t' read -r id name status; do
        if [[ -n "$id" ]]; then
            local display_name="$name"
            if [[ ${#name} -gt 24 ]]; then
                display_name="${name:0:21}..."
            fi
            
            local status_display
            case "$status" in
                "1") 
                    status_display="🔄 В процессе"
                    ((in_progress++))
                    ;;
                "5") 
                    status_display="⏸️  Остановлен"
                    ((stopped++))
                    ;;
                "3") 
                    status_display="🔄 Перезапуск"
                    ((restarting++))
                    ;;
                "0") 
                    status_display="⏳ Ожидание"
                    ((waiting++))
                    ;;
                *) 
                    status_display="⏳ Ожидание"
                    ((waiting++))
                    ;;
            esac
            
            table_content+="$(printf "%-36s %-25s %-12s\n" "$id" "$display_name" "$status_display")\n"
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    local summary="📊 Всего: $total, 🔄 В процессе: $in_progress, ⏸️  Остановлено: $stopped, 🔄 Перезапуск: $restarting, ⏳ Ожидание: $waiting"
    show_message "📊 Статус видеопотоков" "$summary\n\n$table_content" 25 90
}
stop_scanner_instances() {
    echo "🛑 Остановка всех инстансов luna-agent-scanner"
    
    local containers
    containers=$(docker ps -a --filter "name=luna-agent-scanner" --format "{{.Names}}" 2>/dev/null)
    
    if [[ -z "$containers" ]]; then
        show_message "📊 Результат" "Контейнеры luna-agent-scanner не найдены"
        echo "ℹ️  Контейнеры luna-agent-scanner не найдены"
        return 0
    fi
    
    local container_array=()
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            container_array+=("$container")
        fi
    done <<< "$containers"
    
    local total_containers=${#container_array[@]}
    local stopped_count=0
    local current=0
    
    show_message "ℹ️  Информация" "Найдено контейнеров для остановки: $total_containers\n\nКонтейнеры:\n${container_array[*]}"
    
    if ! show_yesno "⚠️  Подтверждение остановки" "Остановить все найденные контейнеры luna-agent-scanner?\n\n📊 Количество: $total_containers"; then
        show_message "❌ Отмена" "Остановка отменена"
        return 0
    fi
    
    for container in "${container_array[@]}"; do
        ((current++))
        local percent=$((current * 100 / total_containers))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "🛑 Остановка контейнеров" "Остановка: $container $current/$total_containers" "$percent"
        else
            echo "🛑 Остановка: $container $current/$total_containers"
        fi
        
        if docker rm -f "$container" 2>/dev/null; then
            ((stopped_count++))
            echo "✅ Остановлен контейнер: $container"
        else
            echo "❌ Ошибка остановки контейнера: $container"
        fi
        sleep 0.3
    done
    
    show_message "📊 Результат" "✅ Остановка завершена:\n\n✅ Успешно остановлено: $stopped_count\n📊 Всего контейнеров: $total_containers"
    echo "✅ Остановлено контейнеров scanner: $stopped_count из $total_containers"
}
# ============================================================================
# ОПТИМИЗИРОВАННЫЕ ФУНКЦИИ ЗАХВАТА КАДРОВ
# ============================================================================
capture_frames() {
    local input_file="$1"
    
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "❌ ffmpeg не установлен. Установите ffmpeg и повторите попытку."
        show_message "❌ Ошибка" "ffmpeg не установлен. Установите ffmpeg и повторите попытку."
        return 1
    fi
    if [[ "$input_file" != */* ]] && [[ "$input_file" != *.* ]]; then
        local config_file_path="$CAMS_LIST_DIR/$input_file"
        if [[ -f "$config_file_path" ]]; then
            input_file="$config_file_path"
            echo "📁 Найден файл в директории cams_list: $input_file"
        else
            config_file_path="$CONFIG_DIR/$input_file"
            if [[ -f "$config_file_path" ]]; then
                input_file="$config_file_path"
                echo "📁 Найден файл в директории конфигурации: $input_file"
            fi
        fi
    fi
    if [[ ! -f "$input_file" ]]; then
        echo "❌ Файл с камерами не найден: $input_file"
        show_message "❌ Ошибка" "Файл с камерами не найден: $input_file"
        return 1
    fi
    local file_basename
    file_basename=$(basename "$input_file" | sed 's/\.[^.]*$//')
    local date_dir
    date_dir=$(date +%Y-%m-%d)
    local frames_subdir="$FRAMES_DIR/$file_basename/$date_dir"
    mkdir -p "$frames_subdir"
    local log_file="$frames_subdir/capture_frames.log"
    > "$log_file"
    local success_count=0
    local failed_count=0
    local total_count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        ((total_count++))
    done < "$input_file"
    if [[ $total_count -eq 0 ]]; then
        show_message "❌ Ошибка" "В файле не найдено валидных записей камер"
        return 1
    fi
    local current=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        ((current++))
        local percent=$((current * 100 / total_count))
        local camera_name camera_url
        if [[ "$line" =~ [[:space:]] ]]; then
            camera_name=$(echo "$line" | awk '{print $1}')
            camera_url=$(echo "$line" | awk '{$1=""; print substr($0,2)}' | sed 's/^[[:space:]]*//')
        else
            camera_name="camera_$current"
            camera_url="$line"
        fi
        if [[ -z "$camera_name" || -z "$camera_url" ]]; then
            echo "⚠️  Игнорирование некорректной строки: $line" >> "$log_file"
            ((failed_count++))
            continue
        fi
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "📸 Получение кадров" "Обработка: $camera_name ($current/$total_count)" "$percent"
        else
            echo "📸 Обработка: $camera_name ($current/$total_count)"
        fi
        local safe_camera_name
        safe_camera_name=$(echo "$camera_name" | tr ' ' '_' | tr '/' '-' | tr '\\' '-')
        local output_file="$frames_subdir/${safe_camera_name}.jpg"
        if timeout 30 ffmpeg -rtsp_transport tcp -i "$camera_url" -vframes 1 -y "$output_file" -nostdin -loglevel error 2>/dev/null; then
            if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
                local file_size
                file_size=$(du -h "$output_file" 2>/dev/null | cut -f1 || echo "0")
                echo "✅ Успешно получен кадр для $camera_name: $output_file (размер: $file_size)" >> "$log_file"
                ((success_count++))
            else
                echo "❌ Ошибка: создан пустой файл для $camera_name" >> "$log_file"
                rm -f "$output_file" 2>/dev/null
                ((failed_count++))
            fi
        else
            echo "❌ Ошибка получения кадра для $camera_name по ссылке $camera_url" >> "$log_file"
            ((failed_count++))
        fi
        
        sleep 0.3
    done < "$input_file"
    echo "========================================" >> "$log_file"
    echo "📊 ИТОГОВАЯ СТАТИСТИКА" >> "$log_file"
    echo "✅ Количество успешно полученных кадров: $success_count" >> "$log_file"
    echo "❌ Количество недоступных камер: $failed_count" >> "$log_file"
    echo "📊 Всего обработано камер: $total_count" >> "$log_file"
    local result_message="📸 Получение кадров завершено.\n\n✅ Успешно: $success_count\n❌ Ошибок: $failed_count\n📊 Всего: $total_count\n\n📁 Кадры сохранены в: $frames_subdir/\n📋 Лог-файл: $log_file"
    
    show_message "📊 Результат" "$result_message"
    echo "✅ Сохранение кадров завершено: успешно $success_count, ошибок $failed_count"
}
# ============================================================================
# УПРОЩЕННАЯ ФУНКЦИЯ АНАЛИЗА КАМЕР
# ============================================================================
analyze_cameras_simple() {
    local cameras_file="$1"
    local report_file="$2"
    
    if [[ "$cameras_file" != */* ]] && [[ "$cameras_file" != *.* ]]; then
        local config_file_path="$CAMS_LIST_DIR/$cameras_file"
        if [[ -f "$config_file_path" ]]; then
            cameras_file="$config_file_path"
            echo "📁 Найден файл в директории cams_list: $cameras_file"
        else
            config_file_path="$CONFIG_DIR/$cameras_file"
            if [[ -f "$config_file_path" ]]; then
                cameras_file="$config_file_path"
                echo "📁 Найден файл в директории конфигурации: $cameras_file"
            fi
        fi
    fi
    
    echo "📊 Отчёт диагностики видеопотоков" > "$report_file"
    echo "📅 Сгенерирован: $(date)" >> "$report_file"
    echo "📁 Файл списка видеопотоков: $cameras_file" >> "$report_file"
    echo "═══════════════════════════════════════" >> "$report_file"
    echo "" >> "$report_file"
    
    local temp_table
    temp_table=$(mktemp)
    
    printf "%-25s | %-12s | %-6s | %-12s | %-10s | %-12s\n" \
        "Камера" "Разрешение" "FPS" "Битрейт" "Кодек" "Статус" >> "$temp_table"
    echo "---------------------------------------------------------------------------------------" >> "$temp_table"
    
    local total_cameras=0
    local online_cameras=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        local camera_name rtsp_url
        if [[ "$line" =~ [[:space:]] ]]; then
            camera_name=$(echo "$line" | awk '{print $1}')
            rtsp_url=$(echo "$line" | awk '{$1=""; print substr($0,2)}' | sed 's/^[[:space:]]*//')
        else
            camera_name="camera_$((total_cameras + 1))"
            rtsp_url="$line"
        fi
        
        [[ -z "$camera_name" || -z "$rtsp_url" ]] && continue
        
        total_cameras=$((total_cameras + 1))
        
        local metadata
        metadata=$(timeout $ANALYSIS_TIMEOUT ffprobe -v quiet -print_format json -show_streams -show_format "$rtsp_url" 2>/dev/null)
        
        if [[ -z "$metadata" ]]; then
            printf "%-25s | %-12s | %-6s | %-12s | %-10s | %-12s\n" \
                "$camera_name" "N/A" "N/A" "N/A" "N/A" "❌ OFFLINE" >> "$temp_table"
            continue
        fi
        
        local video_stream
        video_stream=$(echo "$metadata" | jq -r '.streams[] | select(.codec_type=="video")' 2>/dev/null)
        
        if [ -n "$video_stream" ] && [ "$video_stream" != "null" ]; then
            local width height fps_raw fps codec resolution
            width=$(echo "$video_stream" | jq -r '.width // "N/A"')
            height=$(echo "$video_stream" | jq -r '.height // "N/A"')
            fps_raw=$(echo "$video_stream" | jq -r '.r_frame_rate // "0/0"')
            
            fps="N/A"
            if [[ "$fps_raw" != "N/A" && "$fps_raw" != "0/0" ]]; then
                fps=$(awk "BEGIN {split(\"$fps_raw\", a, \"/\"); if (a[2] > 0) printf \"%.1f\", a[1]/a[2]; else print \"N/A\"}" 2>/dev/null || echo "N/A")
            fi
            
            codec=$(echo "$video_stream" | jq -r '.codec_name // "N/A"')
            
            if [ "$width" != "N/A" ] && [ "$height" != "N/A" ]; then
                resolution="${width}x${height}"
            else
                resolution="N/A"
            fi
            
            printf "%-25s | %-12s | %-6s | %-12s | %-10s | %-12s\n" \
                "$camera_name" "$resolution" "$fps" "OK" "$codec" "✅ ONLINE" >> "$temp_table"
            online_cameras=$((online_cameras + 1))
        else
            printf "%-25s | %-12s | %-6s | %-12s | %-10s | %-12s\n" \
                "$camera_name" "N/A" "N/A" "N/A" "N/A" "⚠️  NO VIDEO" >> "$temp_table"
        fi
    done < "$cameras_file"
    
    cat "$temp_table" >> "$report_file"
    rm -f "$temp_table"
    
    echo "═══════════════════════════════════════" >> "$report_file"
    echo "" >> "$report_file"
    echo "📊 СТАТИСТИКА:" >> "$report_file"
    echo "🎥 Всего видеопотоков: $total_cameras" >> "$report_file"
    echo "✅ Онлайн: $online_cameras" >> "$report_file"
    echo "❌ Оффлайн: $((total_cameras - online_cameras))" >> "$report_file"
}
analyze_cameras_from_file() {
    local cameras_file="$1"
    
    if [[ "$cameras_file" != */* ]] && [[ "$cameras_file" != *.* ]]; then
        local config_file_path="$CAMS_LIST_DIR/$cameras_file"
        if [[ -f "$config_file_path" ]]; then
            cameras_file="$config_file_path"
            echo "📁 Найден файл в директории cams_list: $cameras_file"
        else
            config_file_path="$CONFIG_DIR/$cameras_file"
            if [[ -f "$config_file_path" ]]; then
                cameras_file="$config_file_path"
                echo "📁 Найден файл в директории конфигурации: $cameras_file"
            fi
        fi
    fi
    
    if [[ ! -f "$cameras_file" ]]; then
        show_message "❌ Ошибка" "Файл с камерами не найден: $cameras_file"
        return 1
    fi
    
    mkdir -p "$REPORT_DIR"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M)
    local report_file="$REPORT_DIR/camera_report_${timestamp}.txt"
    
    echo "🔍 Проверка списка видеопотоков из файла: $cameras_file"
    
    analyze_cameras_simple "$cameras_file" "$report_file"
    
    echo "✅ Диагностика завершена, отчет сохранен: $report_file"
    
    if show_yesno "✅ Диагностика завершена" "📋 Отчет сохранен: $report_file\n\n👁️  Хотите просмотреть отчет?"; then
        view_analysis_report "$report_file"
    fi
}
view_analysis_report() {
    local report_file="$1"
    
    if [[ ! -f "$report_file" ]]; then
        show_message "❌ Ошибка" "Файл отчета не найден: $report_file"
        return 1
    fi
    
    show_message "📋 Просмотр отчета" "$(cat "$report_file")" 25 90
}
# ============================================================================
# УПРОЩЕННАЯ ФУНКЦИЯ ОЧИСТКИ ЛОГОВ
# ============================================================================
cleanup_old_logs() {
    echo "🗑️  Удаление старых логов"
    
    local days="$LOG_RETENTION_DAYS"
    local deleted_count=0
    local freed_space=0
    
    if [[ ! "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
        days=7
    fi
    
    echo "🔍 Поиск логов старше $days дней..."
    
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            local file_size
            file_size=$(du -b "$file" 2>/dev/null | cut -f1 || echo 0)
            if rm -f "$file"; then
                ((deleted_count++))
                ((freed_space += file_size))
                echo "🗑️  Удален: $(basename "$file")"
            fi
        fi
    done < <(find "$LOGS_DIR" -name "*.tar.gz" -mtime "+$days" -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        local freed_human
        freed_human=$(numfmt --to=iec-i --suffix=B $freed_space 2>/dev/null || echo "$freed_space байт")
        
        show_message "✅ Очистка завершена" "🗑️  Удалено файлов: $deleted_count\n💾 Освобождено: $freed_human\n📅 Логи старше $days дней удалены"
    else
        show_message "ℹ️  Информация" "Логов для удаления не найдено"
    fi
}
show_logs_stats() {
    mkdir -p "$LOGS_DIR"
    local total_archives oldest_archive newest_archive
    total_archives=$(find "$LOGS_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)
    local total_size
    total_size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    local stats_info="📊 Статистика логов:\n\n"
    stats_info+="📦 Всего архивов: $total_archives\n"
    stats_info+="💾 Общий размер: $total_size\n"
    
    if [[ $total_archives -gt 0 ]]; then
        oldest_archive=$(find "$LOGS_DIR" -name "*.tar.gz" -type f -printf '%T+ %p\n' 2>/dev/null | sort | head -1 | cut -d' ' -f2-)
        newest_archive=$(find "$LOGS_DIR" -name "*.tar.gz" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -1 | cut -d' ' -f2-)
        
        if [[ -n "$oldest_archive" ]]; then
            local oldest_size oldest_date
            oldest_size=$(du -h "$oldest_archive" 2>/dev/null | cut -f1 || echo "N/A")
            oldest_date=$(stat -c %y "$oldest_archive" 2>/dev/null | cut -d' ' -f1 || echo "N/A")
            stats_info+="📅 Самый старый: $(basename "$oldest_archive")\n"
            stats_info+="  📊 Размер: $oldest_size, 📅 Дата: $oldest_date\n"
        fi
        
        if [[ -n "$newest_archive" ]]; then
            local newest_size newest_date
            newest_size=$(du -h "$newest_archive" 2>/dev/null | cut -f1 || echo "N/A")
            newest_date=$(stat -c %y "$newest_archive" 2>/dev/null | cut -d' ' -f1 || echo "N/A")
            stats_info+="🆕 Самый новый: $(basename "$newest_archive")\n"
            stats_info+="  📊 Размер: $newest_size, 📅 Дата: $newest_date\n"
        fi
    fi
    
    stats_info+="\n⚙️  Текущие настройки:\n"
    stats_info+="📁 Директория: $LOGS_DIR\n"
    stats_info+="⏱️  Период хранения: $LOG_RETENTION_DAYS дней\n"
    stats_info+="⏰ Период сбора: $DEFAULT_LOG_HOURS\n"
    
    show_message "📊 Статистика логов" "$stats_info"
}
tail_logs() {
    local lines=${1:-50}
    local log_file="/var/log/syslog"
    
    if [[ ! -f "$log_file" ]]; then
        log_file="/var/log/messages"
    fi
    
    if [[ ! -f "$log_file" ]]; then
        show_message "❌ Ошибка" "Лог-файл не найден: $log_file"
        return 1
    fi
    
    local log_content
    log_content=$(tail -n "$lines" "$log_file" 2>/dev/null || echo "Не удалось прочитать лог-файл")
    show_message "📋 Последние $lines строк логов" "$log_content" 25 90
}
clear_stream_manager_logs() {
    if show_yesno "🗑️  Очистка логов" "Очистить системные логи?\n\n📁 Файл: /var/log/syslog"; then
        if [[ -f "/var/log/syslog" ]]; then
            if echo "" > /var/log/syslog 2>/dev/null; then
                echo "✅ Лог-файл очищен"
                show_message "✅ Успех" "Лог-файл очищен"
            else
                show_message "❌ Ошибка" "Не удалось очистить лог-файл"
            fi
        else
            show_message "ℹ️  Информация" "Лог-файл не существует"
        fi
    fi
}
get_luna_platform_version() {
    local version_response
    version_response=$(curl -s --connect-timeout 5 --max-time 10 "http://${HOST_IP}:5000/version" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$version_response" ]]; then
        local major minor patch version
        
        major=$(echo "$version_response" | jq -r '.["LUNA PLATFORM"].major // empty' 2>/dev/null)
        minor=$(echo "$version_response" | jq -r '.["LUNA PLATFORM"].minor // empty' 2>/dev/null)
        patch=$(echo "$version_response" | jq -r '.["LUNA PLATFORM"].patch // empty' 2>/dev/null)
        
        if [[ -n "$major" && -n "$minor" && -n "$patch" ]]; then
            echo "v${major}.${minor}.${patch}"
            return 0
        fi
        
        version=$(echo "$version_response" | jq -r '.version // empty' 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "v$version"
            return 0
        fi
        
        major=$(echo "$version_response" | jq -r '.major // empty' 2>/dev/null)
        minor=$(echo "$version_response" | jq -r '.minor // empty' 2>/dev/null)
        patch=$(echo "$version_response" | jq -r '.patch // empty' 2>/dev/null)
        
        if [[ -n "$major" && -n "$minor" && -n "$patch" ]]; then
            echo "v${major}.${minor}.${patch}"
            return 0
        fi
    fi
    
    echo "❌ Недоступно"
    return 1
}
get_license_info() {
    local license_response
    license_response=$(curl --silent --location --request GET "http://${HOST_IP}:5120/1/license" --header 'Content-Type: application/json' --data-raw '' 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$license_response" ]]; then
        local streams_limit
        streams_limit=$(echo "$license_response" | jq -r '.streams_limit.value // empty' 2>/dev/null)
        if [[ -n "$streams_limit" ]]; then
            echo "$streams_limit"
            return 0
        fi
    fi
    echo "❌ Недоступно"
    return 1
}
get_cpu_info() {
    local cpu_info=""
    
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//' 2>/dev/null || echo "N/A")
    
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "N/A")
    
    local cpu_freq
    cpu_freq=$(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d':' -f2 | awk '{printf "%.0f MHz", $1}' 2>/dev/null || echo "N/A")
    
    local cpu_load
    cpu_load=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2 + $4}' | awk '{printf "%.1f%%", $1}' 2>/dev/null || echo "N/A")
    
    local cpu_arch
    cpu_arch=$(uname -m 2>/dev/null || echo "N/A")
    
    cpu_info+="🖥️  CPU: $cpu_model\n"
    cpu_info+="   ⚙️  Ядра: $cpu_cores, 🏗️  Архитектура: $cpu_arch\n"
    cpu_info+="   ⏱️  Частота: $cpu_freq, 📊 Загрузка: $cpu_load\n"
    
    echo -e "$cpu_info"
}
get_gpu_info() {
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    
    if [[ "$available_gpus" -eq 0 ]]; then
        echo "🎮 GPU: ❌ не обнаружены (используется CPU)"
        return
    fi
    
    local gpu_info="✅ Доступно GPU: $available_gpus\n"
    
    for ((i=0; i<available_gpus; i++)); do
        local gpu_name
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader --id=$i 2>/dev/null | head -1 | sed 's/ *$//' || echo "N/A")
        local gpu_mem_total
        gpu_mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader --id=$i 2>/dev/null | head -1 | sed 's/ MiB//' | tr -d ' ' || echo "N/A")
        local gpu_util
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader --id=$i 2>/dev/null | head -1 | tr -d ' ' || echo "N/A")
        
        gpu_info+="   🎮 GPU$i: $gpu_name (${gpu_mem_total}MB, ${gpu_util}% загрузка)\n"
    done
    
    echo -e "$gpu_info"
}
# ============================================================================
# РАСШИРЕННАЯ ФУНКЦИЯ ПРОВЕРКИ API
# ============================================================================
check_api_health() {
    echo "🔍 Проверка состояния API и связанных сервисов..."
    
    local overall_status="✅"
    local detailed_report="📊 ОТЧЕТ О СОСТОЯНИИ СИСТЕМЫ\n\n"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M')
    detailed_report+="⏰ Время проверки: $timestamp\n"
    detailed_report+="═════════════════════════════════\n\n"
    
    # 1. Проверка основного API
    detailed_report+="1. 📡 ОСНОВНОЙ API ($API_URL)\n"
    local api_response
    api_response=$(curl -s --connect-timeout 5 --max-time 10 \
        --header "luna-account-id: $ACCOUNT_ID" \
        "$API_URL?page_size=1000" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$api_response" ]]; then
        if echo "$api_response" | jq empty 2>/dev/null; then
            local stream_count
            stream_count=$(echo "$api_response" | jq -r '.streams? | length' 2>/dev/null || echo "0")
            detailed_report+="   ✅ Статус: ДОСТУПЕН\n"
            detailed_report+="   📊 Активных потоков: $stream_count\n"
        else
            detailed_report+="   ⚠️  Статус: ДОСТУПЕН (но невалидный JSON)\n"
            overall_status="⚠️"
        fi
    else
        detailed_report+="   ❌ Статус: НЕДОСТУПЕН\n"
        detailed_report+="   💡 Возможные причины:\n"
        detailed_report+="      • Сервис Luna не запущен\n"
        detailed_report+="      • Проблемы с сетью\n"
        detailed_report+="      • Неверный URL: $API_URL\n"
        overall_status="❌"
    fi
    
    # 2. Проверка счетчика потоков
    detailed_report+="\n2. 🔢 СЧЕТЧИК ПОТОКОВ\n"
    local count_response
    count_response=$(curl -s --max-time 10 --connect-timeout 5 "http://${HOST_IP}:5230/2/streams/count?statuses=1" 2>/dev/null || echo '{"count": 0}')
    
    if [[ $? -eq 0 ]]; then
        local active_count
        active_count=$(echo "$count_response" | jq -r '.count // 0' 2>/dev/null || echo "0")
        detailed_report+="   ✅ Статус: ДОСТУПЕН\n"
        detailed_report+="   📊 Активных потоков: $active_count\n"
    else
        detailed_report+="   ⚠️  Статус: ОГРАНИЧЕННЫЙ ДОСТУП\n"
        overall_status="⚠️"
    fi
    
    # 3. Проверка лицензии
    detailed_report+="\n3. 📄 ЛИЦЕНЗИЯ\n"
    local license_info
    license_info=$(get_license_info)
    
    if [[ "$license_info" != "Недоступно" ]]; then
        detailed_report+="   ✅ Статус: АКТИВНА\n"
        detailed_report+="   📊 Лимит потоков: $license_info\n"
    else
        detailed_report+="   ⚠️  Статус: НЕДОСТУПНА\n"
        detailed_report+="   💡 Проверьте сервис лицензий на порту 5120\n"
        overall_status="⚠️"
    fi
    
    # 4. Проверка Luna Platform
    detailed_report+="\n4. 🚀 LUNA PLATFORM\n"
    local luna_version
    luna_version=$(get_luna_platform_version)
    
    if [[ "$luna_version" != "Недоступно" ]]; then
        detailed_report+="   ✅ Статус: ДОСТУПЕН\n"
        detailed_report+="   📊 Версия: $luna_version\n"
    else
        detailed_report+="   ❌ Статус: НЕДОСТУПЕН\n"
        detailed_report+="   💡 Проверьте сервис luna-api на порту 5000\n"
        overall_status="❌"
    fi
    
    # 5. Проверка Docker
    detailed_report+="\n5. 🐳 DOCKER\n"
    if docker info &>/dev/null; then
        local docker_containers
        docker_containers=$(docker ps -q | wc -l 2>/dev/null || echo "0")
        local docker_images
        docker_images=$(docker images -q | wc -l 2>/dev/null || echo "0")
        
        detailed_report+="   ✅ Статус: ЗАПУЩЕН\n"
        detailed_report+="   📊 Контейнеров: $docker_containers\n"
        detailed_report+="   📊 Образов: $docker_images\n"
        
        local scanner_running=0
        for ((i=1; i<=SCANNER_INSTANCES; i++)); do
            if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "luna-agent-scanner-$i"; then
                ((scanner_running++))
            fi
        done
        
        local bags_running=0
        for ((i=1; i<=BAGS_INSTANCES; i++)); do
            if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "luna-agent-bags-$i"; then
                ((bags_running++))
            fi
        done
        
        local recorder_running=0
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
            recorder_running=1
        fi
        
        detailed_report+="   🔍 Scanner: $scanner_running/$SCANNER_INSTANCES\n"
        detailed_report+="   🎒 Bags: $bags_running/$BAGS_INSTANCES\n"
        detailed_report+="   📹 StreamRecorder: $recorder_running/1\n"
        
        if [[ $scanner_running -eq 0 ]] || [[ $bags_running -eq 0 ]]; then
            overall_status="⚠️"
            detailed_report+="   ⚠️  Не все агенты запущены!\n"
        fi
    else
        detailed_report+="   ❌ Статус: НЕ ЗАПУЩЕН\n"
        detailed_report+="   💡 Запустите сервис Docker\n"
        overall_status="❌"
    fi
    
    # 6. Проверка PostgreSQL (Configurator)
    detailed_report+="\n6. 🗄️  POSTGRESQL (CONFIGURATOR)\n"
    if command -v pg_isready &>/dev/null; then
        if pg_isready -h "$CONFIGURATOR_HOST" -p 5432 &>/dev/null; then
            detailed_report+="   ✅ Статус: ДОСТУПЕН\n"
            detailed_report+="   🌐 Хост: $CONFIGURATOR_HOST:5432\n"
        else
            detailed_report+="   ❌ Статус: НЕДОСТУПЕН\n"
            detailed_report+="   💡 Проверьте запущен ли PostgreSQL\n"
            overall_status="❌"
        fi
    else
        if command -v nc &>/dev/null; then
            if nc -z -w 2 "$CONFIGURATOR_HOST" 5432 &>/dev/null; then
                detailed_report+="   ✅ Статус: ПОРТ ОТКРЫТ\n"
                detailed_report+="   🌐 Хост: $CONFIGURATOR_HOST:5432\n"
            else
                detailed_report+="   ⚠️  Статус: ПОРТ ЗАКРЫТ\n"
                overall_status="⚠️"
            fi
        else
            detailed_report+="   ⚠️  Статус: НЕ ПРОВЕРЕН (нет утилит)\n"
            overall_status="⚠️"
        fi
    fi
    
    # 7. Проверка сетевых настроек
    detailed_report+="\n7. 🌐 СЕТЕВЫЕ НАСТРОЙКИ\n"
    detailed_report+="   📍 Host IP: $HOST_IP\n"
    detailed_report+="   🔗 API URL: $API_URL\n"
    detailed_report+="   👤 Account ID: $ACCOUNT_ID\n"
    
    local primary_ip
    primary_ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -1)
    if [[ -n "$primary_ip" ]]; then
        detailed_report+="   📡 Основной IP: $primary_ip\n"
    else
        detailed_report+="   ⚠️  Основной IP: НЕ ОПРЕДЕЛЕН\n"
        overall_status="⚠️"
    fi
    
    # 8. Проверка системных ресурсов
    detailed_report+="\n8. 💻 СИСТЕМНЫЕ РЕСУРСЫ\n"
    
    local cpu_load
    cpu_load=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk '{print $1}' || echo "N/A")
    detailed_report+="   ⚙️  CPU загрузка: $cpu_load\n"
    
    local mem_usage
    mem_usage=$(free -m 2>/dev/null | awk 'NR==2{printf "%.1f%%", $3*100/$2}' || echo "N/A")
    detailed_report+="   💾 Память: $mem_usage использовано\n"
    
    local disk_usage
    disk_usage=$(df / 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
    detailed_report+="   💿 Диск (/): $disk_usage\n"
    
    local gpu_count
    gpu_count=$(get_available_gpu_count)
    if [[ "$gpu_count" -gt 0 ]]; then
        detailed_report+="   🎮 GPU: $gpu_count доступно\n"
    else
        detailed_report+="   🎮 GPU: не обнаружены\n"
        if [[ "$SCANNER_USE_GPU" == "true" ]] || [[ "$BAGS_USE_GPU" == "true" ]]; then
            detailed_report+="   ⚠️  ВНИМАНИЕ: Агенты настроены на GPU!\n"
            overall_status="⚠️"
        fi
    fi
    
    # Сохранение файла отчета
    local report_dir="$REPORT_DIR/api_health"
    mkdir -p "$report_dir"
    local report_file="$report_dir/api_health_$(date +%Y%m%d_%H%M).txt"
    echo -e "$detailed_report" > "$report_file"
    
    # Отображение отчета
    show_message "🔍 Проверка API и сервисов" "$detailed_report" 35 100
    
    echo "📋 Полный отчет сохранен: $report_file"
    
    return 0
}
check_system_health() {
    local health_info=""
    
    if docker info &>/dev/null; then
        health_info+="🐳 Docker: ✅ запущен\n"
    else
        health_info+="🐳 Docker: ❌ не запущен\n"
    fi
    
    if curl -s --connect-timeout 5 "$API_URL" &>/dev/null; then
        health_info+="📡 API: ✅ доступен\n"
    else
        health_info+="📡 API: ❌ недоступен\n"
    fi
    
    local luna_version
    luna_version=$(get_luna_platform_version)
    health_info+="🚀 Luna Platform: $luna_version\n"
    
    local license_streams
    license_streams=$(get_license_info)
    health_info+="📄 Лицензия: $license_streams потоков\n"
    
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    if [[ "$available_gpus" -gt 0 ]]; then
        health_info+="🎮 Доступно GPU: $available_gpus\n"
    else
        health_info+="🎮 GPU: ❌ не обнаружены (используется CPU)\n"
    fi
    
    local disk_usage
    disk_usage=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    if [[ $disk_usage -lt 80 ]]; then
        health_info+="💿 Диск: ${disk_usage}% использовано\n"
    else
        health_info+="💿 Диск: ${disk_usage}% использовано ⚠️ (мало места)\n"
    fi
    
    local mem_info
    mem_info=$(free -h 2>/dev/null | awk 'NR==2{print $3"/"$2}' || echo "N/A")
    health_info+="💾 Память: $mem_info\n"
    
    local scanner_running=0
    for ((i=1; i<=SCANNER_INSTANCES; i++)); do
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "luna-agent-scanner-$i"; then
            ((scanner_running++))
        fi
    done
    health_info+="🔍 Запущено scanner: $scanner_running/$SCANNER_INSTANCES\n"
    
    local bags_running=0
    for ((i=1; i<=BAGS_INSTANCES; i++)); do
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "luna-agent-bags-$i"; then
            ((bags_running++))
        fi
    done
    health_info+="🎒 Запущено bags: $bags_running/$BAGS_INSTANCES\n"
    
    local recorder_running=0
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
        recorder_running=1
    fi
    health_info+="📹 Запущено StreamRecorder: $recorder_running/1\n"
    
    show_message "📊 Состояние системы" "$health_info"
}
validate_camera_file() {
    local input_file="$1"
    local errors=0
    local warnings=0
    
    if [[ "$input_file" != */* ]] && [[ "$input_file" != *.* ]]; then
        local config_file_path="$CAMS_LIST_DIR/$input_file"
        if [[ -f "$config_file_path" ]]; then
            input_file="$config_file_path"
            echo "📁 Найден файл в директории cams_list: $input_file"
        else
            config_file_path="$CONFIG_DIR/$input_file"
            if [[ -f "$config_file_path" ]]; then
                input_file="$config_file_path"
                echo "📁 Найден файл в директории конфигурации: $input_file"
            fi
        fi
    fi
    
    if [[ ! -f "$input_file" ]]; then
        echo "❌ Файл не найден: $input_file"
        return 1
    fi
    local line_num=0
  
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ ! "$line" =~ [[:space:]]+ ]]; then
            echo "❌ Строка $line_num: отсутствует пробел между именем камеры и URL - '$line'"
            ((errors++))
            continue
        fi
        
        local camera_name camera_url
        camera_name=$(echo "$line" | awk '{print $1}')
        camera_url=$(echo "$line" | awk '{$1=""; print substr($0,2)}' | sed 's/^[[:space:]]*//')
        
        if [[ -z "$camera_name" ]]; then
            echo "❌ Строка $line_num: пустое имя камеры - '$line'"
            ((errors++))
        fi
        
        if [[ -z "$camera_url" ]]; then
            echo "❌ Строка $line_num: пустой URL - '$line'"
            ((errors++))
        elif [[ ! "$camera_url" =~ ^(rtsp|rtsps|http|https):// ]]; then
            echo "❌ Строка $line_num: неверный формат URL (должен начинаться с rtsp://, rtsps://, http:// или https://) - '$line'"
            ((errors++))
        elif [[ "$camera_url" =~ [[:space:]] ]]; then
            echo "❌ Строка $line_num: URL содержит пробелы - '$line'"
            ((errors++))
        fi
        
    done < "$input_file"
    
    echo ""
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        echo "✅ Файл корректен, ошибок не найдено"
        return 0
    elif [[ $errors -eq 0 && $warnings -gt 0 ]]; then
        echo "⚠️  Файл содержит $warnings предупреждений (работать будет, но рекомендуется исправить формат)"
        return 0
    else
        echo "❌ Найдено ошибок: $errors, предупреждений: $warnings"
        return 1
    fi
}
# ============================================================================
# ОПТИМИЗИРОВАННЫЕ ФУНКЦИИ УПРАВЛЕНИЯ BAGS АГЕНТОМ
# ============================================================================
run_bags_migration() {
    echo "🔄 Запуск миграции базы данных конфигурации для Bags"
    
    local migrate_cmd="docker run -v /etc/localtime:/etc/localtime:ro --entrypoint=/bin/bash --rm --network=host $DOCKER_REGISTRY/agent-bags-configs:$BAGS_TAG -c \"python3 -m agent_bags_configs.migrate head --config_db_url postgres://luna:luna@${HOST_IP}:5432/luna_configurator\""
    
    show_message "🔄 Миграция базы данных Bags" "Выполняется миграция базы данных конфигурации для Bags...\n\n⏳ Это может занять несколько секунд."
    
    if eval "$migrate_cmd" 2>&1 | tee /tmp/bags_migration.log; then
        echo "✅ Миграция базы данных Bags успешно выполнена"
        show_message "✅ Миграция Bags завершена" "Миграция базы данных Bags успешно выполнена!"
        return 0
    else
        local migration_error
        migration_error=$(cat /tmp/bags_migration.log 2>/dev/null || echo "Неизвестная ошибка")
        echo "❌ Ошибка выполнения миграции Bags: $migration_error"
        show_message "❌ Ошибка миграции Bags" "Не удалось выполнить миграцию базы данных для Bags:\n\n$migration_error\n\n🔍 Проверьте:\n• Доступность PostgreSQL\n• Корректность учетных данных\n• Сетевое подключение\n• Доступность Docker образа agent-bags-configs:$BAGS_TAG"
        return 1
    fi
}
start_bags_instances() {
    echo "🚀 Запуск инстансов luna-agent-bags"
    
    echo "🔄 Выполнение миграции базы данных для Bags..."
    show_message "🔄 Миграция базы данных Bags" "Выполняется миграция базы данных конфигурации для Bags...\n\n⏳ Это может занять несколько секунд."
    
    if ! run_bags_migration; then
        if ! show_yesno "❌ Ошибка миграции Bags" "Не удалось выполнить миграцию базы данных для Bags.\n\nБез миграции Bags могут работать некорректно.\n\nПродолжить запуск Bags?"; then
            return 1
        fi
    fi
    
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    
    local total_instances=$BAGS_INSTANCES
    local started_count=0
    local failed_count=0
    
    local run_mode="$BAGS_USE_GPU"
    if [[ "$run_mode" != "true" ]]; then
        run_mode="false"
    fi
    
    if [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]]; then
        show_message "ℹ️  Информация" "Конфигурация запуска Bags:\n• 📊 Всего инстансов: $total_instances\n• 🎮 Режим: GPU\n• ❌ Доступно GPU: 0\n\nBags будут запущены на CPU"
        echo "ℹ️  GPU не обнаружены, но режим GPU включен. Запуск Bags на CPU"
    elif [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        show_message "ℹ️  Информация" "Конфигурация запуска Bags: \n• 📊 Всего инстансов: $total_instances\n• ✅ Доступно GPU: $available_gpus\n• 🔄 Распределение: ЧЕТНЫЕ инстансы на GPU0, НЕЧЕТНЫЕ на GPU1"
        echo "✅ Обнаружено доступных GPU для Bags: $available_gpus, распределение: четные на GPU0, нечетные на GPU1"
    else
        show_message "ℹ️  Информация" "Конфигурация запуска Bags: \n• 📊 Всего инстансов: $total_instances\n• 🖥️  Режим: CPU\n"
        echo "ℹ️  Запуск Bags в режиме CPU"
    fi
    
    local current=0
    
    for ((i=1; i<=total_instances; i++)); do
        local instance_name="luna-agent-bags-$i"
        local bags_port=$((BAGS_PORT_START + i - 1))
        
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "$instance_name"; then
            echo "✅ Контейнер $instance_name уже запущен, пропускаем"
            continue
        fi
        
        if netstat -tuln 2>/dev/null | grep -q ":${bags_port} "; then
            echo "❌ Порт $bags_port занят, пропускаем инстанс $instance_name"
            ((failed_count++))
            continue
        fi
        
        ((current++))
        
        local docker_cmd="docker run --env=CONFIGURATOR_HOST=$CONFIGURATOR_HOST \
--env=CONFIGURATOR_PORT=$CONFIGURATOR_PORT \
--env=PORT=$bags_port \
--env=WORKER_COUNT=$WORKER_COUNT \
--env=RELOAD_CONFIG=1 \
--env=RELOAD_CONFIG_INTERVAL=10 \
-v /etc/localtime:/etc/localtime:ro \
--name=$instance_name \
--restart=always \
--detach=true \
--network=host \
$DOCKER_REGISTRY/luna-agent-bags:$BAGS_TAG"
        
        if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
            local gpu_device
            if [[ $((i % 2)) -eq 0 ]]; then
                gpu_device="0"
            else
                if [[ "$available_gpus" -gt 1 ]]; then
                    gpu_device="1"
                else
                    gpu_device="0"
                fi
            fi
            
            if check_gpu_availability "$gpu_device"; then
                docker_cmd=$(echo "$docker_cmd" | sed "s/--detach=true/--gpus device=$gpu_device --detach=true/")
                
                if [[ -n "$TUI_CMD" ]]; then
                    echo "🚀 Запуск: $instance_name на GPU$gpu_device $current/$total_instances"
                else
                    echo "🚀 Запуск: $instance_name на GPU$gpu_device $current/$total_instances"
                fi
            else
                echo "❌ GPU$gpu_device недоступен, запускаем $instance_name на CPU"
                if [[ -n "$TUI_CMD" ]]; then
                    echo "🚀 Запуск: $instance_name на CPU $current/$total_instances"
                else
                    echo "🚀 Запуск: $instance_name на CPU $current/$total_instances"
                fi
            fi
        else
            if [[ -n "$TUI_CMD" ]]; then
                echo "🚀 Запуск: $instance_name на CPU $current/$total_instances"
            else
                echo "🚀 Запуск: $instance_name на CPU $current/$total_instances"
            fi
        fi
        
        if eval "$docker_cmd" 2>/dev/null; then
            echo "✅ Успешно запущен $instance_name порт: $bags_port"
            ((started_count++))
            sleep 0.5
        else
            echo "❌ Ошибка запуска $instance_name"
            ((failed_count++))
        fi
    done
    
    local result_message="✅ Запуск инстансов Bags завершен:\n\n"
    result_message+="✅ Успешно: $started_count\n"
    result_message+="❌ Ошибок: $failed_count\n"
    result_message+="📊 Всего: $total_instances\n\n"
    result_message+="⚙️  Конфигурация:\n"
    result_message+="• 🐳 Docker образ: $DOCKER_REGISTRY/luna-agent-bags:$BAGS_TAG\n"
    
    if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        result_message+="• 🎮 Режим: GPU распределение: четные на GPU0, нечетные на GPU1\n"
        result_message+="• ✅ Доступно GPU: $available_gpus\n"
        
        result_message+="• 🔄 Распределение инстансов:\n"
        for ((gpu=0; gpu<available_gpus; gpu++)); do
            local instances_on_gpu=0
            for ((i=1; i<=total_instances; i++)); do
                local assigned_gpu
                if [[ $((i % 2)) -eq 0 ]]; then
                    assigned_gpu="0"
                else
                    if [[ "$available_gpus" -gt 1 ]]; then
                        assigned_gpu="1"
                    else
                        assigned_gpu="0"
                    fi
                fi
                if [[ "$assigned_gpu" == "$gpu" ]]; then
                    ((instances_on_gpu++))
                fi
            done
            result_message+="  🎮 GPU$gpu: $instances_on_gpu инстансов\n"
        done
    elif [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]]; then
        result_message+="• 🎮 Режим: GPU \n"
        result_message+="• 🖥️  Фактически: запущены на CPU\n"
    else
        result_message+="• 🖥️  Режим: CPU\n"
    fi
    
    result_message+="• 🔌 Порт начала: $BAGS_PORT_START\n"
    result_message+="• ⚙️  Configurator: $CONFIGURATOR_HOST:$CONFIGURATOR_PORT\n\n"
    
    show_message "📊 Результат запуска Bags" "$result_message"
    
    if [[ "$started_count" -eq 0 ]]; then
        echo "❌ Не удалось запустить ни одного инстанса bags"
        return 1
    fi
    
    return 0
}
show_bags_status() {
    local available_gpus
    available_gpus=$(get_available_gpu_count)
    local run_mode="$BAGS_USE_GPU"
    
    local status_info=""
    local running_count=0
    
    status_info+="📊 Статус инстансов luna-agent-bags\n\n"
    status_info+="📋 Системная информация:\n"
    
    if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        status_info+="• 🎮 Режим: GPU распределение: четные на GPU0, нечетные на GPU1\n"
        status_info+="• ✅ Доступно GPU: $available_gpus\n"
    elif [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]]; then
        status_info+="• 🎮 Режим: GPU\n"
        status_info+="• 🖥️  Фактически: запущены на CPU\n"
    else
        status_info+="• 🖥️  Режим: CPU\n"
    fi
    
    status_info+="• 🐳 Docker образ: $DOCKER_REGISTRY/luna-agent-bags:$BAGS_TAG\n"
    status_info+="• 📊 Конфигурация инстансов: $BAGS_INSTANCES\n"
    status_info+="• ⚙️  Luna Configurator: $CONFIGURATOR_HOST:$CONFIGURATOR_PORT\n"
    status_info+="• 🔌 Порт начала: $BAGS_PORT_START\n\n"
    
    status_info+="🔄 Состояние инстансов:\n"
    
    for ((i=1; i<=BAGS_INSTANCES; i++)); do
        local instance_name="luna-agent-bags-$i"
        local bags_port=$((BAGS_PORT_START + i - 1))
        
        local device_info
        if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
            if [[ $((i % 2)) -eq 0 ]]; then
                device_info="GPU0"
            else
                if [[ "$available_gpus" -gt 1 ]]; then
                    device_info="GPU1"
                else
                    device_info="GPU0"
                fi
            fi
        else
            device_info="CPU"
        fi
        
        if docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -q "$instance_name"; then
            local container_status
            container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$instance_name" | awk '{print $2}')
            status_info+="✅ $instance_name ($device_info, порт:$bags_port) - $container_status\n"
            ((running_count++))
        else
            status_info+="❌ $instance_name ($device_info, порт:$bags_port) - ОСТАНОВЛЕН\n"
        fi
    done
    
    status_info+="\n📊 Всего запущено: $running_count/$BAGS_INSTANCES"
    
    if [[ "$run_mode" == "true" && "$available_gpus" -gt 0 ]]; then
        status_info+="\n\n🎮 Распределение по GPU:\n"
        for ((gpu=0; gpu<available_gpus; gpu++)); do
            local instances_on_gpu=0
            for ((i=1; i<=BAGS_INSTANCES; i++)); do
                local assigned_gpu
                if [[ $((i % 2)) -eq 0 ]]; then
                    assigned_gpu="0"
                else
                    if [[ "$available_gpus" -gt 1 ]]; then
                        assigned_gpu="1"
                    else
                        assigned_gpu="0"
                    fi
                fi
                if [[ "$assigned_gpu" == "$gpu" ]]; then
                    ((instances_on_gpu++))
                fi
            done
            status_info+="• 🎮 GPU$gpu: $instances_on_gpu инстансов\n"
        done
    fi
    
    if [[ "$run_mode" == "true" && "$available_gpus" -eq 0 ]] && [[ "$running_count" -gt 0 ]]; then
        status_info+="\n\n⚠️  ВНИМАНИЕ: Bags настроены на GPU, но GPU не обнаружены. Запуск на CPU."
    fi
    
    show_message "📊 Статус Bags" "$status_info" 25 90
}
stop_bags_instances() {
    echo "🛑 Остановка всех инстансов luna-agent-bags"
    
    local containers
    containers=$(docker ps -a --filter "name=luna-agent-bags" --format "{{.Names}}" 2>/dev/null)
    
    if [[ -z "$containers" ]]; then
        show_message "📊 Результат" "Контейнеры luna-agent-bags не найдены"
        return 0
    fi
    local container_array=()
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            container_array+=("$container")
        fi
    done <<< "$containers"
    
    local total_containers=${#container_array[@]}
    local stopped_count=0
    local current=0
    
    show_message "ℹ️  Информация" "Найдено контейнеров для остановки: $total_containers\n\nКонтейнеры:\n${container_array[*]}"
    
    if ! show_yesno "⚠️  Подтверждение остановки" "Остановить все найденные контейнеры luna-agent-bags?\n\n📊 Количество: $total_containers"; then
        show_message "❌ Отмена" "Остановка отменена"
        return 0
    fi
    
    for container in "${container_array[@]}"; do
        ((current++))
        local percent=$((current * 100 / total_containers))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "🛑 Остановка контейнеров" "Остановка: $container $current/$total_containers" "$percent"
        else
            echo "🛑 Остановка: $container $current/$total_containers"
        fi
        
        if docker rm -f "$container" 2>/dev/null; then
            ((stopped_count++))
            echo "✅ Остановлен контейнер: $container"
        else
            echo "❌ Ошибка остановки контейнера: $container"
        fi
        sleep 0.3
    done
    
    show_message "📊 Результат" "✅ Остановка завершена:\n\n✅ Успешно остановлено: $stopped_count\n📊 Всего контейнеров: $total_containers"
    echo "✅ Остановлено контейнера bags: $stopped_count из $total_containers"
}
# ============================================================================
# ФУНКЦИИ УПРАВЛЕНИЯ ЛОГАМИ BAGS
# ============================================================================
collect_bags_logs() {
    local hours="$1"
    local selected_instances="$2"
    
    echo "📦 Сбор логов Bags за $hours"
    
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M")
    local date_dir
    date_dir=$(date +"%Y-%m-%d")
    local logs_date_dir="$LOGS_DIR/$date_dir"
    mkdir -p "$logs_date_dir"
    
    local archive_name="bags_logs_${timestamp}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    mkdir -p "$temp_dir/bags"
    
    local instances_to_collect=()
    if [[ "$selected_instances" == "all" ]]; then
        for ((i=1; i<=BAGS_INSTANCES; i++)); do
            instances_to_collect+=("luna-agent-bags-$i")
        done
    else
        IFS=',' read -ra instances_to_collect <<< "$selected_instances"
    fi
    
    local total_instances=${#instances_to_collect[@]}
    local processed=0
    
    # Создаем файл для объединенных логов
    local bags_all_log="$temp_dir/bags/bags_all.log"
    echo "=== ОБЪЕДИНЕННЫЙ ЛОГ BAGS ===" > "$bags_all_log"
    echo "Время сбора: $(date)" >> "$bags_all_log"
    echo "Период: $hours" >> "$bags_all_log"
    echo "=================================" >> "$bags_all_log"
    echo "" >> "$bags_all_log"
    
    for instance in "${instances_to_collect[@]}"; do
        ((processed++))
        local percent=$((processed * 100 / total_instances))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "📦 Сбор логов Bags" "Сбор логов: $instance ($processed/$total_instances)" "$percent"
        else
            echo "📦 Сбор логов: $instance ($processed/$total_instances)"
        fi
        
        local log_file="$temp_dir/bags/${instance}.log"
        
        if docker ps -a 2>/dev/null | grep -q "$instance"; then
            if docker logs --since "$hours" --timestamps "$instance" > "$log_file" 2>&1; then
                echo "✅ Логи собраны для $instance"
                # Добавляем в объединенный лог
                echo "=== ЛОГ $instance ===" >> "$bags_all_log"
                echo "" >> "$bags_all_log"
                cat "$log_file" >> "$bags_all_log"
                echo "" >> "$bags_all_log"
                echo "=================================" >> "$bags_all_log"
                echo "" >> "$bags_all_log"
            else
                echo "❌ Ошибка сбора логов для $instance"
                echo "❌ Ошибка сбора логов для контейнера $instance" > "$log_file"
            fi
        else
            echo "❌ Контейнер $instance не найден"
            echo "❌ Контейнер $instance не найден или не запущен" > "$log_file"
        fi
    done
    
    if tar -czf "$LOGS_DIR/$archive_name" -C "$temp_dir" .; then
        echo "✅ Архив логов Bags создан: $archive_name"
        rm -rf "$temp_dir"
        
        local archive_size
        archive_size=$(du -h "$LOGS_DIR/$archive_name" 2>/dev/null | cut -f1 || echo "N/A")
        local archive_info="✅ Архив логов Bags успешно создан!\n\n"
        archive_info+="📁 Имя файла: $archive_name\n"
        archive_info+="📊 Размер: $archive_size\n"
        archive_info+="⏱️  Период: $hours\n"
        archive_info+="🔧 Инстансы: ${instances_to_collect[*]}\n"
        archive_info+="📁 Путь: $LOGS_DIR/$archive_name"
        
        show_message "✅ Сбор логов Bags завершен" "$archive_info"
    else
        echo "❌ Ошибка создания архива логов Bags"
        show_message "❌ Ошибка" "Не удалось создать архив логов Bags"
        rm -rf "$temp_dir"
        return 1
    fi
}
collect_bags_logs_screen() {
    local hours
    hours=$(show_input "📦 СБОР ЛОГОВ BAGS" "Введите период для сбора логов (например: 6h, 1d):" "$DEFAULT_LOG_HOURS")
    [[ -z "$hours" ]] && return
    
    local instances_options=()
    
    for ((i=1; i<=BAGS_INSTANCES; i++)); do
        instances_options+=("luna-agent-bags-$i" "Bags инстанс $i" "OFF")
    done
    
    local selected_instances
    selected_instances=$(show_checklist "📋 ВЫБОР ИНСТАНСОВ BAGS" "Выберите инстансы Bags для сбора логов:" "${instances_options[@]}")
    
    if [[ -n "$selected_instances" ]]; then
        selected_instances=$(echo "$selected_instances" | sed 's/"//g')
        
        if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ" "Собрать логи Bags за период: $hours\n\n🔧 Инстансы:\n$selected_instances"; then
            collect_bags_logs "$hours" "$selected_instances"
        fi
    else
        show_message "❌ ОТМЕНА" "Сбор логов Bags отменен"
    fi
}
view_bags_logs() {
    echo "📋 Просмотр логов Bags..."
    
    local instances_options=()
    local running_instances=0
    
    for ((i=1; i<=BAGS_INSTANCES; i++)); do
        local instance_name="luna-agent-bags-$i"
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "$instance_name"; then
            instances_options+=("$instance_name" "Bags инстанс $i (✅ запущен)")
            ((running_instances++))
        else
            instances_options+=("$instance_name" "Bags инстанс $i (❌ остановлен)")
        fi
    done
    
    if [[ $running_instances -eq 0 ]]; then
        show_message "❌ Ошибка" "Нет запущенных инстансов Bags"
        return
    fi
    
    local selected_instance
    selected_instance=$(show_menu "📋 ВЫБОР ИНСТАНСА BAGS" "Выберите инстанс Bags для просмотра логов:" "${instances_options[@]}")
    
    if [[ -n "$selected_instance" ]]; then
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "$selected_instance"; then
            local lines
            lines=$(show_input "📋 ПРОСМОТР ЛОГОВ" "Введите количество строк логов (по умолчанию 50):" "50")
            [[ -z "$lines" ]] && lines=50
            
            docker logs --tail "$lines" "$selected_instance" 2>&1 | tee /tmp/bags_logs.log
            show_message "📋 Логи $selected_instance" "$(cat /tmp/bags_logs.log)" 25 90
        else
            show_message "❌ Ошибка" "Инстанс $selected_instance не запущен"
        fi
    fi
}
# ============================================================================
# НОВАЯ ФУНКЦИЯ: ОСТАНОВКА И УДАЛЕНИЕ ВСЕХ КОНТЕЙНЕРОВ DOCKER
# ============================================================================
stop_all_docker_containers() {
    echo "🛑 Остановка и удаление всех контейнеров Docker..."
    
    # Получаем список всех контейнеров
    local containers
    containers=$(docker container ls -aq 2>/dev/null)
    
    if [[ -z "$containers" ]]; then
        show_message "📊 Результат" "Контейнеры Docker не найдены"
        return 0
    fi
    
    local container_count
    container_count=$(echo "$containers" | wc -l)
    
    show_message "ℹ️  Информация" "Найдено контейнеров для удаления: $container_count"
    
    if ! show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ УДАЛЕНИЯ" "ВЫ УВЕРЕНЫ, ЧТО ХОТИТЕ ОСТАНОВИТЬ И УДАЛИТЬ ВСЕ КОНТЕЙНЕРЫ DOCKER?\n\n📊 Количество: $container_count\n\n⚠️  Это остановит ВСЕ сервисы включая:\n• Агенты Scanner и Bags\n• StreamRecorder\n• Другие контейнеры\n\n⛔ Действие НЕОБРАТИМО!"; then
        show_message "❌ Отмена" "Удаление контейнеров отменено"
        return 0
    fi
    
    echo "🛑 Останавливаем и удаляем все контейнеры..."
    
    # Останавливаем и удаляем все контейнеры
    if docker container rm -f $(docker container ls -aq) 2>&1 | tee /tmp/docker_cleanup.log; then
        local success_count
        success_count=$(grep -c "Removed" /tmp/docker_cleanup.log 2>/dev/null || echo "0")
        
        # Проверяем остались ли контейнеры
        local remaining_containers
        remaining_containers=$(docker container ls -aq 2>/dev/null | wc -l)
        
        local result_message="✅ УДАЛЕНИЕ КОНТЕЙНЕРОВ ЗАВЕРШЕНО\n\n"
        result_message+="📊 Результат:\n"
        result_message+="• Удалено контейнеров: $success_count\n"
        
        if [[ "$remaining_containers" -eq 0 ]]; then
            result_message+="• ✅ Все контейнеры удалены\n"
            result_message+="• 🐳 Система Docker очищена\n"
        else
            result_message+="• ⚠️  Осталось контейнеров: $remaining_containers\n"
            result_message+="• 🔧 Возможно требуются привилегии\n"
        fi
        
        result_message+="\n🛑 Остановлены все сервисы:\n"
        result_message+="• 🔍 Scanner агенты\n"
        result_message+="• 🎒 Bags агенты\n"
        result_message+="• 📹 StreamRecorder\n"
        result_message+="• 🐳 Другие Docker контейнеры\n"
        
        show_message "🎯 Результат" "$result_message"
        
        # Обновляем статус StreamRecorder
        STREAM_RECORDER_RUNNING="false"
        
        echo "✅ Удаление контейнеров завершено"
        return 0
    else
        local error_msg
        error_msg=$(tail -5 /tmp/docker_cleanup.log 2>/dev/null || echo "Неизвестная ошибка")
        show_message "❌ Ошибка" "Не удалось удалить все контейнеры:\n\n$error_msg\n\nПопробуйте выполнить команду вручную:\n  docker container rm -f \$(docker container ls -aq)"
        return 1
    fi
}
# ============================================================================
# ФУНКЦИИ ОСТАНОВКИ ВСЕХ АГЕНТОВ
# ============================================================================
stop_all_agents() {
    echo "🛑 Остановка и удаление всех агентов Scanner и Bags"
    
    local scanner_containers bags_containers
    scanner_containers=$(docker ps -a --filter "name=luna-agent-scanner" --format "{{.Names}}" 2>/dev/null)
    bags_containers=$(docker ps -a --filter "name=luna-agent-bags" --format "{{.Names}}" 2>/dev/null)
    
    local all_containers=()
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            all_containers+=("$container")
        fi
    done <<< "$scanner_containers"
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            all_containers+=("$container")
        fi
    done <<< "$bags_containers"
    
    local total_containers=${#all_containers[@]}
    
    if [[ $total_containers -eq 0 ]]; then
        show_message "📊 Результат" "Контейнеры агентов не найдены"
        return 0
    fi
    
    local container_list=""
    for container in "${all_containers[@]}"; do
        container_list+="• $container\n"
    done
    
    show_message "ℹ️  Информация" "Найдено контейнеров для остановки: $total_containers\n\nКонтейнеры:\n$container_list"
    
    if ! show_yesno "⚠️  Подтверждение остановки" "Остановить и удалить ВСЕ найденные контейнеры агентов?\n\n📊 Количество: $total_containers\n\n⚠️  Это действие остановит всю обработку видеоаналитики!"; then
        show_message "❌ Отмена" "Остановка отменена"
        return 0
    fi
    
    local stopped_count=0
    local current=0
    
    for container in "${all_containers[@]}"; do
        ((current++))
        local percent=$((current * 100 / total_containers))
        
        if [[ -n "$TUI_CMD" ]]; then
            show_progress "🛑 Остановка всех агентов" "Остановка: $container $current/$total_containers" "$percent"
        else
            echo "🛑 Остановка: $container $current/$total_containers"
        fi
        
        if docker rm -f "$container" 2>/dev/null; then
            ((stopped_count++))
            echo "✅ Остановлен контейнер: $container"
        else
            echo "❌ Ошибка остановки контейнера: $container"
        fi
        sleep 0.3
    done
    
    local result_message="✅ Остановка всех агентов завершена:\n\n"
    result_message+="✅ Успешно остановлено: $stopped_count\n"
    result_message+="📊 Всего контейнеров: $total_containers\n\n"
    result_message+="🛑 Остановленные агенты:\n"
    result_message+="• 🔍 Scanner: $SCANNER_INSTANCES инстансов\n"
    result_message+="• 🎒 Bags: $BAGS_INSTANCES инстансов\n\n"
    result_message+="⏸️  Вся обработка видеоаналитики остановлена!"
    
    show_message "📊 Результат остановки" "$result_message"
    echo "✅ Остановка всех агентов завершена: $stopped_count из $total_containers"
}
# ============================================================================
# МЕНЮ УПРАВЛЕНИЯ STREAMRECORDER
# ============================================================================
stream_recorder_menu() {
    while true; do
        local recorder_status="❌ Остановлен"
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
            recorder_status="✅ Запущен"
        fi
        
        local choice
        choice=$(show_menu "📹 УПРАВЛЕНИЕ STREAMRECORDER" "Управление записью видеопотоков\n\n📊 Статус: $recorder_status\n🌐 Веб-интерфейс: http://${HOST_IP}:${DEFAULT_RECORDER_PORT_WEB}" \
            "1" "🚀 Запуск StreamRecorder" \
            "2" "🛑 Остановка StreamRecorder" \
            "3" "🔄 Перезапуск StreamRecorder" \
            "4" "📊 Статус StreamRecorder" \
            "5" "📋 Просмотр логов StreamRecorder" \
            "6" "⚙️ Конфигурация StreamRecorder" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") start_stream_recorder ;;
            "2") stop_stream_recorder ;;
            "3") restart_stream_recorder ;;
            "4") show_stream_recorder_status ;;
            "5") view_stream_recorder_logs ;;
            "6") configure_stream_recorder ;;
            "0") break ;;
        esac
    done
}
# ============================================================================
# ОСНОВНОЕ МЕНЮ И ПОДМЕНЮ
# ============================================================================
main_menu() {
    while true; do
        local recorder_status="❌"
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
            recorder_status="✅"
        fi
        
        local choice
        choice=$(show_menu "🎥 СИСТЕМА УПРАВЛЕНИЯ КАМЕРАМИ АНАЛИТИКИ v5.5.5" "Универсальная система управления видеопотоками и аналитикой\n\n📊 Мониторинг • ⚙️  Конфигурация • 🔍 Диагностика • 📦 Релизы\n\n📹 StreamRecorder: $recorder_status" \
            "1" "🔍 Управление агентами аналитики" \
            "2" "🎥 Управление видеопотоками" \
            "3" "📹 Запуск записи потоков StreamRecorder" \
            "4" "⚙️ Конфигурация системы" \
            "5" "🔍 Диагностика и мониторинг" \
            "6" "🛑 Остановка и удаление всех Docker контейнеров" \
            "7" "🚪 Выход")
        
        case "$choice" in
            "1") analytics_agents_management_menu ;;
            "2") video_streams_management_menu ;;
            "3") stream_recorder_menu ;;
            "4") system_configuration_menu ;;
            "5") diagnostics_monitoring_menu ;;
            "6") stop_all_docker_containers ;;
            "7") exit_screen ;;
            *) break ;;
        esac
    done
}
analytics_agents_management_menu() {
    while true; do
        local choice
        choice=$(show_menu "🔍 УПРАВЛЕНИЕ АГЕНТАМИ АНАЛИТИКИ" "Управление всеми агентами видеоаналитики\n\n🔍 Scanner • 🎒 Bags • 📦 Релизы • 🛑 Глобальная остановка" \
            "1" "🔍 Управление агентом Scanner" \
            "2" "🎒 Управление агентом Bags" \
            "3" "📦 Получить релизы агентов аналитики" \
            "4" "🛑 Остановка агентов" \
            "5" "📊 Статус агентов" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") scanner_management_menu ;;
            "2") bags_management_menu ;;
            "3") get_agent_releases ;;
            "4") stop_all_agents ;;
            "5") show_all_agents_status ;;
            "0") break ;;
        esac
    done
}
show_all_agents_status() {
    local status_info=""
    
    status_info+="📊 СТАТУС LUNA-AGENT-SCANNER\n"
    local scanner_running=0
    for ((i=1; i<=SCANNER_INSTANCES; i++)); do
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "luna-agent-scanner-$i"; then
            ((scanner_running++))
        fi
    done
    status_info+="✅ Запущено: $scanner_running/$SCANNER_INSTANCES\n\n"
    
    status_info+="📊 СТАТУС LUNA-AGENT-BAGS\n"
    local bags_running=0
    for ((i=1; i<=BAGS_INSTANCES; i++)); do
        if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "luna-agent-bags-$i"; then
            ((bags_running++))
        fi
    done
    status_info+="✅ Запущено: $bags_running/$BAGS_INSTANCES\n\n"
    
    status_info+="📊 СТАТУС STREAMRECORDER\n"
    local recorder_running=0
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "recorder"; then
        recorder_running=1
    fi
    status_info+="✅ Запущен: $recorder_running/1\n\n"
    
    local total_agents=$((SCANNER_INSTANCES + BAGS_INSTANCES + 1))
    local total_running=$((scanner_running + bags_running + recorder_running))
    status_info+="📊 ОБЩИЙ СТАТУС АГЕНТОВ\n"
    status_info+="📊 Всего агентов: $total_agents\n"
    status_info+="✅ Запущено: $total_running\n"
    status_info+="❌ Остановлено: $((total_agents - total_running))\n\n"
    
    if [[ $total_running -eq 0 ]]; then
        status_info+="⏸️  Все агенты остановлены!\n"
    elif [[ $total_running -lt $total_agents ]]; then
        status_info+="⚠️  Часть агентов не запущена\n"
    else
        status_info+="✅ Все агенты работают\n"
    fi
    
    show_message "📊 Статус всех агентов" "$status_info"
}
video_streams_management_menu() {
    while true; do
        local choice
        choice=$(show_menu "🎥 УПРАВЛЕНИЕ ВИДЕОПОТОКАМИ" "Управление видеопотоками и аналитикой\n\n➕ Добавление • 🎛️ Управление • 📊 Мониторинг" \
            "1" "➕ Добавление видеопотоков" \
            "2" "🎛️ Управление выбранными видеопотоками" \
            "3" "⚙️ Операции с видеопотоками" \
            "4" "📊 Мониторинг видеопотоков" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") add_streams_menu ;;
            "2") selected_streams_management_menu ;;
            "3") stream_operations_menu ;;
            "4") status_screen ;;
            "0") break ;;
        esac
    done
}
scanner_management_menu() {
    while true; do
        local choice
        choice=$(show_menu "🔍 УПРАВЛЕНИЕ LUNA-AGENT-SCANNER" "Управление инстансами сканера\n\n🚀 Запуск • 🛑 Остановка • 📊 Мониторинг • 📦 Логи" \
            "1" "🚀 Запуск всех инстансов" \
            "2" "🛑 Остановка всех инстансов" \
            "3" "📊 Статус инстансов" \
            "4" "⚙️  Конфигурация Scanner" \
            "5" "📦 Управление логами Scanner" \
#            "6" "🔄 Принудительная миграция БД" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") start_scanner_instances ;;
            "2") stop_scanner_instances ;;
            "3") show_scanner_status ;;
            "4") scanner_configuration_screen ;;
            "5") scanner_logs_menu ;;
            "6") run_migration ;;
            "0") break ;;
        esac
    done
}
scanner_logs_menu() {
    while true; do
        local choice
        choice=$(show_menu "📦 УПРАВЛЕНИЕ ЛОГАМИ SCANNER" "Управление логами агента Scanner\n\n📦 Сбор • 📋 Просмотр • 🗑️  Очистка" \
            "1" "📦 Сбор логов Scanner" \
            "2" "📋 Просмотр логов Scanner" \
#            "3" "🗑️  Очистка старых логов" \
#            "4" "📊 Статистика логов" \
#            "5" "⚙️  Настройки логов" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") collect_scanner_logs_screen ;;
            "2") view_scanner_logs ;;
            "3") cleanup_old_logs ;;
            "4") show_logs_stats ;;
            "5") logs_configuration_screen ;;
            "0") break ;;
        esac
    done
}
bags_management_menu() {
    while true; do
        local choice
        choice=$(show_menu "🎒 УПРАВЛЕНИЕ LUNA-AGENT-BAGS" "Управление инстансами bags\n\n⚠️  Перед запуском выполняется миграция БД\n⚙️  Режим: $([[ "$BAGS_USE_GPU" == "true" ]] && echo "🎮 GPU" || echo "🖥️  CPU")" \
            "1" "🚀 Запуск всех инстансов" \
            "2" "🛑 Остановка всех инстансов" \
            "3" "📊 Статус инстансов" \
            "4" "⚙️ Конфигурация агента Bags" \
            "5" "📦 Управление логами Bags" \
#            "6" "🔄 Принудительная миграция БД" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") start_bags_instances ;;
            "2") stop_bags_instances ;;
            "3") show_bags_status ;;
            "4") bags_configuration_screen ;;
            "5") bags_logs_menu ;;
            "6") run_bags_migration ;;
            "0") break ;;
        esac
    done
}
bags_logs_menu() {
    while true; do
        local choice
        choice=$(show_menu "📦 УПРАВЛЕНИЕ ЛОГАМИ BAGS" "Управление логами агента Bags\n\n📦 Сбор • 📋 Просмотр • 🗑️  Очистка" \
            "1" "📦 Сбор логов Bags" \
            "2" "📋 Просмотр логов Bags" \
#            "3" "🗑️ Очистка старых логов" \
#            "4" "📊 Статистика логов" \
#            "5" "⚙️ Настройки логов" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") collect_bags_logs_screen ;;
            "2") view_bags_logs ;;
            "3") cleanup_old_logs ;;
            "4") show_logs_stats ;;
            "5") logs_configuration_screen ;;
            "0") break ;;
        esac
    done
}
system_configuration_menu() {
    while true; do
        local choice
        choice=$(show_menu "⚙️  КОНФИГУРАЦИЯ СИСТЕМЫ" "Управление конфигурациями и шаблонами\n\n⚙️  Настройки • 📋 Шаблоны • 🔧 Агенты" \
            "1" "⚙️ Основные настройки" \
            "2" "📋 Шаблон конфигурации аналитики" \
            "3" "🔧 Настройки агента Scanner" \
            "4" "🎒 Настройки агента Bags" \
            "5" "👁️ Просмотр файлов конфигурации" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") system_settings_screen ;;
            "2") template_management_screen ;;
            "3") scanner_configuration_screen ;;
            "4") bags_configuration_screen ;;
            "5") show_config_files ;;
            "0") break ;;
        esac
    done
}
diagnostics_monitoring_menu() {
    while true; do
        local choice
        choice=$(show_menu "🔍 ДИАГНОСТИКА И МОНИТОРИНГ" "Диагностика потоков и технические отчёты\n\n🔍 Анализ • 📊 Мониторинг • 📋 Отчеты • 📡 Проверка API" \
            "1" "🔍 Диагностика видеопотоков камер" \
            "2" "📸 Получить кадры видеопотоков" \
            "3" "📊 Системный мониторинг" \
            "4" "📊 Состояние системы" \
            "5" "🎮 Состояние GPU" \
            "6" "📋 Отчёт состояния ОС" \
            "7" "📡 Проверка состояния API и сервисов" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") stream_analysis_menu ;;
            "2") recording_and_frames_menu ;;
            "3") system_monitoring_menu ;;
            "4") check_system_health ;;
            "5") check_gpu_health ;;
            "6") generate_system_report ;;
            "7") check_api_health ;;
            "0") break ;;
        esac
    done
}
recording_and_frames_menu() {
    while true; do
        local choice
        choice=$(show_menu "📸 ПОЛУЧЕНИЕ КАДРОВ ВИДЕОПОТОКОВ" "Получить кадры с камер\n\n📸 Кадры • 🎥 Одиночные • 📦 Пакетные" \
            "1" "📦 Получение кадров из файла" \
            "2" "🎥 Получение кадра с одной камеры" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") capture_frames_screen ;;
            "2") capture_single_frame_screen ;;
            "0") break ;;
        esac
    done
}
add_streams_menu() {
    while true; do
        local choice
        choice=$(show_menu "➕ ДОБАВЛЕНИЕ ВИДЕОПОТОКОВ" "Добавление новых видеопотоков в видеоаналитике\n\n📁 Файлы • 🎥 Одиночные • 📦 Пакетные" \
            "1" "📁 Добавить список видеопотоков из файла" \
            "2" "🎥 Добавить видеопоток" \
            "3" "👁️ Предпросмотр шаблона аналитики" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") add_cameras_file_screen ;;
            "2") add_single_camera_screen ;;
            "3") preview_template_screen ;;
            "0") break ;;
        esac
    done
}
preview_template_screen() {
    if [[ -f "$TEMPLATE_FILE" ]]; then
        local template_content
        template_content=$(cat "$TEMPLATE_FILE")
        show_message "👁️  ПРЕДПРОСМОТР ШАБЛОНА АНАЛИТИКИ" "$template_content" 25 90
    else
        show_message "❌ ОШИБКА" "Шаблонный файл не найден"
    fi
}
add_cameras_file_screen() {
    local file_path
    file_path=$(show_input "➕ ДОБАВЛЕНИЕ КАМЕР" "Введите путь к файлу с камерами:" "$DEFAULT_CAMERAS_FILE")
    
    if [[ -n "$file_path" ]]; then
        if select_analytics_before_add; then
            local preview
            preview=$(head -10 "$file_path" 2>/dev/null || echo "Не удалось прочитать файл")
            
            local template_preview=""
            if [[ -f "$TEMPLATE_FILE" ]]; then
                template_preview=$(jq -c '.' "$TEMPLATE_FILE" 2>/dev/null || cat "$TEMPLATE_FILE")
                template_preview="📋 Шаблон аналитики:\n${template_preview:0:200}..."
            else
                template_preview="❌ Шаблон аналитики не найден"
            fi
            
            local confirmation_message="📁 Файл: $file_path\n\n"
            confirmation_message+="📄 Первые 10 строк:\n$preview\n\n"
            confirmation_message+="$template_preview\n\n"
            confirmation_message+="📊 ВЫБРАННЫЕ АНАЛИТИКИ:\n"
                
            [[ "$WEAPON_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 🔫 Обнаружение оружия\n"
            [[ "$FIGHTS_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 🥊 Обнаружение драк\n"
            [[ "$FIRE_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 🔥 Обнаружение огня\n"
            [[ "$FACECOVER_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 😷 Обнаружение балаклав\n"
            [[ "$PEOPLE_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 👥 Подсчет людей\n"
            [[ "$BAGS_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 🎒 Оставленные предметы\n"
            [[ "$HANDSUP_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 🙌 Обнаружение рук вверх\n"
            [[ "$LYINGDOWN_ANALYTICS_ENABLED" == "true" ]] && confirmation_message+="• 🛌 Обнаружение лежащих людей\n"
            confirmation_message+="➕ Продолжить добавление?"
            
            if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ" "$confirmation_message"; then
                add_streams_from_file "$file_path"
            fi
        fi
    else
        show_message "❌ ОШИБКА" "Файл не указан"
    fi
}
add_single_camera_screen() {
    local camera_name
    camera_name=$(show_input "➕ ДОБАВЛЕНИЕ КАМЕРЫ" "Введите имя камеры:" "")
    [[ -z "$camera_name" ]] && return
    
    local camera_url
    camera_url=$(show_input "➕ ДОБАВЛЕНИЕ КАМЕРЫ" "Введите URL камеры:" "")
    [[ -z "$camera_url" ]] && return
    
    if [[ -f "$TEMPLATE_FILE" ]]; then
        local template_content
        template_content=$(cat "$TEMPLATE_FILE")
        
        local confirmation_message="🎥 Камера: $camera_name\n🔗 URL: $camera_url\n\n"
        confirmation_message+="📋 Текущий шаблон аналитики:\n"
        confirmation_message+="${template_content:0:300}...\n\n"
        confirmation_message+="✏️  Хотите редактировать шаблон перед добавлением?"
        
        if show_yesno "✏️  РЕДАКТИРОВАНИЕ ШАБЛОНА" "$confirmation_message"; then
            local editor="${EDITOR:-nano}"
            if command -v "$editor" &> /dev/null; then
                local temp_template
                temp_template=$(mktemp)
                cp "$TEMPLATE_FILE" "$temp_template"
                
                $editor "$temp_template"
                
                if jq empty "$temp_template" 2>/dev/null; then
                    cp "$temp_template" "$TEMPLATE_FILE"
                    show_message "✅ УСПЕХ" "Шаблон успешно обновлен"
                else
                    show_message "❌ ОШИБКА" "Неверный JSON в шаблоне. Шаблон не изменен."
                    rm -f "$temp_template"
                    return
                fi
                rm -f "$temp_template"
            else
                show_message "❌ ОШИБКА" "Текстовый редактор $editor не найден"
            fi
        fi
    fi
    
    if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ" "➕ Добавить камеру?\n🎥 Имя: $camera_name\n🔗 URL: $camera_url"; then
        if add_stream "$camera_name" "$camera_url"; then
            show_message "✅ УСПЕХ" "Камера успешно добавлена"
        else
            show_message "❌ ОШИБКА" "Не удалось добавить камеру"
        fi
    fi
}
selected_streams_management_menu() {
    while true; do
        local choice
        choice=$(show_menu "🎛️  УПРАВЛЕНИЕ ВЫБРАННЫМИ ПОТОКАМИ" "Работа с выбранными видеопотоками\n\n📋 Выбор • 🎛️ Управление • 👁️  Просмотр" \
            "1" "📋 Выбрать видеопотоки" \
            "2" "⏸️  Остановить выбранные" \
            "3" "▶️  Возобновить выбранные" \
            "4" "🗑️  Удалить выбранные" \
            "5" "👁️  Показать выбранные" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") select_streams_screen ;;
            "2") stop_selected_streams_screen ;;
            "3") resume_selected_streams_screen ;;
            "4") delete_selected_streams_screen ;;
            "5") show_selected_streams ;;
            "0") break ;;
        esac
    done
}
stream_operations_menu() {
    while true; do
        local choice
        choice=$(show_menu "⚙️  ОПЕРАЦИИ С ВИДЕОПОТОКАМИ" "Операции со всеми видеопотоками\n\n⏸️  Остановка • ▶️  Возобновление • 🗑️  Удаление" \
            "1" "⏸️  Остановить все потоки" \
            "2" "▶️  Возобновить все потоки" \
            "3" "🗑️  Удалить все потоки" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") stop_all_streams_screen ;;
            "2") resume_all_streams_screen ;;
            "3") delete_all_streams_screen ;;
            "0") break ;;
        esac
    done
}
stream_analysis_menu() {
    while true; do
        local choice
        choice=$(show_menu "🔍 ДИАГНОСТИКА ВИДЕОПОТОКОВ" "Получить технические параметры видеопотоков\n\n⚡ Быстрая проверка • ⚙️  Настройки • 📋 Выбор отчета" \
            "1" "⚡ Быстрая проверка видеопотоков из файла" \
            "2" "🎥 Быстрая проверка одного видеопотока" \
#            "3" "🔍 Проверить формат файла камер" \
            "4" "📋 Просмотр отчетов диагностики" \
            "5" "⚙️ Настройки диагностики" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") analyze_cameras_simple_screen ;;
            "2") analyze_single_camera_screen ;;
            "3") validate_camera_file_screen ;;
            "4") view_reports_screen ;;
            "5") analysis_configuration_screen ;;
            "0") break ;;
        esac
    done
}
validate_camera_file_screen() {
    local input_file
    input_file=$(show_input "🔍 ПРОВЕРКА ФОРМАТА ФАЙЛА" "Введите путь к файлу с камерами:" "$DEFAULT_CAMERAS_FILE")
    
    if [[ -n "$input_file" ]]; then
        local validation_result
        validation_result=$(validate_camera_file "$input_file")
        show_message "📊 РЕЗУЛЬТАТ ПРОВЕРКИ" "$validation_result" 20 80
    else
        show_message "❌ ОШИБКА" "Файл не указан"
    fi
}
view_reports_screen() {
    while true; do
        local choice
        choice=$(show_menu "📋 ПРОСМОТР ОТЧЕТОВ" "Просмотр сохраненных отчетов диагностики\n\n🆕 Последний • 📋 Выбор • 📂 Все" \
            "1" "👁️  Просмотр последнего отчета" \
            "2" "📋 Выбрать отчет для просмотра" \
            "3" "📂 Показать все отчеты" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") view_latest_report ;;
            "2") select_report_screen ;;
            "3") view_all_reports ;;
            "0") break ;;
        esac
    done
}
select_report_screen() {
    local reports
    reports=($(find "$REPORT_DIR" -name "camera_report_*.txt" -type f 2>/dev/null | sort -r))
    
    if [[ ${#reports[@]} -eq 0 ]]; then
        show_message "ℹ️  Информация" "Отчеты не найдены"
        return
    fi
    
    local report_options=()
    for report in "${reports[@]}"; do
        local report_name report_date
        report_name=$(basename "$report")
        report_date=$(stat -c %y "$report" 2>/dev/null | cut -d' ' -f1,2 || echo "N/A")
        report_options+=("$report" "$report_name - $report_date")
    done
    
    local selected_report
    selected_report=$(show_menu "📋 ВЫБОР ОТЧЕТА" "Выберите отчет для просмотра:" "${report_options[@]}")
    
    if [[ -n "$selected_report" ]]; then
        view_analysis_report "$selected_report"
    fi
}
system_monitoring_menu() {
    while true; do
        local choice
        choice=$(show_menu "📊 СИСТЕМНЫЙ МОНИТОРИНГ" "Просмотр системной информации\n\n📋 Информация • 📊 Отчеты" \
            "1" "📋 Техническая информация СВТ" \
            "2" "📊 Отчёт состояния ОС" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1") show_system_info ;;
            "2") generate_system_report ;;
            "0") break ;;
        esac
    done
}
capture_frames_screen() {
    local input_file
    input_file=$(show_input "📸 ПОЛУЧЕНИЕ КАДРОВ" "Введите путь к файлу с камерами:" "$DEFAULT_CAMS_LIST")
    
    if [[ -n "$input_file" ]]; then
        local preview
        preview=$(head -10 "$input_file" 2>/dev/null || echo "Не удалось прочитать файл")
        if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ" "📁 Файл: $input_file\n\n📄 Первые 10 строк:\n$preview\n\n📸 Продолжить получение кадров?"; then
            capture_frames "$input_file"
        fi
    else
        show_message "❌ ОШИБКА" "Файл не указан"
    fi
}
capture_single_frame_screen() {
    local camera_name
    camera_name=$(show_input "📸 ПОЛУЧЕНИЕ СНИМКА" "Введите имя камеры:" "")
    [[ -z "$camera_name" ]] && return
    
    local camera_url
    camera_url=$(show_input "📸 ПОЛУЧЕНИЕ СНИМКА" "Введите URL камеры:" "")
    [[ -z "$camera_url" ]] && return
    
    local temp_file
    temp_file=$(mktemp)
    echo "$camera_name $camera_url" > "$temp_file"
    
    capture_frames "$temp_file"
    
    rm -f "$temp_file"
}
select_streams_screen() {
    if select_streams_dialog "📋 ВЫБОР ВИДЕОПОТОКОВ" "Выберите видеопотоки для операций:" "multi"; then
        show_message "✅ ВЫБОР ЗАВЕРШЕН" "✅ Выбрано видеопотоков: ${#SELECTED_STREAMS[@]}\n\n📋 Идентификаторы:\n${SELECTED_STREAMS[*]}"
    else
        show_message "❌ ОТМЕНА" "Выбор видеопотоков отменен"
    fi
}
stop_selected_streams_screen() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "❌ ОШИБКА" "Сначала выберите видеопотоки через меню '📋 Выбрать видеопотоки'"
        return 1
    fi
    
    if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ ОСТАНОВКИ" "⏸️  Остановить выбранные видеопотоки?\n\n📊 Количество: ${#SELECTED_STREAMS[@]}\n\n🎥 Потоки:\n${SELECTED_STREAMS[*]}"; then
        stop_selected_streams
    else
        show_message "❌ ОТМЕНА" "Остановка отменена"
    fi
}
resume_selected_streams_screen() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "❌ Ошибка" "Сначала выберите видеопотоки через меню '📋 Выбрать видеопотоки'"
        return 1
    fi
    
    if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ ВОЗОБНОВЛЕНИЯ" "▶️  Возобновить выбранные видеопотоки?\n\n📊 Количество: ${#SELECTED_STREAMS[@]}\n\n🎥 Потоки:\n${SELECTED_STREAMS[*]}"; then
        resume_selected_streams
    else
        show_message "❌ ОТМЕНА" "Возобновление отменена"
    fi
}
delete_selected_streams_screen() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "❌ ОШИБКА" "Сначала выберите видеопотоки через меню '📋 Выбрать видеопотоки'"
        return 1
    fi
    
    delete_selected_streams
}
show_selected_streams() {
    if [[ ${#SELECTED_STREAMS[@]} -eq 0 ]]; then
        show_message "ℹ️  ИНФОРМАЦИЯ" "Нет выбранных видеопотоков"
        return
    fi
    
    local stream_info="✅ Выбрано видеопотоков: ${#SELECTED_STREAMS[@]}\n\n"
    stream_info+="📋 Идентификаторы:\n"
    for stream_id in "${SELECTED_STREAMS[@]}"; do
        stream_info+="• $stream_id\n"
    done
    
    show_message "🎥 ВЫБРАННЫЕ ВИДЕОПОТОКИ" "$stream_info"
}
stop_all_streams_screen() {
    if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ ОСТАНОВКИ" "ВЫ УВЕРЕНЫ, ЧТО ХОТИТЕ ОСТАНОВИТЬ ВСЕ ВИДЕОПОТОКИ?\n\n⏸️  Это приостановит обработку видео."; then
        stop_all_streams
    else
        show_message "❌ Отмена" "Остановка отменена"
    fi
}
resume_all_streams_screen() {
    if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ ВОЗОБНОВЛЕНИЯ" "ВЫ УВЕРЕНЫ, ЧТО ХОТИТЕ ВОЗОБНОВИТЬ ВСЕ ВИДЕОПОТОКИ?\n\n▶️  Это возобновит обработку видео."; then
        resume_all_streams
    else
        show_message "❌ Отмена" "Возобновление отменена"
    fi
}
delete_all_streams_screen() {
    delete_all_streams
}
status_screen() {
    show_stream_status
}
scanner_configuration_screen() {
    while true; do
        local gpu_status="❌ Отключено"
        if [[ "$SCANNER_USE_GPU" == "true" ]]; then
            gpu_status="✅ Включено"
        fi
        
        local choice
        choice=$(show_menu "⚙️  КОНФИГУРАЦИЯ SCANNER" "Текущие настройки:\n🏷️  Tag: $SCANNER_TAG\n📊 Инстансы: $SCANNER_INSTANCES\n🐳 Registry: $DOCKER_REGISTRY\n🎮 Использование GPU: $gpu_status" \
            "1" "🏷️  Изменить Tag" \
            "2" "📊 Изменить количество инстансов" \
            "3" "🐳 Изменить Docker Registry" \
            "4" "⚙️ Изменить Luna Configurator" \
            "5" "🎮 Использование GPU: $gpu_status" \
            "6" "🔄 Сбросить настройки" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                local new_tag
                new_tag=$(show_input "🏷️  SCANNER TAG" "Введите новый tag:" "$SCANNER_TAG")
                if [[ -n "$new_tag" ]]; then
                    SCANNER_TAG="$new_tag"
                    save_scanner_config
                    show_message "✅ УСПЕХ" "🏷️  Tag обновлен: $SCANNER_TAG"
                fi
                ;;
            "2")
                local new_instances
                new_instances=$(show_input "📊 КОЛИЧЕСТВО ИНСТАНСОВ" "Введите количество инстансов:" "$SCANNER_INSTANCES")
                if [[ -n "$new_instances" ]] && [[ "$new_instances" =~ ^[0-9]+$ ]]; then
                    SCANNER_INSTANCES="$new_instances"
                    save_scanner_config
                    show_message "✅ УСПЕХ" "📊 Количество инстансов обновлено: $SCANNER_INSTANCES"
                else
                    show_message "❌ ОШИБКА" "Введите корректное число"
                fi
                ;;
            "3")
                local new_registry
                new_registry=$(show_input "🐳 DOCKER REGISTRY" "Введите адрес registry:" "$DOCKER_REGISTRY")
                if [[ -n "$new_registry" ]]; then
                    DOCKER_REGISTRY="$new_registry"
                    save_scanner_config
                    show_message "✅ УСПЕХ" "🐳 Docker Registry обновлен: $DOCKER_REGISTRY"
                fi
                ;;
            "4")
                local new_host new_port
                new_host=$(show_input "⚙️  CONFIGURATOR HOST" "Введите хост configurator:" "$CONFIGURATOR_HOST")
                new_port=$(show_input "⚙️  CONFIGURATOR PORT" "Введите порт configurator:" "$CONFIGURATOR_PORT")
                if [[ -n "$new_host" ]] && [[ -n "$new_port" ]]; then
                    CONFIGURATOR_HOST="$new_host"
                    CONFIGURATOR_PORT="$new_port"
                    save_scanner_config
                    show_message "✅ УСПЕХ" "⚙️  Configurator обновлен: $CONFIGURATOR_HOST:$CONFIGURATOR_PORT"
                fi
                ;;
            "5")
                if [[ "$SCANNER_USE_GPU" == "true" ]]; then
                    SCANNER_USE_GPU="false"
                    show_message "🎮 РЕЖИМ GPU" "🎮 Использование GPU для Scanner отключено"
                else
                    SCANNER_USE_GPU="true"
                    show_message "🎮 РЕЖИМ GPU" "🎮 Использование GPU для Scanner включено"
                fi
                save_scanner_config
                ;;
            "6")
                if show_yesno "🔄 СБРОС НАСТРОЕК" "Сбросить настройки scanner к значениям по умолчанию?"; then
                    create_default_scanner_config
                    # shellcheck source=/dev/null
                    source "$SCANNER_CONFIG_FILE"
                    show_message "✅ УСПЕХ" "Настройки scanner сброшены"
                fi
                ;;
            "0") break ;;
        esac
    done
}
bags_configuration_screen() {
    while true; do
        local gpu_status="❌ Отключено"
        if [[ "$BAGS_USE_GPU" == "true" ]]; then
            gpu_status="✅ Включено"
        fi
        
        local choice
        choice=$(show_menu "⚙️  КОНФИГУРАЦИЯ BAGS" "Текущие настройки:\n🏷️  Tag: $BAGS_TAG\n📊 Инстансы: $BAGS_INSTANCES\n🐳 Registry: $DOCKER_REGISTRY\n🎮 Использование GPU: $gpu_status" \
            "1" "🏷️ Изменить Tag" \
            "2" "📊 Изменить количество инстансов" \
            "3" "🐳 Изменить Docker Registry" \
            "4" "⚙️ Изменить Luna Configurator" \
            "5" "🎮 Использование GPU: $gpu_status" \
            "6" "🔄 Сбросить настройки" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                local new_tag
                new_tag=$(show_input "🏷️  BAGS TAG" "Введите новый tag:" "$BAGS_TAG")
                if [[ -n "$new_tag" ]]; then
                    BAGS_TAG="$new_tag"
                    save_bags_config
                    show_message "✅ УСПЕХ" "🏷️  Tag обновлен: $BAGS_TAG"
                fi
                ;;
            "2")
                local new_instances
                new_instances=$(show_input "📊 КОЛИЧЕСТВО ИНСТАНСОВ" "Введите количество инстансов:" "$BAGS_INSTANCES")
                if [[ -n "$new_instances" ]] && [[ "$new_instances" =~ ^[0-9]+$ ]]; then
                    BAGS_INSTANCES="$new_instances"
                    save_bags_config
                    show_message "✅ УСПЕХ" "📊 Количество инстансов обновлен: $BAGS_INSTANCES"
                else
                    show_message "❌ ОШИБКА" "Введите корректное число"
                fi
                ;;
            "3")
                local new_registry
                new_registry=$(show_input "🐳 DOCKER REGISTRY" "Введите адрес registry:" "$DOCKER_REGISTRY")
                if [[ -n "$new_registry" ]]; then
                    DOCKER_REGISTRY="$new_registry"
                    save_bags_config
                    show_message "✅ УСПЕХ" "🐳 Docker Registry обновлен: $DOCKER_REGISTRY"
                fi
                ;;
            "4")
                local new_host new_port
                new_host=$(show_input "⚙️  CONFIGURATOR HOST" "Введите хост configurator:" "$CONFIGURATOR_HOST")
                new_port=$(show_input "⚙️  CONFIGURATOR PORT" "Введите порт configurator:" "$CONFIGURATOR_PORT")
                if [[ -n "$new_host" ]] && [[ -n "$new_port" ]]; then
                    CONFIGURATOR_HOST="$new_host"
                    CONFIGURATOR_PORT="$new_port"
                    save_bags_config
                    show_message "✅ УСПЕХ" "⚙️  Configurator обновлен: $CONFIGURATOR_HOST:$CONFIGURATOR_PORT"
                fi
                ;;
            "5")
                if [[ "$BAGS_USE_GPU" == "true" ]]; then
                    BAGS_USE_GPU="false"
                    show_message "🎮 РЕЖИМ GPU" "🎮 Использование GPU для Bags отключено"
                else
                    BAGS_USE_GPU="true"
                    show_message "🎮 РЕЖИМ GPU" "🎮 Использование GPU для Bags включено"
                fi
                save_bags_config
                ;;
            "6")
                if show_yesno "🔄 СБРОС НАСТРОЕК" "Сбросить настройки bags к значениям по умолчанию?"; then
                    create_default_bags_config
                    # shellcheck source=/dev/null
                    source "$BAGS_CONFIG_FILE"
                    show_message "✅ УСПЕХ" "Настройки bags сброшены"
                fi
                ;;
            "0") break ;;
        esac
    done
}
analyze_cameras_simple_screen() {
    local cameras_file
    cameras_file=$(show_input "🔍 БЫСТРАЯ ДИАГНОСТИКА" "Введите путь к файлу с камерами:" "$DEFAULT_CAMERAS_FILE")
    
    if [[ -n "$cameras_file" ]]; then
        local preview
        preview=$(head -10 "$cameras_file" 2>/dev/null || echo "Не удалось прочитать файл")
        if show_yesno "⚠️  ПОДТВЕРЖДЕНИЕ" "📁 Файл: $cameras_file\n\n📄 Первые 10 строк:\n$preview\n\n🔍 Продолжить диагностику?"; then
            analyze_cameras_from_file "$cameras_file"
        fi
    else
        show_message "❌ ОШИБКА" "Файл не указан"
    fi
}
analyze_single_camera_screen() {
    local camera_url
    camera_url=$(show_input "🎥 ДИАГНОСТИКА ОДНОЙ КАМЕРЫ" "Введите URL камеры:" "")
    [[ -z "$camera_url" ]] && return
    
    local temp_file
    temp_file=$(mktemp)
    echo "single_camera $camera_url" > "$temp_file"
    
    analyze_cameras_from_file "$temp_file"
    
    rm -f "$temp_file"
}
view_latest_report() {
    local latest_report
    latest_report=$(find "$REPORT_DIR" -name "camera_report_*.txt" -type f 2>/dev/null | sort -r | head -1)
    
    if [[ -n "$latest_report" ]]; then
        view_analysis_report "$latest_report"
    else
        show_message "ℹ️  Информация" "Отчеты не найдены"
    fi
}
view_all_reports() {
    local reports
    reports=($(find "$REPORT_DIR" -name "camera_report_*.txt" -type f 2>/dev/null | sort -r))
    
    if [[ ${#reports[@]} -eq 0 ]]; then
        show_message "ℹ️  Информация" "Отчеты не найдены"
        return
    fi
    
    local report_list="📋 НАЙДЕННЫЕ ОТЧЕТЫ:\n\n"
    for report in "${reports[@]}"; do
        local report_name report_date report_size
        report_name=$(basename "$report")
        report_date=$(stat -c %y "$report" 2>/dev/null | cut -d' ' -f1,2 || echo "N/A")
        report_size=$(du -h "$report" 2>/dev/null | cut -f1 || echo "N/A")
        report_list+="📄 $report_name\n📅 $report_date\n📊 $report_size\n────────────────────────────────\n"
    done
    
    show_message "📋 ВСЕ ОТЧЕТЫ ДИАГНОСТИКИ" "$report_list" 25 90
}
analysis_configuration_screen() {
    while true; do
        local choice
        choice=$(show_menu "⚙️  НАСТРОЙКИ ДИАГНОСТИКИ" "Текущие настройки диагностики:\n⏱️  Таймаут: ${ANALYSIS_TIMEOUT} сек\n📁 Файл по умолчанию: $DEFAULT_CAMERAS_FILE" \
            "1" "⏱️  Изменить таймаут диагностики" \
            "2" "📁 Изменить файл по умолчанию" \
            "3" "🔄 Сбросить настройки" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                local new_timeout
                new_timeout=$(show_input "⏱️  ТАЙМАУТ ДИАГНОСТИКИ" "Введите таймаут в секундах:" "$ANALYSIS_TIMEOUT")
                if [[ -n "$new_timeout" ]] && [[ "$new_timeout" =~ ^[0-9]+$ ]]; then
                    ANALYSIS_TIMEOUT="$new_timeout"
                    save_analysis_config
                    show_message "✅ УСПЕХ" "⏱️  Таймаут обновлен: ${ANALYSIS_TIMEOUT} сек"
                else
                    show_message "❌ ОШИБКА" "Введите корректное число"
                fi
                ;;
            "2")
                local new_cameras_file
                new_cameras_file=$(show_input "📁 ФАЙЛ КАМЕР ПО УМОЛЧАНИЮ" "Введите путь к файлу:" "$DEFAULT_CAMERAS_FILE")
                if [[ -n "$new_cameras_file" ]]; then
                    DEFAULT_CAMERAS_FILE="$new_cameras_file"
                    save_analysis_config
                    show_message "✅ УСПЕХ" "📁 Файл по умолчанию обновлен: $DEFAULT_CAMERAS_FILE"
                fi
                ;;
            "3")
                if show_yesno "🔄 СБРОС НАСТРОЕК" "Сбросить настройки диагностики к значениям по умолчанию?"; then
                    create_default_analysis_config
                    # shellcheck source=/dev/null
                    source "$ANALYSIS_CONFIG_FILE"
                    show_message "✅ УСПЕХ" "Настройки диагностики сброшены"
                fi
                ;;
            "0") break ;;
        esac
    done
}
logs_configuration_screen() {
    while true; do
        local choice
        choice=$(show_menu "⚙️  НАСТРОЙКИ ЛОГОВ" "Текущие настройки:\n⏰ Период сбора: $DEFAULT_LOG_HOURS\n🗑️  Хранение: $LOG_RETENTION_DAYS дней\n📁 Директория: $LOGS_DIR" \
            "1" "⏰ Изменить период сбора логов" \
            "2" "🗑️  Изменить период хранения логов" \
            "3" "📁 Изменить директорию логов" \
            "4" "🔄 Сбросить настройки" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                local new_hours
                new_hours=$(show_input "⏰ ПЕРИОД СБОРА ЛОГОВ" "Введите период (например: 6h, 1d, 24h):" "$DEFAULT_LOG_HOURS")
                if [[ -n "$new_hours" ]]; then
                    DEFAULT_LOG_HOURS="$new_hours"
                    save_logs_config
                    show_message "✅ УСПЕХ" "⏰ Период сбора обновлен: $DEFAULT_LOG_HOURS"
                fi
                ;;
            "2")
                local new_days
                new_days=$(show_input "🗑️  ПЕРИОД ХРАНЕНИЯ ЛОГОВ" "Введите количество дней хранения:" "$LOG_RETENTION_DAYS")
                if [[ -n "$new_days" ]] && [[ "$new_days" =~ ^[0-9]+$ ]]; then
                    LOG_RETENTION_DAYS="$new_days"
                    save_logs_config
                    show_message "✅ УСПЕХ" "🗑️  Период хранения обновлен: $LOG_RETENTION_DAYS дней"
                else
                    show_message "❌ ОШИБКА" "Введите корректное число"
                fi
                ;;
            "3")
                local new_logs_dir
                new_logs_dir=$(show_input "📁 ДИРЕКТОРИЯ ЛОГОВ" "Введите путь к директории:" "$LOGS_DIR")
                if [[ -n "$new_logs_dir" ]]; then
                    LOGS_DIR="$new_logs_dir"
                    mkdir -p "$LOGS_DIR"
                    save_logs_config
                    show_message "✅ УСПЕХ" "📁 Директория логов обновлена: $LOGS_DIR"
                fi
                ;;
            "4")
                if show_yesno "🔄 СБРОС НАСТРОЕК" "Сбросить настройки логов к значениям по умолчанию?"; then
                    create_default_logs_config
                    # shellcheck source=/dev/null
                    source "$LOGS_CONFIG_FILE"
                    show_message "✅ УСПЕХ" "Настройки логов сброшены"
                fi
                ;;
            "0") break ;;
        esac
    done
}
system_settings_screen() {
    while true; do
        local choice
        choice=$(show_menu "⚙️  ОСНОВНЫЕ НАСТРОЙКИ" "Текущие настройки системы:\n👤 Account ID: $ACCOUNT_ID\n🌐 API URL: $API_URL\n📡 Host IP: $HOST_IP" \
            "1" "👤 Изменить Account ID" \
            "2" "🌐 Изменить API URL" \
            "3" "📡 Изменить Host IP" \
            "4" "🔄 Сбросить настройки" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                local new_account_id
                new_account_id=$(show_input "👤 ACCOUNT ID" "Введите Account ID:" "$ACCOUNT_ID")
                if [[ -n "$new_account_id" ]]; then
                    ACCOUNT_ID="$new_account_id"
                    save_config
                    show_message "✅ УСПЕХ" "👤 Account ID обновлен: $ACCOUNT_ID"
                fi
                ;;
            "2")
                local new_api_url
                new_api_url=$(show_input "🌐 API URL" "Введите URL API:" "$API_URL")
                if [[ -n "$new_api_url" ]]; then
                    API_URL="$new_api_url"
                    save_config
                    show_message "✅ УСПЕХ" "🌐 API URL обновлен: $API_URL"
                fi
                ;;
            "3")
                local new_host_ip
                new_host_ip=$(show_input "📡 HOST IP" "Введите IP адрес хоста:" "$HOST_IP")
                if [[ -n "$new_host_ip" ]]; then
                    HOST_IP="$new_host_ip"
                    save_config
                    show_message "✅ УСПЕХ" "📡 Host IP обновлен: $HOST_IP"
                fi
                ;;
            "4")
                if show_yesno "🔄 СБРОС НАСТРОЕК" "Сбросить основные настройки к значениям по умолчанию?"; then
                    ACCOUNT_ID="$DEFAULT_ACCOUNT_ID"
                    API_URL="$DEFAULT_API_URL"
                    HOST_IP="$DEFAULT_HOST_IP"
                    save_config
                    show_message "✅ УСПЕХ" "Основные настройки сброшены к значениям по умолчанию"
                fi
                ;;
            "0") break ;;
        esac
    done
}
template_management_screen() {
    while true; do
        local analytics_status=""
        [[ "$WEAPON_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="🔫 "
        [[ "$FIGHTS_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="🥊 "
        [[ "$FIRE_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="🔥 "
        [[ "$PEOPLE_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="👥 "
        [[ "$FACECOVER_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="😷 "
        [[ "$BAGS_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="🎒 "
        [[ "$HANDSUP_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="🙌 "
        [[ "$LYINGDOWN_ANALYTICS_ENABLED" == "true" ]] && analytics_status+="🛌 "
        
        if [[ -z "$analytics_status" ]]; then
            analytics_status="❌ Нет активных аналитик"
        fi
        
        local choice
        choice=$(show_menu "📋 УПРАВЛЕНИЕ ШАБЛОНОМ АНАЛИТИКИ" "Управление шаблоном конфигурации аналитик\n\n📊 Активные аналитики: $analytics_status\n📁 Файл шаблона: $TEMPLATE_FILE" \
            "1" "📊 Выбрать аналитики для шаблона" \
            "2" "👁️  Просмотр текущего шаблона" \
            "3" "✏️  Редактировать шаблон вручную" \
            "4" "🔄 Обновить шаблон с выбранными аналитиками" \
            "5" "🔄 Сбросить шаблон к умолчанию" \
            "0" "🔙 Назад")
        
        case "$choice" in
            "1")
                select_analytics_before_add
                ;;
            "2")
                if [[ -f "$TEMPLATE_FILE" ]]; then
                    local template_content
                    template_content=$(cat "$TEMPLATE_FILE")
                    show_message "👁️  ТЕКУЩИЙ ШАБЛОН АНАЛИТИКИ" "$template_content" 25 90
                else
                    show_message "❌ ОШИБКА" "Шаблонный файл не найден"
                fi
                ;;
            "3")
                if [[ -f "$TEMPLATE_FILE" ]]; then
                    local editor="${EDITOR:-nano}"
                    if command -v "$editor" &> /dev/null; then
                        $editor "$TEMPLATE_FILE"
                        show_message "✅ УСПЕХ" "Шаблон отредактирован"
                    else
                        show_message "❌ ОШИБКА" "Текстовый редактор $editor не найден"
                    fi
                else
                    show_message "❌ ОШИБКА" "Шаблонный файл не найден"
                fi
                ;;
            "4")
                create_default_template
                show_message "✅ УСПЕХ" "Шаблон обновлен с текущими настройками аналитик"
                ;;
            "5")
                if show_yesno "🔄 СБРОС ШАБЛОНА" "Сбросить шаблон аналитики к значениям по умолчанию?\n\n⚠️  Это удалит все пользовательские изменения в шаблоне."; then
                    create_default_template_config
                    # shellcheck source=/dev/null
                    source "$TEMPLATE_CONFIG_FILE"
                    create_default_template
                    show_message "✅ УСПЕХ" "Шаблон сброшен к значениям по умолчанию"
                fi
                ;;
            "0") break ;;
        esac
    done
}
show_config_files() {
    local config_files=""
    
    if [[ -f "$CONFIG_FILE" ]]; then
        config_files+="⚙️  Основные настройки ($CONFIG_FILE):\n"
        config_files+="$(cat "$CONFIG_FILE")\n\n"
    fi
    
    if [[ -f "$TEMPLATE_CONFIG_FILE" ]]; then
        config_files+="📋 Шаблон аналитики ($TEMPLATE_CONFIG_FILE):\n"
        config_files+="$(cat "$TEMPLATE_CONFIG_FILE")\n\n"
    fi
    
    if [[ -f "$SCANNER_CONFIG_FILE" ]]; then
        config_files+="🔍 Scanner ($SCANNER_CONFIG_FILE):\n"
        config_files+="$(cat "$SCANNER_CONFIG_FILE")\n\n"
    fi
    
    if [[ -f "$BAGS_CONFIG_FILE" ]]; then
        config_files+="🎒 Bags ($BAGS_CONFIG_FILE):\n"
        config_files+="$(cat "$BAGS_CONFIG_FILE")\n\n"
    fi
    
    if [[ -f "$ANALYSIS_CONFIG_FILE" ]]; then
        config_files+="🔍 Диагностика ($ANALYSIS_CONFIG_FILE):\n"
        config_files+="$(cat "$ANALYSIS_CONFIG_FILE")\n\n"
    fi
    
    if [[ -f "$LOGS_CONFIG_FILE" ]]; then
        config_files+="📦 Логи ($LOGS_CONFIG_FILE):\n"
        config_files+="$(cat "$LOGS_CONFIG_FILE")\n"
    fi
    
    if [[ -z "$config_files" ]]; then
        show_message "📂 ФАЙЛЫ КОНФИГУРАЦИИ" "Файлы конфигурации не найдены"
    else
        show_message "📂 ФАЙЛЫ КОНФИГУРАЦИИ" "$config_files" 30 90
    fi
}
exit_screen() {
    if show_yesno "🚪 ВЫХОД" "Вы уверены, что хотите выйти из системы?"; then
        exit 0
    fi
}
# Проверяем зависимости
check_dependencies
# Инициализируем систему
init
# Показываем информационный экран
show_system_info_splash
# Запускаем главное меню
main_menu

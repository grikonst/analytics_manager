#!/bin/bash
# build_with_makeself.sh

echo "🔨 Создание бинарного файла с помощью makeself..."

VER=v.5.5.0
# Проверяем установлен ли makeself
if ! command -v makeself &> /dev/null; then
    echo "Установка makeself..."
    sudo apt-get update && sudo apt-get install -y makeself
fi

# Создаем временную директорию для пакета
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/analytics_manager"

# Копируем скрипт
#cp 535.sh "$TEMP_DIR/analytics_manager/analytics_manager.sh"
#cp 542.sh "$TEMP_DIR/analytics_manager/analytics_manager.sh"
cp main.sh "$TEMP_DIR/analytics_manager/analytics_manager.sh"

chmod +x "$TEMP_DIR/analytics_manager/analytics_manager.sh"

# Создаем скрипт запуска
cat > "$TEMP_DIR/analytics_manager/launch.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./analytics_manager.sh "$@"
EOF
chmod +x "$TEMP_DIR/analytics_manager/launch.sh"

# Создаем бинарный файл
makeself --notemp --gzip --nox11 --nomd5 --nocrc "$TEMP_DIR/analytics_manager" cyk "Analytics Manager $VER" ./launch.sh

# Очистка
rm -rf "$TEMP_DIR"

echo "✅ Бинарный файл создан: cyk"
echo "Размер: $(du -h cyk | cut -f1)"

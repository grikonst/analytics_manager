#!/bin/bash
# build_with_makeself.sh

echo "🔨 Создание бинарного файла с помощью makeself..."

VER=v.5.5.5
# Проверяем установлен ли makeself
if ! command -v makeself &> /dev/null; then
    echo "Установка makeself..."
    sudo apt-get update && sudo apt-get install -y makeself
fi

# Создаем временную директорию для пакета
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/.analytics_manager"

# Копируем скрипт
cp main.sh "$TEMP_DIR/.analytics_manager/analytics_manager.sh"
chmod +x "$TEMP_DIR/.analytics_manager/analytics_manager.sh"

# Создаем скрипт запуска с автоматической очисткой
cat > "$TEMP_DIR/.analytics_manager/launch.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

# Запускаем основной скрипт
./analytics_manager.sh "$@"
EXIT_CODE=$?

# Удаляем папку с исходными файлами после завершения
cd ..
rm -rf "$SCRIPT_DIR"

exit $EXIT_CODE
EOF
chmod +x "$TEMP_DIR/.analytics_manager/launch.sh"

# Создаем бинарный файл
makeself --notemp --gzip --nox11 --nomd5 --nocrc "$TEMP_DIR/.analytics_manager" cyk "Analytics Manager $VER" ./launch.sh

echo "✅ Бинарный файл создан: cyk"
echo "Размер: $(du -h cyk | cut -f1)"
# Очистка временной директории
rm -rf "$TEMP_DIR"
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
mkdir -p "$TEMP_DIR/.a"

# Копируем скрипт
cp main.sh "$TEMP_DIR/.a/a.sh"
chmod +x "$TEMP_DIR/.a/a.sh"

# Создаем скрипт запуска с автоматической очисткой
cat > "$TEMP_DIR/.a/launch.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
cd "$SCRIPT_DIR"

# Запускаем основной скрипт
./a.sh "$@"
EXIT_CODE=$?

# Определяем родительскую директорию и удаляем только .a
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ANALYTICS_DIR_NAME="$(basename "$SCRIPT_DIR")"

# Переходим в родительскую директорию и удаляем папку .a
cd "$PARENT_DIR"
if [ -d "$ANALYTICS_DIR_NAME" ]; then
    rm -rf "$ANALYTICS_DIR_NAME"
fi

exit $EXIT_CODE
EOF
chmod +x "$TEMP_DIR/.a/launch.sh"

# Создаем бинарный файл
makeself --notemp --gzip --nox11 --nomd5 --nocrc "$TEMP_DIR/.a" cyk "Analytics Manager $VER" ./launch.sh

echo "✅ Бинарный файл создан: cyk"
echo "Размер: $(du -h cyk | cut -f1)"
# Очистка временной директории
rm -rf "$TEMP_DIR"

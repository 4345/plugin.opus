#!/bin/bash

# build.sh
# Скрипт сборки плагина Opus для macOS

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

OUTPUT_DIR=$1
TARGET_NAME=plugin_opus
OUTPUT_SUFFIX=dylib
CONFIG=Release

# Функция проверки ошибок после каждой команды
checkError() {
    if [ $? -ne 0 ]
    then
        echo "Ошибка выполнения (код $?). Сборка остановлена."
        exit -1
    fi
}

if [ -z "$OUTPUT_DIR" ]
then
    OUTPUT_DIR=.
fi

pushd "$OUTPUT_DIR" > /dev/null
dir=`pwd`
OUTPUT_DIR=$dir
popd > /dev/null

echo "Выходная директория: $OUTPUT_DIR"
echo "Директория скрипта: $SCRIPT_DIR"

# Шаг 1: Сборка статической библиотеки Opus для macOS (Universal)
echo "=== Шаг 1: Запуск сборки Opus ==="
"$SCRIPT_DIR/build_opus_mac.sh"
checkError

# Шаг 2: Сборка Xcode проекта плагина
echo "=== Шаг 2: Очистка проекта Xcode ==="
rm -rf "$SCRIPT_DIR/build"
xcodebuild -project "$SCRIPT_DIR/Plugin.xcodeproj" -configuration $CONFIG clean
checkError

echo "=== Шаг 3: Компиляция плагина Xcode ==="
xcodebuild -project "$SCRIPT_DIR/Plugin.xcodeproj" -configuration $CONFIG
checkError

FINAL_DYLIB="$SCRIPT_DIR/build/Release/$TARGET_NAME.$OUTPUT_SUFFIX"

# Шаг 4: Очистка локальных/отладочных символов из dylib и восстановление подписи кода
echo "=== Шаг 4: Очистка символов (strip -x) ==="
strip -x "$FINAL_DYLIB"
checkError

echo "=== Шаг 4.1: Восстановление подписи кода (codesign) ==="
codesign --force --sign - "$FINAL_DYLIB"
checkError

# Шаг 5: Деплой скомпилированной dylib в нужные папки
echo "=== Шаг 5: Копирование и деплой файлов ==="

# Копирование в указанную выходную папку
cp -v "$FINAL_DYLIB" "$OUTPUT_DIR/"
checkError

# Копирование в глобальный каталог плагинов симулятора Solar2D
SIMULATOR_PLUGINS_DIR="${HOME}/Library/Application Support/Corona/Simulator/Plugins"
mkdir -p "$SIMULATOR_PLUGINS_DIR"
cp -v "$FINAL_DYLIB" "$SIMULATOR_PLUGINS_DIR/"
echo "Плагин скопирован в каталог симулятора: $SIMULATOR_PLUGINS_DIR/"

# Деплой в папку публикации этого репозитория (plugin.opus/mac-sim)
PUB_DIR="$SCRIPT_DIR/../plugin.opus/mac-sim"
if [ -d "$PUB_DIR" ]; then
    cp -v "$FINAL_DYLIB" "$PUB_DIR/"
    cp -v "$SCRIPT_DIR/metadata.lua" "$PUB_DIR/"
    echo "Плагин скопирован в папку публикации: $PUB_DIR/"
fi

echo "=== Сборка плагина Opus под macOS успешно завершена! ==="

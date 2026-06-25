@echo off
:: Запуск PowerShell скрипта установки зависимостей с обходом политики выполнения скриптов
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_dependencies.ps1"

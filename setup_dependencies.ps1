# Скрипт для автоматической проверки и установки Microsoft Visual C++ Redistributable 2015-2022
# Требуются права администратора для установки библиотек в систему

$ErrorActionPreference = "Stop"

# Функция для проверки установки VC++ Redistributable в реестре Windows
function Test-VCRedistInstalled([string]$arch) {
    $path = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch"
    if ($arch -eq "x86" -and [Environment]::Is64BitOperatingSystem) {
        $path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86"
    }
    
    if (Test-Path $path) {
        $installed = Get-ItemProperty -Path $path -Name "Installed" -ErrorAction SilentlyContinue
        if ($installed -and $installed.Installed -eq 1) {
            return $true
        }
    }
    return $false
}

# Функция для скачивания и тихой установки
function Install-VCRedist([string]$url, [string]$arch) {
    Write-Host "Скачивание Visual C++ Redistributable 2015-2022 ($arch)..." -ForegroundColor Cyan
    $tempPath = Join-Path $env:TEMP "vc_redist_$arch.exe"
    
    # Скачивание файла
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing
    
    Write-Host "Установка ($arch)... Пожалуйста, подождите." -ForegroundColor Cyan
    # Запуск тихой установки без перезагрузки (/quiet /norestart)
    $process = Start-Process -FilePath $tempPath -ArgumentList "/quiet", "/norestart" -Wait -PassThru
    
    # Удаление временного файла
    Remove-Item -Path $tempPath -Force
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Host "Установка VC++ Redistributable ($arch) успешно завершена!" -ForegroundColor Green
    } else {
        Write-Warning "Установка завершилась с кодом: $($process.ExitCode)"
    }
}

# Проверка прав администратора
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Для установки системных библиотек требуются права администратора!" -ForegroundColor Yellow
    Write-Host "Перезапуск скрипта с правами администратора..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "=== Проверка зависимостей для сборщика Solar2D ===" -ForegroundColor White

# Проверка x86 версии
if (Test-VCRedistInstalled -arch "x86") {
    Write-Host "[OK] Visual C++ Redistributable 2015-2022 (x86) уже установлен." -ForegroundColor Green
} else {
    Write-Host "[WARNING] Visual C++ Redistributable 2015-2022 (x86) не найден!" -ForegroundColor Yellow
    Install-VCRedist -url "https://aka.ms/vs/17/release/vc_redist.x86.exe" -arch "x86"
}

# Проверка x64 версии
if (Test-VCRedistInstalled -arch "x64") {
    Write-Host "[OK] Visual C++ Redistributable 2015-2022 (x64) уже установлен." -ForegroundColor Green
} else {
    Write-Host "[WARNING] Visual C++ Redistributable 2015-2022 (x64) не найден!" -ForegroundColor Yellow
    Install-VCRedist -url "https://aka.ms/vs/17/release/vc_redist.x64.exe" -arch "x64"
}

Write-Host "`nВсе проверки завершены. Нажмите любую клавишу для выхода..."
$null = [Console]::ReadKey()

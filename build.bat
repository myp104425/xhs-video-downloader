@echo off
REM ============================================
REM  Flutter APK Build Script (Windows)
REM  用法: 双击运行 或 命令行执行 build.bat
REM ============================================

echo ========================================
echo    视频解析下载器 - APK 构建脚本
echo ========================================
echo.

REM 检查 Flutter
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到 Flutter!
    echo 请先安装 Flutter SDK: https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

echo [1/4] 检查 Flutter 环境...
flutter doctor --android-licenses >nul 2>nul
echo.

echo [2/4] 安装依赖...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 依赖安装失败
    pause
    exit /b 1
)
echo.

echo [3/4] 构建 Release APK...
call flutter build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo [错误] APK 构建失败
    pause
    exit /b 1
)
echo.

echo [4/4] 构建 Debug APK...
call flutter build apk --debug
echo.

echo ========================================
echo   ✅ 构建完成!
echo ========================================
echo.
echo  Release APK:
echo   build\app\outputs\flutter-apk\app-release.apk
echo.
echo  Debug APK:
echo   build\app\outputs\flutter-apk\app-debug.apk
echo.

pause

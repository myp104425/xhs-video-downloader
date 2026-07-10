#!/bin/bash
# ============================================
#  Flutter APK Build Script (macOS / Linux)
#  用法: chmod +x build.sh && ./build.sh
# ============================================

set -e

echo "========================================"
echo "   视频解析下载器 - APK 构建脚本"
echo "========================================"
echo ""

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "[错误] 未找到 Flutter!"
    echo "请先安装 Flutter SDK: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "[1/4] 检查 Flutter 环境..."
flutter doctor --android-licenses 2>/dev/null || true
echo ""

echo "[2/4] 安装依赖..."
flutter pub get
echo ""

echo "[3/4] 构建 Release APK..."
flutter build apk --release
echo ""

echo "[4/4] 构建 Debug APK..."
flutter build apk --debug
echo ""

echo "========================================"
echo "  ✅ 构建完成!"
echo "========================================"
echo ""
echo "Release APK:"
echo "  build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "Debug APK:"
echo "  build/app/outputs/flutter-apk/app-debug.apk"
echo ""

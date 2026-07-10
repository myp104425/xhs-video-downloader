# 🎥 多平台视频解析下载器 (Video Downloader)

> 一个轻量级 Flutter 应用，粘贴视频分享链接，即可解析并下载无水印视频。
>
> 支持 **小红书 · 抖音 · 快手 · B站 · 微博**

![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/Platform-Android-brightgreen)
![License](https://img.shields.io/badge/License-MIT-blue)

---

## ✨ 功能特色

| 特性 | 说明 |
|------|------|
| 🔗 **智能链接识别** | 自动检测链接来源平台，粘贴即解析 |
| 🎥 **无水印下载** | 解析获取最高画质视频直链 |
| 📊 **实时进度显示** | 显示下载速度、进度百分比、文件大小 |
| 🗂️ **下载历史管理** | 记录已下载视频，支持查看和删除 |
| 🌙 **深色模式** | 跟随系统，自动切换明暗主题 |
| 🎨 **Material Design 3** | 精致现代 UI，平台专属配色 |

## 📱 支持平台

| 平台 | 品牌色 | 标识 |
|------|--------|------|
| 📕 **小红书** | `#FF2442` | `xiaohongshu.com` / `xhslink.com` |
| 🎵 **抖音** | `#161823` | `douyin.com` / `iesdouyin.com` |
| 📱 **快手** | `#FF4906` | `kuaishou.com` |
| 📺 **B站** | `#00A1D6` | `bilibili.com` / `b23.tv` |
| 📰 **微博** | `#E6162D` | `weibo.com` |

## 🚀 快速开始

### 前置要求

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (>=3.0.0)
- Android Studio / VS Code + Flutter 插件

### 获取源码

```bash
git clone https://github.com/your-username/xhs-video-downloader.git
cd xhs-video-downloader
```

### 安装依赖

```bash
flutter pub get
```

### 运行

```bash
flutter run
```

### 构建 APK

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```

APK 位于：`build/app/outputs/flutter-apk/`

## 📖 使用方法

1. 打开应用
2. 在小红书/抖音/快手/B站/微博 App 中复制视频分享链接
3. 粘贴到应用的输入框中（自动识别平台）
4. 点击「解析视频」
5. 查看视频信息并点击「下载」
6. 下载完成后可在「下载管理」中查看

## 🏗️ 技术架构

借鉴浏览器 Video Download Helper 插件的核心思路：

```
┌─ 用户粘贴链接 ─────────────────────────┐
│                                        │
├─ ParserManager（自动检测平台）          │
│  ├─ 小红书 → XiaohongshuParser         │
│  ├─ 抖音   → DouyinParser              │
│  ├─ 快手   → KuaishouParser            │
│  ├─ B站    → BilibiliParser            │
│  └─ 微博   → WeiboParser               │
│                                        │
├─ 解析流程（每个解析器）                  │
│  1. 桌面端 User-Agent 请求页面          │
│  2. 提取 __INITIAL_STATE__ JSON        │
│  3. 解析视频直链（最高画质）            │
│  4. 降级策略：JSON-LD → Meta 标签      │
│                                        │
├─ DownloadService（Dio 流式下载）        │
│  ├─ 分片下载 · 断点续传                │
│  ├─ 实时速度/进度回调                  │
│  └─ 暂停/取消/错误处理                 │
│                                        │
└─ HistoryService（JSON 持久化）          │
   └─ 记录管理 · 自动清理失效文件         │
```

## 📁 项目结构

```
xhs-video-downloader/
├── lib/
│   ├── main.dart                       # 应用入口 + 主题
│   ├── models/
│   │   └── video_info.dart             # 数据模型 + 平台枚举
│   ├── services/
│   │   ├── parsers/
│   │   │   ├── parser_base.dart        # 解析器基类 + 桌面端 UA
│   │   │   ├── parser_manager.dart     # 平台检测 + 路由
│   │   │   ├── xiaohongshu_parser.dart # 小红书解析器
│   │   │   ├── douyin_parser.dart      # 抖音解析器
│   │   │   ├── kuaishou_parser.dart    # 快手解析器
│   │   │   ├── bilibili_parser.dart    # B站解析器
│   │   │   └── weibo_parser.dart       # 微博解析器
│   │   ├── download_service.dart       # 视频下载服务
│   │   └── history_service.dart        # 下载历史管理
│   ├── screens/
│   │   ├── home_screen.dart            # 首页（解析+下载）
│   │   └── download_screen.dart        # 下载管理页
│   └── widgets/
│       ├── url_input_bar.dart          # 链接输入组件
│       ├── video_card.dart             # 视频信息卡片
│       └── platform_badge.dart         # 平台标识徽章
├── android/                            # Android 配置
├── test/                               # 单元测试
├── pubspec.yaml
└── README.md
```

## ⚠️ 免责声明

本工具仅供**学习和个人使用**。使用者应遵守：
- 各平台的使用条款和条件
- 相关法律法规关于网络信息内容的管理规定
- 尊重原作者的版权，下载内容仅用于个人学习研究

**请勿将本工具用于商业用途或任何侵犯他人权益的行为。**

## 📄 License

[MIT](LICENSE)

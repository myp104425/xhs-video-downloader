import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置服务 — 持久化存储用户偏好（下载路径等）
class SettingsService {
  static const String _keyDownloadPath = 'download_path';
  static const String _keyUseCustomPath = 'use_custom_path';

  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 获取下载目录
  Future<Directory> getDownloadDirectory() async {
    // 如果用户设置了自定义路径（通过系统文件选择器 SAF 授予权限）
    if (useCustomPath) {
      final customPath = _prefs?.getString(_keyDownloadPath);
      if (customPath != null && customPath.isNotEmpty) {
        final dir = Directory(customPath);
        try {
          if (await dir.exists() || await dir.create(recursive: true).then((_) => true)) {
            return dir;
          }
        } catch (_) {
          // 自定义路径不可写，回退到默认
        }
      }
    }

    // 默认：使用应用内部文档目录（Android / iOS 均可写，无权限问题）
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/XHS_Videos');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } catch (_) {
      // 极端 fallback
      final dir = Directory('/storage/emulated/0/Download/XHS_Videos');
      await dir.create(recursive: true);
      return dir;
    }
  }

  /// 是否使用自定义路径
  bool get useCustomPath {
    return _prefs?.getBool(_keyUseCustomPath) ?? false;
  }

  /// 获取自定义路径
  String? get customPath {
    return _prefs?.getString(_keyDownloadPath);
  }

  /// 获取可读的路径显示
  Future<String> getDisplayPath() async {
    if (useCustomPath && customPath != null) {
      return customPath!;
    }
    final dir = await getDownloadDirectory();
    return dir.path;
  }

  /// 设置自定义下载路径
  Future<void> setDownloadPath(String path) async {
    // ★ 修复: 验证路径是否有效
    if (!path.startsWith('/')) {
      throw Exception('无效的路径: $path\nAndroid 路径应以 / 开头');
    }
    final dir = Directory(path);
    final exists = await dir.exists();
    if (!exists) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        throw Exception('无法创建目录: $e');
      }
    }
    // 测试写入权限
    try {
      final testFile = File('$path/.write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
    } catch (e) {
      throw Exception('目录不可写: $e');
    }
    await _prefs?.setString(_keyDownloadPath, path);
    await _prefs?.setBool(_keyUseCustomPath, true);
  }

  /// 重置为默认路径
  Future<void> resetToDefault() async {
    await _prefs?.setBool(_keyUseCustomPath, false);
    await _prefs?.remove(_keyDownloadPath);
  }
}

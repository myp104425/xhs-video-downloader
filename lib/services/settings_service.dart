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
    // 如果用户设置了自定义路径
    if (useCustomPath) {
      final customPath = _prefs?.getString(_keyDownloadPath);
      if (customPath != null && customPath.isNotEmpty) {
        final dir = Directory(customPath);
        if (await dir.exists() || await dir.create(recursive: true).then((_) => true).catchError((_) => false)) {
          return dir;
        }
      }
    }

    // 默认：优先使用公共 Download 目录（用户可在文件管理器看到）
    try {
      final dir = Directory('/storage/emulated/0/Download/XHS_Videos');
      if (await dir.exists() || await dir.create(recursive: true).then((_) => true).catchError((_) => false)) {
        return dir;
      }
    } catch (_) {}

    // 备用 1：getExternalStorageDirectory
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final downloadDir = Directory('${dir.path}/XHS_Videos');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      }
    } catch (_) {}

    // 备用 2：应用文档目录
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/XHS_Videos');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
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
    await _prefs?.setString(_keyDownloadPath, path);
    await _prefs?.setBool(_keyUseCustomPath, true);
  }

  /// 重置为默认路径
  Future<void> resetToDefault() async {
    await _prefs?.setBool(_keyUseCustomPath, false);
    await _prefs?.remove(_keyDownloadPath);
  }
}

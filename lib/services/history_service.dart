import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../models/video_info.dart';
import '../services/download_service.dart';

/// 下载历史管理服务
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  List<VideoInfo> _history = [];
  bool _loaded = false;

  /// 获取历史记录文件路径
  Future<String> get _historyFilePath async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/download_history.json';
  }

  /// 加载历史记录
  Future<List<VideoInfo>> loadHistory() async {
    if (_loaded) return _history;

    try {
      final path = await _historyFilePath;
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _history = jsonList.map((e) => VideoInfo.fromJson(e)).toList();

        // 清理无效记录（文件已被删除的）
        final downloadService = DownloadService();
        final validHistory = <VideoInfo>[];
        for (final info in _history) {
          if (info.localPath != null) {
            if (await downloadService.fileExists(info.localPath!)) {
              validHistory.add(info);
            }
          }
        }
        _history = validHistory;
      }
      _loaded = true;
    } catch (e) {
      debugPrint('加载历史记录失败: $e');
      _history = [];
    }

    return _history;
  }

  /// 保存历史记录
  Future<void> saveHistory() async {
    try {
      final path = await _historyFilePath;
      final file = File(path);
      final jsonList = _history.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('保存历史记录失败: $e');
    }
  }

  /// 添加下载记录
  Future<void> addRecord(VideoInfo info) async {
    // 如果已存在相同 noteId，更新状态
    final existingIndex = _history.indexWhere((e) => e.noteId == info.noteId);
    if (existingIndex >= 0) {
      _history[existingIndex] = info;
    } else {
      _history.insert(0, info);
    }
    await saveHistory();
  }

  /// 更新记录状态
  Future<void> updateRecord(VideoInfo info) async {
    final existingIndex = _history.indexWhere((e) => e.noteId == info.noteId);
    if (existingIndex >= 0) {
      _history[existingIndex] = info;
      await saveHistory();
    }
  }

  /// 删除记录
  Future<void> deleteRecord(String noteId) async {
    _history.removeWhere((e) => e.noteId == noteId);
    await saveHistory();
  }

  /// 获取所有记录
  List<VideoInfo> get history => _history;
}

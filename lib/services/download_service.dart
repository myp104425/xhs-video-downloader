import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_info.dart';

/// 视频下载服务
class DownloadService {
  static const String _tag = 'DownloadService';

  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<DownloadProgress>> _progressControllers = {};

  /// 获取下载目录
  Future<Directory> getDownloadDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/VideoDownloader');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// 生成安全的文件名
  String _sanitizeFileName(String name) {
    String safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (safe.length > 100) {
      safe = safe.substring(0, 100);
    }
    return safe.isEmpty ? 'xhs_video' : safe;
  }

  /// 开始下载视频
  ///
  /// 返回下载流（进度信息）
  Stream<DownloadProgress> downloadVideo(
    VideoInfo videoInfo, {
    bool saveToGallery = false,
  }) {
    final noteId = videoInfo.noteId;

    // 创建进度流控制器
    final controller = StreamController<DownloadProgress>(
      onCancel: () {
        cancelDownload(noteId);
      },
    );
    _progressControllers[noteId] = controller;

    // 开始下载
    _startDownload(videoInfo, controller, saveToGallery);

    return controller.stream;
  }

  /// 执行下载
  Future<void> _startDownload(
    VideoInfo videoInfo,
    StreamController<DownloadProgress> controller,
    bool saveToGallery,
  ) async {
    final noteId = videoInfo.noteId;
    final cancelToken = CancelToken();
    _cancelTokens[noteId] = cancelToken;

    try {
      final downloadDir = await getDownloadDirectory();
      final fileName =
          '${_sanitizeFileName(videoInfo.title)}_$noteId.mp4';
      final filePath = '${downloadDir.path}/$fileName';
      final file = File(filePath);

      // 检查是否已下载
      if (await file.exists()) {
        final existingFileSize = await file.length();
        if (existingFileSize > 0) {
          developer.log('文件已存在: $filePath', name: _tag);
          controller.add(DownloadProgress(
            received: existingFileSize,
            total: existingFileSize,
          ));

          videoInfo.downloadStatus = DownloadStatus.completed;
          videoInfo.localPath = filePath;
          videoInfo.downloadTime = DateTime.now();

          controller.close();
          _cleanup(noteId);
          return;
        }
      }

      // 获取视频真实 URL（处理重定向）
      final videoUrl = videoInfo.videoUrl;
      developer.log('开始下载: $videoUrl', name: _tag);

      // 用于计算下载速度
      int lastReceived = 0;
      DateTime lastTime = DateTime.now();

      await _dio.download(
        videoUrl,
        filePath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            'Referer': 'https://www.xiaohongshu.com/',
          },
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 10),
        ),
        onReceiveProgress: (received, total) {
          if (cancelToken.isCancelled) return;

          // 计算速度
          final now = DateTime.now();
          final elapsed = now.difference(lastTime).inMilliseconds;
          double speed = 0;
          if (elapsed > 500) {
            speed = (received - lastReceived) / (elapsed / 1000.0);
            lastReceived = received;
            lastTime = now;
          }

          controller.add(DownloadProgress(
            received: received,
            total: total > 0 ? total : received,
            speed: speed,
          ));

          // 更新状态
          if (received >= total && total > 0) {
            videoInfo.downloadStatus = DownloadStatus.completed;
            videoInfo.localPath = filePath;
            videoInfo.downloadTime = DateTime.now();
          } else {
            videoInfo.downloadStatus = DownloadStatus.downloading;
          }
        },
      );

      // 下载完成
      final downloadedFile = File(filePath);
      if (await downloadedFile.exists()) {
        final fileSize = await downloadedFile.length();
        developer.log('下载完成: $filePath ($fileSize bytes)', name: _tag);

        videoInfo.downloadStatus = DownloadStatus.completed;
        videoInfo.localPath = filePath;
        videoInfo.downloadTime = DateTime.now();

        controller.add(DownloadProgress(
          received: fileSize,
          total: fileSize,
        ));
      }

      controller.close();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        developer.log('下载已取消: $noteId', name: _tag);
        videoInfo.downloadStatus = DownloadStatus.paused;
        controller.addError(Exception('下载已取消'));
      } else {
        developer.log('下载失败: $e', name: _tag);
        videoInfo.downloadStatus = DownloadStatus.failed;

        String errorMsg = '下载失败';
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          errorMsg = '下载超时，请检查网络连接';
        } else if (e.type == DioExceptionType.connectionError) {
          errorMsg = '网络连接失败，请检查网络';
        } else if (e.response != null) {
          errorMsg = '服务器错误: HTTP ${e.response?.statusCode}';
        }

        controller.addError(Exception(errorMsg));
      }
      controller.close();
    } catch (e) {
      developer.log('下载异常: $e', name: _tag);
      videoInfo.downloadStatus = DownloadStatus.failed;
      controller.addError(Exception('下载异常: $e'));
      controller.close();
    } finally {
      _cleanup(noteId);
    }
  }

  /// 取消/暂停下载
  void cancelDownload(String noteId) {
    final cancelToken = _cancelTokens[noteId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel();
    }
    _cleanup(noteId);
  }

  /// 清理下载状态
  void _cleanup(String noteId) {
    _cancelTokens.remove(noteId);
    _progressControllers.remove(noteId);
  }

  /// 检查文件是否存在
  Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// 获取已下载的文件大小
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return file.length();
    }
    return 0;
  }

  /// 删除下载的视频文件
  Future<bool> deleteVideo(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      developer.log('删除文件失败: $e', name: _tag);
      return false;
    }
  }

  /// 获取所有已下载的视频文件信息
  Future<List<FileSystemEntity>> getDownloadedFiles() async {
    try {
      final downloadDir = await getDownloadDirectory();
      return await downloadDir.list().toList();
    } catch (e) {
      developer.log('获取下载文件列表失败: $e', name: _tag);
      return [];
    }
  }

  /// 释放资源
  void dispose() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel();
      }
    }
    _cancelTokens.clear();
    for (final controller in _progressControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _progressControllers.clear();
  }
}

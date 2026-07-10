import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';

import '../models/video_info.dart';
import 'settings_service.dart';

/// 下载格式
enum DownloadFormat {
  video,
  mp3,
}

/// 视频下载服务
class DownloadService {
  static const String _tag = 'DownloadService';

  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Dio _dio = Dio();
  final SettingsService _settings = SettingsService();
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<DownloadProgress>> _progressControllers = {};

  /// 生成安全的文件名
  String _sanitizeFileName(String name) {
    String safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (safe.length > 100) safe = safe.substring(0, 100);
    return safe.isEmpty ? 'video' : safe;
  }

  /// 开始下载
  Stream<DownloadProgress> downloadVideo(
    VideoInfo videoInfo, {
    DownloadFormat format = DownloadFormat.video,
  }) {
    final noteId = videoInfo.noteId;

    final controller = StreamController<DownloadProgress>(
      onCancel: () => cancelDownload(noteId),
    );
    _progressControllers[noteId] = controller;

    _startDownload(videoInfo, controller, format);

    return controller.stream;
  }

  Future<void> _startDownload(
    VideoInfo videoInfo,
    StreamController<DownloadProgress> controller,
    DownloadFormat format,
  ) async {
    final noteId = videoInfo.noteId;
    final cancelToken = CancelToken();
    _cancelTokens[noteId] = cancelToken;

    try {
      final downloadDir = await _settings.getDownloadDirectory();
      final safeName = _sanitizeFileName(videoInfo.title);

      if (format == DownloadFormat.video) {
        await _downloadAsVideo(videoInfo, controller, cancelToken, downloadDir, safeName);
      } else {
        await _downloadAsMp3(videoInfo, controller, cancelToken, downloadDir, safeName);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        videoInfo.downloadStatus = DownloadStatus.paused;
        controller.addError(Exception('下载已取消'));
      } else {
        videoInfo.downloadStatus = DownloadStatus.failed;
        String msg = '下载失败';
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          msg = '下载超时，请检查网络连接';
        } else if (e.type == DioExceptionType.connectionError) {
          msg = '网络连接失败，请检查网络';
        } else if (e.response != null) {
          msg = '服务器错误: HTTP ${e.response?.statusCode}';
        }
        controller.addError(Exception(msg));
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

  /// 下载为视频 MP4
  Future<void> _downloadAsVideo(
    VideoInfo videoInfo,
    StreamController<DownloadProgress> controller,
    CancelToken cancelToken,
    Directory downloadDir,
    String safeName,
  ) async {
    final filePath = '${downloadDir.path}/${safeName}_${videoInfo.noteId}.mp4';
    final file = File(filePath);

    if (await file.exists() && await file.length() > 0) {
      final size = await file.length();
      controller.add(DownloadProgress(received: size, total: size, stage: DownloadStage.done));
      videoInfo.downloadStatus = DownloadStatus.completed;
      videoInfo.localPath = filePath;
      videoInfo.downloadTime = DateTime.now();
      controller.close();
      return;
    }

    int lastReceived = 0;
    DateTime lastTime = DateTime.now();

    await _dio.download(
      videoInfo.videoUrl,
      filePath,
      cancelToken: cancelToken,
      options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
          'Referer': 'https://www.xiaohongshu.com/',
        },
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 10),
      ),
      onReceiveProgress: (received, total) {
        if (cancelToken.isCancelled) return;
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
          stage: DownloadStage.downloading,
        ));
        videoInfo.downloadStatus = DownloadStatus.downloading;
      },
    );

    final f = File(filePath);
    if (await f.exists()) {
      final size = await f.length();
      videoInfo.downloadStatus = DownloadStatus.completed;
      videoInfo.localPath = filePath;
      videoInfo.downloadTime = DateTime.now();
      controller.add(DownloadProgress(
        received: size, total: size, stage: DownloadStage.done,
      ));
    }
    controller.close();
  }

  /// 下载并转换为 MP3
  Future<void> _downloadAsMp3(
    VideoInfo videoInfo,
    StreamController<DownloadProgress> controller,
    CancelToken cancelToken,
    Directory downloadDir,
    String safeName,
  ) async {
    final tempVideoPath = '${downloadDir.path}/${safeName}_${videoInfo.noteId}_temp.mp4';
    final mp3Path = '${downloadDir.path}/${safeName}_${videoInfo.noteId}.mp3';

    // 如果 MP3 已存在，直接返回
    final mp3File = File(mp3Path);
    if (await mp3File.exists() && await mp3File.length() > 0) {
      final size = await mp3File.length();
      controller.add(DownloadProgress(received: size, total: size, stage: DownloadStage.done));
      videoInfo.downloadStatus = DownloadStatus.completed;
      videoInfo.localPath = mp3Path;
      videoInfo.downloadTime = DateTime.now();
      controller.close();
      return;
    }

    // 第一步：下载视频
    int lastReceived = 0;
    DateTime lastTime = DateTime.now();

    await _dio.download(
      videoInfo.videoUrl,
      tempVideoPath,
      cancelToken: cancelToken,
      options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
          'Referer': 'https://www.xiaohongshu.com/',
        },
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 10),
      ),
      onReceiveProgress: (received, total) {
        if (cancelToken.isCancelled) return;
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
          stage: DownloadStage.downloading,
        ));
      },
    );

    if (cancelToken.isCancelled) {
      await File(tempVideoPath).delete();
      controller.close();
      return;
    }

    // 第二步：FFmpeg 提取音频为 MP3
    controller.add(DownloadProgress(
      received: 0,
      total: 100,
      stage: DownloadStage.converting,
    ));

    try {
      final command = '-i "$tempVideoPath" -vn -acodec libmp3lame -ab 192k "$mp3Path" -y';
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // 删除临时视频文件
        await File(tempVideoPath).delete();

        final mp3File = File(mp3Path);
        if (await mp3File.exists()) {
          final size = await mp3File.length();
          videoInfo.downloadStatus = DownloadStatus.completed;
          videoInfo.localPath = mp3Path;
          videoInfo.downloadTime = DateTime.now();
          controller.add(DownloadProgress(
            received: size, total: size, stage: DownloadStage.done,
          ));
        }
      } else {
        throw Exception('音频转换失败');
      }
    } catch (e) {
      // FFmpeg 失败，清理临时文件
      await File(tempVideoPath).delete();
      rethrow;
    }

    controller.close();
  }

  /// 取消/暂停下载
  void cancelDownload(String noteId) {
    final cancelToken = _cancelTokens[noteId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel();
    }
    _cleanup(noteId);
  }

  void _cleanup(String noteId) {
    _cancelTokens.remove(noteId);
    _progressControllers.remove(noteId);
  }

  Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  Future<bool> deleteVideo(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<FileSystemEntity>> getDownloadedFiles() async {
    try {
      final dir = await _settings.getDownloadDirectory();
      return await dir.list().toList();
    } catch (e) {
      return [];
    }
  }

  void dispose() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel();
    }
    _cancelTokens.clear();
    for (final c in _progressControllers.values) {
      if (!c.isClosed) c.close();
    }
    _progressControllers.clear();
  }
}

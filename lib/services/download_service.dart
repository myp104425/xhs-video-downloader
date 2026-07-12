import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../models/video_info.dart';
import 'settings_service.dart';
import 'm3u8_downloader.dart';
import 'mpd_downloader.dart';

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
  final Map<String, dynamic> _cancelTokens = {};
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
    int trimStart = 0,
    int trimEnd = 0,
  }) {
    final noteId = videoInfo.noteId;

    final controller = StreamController<DownloadProgress>(
      onCancel: () => cancelDownload(noteId),
    );
    _progressControllers[noteId] = controller;

    _startDownload(videoInfo, controller, format, trimStart: trimStart, trimEnd: trimEnd);

    return controller.stream;
  }

  Future<void> _startDownload(
    VideoInfo videoInfo,
    StreamController<DownloadProgress> controller,
    DownloadFormat format,
    {int trimStart = 0, int trimEnd = 0}
  ) async {
    final noteId = videoInfo.noteId;
    final cancelToken = CancelToken();
    _cancelTokens[noteId] = cancelToken;

    try {
      final downloadDir = await _settings.getDownloadDirectory();
      final safeName = _sanitizeFileName(videoInfo.title);
      final fileName = '${safeName}_$noteId.mp4';
      final mp3Name = '${safeName}_$noteId.mp3';
      final filePath = '${downloadDir.path}/$fileName';
      final mp3Path = '${downloadDir.path}/$mp3Name';
      final targetPath = format == DownloadFormat.mp3 ? mp3Path : filePath;

      // 先确保下载目录存在
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // 目标文件已存在则直接返回
      final targetFile = File(targetPath);
      if (await targetFile.exists() && await targetFile.length() > 0) {
        final size = await targetFile.length();
        controller.add(DownloadProgress(received: size, total: size, stage: DownloadStage.done));
        videoInfo.downloadStatus = DownloadStatus.completed;
        videoInfo.localPath = targetPath;
        videoInfo.downloadTime = DateTime.now();
        controller.close();
        return;
      }

      // ★ 先创建临时目录
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      final tempFile = File(tempPath);

      // ★ 检测是否为流媒体链接（HLS / DASH），使用专用下载器
      final videoUrlLower = videoInfo.videoUrl.toLowerCase();
      if (videoUrlLower.endsWith('.m3u8') || videoUrlLower.contains('.m3u8')) {
        controller.add(DownloadProgress(received: 0, total: 100, stage: DownloadStage.downloading));
        final m3u8 = M3U8Downloader();
        _cancelTokens[noteId] = m3u8; // 用于取消
        await m3u8.download(videoInfo.videoUrl, tempPath,
          onProgress: (current, total, stage) {
            if (!controller.isClosed) {
              controller.add(DownloadProgress(
                received: current, total: total > 0 ? total : current,
                stage: DownloadStage.downloading,
              ));
            }
          },
        );
      } else if (videoUrlLower.endsWith('.mpd') || videoUrlLower.contains('.mpd')) {
        controller.add(DownloadProgress(received: 0, total: 100, stage: DownloadStage.downloading));
        final mpd = MPDDownloader();
        _cancelTokens[noteId] = mpd;
        await mpd.download(videoInfo.videoUrl, tempPath,
          onProgress: (current, total, stage) {
            if (!controller.isClosed) {
              controller.add(DownloadProgress(
                received: current, total: total > 0 ? total : current,
                stage: DownloadStage.downloading,
              ));
            }
          },
        );
      } else {
        // 普通视频文件 — 用 Dio 直接下载
        int lastReceived = 0;
        DateTime lastTime = DateTime.now();

        await _dio.download(
          videoInfo.videoUrl,
          tempPath,
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
              'Referer': 'https://www.xiaohongshu.com/',
            },
            receiveTimeout: const Duration(seconds: 60),
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
              total: total, // ★ 直接传递 total（-1 表示未知），model 会处理
              speed: speed,
              stage: DownloadStage.downloading,
            ));
            videoInfo.downloadStatus = DownloadStatus.downloading;
          },
        );
      }

      if (!await tempFile.exists()) {
        throw Exception('临时文件创建失败');
      }

      // 需要 FFmpeg 处理：MP3 转换 或 视频剪辑
      final needsProcessing = format == DownloadFormat.mp3 || trimStart > 0 || trimEnd > 0;

      if (needsProcessing) {
        controller.add(DownloadProgress(
          received: 0, total: 100, stage: DownloadStage.converting,
        ));

        // 确保目标目录存在
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        await _processFile(tempPath, targetPath, format: format, trimStart: trimStart, trimEnd: trimEnd);
        await tempFile.delete();
      } else {
        // 直接复制到目标路径
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        await tempFile.copy(targetPath);
        await tempFile.delete();
      }

      if (await File(targetPath).exists()) {
        final size = await File(targetPath).length();
        videoInfo.downloadStatus = DownloadStatus.completed;
        videoInfo.localPath = targetPath;
        videoInfo.downloadTime = DateTime.now();
        controller.add(DownloadProgress(received: size, total: size, stage: DownloadStage.done));
      }

      // ★★★ 关键修复: 关闭控制器，触发 onDone 回调 ★★★
      controller.close();
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

  /// 使用 FFmpeg 处理文件（MP3 转换 / 视频剪辑）
  Future<void> _processFile(
    String inputPath,
    String outputPath, {
    DownloadFormat format = DownloadFormat.video,
    int trimStart = 0,
    int trimEnd = 0,
  }) async {
    try {
      final buffer = StringBuffer();

      // 剪辑起始时间
      if (trimStart > 0) {
        buffer.write('-ss ${_formatDuration(trimStart)} ');
      }

      buffer.write('-i "$inputPath"');

      // 剪辑时长
      if (trimEnd > 0 && trimEnd > trimStart) {
        final duration = trimEnd - trimStart;
        buffer.write(' -t ${_formatDuration(duration)}');
      }

      if (format == DownloadFormat.mp3) {
        // 提取音频为 MP3
        buffer.write(' -vn -acodec libmp3lame -ab 192k -ar 44100 -ac 2');
      } else {
        // 视频剪辑：复制编码（最快）
        buffer.write(' -c copy -avoid_negative_ts make_zero');
      }

      buffer.write(' -y "$outputPath"');

      final command = buffer.toString();
      developer.log('FFmpeg: $command', name: _tag);

      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();

      if (!ReturnCode.isSuccess(rc)) {
        // 如果复杂参数失败，降级为简单参数
        if (format == DownloadFormat.mp3) {
          final fallbackCmd = '-i "$inputPath" -vn -acodec libmp3lame -y "$outputPath"';
          final fbSession = await FFmpegKit.execute(fallbackCmd);
          if (!ReturnCode.isSuccess(await fbSession.getReturnCode())) {
            throw Exception('音频转换失败');
          }
        } else {
          // 视频剪辑降级：简单 copy
          final fallbackCmd = '-i "$inputPath" -c copy -y "$outputPath"';
          final fbSession = await FFmpegKit.execute(fallbackCmd);
          if (!ReturnCode.isSuccess(await fbSession.getReturnCode())) {
            throw Exception('视频处理失败');
          }
        }
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('FFmpeg 异常: $e');
    }
  }

  /// 格式化时长（秒 → HH:MM:SS.mmm）
  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.000';
  }

  void cancelDownload(String noteId) {
    final cancelTarget = _cancelTokens[noteId];
    if (cancelTarget != null) {
      // 支持 Dio CancelToken / M3U8Downloader / MPDDownloader 的 cancel()
      if (cancelTarget is CancelToken) {
        if (!cancelTarget.isCancelled) cancelTarget.cancel();
      } else {
        try { cancelTarget.cancel(); } catch (_) {}
      }
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
      try { token.cancel(); } catch (_) {}
    }
    _cancelTokens.clear();
    for (final c in _progressControllers.values) {
      if (!c.isClosed) c.close();
    }
    _progressControllers.clear();
  }
}
